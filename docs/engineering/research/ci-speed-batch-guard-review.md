# Security review — the permission guard's batch path (ci-speed task-005)

Objective `ci-speed`, task-005, tracking issue #380. Reviewed on **2026-11-05/06** by the
security-reviewer role (read-only on code). Subject:

- **task-001**, commit `702bbd3` — `--judge-batch` / `--classify-batch` on
  `hooks/permission-guard.sh`, the driver `hooks/lib/pg_batch.py`, the shared
  `_pg_prepare` / `_pg_decide` / `_pg_shape` refactor, and `HOOK_JQ_*` / `hook_ask_carried`
  in `hooks/lib/hook-output.sh`. Reviewed **committed**, at the integration head `924a737`.
- **task-002**, branch `worker/ci-speed/002` — the suites on the batch path. Reviewed as a
  **working tree in progress**: nothing is committed past `702bbd3`; read were the
  uncommitted `tests/lib/pg-batch.sh` (new), `tests/test-permission-fuzz.sh` and
  `tests/test-permission-guard.sh` as they stood on 2026-11-05 ~23:50.

Every reproduction ran hermetically: a scratch `HOME`, `TAMIRS_PERMISSION_TEST_ROOT` in a
0700 temp dir, an empty git config, the client variables unset. No real permission state,
no network writes.

## Verdict

**No P1.** The live hook is unchanged: a 453-case differential of the pre-task-001 tree
against the integration head found no difference in stdout, stderr or exit code, and the four
suites pass. The batch flags are unreachable from every manifest. Four **P2**s, none blocking
delivery, are listed below. Three are in the batch entry: an inherited control variable,
silent truncation on invalid UTF-8, and a verdict that is looser than the hook on invalid
UTF-8. The fourth is in task-002's agreement check, which cannot see a same-decision
divergence.

| # | Sev | Confidence | Blocking | One-line fix |
|---|---|---|---|---|
| F1 | P2 | high | no | Assign `_PG_BATCH=0` at top level; only `_pg_batch` sets it to 1. |
| F2 | P2 | high | no | Run `tr` and the line count under `LC_ALL=C`, and count the lines before `tr` runs. |
| F3 | P2 | high | no | Detect a line that is not valid UTF-8 before jq, and send its raw bytes to a strictly-decoding engine. |
| F4 | P2 | high | no | Add the named id set and the `on \`…\`` target to the canonical form, and return to bytes after F5. |
| F5 | P3 | high | no | Sort `rest_ids()` and every set feeding `HITS`, and give `max()` a deterministic last key. |
| F6 | P3 | high | no | Put a `read -t` deadline on every fd 6 read and mark the engine dead on timeout. |
| F7 | P3 | medium | no | Stratify the fuzz sample by family, kind and dialect, and add Cursor and OpenCode lines. |
| F8 | P3 | high | no | None. The multi-value stdin behaviour predates task-001; record it only. |

## Suite counts on the integration head `924a737`

| Suite | Result | Wall time |
|---|---|---|
| `bash tests/test-permission-guard.sh` | passed 1046, failed 0 | 1082 s |
| `bash tests/test-hook-conformance.sh` | passed 1087, failed 0 | 98 s |
| `bash tests/test-manifest-invariants.sh` | passed 33, failed 0 | 25 s |
| `bash tests/test-security-regressions.sh` | passed 217, failed 0 | 440 s |

## Resolution status

The findings above are as reviewed at `924a737`. Since then the lead has acted on them on
`objective/ci-speed`:

- **F1, F2, F3 and F5 are fixed in `e4cfb3e`**, "batch transport can't be inherited;
  deterministic tie-break between tied action ids". F5's fix covers the nondeterminism task-002
  found, through a deterministic `JOBS` tie-break. This review did not re-test `e4cfb3e`.
- **F4 went to task-002.** After F5's fix, the agreement check can return to bytes.
- **F6, F7 and F8 are open** as P3 followups.

## Q1 — no verdict widening

**Answer: yes for valid UTF-8, no for one byte class.** Every malformed, blank,
whitespace-only, NUL-carrying, over-1-MiB, unknown-host, non-string-host, two-objects-on-one-line
and engine-failed line is a deny (Q4 table). The refactor shares the tokeniser, the engine
source, `PG_BUDGET`, the resolver level and the dialect ranking literally, so on valid UTF-8 the
batch is the hook. The batch is also *stricter* than the hook in two documented places: a blank
line is a deny where a blank payload is an allow, and a line over 1 MiB is denied unread. The
exception is invalid UTF-8, where the batch is **looser** than the hook (F3).

### F3 (P2) — invalid UTF-8: the batch asks where the hook denies

`jq -R` (`hooks/permission-guard.sh:3064`) replaces invalid bytes with U+FFFD and re-emits the
line as valid UTF-8. That repaired text is what reaches the engine. On the single-call path
the engine reads the raw bytes, a strict decode fails, the engine exits 1, and
`_pg_decide` denies.

```text
command: gh repo delete o/r --yes <invalid bytes>        (Claude payload, same bytes both sides)
  tail ' \xff\xfe'            live: deny "its engine exited 1"    batch (LC_ALL=C): ask repo.delete (R4)
  tail ' x\xc3'               live: deny "its engine exited 1"    batch (LC_ALL=C): ask repo.delete (R4)
  tail ' --description \xe9t\xe9'  live: deny "its engine exited 1"    batch (LC_ALL=C): ask repo.delete (R4)
```

**Blast radius.** Live users are unaffected, because the batch is a test entry only (Q3). The
error runs in the safe direction for live users, since the live hook is the stricter side. But the
oracle stops being the hook: a suite would certify `ask` where users get `deny`. Run under the
default locale, F2 turns the same input into a truncated batch instead.

**Fix.** Before jq, flag every line whose raw bytes are not valid UTF-8, using a
`python3 -I -S` pre-pass or `LC_ALL=C grep -naxv '.*'`. Send the flagged line's original
bytes to the engine, and have `pg_batch.py:73` decode them the way the single path does,
or deny the line whenever it leaves the fast path. Add one guard-suite case per side.

## Q2 — did the live hook change?

**Answer: no observable change.**

- **Code read.** The old `_pg_finish` printed the reason on stderr for every non-allow verdict
  and dispatched on the host. The new `_pg_shape` computes the same four delivered shapes from the
  same variables, and the new `_pg_finish` prints the same stderr and calls the same helpers.
  `hook_ask` now calls `hook_ask_carried`, which holds the identical predicate. Each
  `HOOK_JQ_*` is the old literal program, assigned at source time, so the environment cannot
  override it. `_pg_prepare` returns where the old code called `_pg_finish`, and `_pg_decide`
  returns at the first verdict set. The NUL, invalid-JSON, out-of-scope, blank and fast-path
  early answers keep their old order. `PG_CURSOR_ASK` is still reset before use and never
  inherited.
- **Differential.** 453 cases ran against two trees: `git archive 702bbd3^` and the head. The
  cases cover seven dialects (Claude, Codex, OpenCode, Gemini, Cursor CLI, Cursor desktop
  3.28.7 on both events) times 20 commands, plus 11 malformed and MCP payloads. Each case ran
  under three environments: none, `CODEX_HOME`, and `GEMINI_SESSION_ID`. Each side had its own
  hermetic root. Spot checks confirmed the cases are not vacuous: matching 966-byte denies,
  18-byte allows.

  ```text
  LIVE DIFFERENTIAL: 453 cases, 0 differ (stdout+stderr+rc)
  ```

- **onFailure: block.** `tests/test-manifest-invariants.sh` passes 33 of 33, and no manifest
  changed. The exit code is still 0 on every answer.

### F1 (P2) — `_PG_BATCH` is inherited from the environment into the live hook

The refactor added `${_PG_BATCH:-0}` reads to the shared live path
(`hooks/permission-guard.sh:2900`, `:2965`). `_PG_BATCH` is assigned only inside `_pg_batch`
(`:3043`), never at top level. `_PG_BATCH_DEAD=0` is assigned at top level and is not
affected. The guard's own doctrine (`:2905`) treats the environment as settable by a
repository. Two effects follow.

1. **The variable alone** makes `_pg_prepare` set `HOOK_PLATFORM` to the empty
   `_pg_platform`, and makes every engine-path call go to the unopened fd 5. Each such call
   denies with "its engine exited 1". On Cursor every answer leaves in Claude's shape: a deny as
   `hookSpecificOutput`, an allow as `{}` instead of `{"permission":"allow"}`. Cursor's hooks
   reference, doc-cited in `platforms/cursor/README.md`, says a permission hook blocks on a
   schema mismatch, so the verdicts get stricter, not looser. R2 asks become denies on Claude.
2. **The variable plus inherited fds 5 and 6** let whoever holds fd 6 answer for the engine.
   This forged an allow for an R4 call:

   ```text
   $ printf '0\t1\nallow\n' > forged
   $ claude_bash 'gh repo delete o/r --yes' | _PG_BATCH=1 bash hooks/permission-guard.sh 5>/dev/null 6<forged
   {}
   # without _PG_BATCH: the same fds, "ask"
   ```

**Severity.** Exploiting the forge needs control of the hook's parent environment *and* its file
descriptors. A party with that already controls the host and could simply not run the hook. A
repository-set `env` reaches only the first effect, which fails closed. So this is P2, not P1.
It is still a new live-path input that did not exist before task-001.

**Fix.** Put `_PG_BATCH=0` and `_pg_platform=""` at top level, before any function runs.
Better still, also run `unset _PG_BATCH` at the top of the script. Add a guard-suite case that
runs `_PG_BATCH=1` on a Cursor payload and expects Cursor's shape and the rule's own reason.

## Q3 — reachability

**Answer: unreachable from every manifest. One invocation carries one payload, as before.**

- A grep for the two flags and `_PG_BATCH` across `hooks/hooks.json`, `platforms/`, `mod/`,
  `.claude-plugin/` and `.cursor-plugin/` finds nothing. Only the three task-001 files name
  them.
- The guard runs without arguments on every platform: Claude and Codex
  (`bash "${CLAUDE_PLUGIN_ROOT}"/hooks/permission-guard.sh`), Cursor (both events), and Gemini
  through `hooks/gemini-wrap.sh`, which forwards only the manifest's arguments, and there are
  none. OpenCode's `platforms/opencode/plugin/guard.ts:398` runs
  `execFileSync("bash", [PERMISSION_GUARD])`, whose stdio has no fds past 2.
- A payload cannot select batch mode, because batch mode needs `argv`, and the hook has none.
- **Smuggling a second payload (F8, P3, pre-existing).** A stdin holding two JSON values is
  judged by the *first* value on the fast path. A benign value first allows, and a dangerous
  value first denies, because the engine rejects the multi-value text. This is byte-identical
  on `702bbd3^` and the head, so task-001 did not introduce it. Every host sends exactly one
  object, so no model-authored text reaches this.
- **A model running the guard by hand.** A Bash call such as
  `bash hooks/permission-guard.sh --judge-batch < x` is allowed. So is the no-argument form,
  before and after task-001. Batch mode therefore adds no capability that a model did not
  already have by piping a payload into the script. Whether the engine's stamp writes
  (`write_stamps`, `write_asked`) should refuse a run that is not a host's hook is a
  pre-existing question, outside this objective.

## Q4 — ordering and desync

**Answer: no line was attributed to another line's input under a C locale. Under the default
macOS locale, the batch silently truncates (F2).**

A 24-line NDJSON file mixed hostile lines with marker lines of known verdict. Run with
`LC_ALL=C`, all 24 lines came back in order, every expectation held, and the markers after each
hostile line kept their verdicts:

| Line | Batch answer |
|---|---|
| GraphQL document, newlines escaped in JSON | ask (UNCLASSIFIED, R4), same as the single call |
| Same document, raw newlines inside the string | three lines, three denies ("not valid JSON"); the next marker is still `ask` |
| Over 1 MiB | deny, unread; the next marker is still `ask` |
| CRLF, U+2028, tab and CR in the command | ask, same as the single call |
| Escaped `\u0000` | deny (NUL) |
| Raw NUL byte | dropped by `tr`, as the hook's `read` drops it; ask |
| Blank, whitespace, `[1,2,3]`, `"host":"vim"`, `"host":7`, two objects | deny |

A driver sabotaged in a scratch copy of the tree produced the following:

| Sabotage at request 3 | Result |
|---|---|
| `os._exit(1)` | Line 3 and every later engine-path line deny ("engine exited 1"). Fast-path allows stay allows. Nothing shifts. |
| A malformed payload reaches the engine | Line 3 denies. Later lines are correct. |
| The header over-reports by one line | Both sides deadlock. Nothing prints until a 60 s alarm (F6). |

Fds 3 and 4 are opened only on the driver, and the engine's children run under
`subprocess`'s default `close_fds=True`. The bash side's fds 5, 6 and 7 are not close-on-exec,
but the per-line bash code spawns no external process, so nothing inherits them today.

### F2 (P2) — invalid UTF-8 truncates the batch, and it exits 0

`tr -d '\000' > "$T/in"` (`hooks/permission-guard.sh:3056`) runs under the caller's locale.
macOS `tr` in `en_US.UTF-8` aborts at the first invalid byte with "Illegal byte sequence".
`n_in` is then counted from the truncated file (`:3057`), so the final count check (`:3178`)
compares two truncated numbers and passes.

```text
24 lines in (default locale)  ->  rc=0, 7 lines out    stderr: tr: Illegal byte sequence
4 lines in, one invalid byte  ->  rc=0, 2 lines out    (four byte patterns, same result)
LC_ALL=C                      ->  rc=0, 24 lines out
```

The printed lines are a correct prefix, so nothing shifts. task-002's runner compares lines
read with lines printed for each shard, so a suite fails loudly rather than passing. But the
batch's own contract, the line count out equals the line count in by construction, is false,
and the exit code says success. GNU `tr` on Linux CI is byte-based and does not trigger this.

**Fix.** Prefix `LC_ALL=C` on `tr` and `wc`. Count the input lines from the raw stdin before
`tr` runs, check `tr`'s exit status, and return 2 when it fails. Add a case with one invalid
byte that asserts the line count out and the exit code.

### F6 (P3) — no deadline on the engine protocol

`_pg_engine_batch` reads fd 6 with no timeout (`hooks/permission-guard.sh:3016`, `:3020`).
A driver that over-reports, or one that wedges, hangs the batch until CI kills the job. The
driver is repository code, so this is about robustness, not an attack. **Fix:** use
`read -t "$((PG_BUDGET + 5))"` on both reads, and set `_PG_BATCH_DEAD=1` on timeout.

## Q5 — nondeterminism of tied rule ids

**Reproduced.** For `gh api -X PUT repos/o/r/contents/.github/workflows/ci.yml …`, ten single
calls of the live hook returned `ask` every time. The reason named `workflow.edit` 6 times and
`file.write.remote` 4 times. The order follows the hash seed: run without `-I` under explicit
`PYTHONHASHSEED` values, the engine is stable for a given seed and splits across seeds 0 to 9.
`-I` makes the real path ignore `PYTHONHASHSEED`. One batch process fixes a single seed for all
its lines: eight identical lines gave eight identical reasons, and that reason varied from one
process to the next.

**Root cause.** `rest_ids()` returns a `set` (`hooks/permission-guard.sh:1062`). Iterating it at
`:1272` fixes the order of `HITS`, then `JOBS`. `final = max(JOBS, key=(verdict rank, R))`
(`:2582`, `:2729`) keeps the first of a tie.

### F5 (P3) — what the tie can and cannot change

| Reads the tie | Order-invariant? |
|---|---|
| Verdict: the maximum rank over all jobs | yes |
| Delivered shape: `ask_carried` over all asking jobs, `ASK_AS_DENY` | yes |
| Call stamps and confirm stamps: all written, keyed by token and nonce | yes |
| Resolver: every job's id is passed; processes start together under one absolute deadline | yes, the set of inputs. A deadline failure on any job is a deny, whichever job it hits. |
| The resolver's only write: a host-version probe cache, independent of the id | yes |
| Reason head (`describe(final)`), "raised from", the "Not established" note, "To allow it" (`settings(final)`), "The call also reaches" | **no**, text only |
| `--classify`'s `resolver_calls` list order | **no**, ordering only |

**Blast radius.** The verdict, the id set given to the resolver and the stored state never
change. What changes is the reason the user reads. Where two tied ids carry different
settings, it also changes which "To allow it" advice they are shown. Following that advice
lifts only the named id, and the other id still gates the call, so the call is not widened.

**Recommendations.**

1. **Yes, sort deterministically, as a followup fix.** Use `sorted(rest_ids(...))` and sort
   every other `set` that feeds `HITS` (GraphQL and MCP). Add a stable final key to both
   `max()` calls, preferably a meaningful one such as the raised id first, then the id string.
2. **Yes, return to bytes after that fix,** keeping the single retry for deadline denies under
   load. Bytes compare the command text in `on \`…\``, which catches F4's swap class for free.

## Q6 — is the 150-call sample a real divergence detector?

| Property | Finding |
|---|---|
| Seeded | Yes. The fuzz suite uses `FUZZ_SEED`, default 349. The guard suite seeds each flush with its number plus 100. The same seed and line count pick the same lines. |
| Stratified | **No.** The sample is a uniform `random.Random(seed).sample` over the row indices, 150 of about 2,400 rows. It covers the classify, Claude and Codex files only, with no Cursor, OpenCode, Gemini or MCP lines. The guard suite samples 8 per flush, but it also checks each case's expected decision and a per-case needle in the reason. |
| Planted proof bites | Yes, for a decision flip: the stub that turns the third answer into an allow is named, and a short shard is refused. I also planted a Cursor answer in Claude's shape; it is caught (1 DIFF). |

### F4 (P2) — the check cannot see a divergence that keeps the decision

I ran task-002's `pg_batch_agree` unmodified, against the real hook, on five lines:

```text
batch deny reasons replaced by "its engine exited 1 …" on 4 of 5 lines  ->  AGREE 5 0  (rc 0)
batch lines 2 and 3 swapped (both deny: Claude merge --admin, Codex push --force)  ->  AGREE 5 0  (rc 0)
```

1. A batch that fails closed for its own reasons (a crashed driver, F3's bytes, the reader
   stopping) matches every true deny. On Codex, where every mutating call is a deny, a driver
   crashing on a whole family would be invisible both to the agreement check and to the fuzz
   properties, which require "ask or deny" on Claude and "deny" on Codex. A total crash is
   still caught, but only through Claude's asks.
2. An ordering desync among lines with the same decision is invisible. That is exactly the
   failure Q4 guards against.

**Fix, until F5 lands.** Add three things to the canonical judge form: the sorted set of ids the
reason names (`asks before|denied <id>` plus the "also reaches" list), the `on \`…\`` target,
and a reason class (rule, NUL, invalid JSON, transport). The class covers the batch-only
fail-closed strings: "engine exited", "gave no verdict", "batch reader stopped", "control
character" and "longer than 1 MiB". The comparison can then ignore which tied id is named
without ignoring which call was judged. Once F5 lands, compare bytes. Record the two plants
above as task-002 self-tests.

### F7 (P3) — sample coverage

Stratify the 150 picks across the corpus's (family, kind) cells and the three files, with at
least one pick per cell. Add a Cursor file and an OpenCode file to the fuzz agreement, so the
dialects with the most shape logic get a real-hook comparison.

## Method notes

- The suites ran in the task-005 worktree at `924a737`, one after another, with each log's
  `EXIT=` line read.
- The differential, desync and sabotage harnesses lived in the session scratchpad only. Nothing
  outside this file was written in the repository.
- The `PYTHONHASHSEED` run fed the engine heredoc (lines 394 to 2864) to `python3 -S` directly,
  so it is evidence about the engine, not the hook. The hook evidence is the ten single calls
  and the in-process batch repetition.

---

<p align="center"><a href="https://github.com/Tamircohen28">Have a Question?</a>&nbsp;·&nbsp;<a href="https://github.com/Tamircohen28/tamirs-superpowers/issues/new/choose">Open an Issue</a></p>
