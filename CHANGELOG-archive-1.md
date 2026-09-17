# Changelog archive (1/3): 3.6.1 – 3.4.0

Older `tamirs-superpowers` changelog entries, moved out of `CHANGELOG.md` on 2026-09-17 to keep that file a manageable size for tooling that must round-trip its full content. Same format, same content, split only by size. Continues in [CHANGELOG-archive-2.md](CHANGELOG-archive-2.md).

---

## [3.6.1] — 2026-09-02

### Fixed
- **`tests/lib/harness.sh` cleaned up nothing, leaking a temp directory per
  call.** `harness_tmpdir` appended to the `_HARNESS_TMPDIRS` array, but all 33
  callers invoke it as `d="$(harness_tmpdir)"` — a command substitution, so the
  append mutated a subshell's copy and was discarded on return. The
  `trap _harness_cleanup EXIT` then iterated an empty array and deleted nothing.
  The registry is now a file, because a write is a syscall and survives the
  subshell where a variable does not:

  ```
  bash -c 'A=(); f(){ A+=(x); echo /tmp/z; }; d="$(f)"; echo ${#A[@]}'   ->  0
  ```

  Measured before and after on one suite: `tests/test-shape.sh` left `+1` temp
  directory behind and now leaves `0`. This is what had put ~140 stray
  `tmp.XXXXXXXXXX` directories in `/tmp` by the end of a CI run.

### Changed
- **`tests/test-statusline.sh` now reports and recovers when its temp root
  vanishes, instead of aborting the suite.** Four CI jobs on 2026-09-02 have hit
  this: run 33595749097 on `aeb42caf` (on **master**), both jobs of run
  33597009636 attempt 1 on `9a7c916` (**two separate runner VMs**), and run
  33599695141 on a branch whose entire diff was `.claude/memory/*.md`. Greens
  and reds interleave inside one hour, so it is neither deterministic nor a
  clean transient.

  **The cause is still unknown, and the previous explanation shipped here has
  been withdrawn.** v3.6.0 added `: > "$TMPROOT/.keep"` on the theory that an
  empty, unreferenced directory was being reaped; the run on the memory-only
  branch then vanished a `$TMPROOT` that had the `.keep` file in it. That is the
  second mechanism claim about this bug to be falsified, so the line is gone and
  the comment now records what is known rather than a third guess.

  What replaces it is instrumentation chosen to discriminate, not to fix: a
  `SENTINEL` temp dir that is created and never touched (if it dies too, the
  sweeper is external and this repo is exonerated; if only `$TMPROOT` dies,
  something targets this suite), a startup snapshot of `$TMPDIR` diffed on the
  failure path to name every other casualty, a `ps` listing for detached workers
  left by earlier suites, and a second probe immediately after the 2s watchdog
  kill so the window is halved rather than "somewhere in the first ~2.01s".
  The suite then recreates the directory and continues — asserting statusline
  behavior is its job, `/tmp` durability is not, and hard-failing red-gated
  unrelated PRs to buy evidence already captured. The warning is repeated in the
  final summary line so it cannot scroll past.

  An audit of every destructive path in the repo (recorded in the file) found
  none that can reach a bare `mktemp` root: all are anchored to `$WORKTREE_ROOT`,
  itself recomputed as `"${HOME}/.claude/worktrees"`; the retirement `find`
  requires depth 2 plus a `.git` entry; the only `find -delete` is `-type f`.


### Added
- **`SUPERPOWERS_WORKTREE_CLEANUP=0` disables stale-worktree retirement.** Every
  hook invocation starts a *detached* `rm -rf` pass over `~/.claude/worktrees`
  that outlives the hook by design, so a test suite that runs a hook is running
  alongside an ownerless `rm -rf` for the rest of its life. The pass is anchored
  to `$WORKTREE_ROOT` and cannot reach a suite's own temp dir — that was
  confirmed while chasing the flake above — but it is exactly the sort of thing
  a `ps` listing turns into a false lead. `make test-hooks` now sets the guard
  for the whole loop; `tests/test-worktree-objective.sh` unsets it for the three
  cases that assert on the default behaviour, which is also what proves the
  guard is wired to the pass and not merely a correct predicate nobody calls.

## [3.6.0] — 2026-09-02

### Added
- **Statusline: a `spend` line when a Claude apps gateway reports a spend
  limit.** Claude Code 2.1.251 added `rate_limits.spend_limit`
  (`used_percentage`, `resets_at`) to the statusline payload — present only
  behind a gateway that has a spend limit configured and whose `resets_at`
  has not passed. `scripts/statusline.sh` renders it as a fourth line using
  the exact same only-when-present pattern already used for the 7-day line,
  so nobody outside that configuration sees any change. Documented in
  [statusline](docs/engineering/statusline.md). Covered by two new cases in
  `tests/test-statusline.sh`: the line renders when the field is present,
  and it is absent (not merely empty) when it is not.
- **`session-init.sh`: a one-line heads-up when a resumed session's prompt
  cache has likely expired.** Claude Code 2.1.251 added
  `prompt_cache_likely_expired`, `context_tokens`, and
  `estimated_cache_write_usd` to `SessionStart` payloads for `resume`/`fork`.
  The hook now adds a note to `additionalContext` when the cache is likely
  cold, naming the token count and estimated re-cache cost when the host
  supplies them, so the first request's higher cost and latency is
  explained up front instead of showing up afterward as an unexplained
  spike. New `tests/test-session-init-staleness.sh` (6 cases): fires on a
  stale resume including both detail fields, stays silent on a warm resume,
  and stays silent on plain startup where none of these fields exist.

### Changed
- **Platform target: Claude Code 2.1.252** (from 2.1.251), plus the two
  adoptions above. The 2.1.252 delta is "bug fixes and reliability
  improvements" per the official changelog (a Bash task-output-swap failure
  on some Macs, `always allow` not saving in a project with no
  `.claude/settings.local.json` yet, Remote Control stalls hosted by Claude
  Desktop/VS Code, oversized background-task failure notifications) — all
  host-side, nothing with a plugin-side surface.

  Re-reviewing 2.1.251 turned up two items the last cycle had bucketed into
  its generic "no plugin-side surface" list without naming: the
  `rate_limits.spend_limit` statusline field and the `SessionStart` resume
  staleness / estimated re-cache cost fields, both adopted above. A third —
  the plugin-marketplace-refresh race that could start a background session
  with zero plugin skills — has no plugin-side fix available (it is a host
  bug, fixed host-side in 2.1.251), but is genuinely relevant given how much
  of this repo's own orchestration leans on background sessions and
  worktree isolation; documented in
  [troubleshooting](docs/user/troubleshooting.md#skills-do-not-appear-after-installing)
  next to the existing 2.1.246 `0 skills` entry, since both present the same
  symptom ("no skills") for a different underlying reason. Re-reviewed and
  still not adopted: `PreModelSwitch`/`PostModelSwitch` hook events (2.1.251)
  — nothing in this repo's orchestration currently needs to gate or observe
  a model switch, so wiring one would be dead surface; noted in
  [CLAUDE.md](CLAUDE.md) for Tamir's judgment rather than wired speculatively.
  `experimental.cacheTtl` agent frontmatter (2.1.248) was re-checked against
  all ten `agents/*.md` — still nothing here needs a cache TTL narrower than
  the session default, same conclusion as the 2.1.250 cycle.

  `validated_against` advances to 2.1.252. This cycle's automation
  environment had a live `claude` CLI (2.1.252) — the first live-CLI cycle
  since 2.1.247 — so `claude plugin validate .` and `bash scripts/doctor.sh .`
  were run for real (both passed) instead of relying on the changelog +
  npm-registry method alone; `platform-targets.json`'s `verification_method`
  records this. `scripts/check-platform-targets.sh`,
  `check-feature-equivalence.sh`, `check-doc-claims.sh`,
  `check-version-truth.sh`, `check-capability-registry.sh`,
  `check-marketplace-schema.sh`, and `check-github-policy.sh` were run
  directly and passed; every `tests/test-*.sh` file, including the two new
  ones above, passed when run directly — except `tests/test-statusline.sh`,
  which failed once here — for a reason that turned out not to be in the test
  file at all. **Correction:** the diagnosis first written up in this entry —
  that `run_with_timeout`'s backgrounded watcher `( ... )` subshell inherits
  the suite's own `trap ... EXIT` and deletes the shared tmpdir on its way out
  — is wrong. A minimal repro across six trap/subshell variants on bash 3.2.57
  and 5.3.15 shows bash does **not** run an inherited EXIT trap in a subshell;
  the tmpdir survived every one. What the failure *is* has since been narrowed
  but not solved — see the `tests/test-statusline.sh` entry under **Fixed**
  below; the "one-off flake, no patch warranted" call recorded here while this
  entry was being drafted was also wrong, and the patch it declined has now
  been made. Every assertion in the file, including the two new spend-limit
  cases, passes.
- **Platform target: Claude Code 2.1.257** (from 2.1.252; 2.1.253–2.1.256 were
  never published). `CLAUDE.md`'s Subagents bullet now also names
  `CLAUDE_CODE_SUBAGENT_MODEL_FORCE`, which — unlike `CLAUDE_CODE_SUBAGENT_MODEL`
  — overrides every `agents/*.md` frontmatter `model:` pin and every per-spawn
  model, so the 2.1.251 guarantee that a pinned agent model always wins no
  longer holds unconditionally: it holds unless `_FORCE` is set. The auto-mode
  Containment Escape rule (cloud metadata-credential fetches, egress evasion,
  cross-tenant reach no longer auto-approved) composes automatically with
  `platforms/claude/settings.d/auto-mode.json`'s `autoMode.soft_deny` — that
  file's docker-containers rule sits alongside `"$defaults"`, which is exactly
  where a new built-in rule like this lands, so nothing in that fragment needed
  to change. `permissions.blockReadsOutsideWorkingDirectories` was reviewed and
  left off: it is a personal auto-mode preference, not a plugin default, and
  `platforms/claude/settings.d/` mirrors what is actually captured from the live
  machine rather than prescribing new settings. `/doctor`'s stale-sandbox-mask
  warning is Claude Code's own diagnostic, not this repo's `scripts/doctor.sh`
  (a plugin-install health report); noted in
  [doctor.sh](scripts/doctor.sh) as a complementary, not overlapping, check.
  `/fork`'s worktree-briefing/prompt-cache fix is about Claude Code's own
  native `/fork` briefing message, a different mechanism from this repo's
  `hooks/session-init.sh` `SessionStart` `additionalContext` (which has always
  arrived as context at session start, fork or not) — reviewed, no change
  needed. The sandboxed-git-in-a-linked-worktree and
  worktree-isolated-Bash-loop fixes are inside Claude Code's own sandbox
  verifier; this repo's `hooks/enforce-worktree-edits.sh` only judges
  `Edit`/`Write`/`MultiEdit`/`NotebookEdit` targets and never re-implements
  Bash-loop worktree verification, so there is nothing here for the fix to
  make redundant. No plugin-declared component path
  (`.claude-plugin/plugin.json`'s `skills`/`mcpServers`, or `agents/`, or
  `hooks/`) is a symlink, so the new plugin-symlink-path rejection changes
  nothing here; the `.gemini/skills/*` symlinks are a different target's
  (Gemini CLI's) surface, out of scope for this review. No `.claude/settings.json`
  or `.claude/settings.local.json` exists in this repo, so the
  `defaultMode: "bypassPermissions"` project-settings change is not
  applicable; `platforms/claude/settings.d/defaults.json`'s `bypassPermissions`
  renders into the **user's** `~/.claude/settings.json`, which this change does
  not touch.

  `validated_against`/`latest_known` advance to 2.1.257. `verified_on` →
  2026-09-02. This cycle's automation environment had a live `claude` CLI —
  and it reported exactly `2.1.257`, matching the changelog target — so
  `claude plugin validate .` and `bash scripts/doctor.sh .` were re-run for
  real (both passed: marketplace manifest valid; all capability rows
  native/native-experimental/partial as expected) instead of the
  changelog + npm-registry method alone; `platform-targets.json`'s
  `verification_method` records this. `scripts/check-platform-targets.sh`,
  `check-feature-equivalence.sh`, `check-doc-claims.sh`,
  `check-version-truth.sh`, `check-capability-registry.sh`,
  `check-marketplace-schema.sh`, `check-github-policy.sh`, and
  `check-agent-drift.sh` were run directly and passed; every
  `tests/test-*.sh` file passed when run directly, `tests/test-statusline.sh`
  included — see the correction above for why last cycle's "racy harness"
  note was itself wrong.

### Fixed
- **`tests/test-statusline.sh` no longer leaves its tmpdir empty, and says so
  if it disappears anyway.** Three CI jobs have failed with the suite's
  `$TMPROOT` gone mid-run — run 33595749097 on `aeb42caf` and both jobs of run
  33597009636 attempt 1 on `9a7c916`, all on ubuntu-24.04 image
  20260823.283.1. Attempt 2 of the same commit, unchanged, went green. **The
  root cause is not established.** What is established: no code in this repo
  can delete a bare `/tmp/tmp.XXXXXXXXXX` — every destructive path is rooted
  under `$HOME/.claude/…` or the script's own `mktemp` output, and
  `scripts/statusline.sh` contains no `rm`, `mktemp`, `find` or `trap` at all;
  the runner version is not the discriminator (2.337.0 on both failures and
  passes); and the `rm: … Directory not empty` line from
  `cleanup_stale_worktrees` appears on green runs too, so it is a constant, not
  the trigger. The one property that distinguishes this suite from the eight
  other tmpdir-using suites is that its ~2s watchdog self-test leaves the
  directory **empty and unreferenced** for that whole window, where every other
  suite writes a child within milliseconds. So the fix removes that property —
  `: > "$TMPROOT/.keep"` — rather than claiming a mechanism. A `[ -d "$TMPROOT" ]`
  assertion after the self-test turns a recurrence into one named failure with
  `ls -ld /tmp` attached, instead of five cases failing as bogus timeouts.
  Prevention, not diagnosis; the comment in the file says exactly that.


## [3.5.0] — 2026-09-01

### Fixed
- **The protected-file guard was blind to `Bash`: it matched editing TOOLS, not
  file PATHS.** `guard-sensitive-files.sh` was wired only to
  `Edit|Write|MultiEdit|NotebookEdit|StrReplace` and read a `file_path` out of
  the payload, so every path it protected — lockfiles, `.github/workflows/`,
  `.yarn/releases/`, generated shadcn UI, gitignored build output — stayed
  writable through `cat > f <<EOF`, `sed -i`, `tee`, `cp` or a shell redirect.
  No prompt, no override, no log entry.

  The guard's subject is an agent, and agents have Bash, so the bypass was
  available to precisely the actor the control exists to constrain — by
  default, with no intent to circumvent. An agent that simply preferred Bash
  for edits never saw the guard and never learned the file was protected, while
  the agents that used `Edit` and stopped were the only ones it cost anything.

  The hook now runs on `Bash` as well, and decides on the write TARGET. A new
  `hooks/lib/write-targets.py` parses the command and reports only operands in
  a writing position: redirections, `tee`, `sed -i`/`perl -i`/`awk -i inplace`,
  `cp`/`mv`/`install`/`rsync`/`ln`, `touch`/`truncate`, `dd of=`, `curl -o`,
  `wget -O`, `rm`. It also follows a literal `cd` so relative targets resolve
  against the right repo.

  It deliberately does **not** grep the command for protected paths — that is
  the defect `docker-guard.py` already has on record, where a read-only `grep`
  and a `git commit -m` were blocked for containing a matching literal. Because
  a path is only a target when it sits in a target position, a path named in a
  `grep` pattern, a commit message, a `sed` script or a heredoc body is not a
  finding. `tests/test-write-target-guard.sh` (38 assertions) holds both halves.

  **What it still cannot decide, it says.** Inline interpreter code
  (`python3 -c`, `eval`, code piped into a shell), runtime-built targets
  (`> "$OUT"`, `xargs`, `find -exec`, globs) and paths inside a patch produce a
  non-blocking advisory naming what went unchecked, rather than an allow that
  reads as "nothing protected was touched". Ordinary programs that merely
  *could* write (`make`, `npm install`, a checked-in script) are not reported —
  at that breadth the warning fires on everything and means nothing. Closing
  those needs a git/CI check on the modified path, which observes the outcome
  instead of the mechanism; this hook is the fast-feedback half, not the
  binding one.

- **Five ways past that guard, found in review of it.** None needed any attempt
  to evade the guard; each is a shape an agent writes by habit, and each left
  the guard installed and silent — the failure mode the guard exists to remove,
  reproduced inside the guard itself.

  - **The hook matched the tool name `Bash` only.** `write-targets.py` had
    always handled a `Shell` payload, and the concurrency hook next to it
    already matched `Bash|Shell`; only this matcher was narrow. On a host that
    names the tool `Shell`, `tee yarn.lock` kept the entire pre-guard bypass.
  - **A wrapper's own options were not consumed, so the first one became the
    command.** `env -i tee yarn.lock`, `nice -n 10 tee yarn.lock` and
    `sudo -u root tee yarn.lock` each parsed as running `-i` / `-n` / `-u`,
    which write nothing — so a real lockfile write was reported as no write at
    all. Each wrapper's options are now consumed per its documented form.
    `sudo -R`/`-D`, `env -C` and `env -S` are deliberately NOT consumed: the
    first three move the directory a relative target resolves against and the
    last hides a whole command line in one argument, so they report UNSURE
    instead of answering confidently against the wrong frame.
  - **A value-taking option's value counted as an operand.** In
    `install -m 0644 src yarn.lock` the mode `0644` read as a second SOURCE,
    which made the last operand look like a DIRECTORY — the guard reported
    writes to `yarn.lock/0644` and `yarn.lock/src` and never reported the write
    to the lockfile. Options are now parsed per command; for the commands whose
    operand POSITION decides the destination (`cp`, `mv`, `install`, `ln`,
    `rsync`) an option the parser cannot size reports UNSURE rather than
    guessing. This also removed a false positive — `cp -t DIR a b` used to
    invent a target named after the directory — and fixed `sed -i -e`,
    `perl -0777 -i -pe`, `touch -r`, `truncate -s` and `awk -v`.
  - **A `cd` inside `( … )` was never undone.** One global cwd, not restored at
    the `)`, resolved `(cd /tmp); echo x > src/components/ui/button.tsx`
    against `/tmp` — so the guard checked a different file from the one Bash
    wrote, and cleared it. Paren depth is now tracked with a stack, a `cd` in a
    pipeline component is scoped to it, and an unbalanced `)` leaves the cwd
    unknown (UNSURE for later relative writes) rather than wrong.
  - **The plugin version was not bumped.** Marketplace installs cache hooks
    against the manifest version, so shipping changed hook behaviour under the
    same `3.4.0` would leave every installed copy running the old hook while
    `/plugin update` reported it current — installed and absent at once. The
    canonical version is now `3.5.0` across every manifest.

  `tests/test-write-target-guard.sh` grew from 38 to 73 assertions; 20 of them
  fail against the code as it stood before this change.

### Fixed
- **`pr-dev`'s scripts resolved the repository from the current directory, so a
  wrong cwd produced a plausible answer about a different repository instead of
  an error.** All four (`fetch-pr-state.sh`, `resolve-merge-policy.sh`,
  `resolve-thread.sh`, `cleanup-after-merge.sh`) now accept
  `--repo <owner>/<name>` (and `--repo=<slug>`), which pins `GH_REPO` for every
  `gh` call they make — including `gh api repos/{owner}/{repo}`.

  This is a wrong *answer*, not a failure, which is why it goes unnoticed: the
  same PR number exists in a sibling checkout and comes back looking entirely
  legitimate. It happened three times while developing the ruleset fix above,
  once returning a PR that had been merged in July — which reads as "already
  merged, nothing to do". An agent whose shell resets to a different directory
  between commands hits this constantly.

  A slug without a `/` is rejected with exit 2 rather than silently ignored, and
  omitting the flag keeps the existing cwd inference, so nothing changes for
  callers already running from the right directory.

### Fixed
- **`goal-condition-lint.sh` could be silently disarmed, and mishandled
  `/GOAL`.** Three defects, two of them the same fail-open shape the hook was
  written to prevent — found by salvaging the `goal-condition-guard` prototype
  (PR #95), which had solved them first.

  1. **A check that could not run exited 0 in silence.** No `jq`, a malformed
     payload, or a renamed field all produced a hook that looked installed and
     screened nothing. It now prints `CHECK DID NOT RUN — <why>` on stderr and
     still exits 0, so the user's prompt is never erased by a broken guard but
     the gap is visible. A *present-but-empty* prompt stays quiet — that is a
     real state, and crying wolf on it would train people to ignore the warning.
  2. **The prompt was read only from `.prompt`.** `.user_input` and
     `.user_message` both appear in published schema descriptions, so a field
     rename would have disarmed the guard while it reported healthy. All three
     are now read, and a payload carrying none of them is loud rather than
     treated as "no prompt".
  3. **`/GOAL` leaked the command word into the condition.** The command match
     is case-insensitive but the strip was a lowercase literal, so uppercase
     invocations kept `/GOAL` inside the condition: the menu's rewrites came out
     mangled, and `/GOAL force: …` was **blocked despite the escape hatch**.
     Now stripped with explicit character classes — sed's `I` flag is GNU-only
     and silently does nothing on the BSD sed shipped with macOS.

  `tests/test-goal-condition-lint.sh` 45 cases (was 34): the three field names,
  all four cannot-run paths, both quiet-by-design paths, and uppercase parity
  including the `force:` regression.

### Fixed
- **`resolve-merge-policy.sh` read only classic branch protection, so every
  ruleset-governed repository looked unprotected.** GitHub has two independent
  protection systems and they do not shadow each other: classic branch
  protection, and rulesets (whose effective result for one branch is
  `/repos/{o}/{r}/rules/branches/{b}`). The resolver queried only the classic
  endpoint, which answers **404 "Branch not protected"** on a ruleset-governed
  branch — so it reported `required_checks: []`, `requires_review: false`,
  `strict_branch_update: null` for a branch that actually required nine status
  checks and a pull request. `pr-dev`'s readiness gate then had no required
  checks to wait for, and the loose/strict branch-freshness rule took the loose
  path without ever reading the setting. Observed on this repository, whose
  `master` has been ruleset-governed since 3.2.0 landed the org rulesets.
  Both sources are now read and unioned, and the new `protection_source` field
  (`classic` | `rulesets` | `classic+rulesets` | `none`) records which actually
  answered, so a wrong reading is visible instead of inferred.

- **The head-branch read had the same bug with a destructive consequence.** A
  ruleset-protected head answered 404 and was classified "unprotected — safe to
  delete after merge", so `pr-dev` would delete a governed branch. Deleting is
  not recoverable from the PR, so this now fails closed: an unreadable rules
  response keeps the branch and says the read failed, rather than implying the
  branch is unprotected.

- **`jq`'s alternative operator treats `false` as empty, so an explicit
  `strict: false` was reported as `null`.** `.required_status_checks.strict //
  "null"` yields `"null"` when strict is genuinely `false`, meaning every
  classic-protected repository with strict OFF reported "unknown" and reached
  the loose path by accident rather than by reading the setting — the right
  answer for the wrong reason, and the *wrong* answer had the default been
  strict. Replaced with an explicit three-way test.

- **A `pull_request` rule requiring 0 approvals is no longer reported as
  `requires_review: true`.** It requires a pull request, not a review; treating
  the block's presence as an approval requirement makes `pr-dev` wait for an
  approval nothing will ever demand.

  Covered by 11 new cases in `tests/test-shape.sh` (125 total), including the
  classic/ruleset union, the source labelling, both `strict` paths, the
  0-approval case, the destructive head-branch case, and the fail-closed
  behaviour when the rules endpoint errors.

- **`check-doc-claims.sh` asserted the README's generated badges but not the prose
  beside them.** The per-target badges are built from `platform-targets.json`; the
  support table three lines below them is hand-typed. Nothing derived that prose, so
  nothing caught it drifting: the Cursor row read `validated 3.16.17` for two minor
  versions while the badge above it correctly read `3.18.9`, and every check stayed
  green — the badge was asserted, the target count was asserted, the version in the
  sentence was not. The check now compares every `validated <x.y.z>` claim in Markdown
  prose against the same `validated_against` the badge is generated from, naming the
  file, the line, and both values. A target pinned `"unknown"` asserts nothing, which
  is the honest state for one that is declared but not yet validated.
- **`check-doc-claims.sh` sourced its own library out of the tree it was auditing.**
  `. "$ROOT/scripts/lib/registry.sh"` resolved against the *target* root rather than the
  script's own directory. That works only while the two are the same checkout: pointed at
  another repo (which is how `repo-standards` invokes it) or at a synthetic root, the `.`
  failed under `set -e` and the run died before a single claim was checked. It now
  resolves from `$SCRIPT_DIR`.
- **`check-doc-claims.sh --self-test` was failing on master and nothing ran it.** Five of
  its seven cases had been reporting failure for the library-resolution reason above —
  not for anything they were written to test — and no Makefile target, workflow or test
  file invoked the flag, so the rot was invisible. `make check-doc-claims` now runs the
  self-test before the real check, and the suite covers the new version assertion in all
  three positions: stale prose fails, correct prose passes, and a stale value quoted
  inside a fence stays exempt. 10 cases, all passing.

### Changed
- **README's Cursor row now reads `validated 3.18.9`**, matching `platform-targets.json`
  and the badge. It had said `3.16.17`.

## [3.4.0] — 2026-08-31

### Added
- **`goal-condition-lint.sh` — refuse to arm a `/goal` condition that cannot
  terminate.** Claude Code's built-in `/goal` evaluator re-judges its condition
  from scratch on every turn-end, with no memory of having already blocked and
  without consulting `stop_hook_active`. A condition that is unsatisfiable *in
  principle* therefore does not fail once — it blocks every turn until the
  harness block cap trips or the user runs `/goal clear`. It has happened twice:
  21 consecutive blocks on 2026-08-17, ~15 on 2026-08-31.

  The hook refuses two families of phrasing, both with no terminating form:
  *"do not yield" / "don't stop"*, which makes **stopping itself** the violation
  so no world-state satisfies it; and unbounded scope (*"all remaining work"*)
  with no carve-out, which counts third-party-blocked work as still outstanding
  so it stays false no matter what the session does. Everything else passes,
  including an unbounded scope that already carries a carve-out.

  **Why it blocks rather than advises.** An advisory version was tried first and
  demonstrably loses: `/goal` injects *"treat the condition itself as your
  directive and do not pause to ask the user what to do"* in the same turn, and
  `additionalContext` asking the model to stop and question the condition is
  outranked by that. `goal-compact-reminder.sh` fired correctly on 2026-08-31
  and was ignored for exactly this reason. Preventing the prompt from being
  processed is the only intervention that survives the conflict.

  **The block message is the menu**, in the shape of the `decision` skill: a
  one-line diagnosis, two ready-to-paste rewrites derived from the user's own
  wording, a keep-as-is escape (`/goal force: <condition>`, which arms
  verbatim), and a free-form option. It is text rather than an
  `AskUserQuestion` picker because the docs are explicit that a blocked
  `UserPromptSubmit` prompt is *erased* and Claude never runs — so there is no
  turn in which to render one, and `additionalContext` cannot accompany a block.

  **It blocks via stderr + `exit 2`, not a JSON decision field.** A JSON form
  was written first and withdrawn. The docs carry a decision-control JSON
  example for `PreToolUse` (`permissionDecision` / `permissionDecisionReason`,
  which is also what `lib/hook-output.sh` emits) but none for
  `UserPromptSubmit`, and two readings of the same page produced two different
  field spellings for this event, neither quotable. A hook whose entire job is
  to block must not depend on a field name nobody can cite — an unrecognised key
  fails **open**, silently, exactly when the guard matters. The exit-2 row is
  quoted verbatim in the docs ("Blocks prompt processing and erases the
  prompt") and needs no schema at all.

  Covered by `tests/test-goal-condition-lint.sh` (32 cases). The pass cases
  deliberately outnumber the block cases: a false positive here costs the user a
  workflow they cannot run at all, so near-miss phrasings, both real incident
  strings verbatim, the `force:` override, hostile quoting, and the fact that
  the menu's own recommended rewrite passes the hook are all asserted.

### Changed
- **Platform target: Claude Code 2.1.247** (from 2.1.233). Docs-only bump — no shipped
  plugin content changed. This is the first review of the Claude Code delta against the
  repo's current tree (post `[3.0.0]`–`[3.3.0]`, i.e. `core/`, `rules/`, the six-surface
  registry, and `platforms/claude/settings.d/` all exist now, none of which existed when
  the previous nightly review last ran against this branch). Reviewed 2.1.234 through
  2.1.247:
  - **2.1.234 — `CLAUDE_CODE_PROJECT_DIR_NAME`.** `CLAUDE.md`'s Project memory section
    now documents pinning the auto-loaded transcript directory name instead of relying on
    the path *derived* from the clone's absolute location, which shifts per
    machine/username and breaks if the clone moves; the restore command prefers the pin
    when set. Also reviewed, host-side with no plugin change needed: the GitLab MR badge
    (this repo is GitHub-hosted), auto-continue on usage-limit reset and
    account-email-only identification, `selection:clear`, `/permissions`/`/add-dir`
    usable mid-turn, Remote Control and `SendMessage`/`ListAgents` session-list fixes, the
    claude-api skill's context reduction (no `claude-api` skill bundled here), removal of
    the "Default teammate model" setting (the six `agents/*.md` are declarative, not
    per-teammate model call sites), and the Windows NT-namespace path-read hardening.
  - **2.1.235 — nothing adopted.** The opt-in `spellcheck` setting, the Agent tool's
    clearer `subagent_type` error, and UI/dialog/markdown-rendering polish are
    host/editor-side. `spellcheck` is a personal editor preference captured from the
    maintainer's live machine via `scripts/capture-config.sh`, not something this
    automated review adds speculatively on Tamir's behalf — noted for Tamir's judgment in the PR description.
  - **2.1.236 — nothing adopted.** `ANTHROPIC_DEFAULT_MODEL`, `notify_when_idle` for
    cross-session `SendMessage` (no skill or hook here polls another session's idle state
    for it to replace), and the macOS sandbox wildcard-deny precedence fix (no
    `sandbox.filesystem.denyRead` entries in this repo's settings fragments) are reviewed
    and not applicable. `ANTHROPIC_DEFAULT_MODEL` is the same kind of personal-preference
    setting as `spellcheck` above — noted for Tamir's judgment in the PR description rather than added.
  - **2.1.237 — nothing adopted.** The built-in "Concise" output style and its
    prompt-caching fix for gateway/custom-base-URL sessions: this repo ships no
    output-style file and none of the settings fragments set one.
  - **2.1.238 — nothing adopted.** `keybindingFlavor` (personal preference, same
    treatment as `spellcheck`); `headersHelper` for marketplace/catalog and MCP entries
    (`.mcp.json` declares one plain `stdio` `github` server with no headers to mint); the
    output-style mid-session drift fix (no output style here); the MCP elicitation
    URL-length fix and the stdio `server/discover`-before-`initialize` fix (this repo's
    one MCP server is a local `stdio` process this session launches, not one Claude Code
    itself must discover); `claude mcp list`/`get` showing disabled servers.
  - **2.1.239 — `name@synced` documented.** A cloud-synced copy of this plugin shows up
    as `tamirs-superpowers@synced` and never overrides a marketplace install of the same
    name — documented in the install guide's Update section. `/claude-api upgrade` (no
    `claude-api` skill here) and Windows cross-session messaging (host platform support)
    are reviewed and not applicable.
  - **2.1.240 / 2.1.241 — bug fixes and reliability improvements only**, per the official
    changelog, with nothing to adopt or review.
  - **2.1.242 / 2.1.244 — no separately documented changes.**
  - **2.1.243 — three items adopted, several reviewed and not applicable.** Adopted:
    `/tasks` and the agent detail dialogs now show each subagent's model and effort level
    — useful for spot-checking `orchestrate-dev`/`worker-dev` fan-outs, noted in
    `CLAUDE.md`'s Subagents bullet; the fix for background subagents not waking when
    their last background Bash task finished, noted in the same place so a fanned-out
    worker that seemed to hang isn't mistaken for a bug in this repo's orchestration; and
    the new `managed` connector marker in `/mcp`/`/plugins`, documented in the install
    guide alongside the `name@synced` note above (this plugin is never installed as a
    claude.ai-managed connector, so it never shows the marker on that basis alone). Also
    genuinely relevant and reviewed with no change needed: the auto-mode fixes (the git
    status check can no longer be fooled by `status.showUntrackedFiles=no`; Monitor allow
    rules are set aside while auto mode is active; auto mode's classifier now matches
    Claude-API defaults on Bedrock/Vertex/Foundry) — this repo configures
    `autoMode.soft_deny` in `platforms/claude/settings.d/auto-mode.json`, so these
    reliability fixes affect sessions that use it, but none required a config change;
    and the cross-session-messaging fix for user namespaces/rootless containers, relevant
    given this repo's multi-agent handoff workflows use `SendMessage`/`ListAgents`.
    Reviewed and not applicable: the hook `if`-condition command-substitution fix (
    `hooks/hooks.json` has no `if` conditions, only `matcher` patterns); the
    plugin-dependency-with-`marketplace`-field `--plugin-dir` fix (this repo's own
    `.claude-plugin/marketplace.json` declares one plugin with no `dependencies` field);
    the `/reload-plugins` LSP-tool fix (no LSP plugin here); `--agents` JSON validation
    (no command here launches with `--agents`); `modelPicker`, `promptCacheTtl`/
    `subagentPromptCacheTtl`, and `modelPricing` (all personal/org preference or billing
    settings, not this pass's call to add); the `/usage` Loops breakdown, keyless Console
    sign-in, and `/web-setup` tip (host UI, no plugin surface).
  - **2.1.245 — a Linux glibc 2.44 startup crash fix.** Host binary issue, no plugin
    surface.
  - **2.1.246 — two items adopted, several reviewed and not applicable.** Adopted: a
    subagent that stops at its own `maxTurns` limit now returns output marked `partial`
    with a hint to continue it via `SendMessage` — noted in `CLAUDE.md`'s Subagents
    bullet next to this repo's own `completed`/`partial`/`failed`/`blocked` handoff
    vocabulary, since a `maxTurns`-truncated worker now surfaces the same `partial`
    signal `worker-dev` already treats as "decide, never quietly integrate around it";
    and the `/reload-plugins` fix for plugins that declare skills under
    `skills/*/SKILL.md` relative to a declared root — this plugin's own `skills` array in
    `plugin.json` is exactly that shape (`./skills/dev-workflow` → `start-dev/SKILL.md`
    one level down), so pre-2.1.246 `/reload-plugins` could report `0 skills` for this
    install; documented as a known, now-fixed failure mode in
    `docs/user/troubleshooting.md`. Reviewed and not applicable: the wildcard-before-
    subcommand Bash allow-rule warning (no rule in `platforms/claude/settings.d/
    permissions-allow.json` has a wildcard positioned before a literal subcommand token);
    the Auto Mode tab in `/permissions` (this repo configures `autoMode.soft_deny` via
    `platforms/claude/settings.d/auto-mode.json`, a settings file, not the interactive
    `/permissions` UI); the dynamic-workflow subagent-restart confirmation (this repo's
    own orchestration is `Agent`-tool fan-out under `orchestrate-dev`/`worker-dev`, not
    Claude Code's native Workflow construct); the plugin-cache duplicate-SHA-directory
    fix, `claude plugin update` by bare name, and the `keybindings.json` unknown-action
    fix (host-side, no plugin surface); the skill-frontmatter-name-doubling fix (no
    `SKILL.md` here has a `name:` that already includes a `<plugin>:` prefix); the
    plugin.json-BOM install fix (`.claude-plugin/plugin.json` has no byte-order mark);
    the `${CLAUDE_PLUGIN_ROOT}`-in-hook-errors fix (informational — this repo's hooks
    already reference `${CLAUDE_PLUGIN_ROOT}` correctly, the bug was only in how errors
    *displayed* the path); the MCP `requiresUserInteraction` permission-prompt fix (this
    repo's one MCP server is a plain `stdio` process with no such flag); non-interactive
    auto-continue on a cut-off response and `/code-review`'s Bedrock/Vertex/Foundry
    self-start (host/session behavior); and `/goal`'s three-check-ins-per-goal cap
    (informational — no hook here polls or counts `/goal` check-ins).
  - **2.1.247 — four items adopted, several reviewed and not applicable.** Adopted: a
    subagent whose first model call 404s now falls back through the session's own
    fallback model chain with a detailed error instead of dying outright — the same
    reliability class as the two 2.1.243/2.1.246 subagent fixes above, noted next to them
    in `CLAUDE.md`'s Subagents bullet; the fixes for hook/background-task error output
    overflowing the conversation with a "Prompt is too long" error and for unbounded
    memory growth on repeated output-file write failures, noted in `CLAUDE.md`'s Hooks
    bullet given this plugin wires 25 hook scripts across nine lifecycle events (no hook
    here needed a change — none write to an unbounded log file — but the fix directly
    covers this repo's hook surface); the Bash sandbox fix for a dotfile-managed symlink
    being deleted when repointed outside the writable area, documented in
    `rules/dev/plugin-version-bump.md` next to the exact symlink workflow it protects
    (`ln -s /path/to/your/clone ~/.claude/plugins/cache/.../X.Y.Z`); and the default
    collapse of inbound cross-session peer messages to a one-line preview (Ctrl+O
    expands), documented in `docs/user/cross-platform-workflow.md`'s existing
    version-tagged `SendMessage`/`ListAgents` callout. Also genuinely relevant and
    reviewed with no change needed: the Bash-permission-prompt tip pointing at auto mode
    (this repo already configures `autoMode.soft_deny`); the fix for shell commands in
    background sessions logging internal errors or misleading exit codes (this repo's
    `worktree-create.sh` and `capture-task-slug.sh` both install dependencies in the
    background); and Bedrock/Vertex/Foundry sessions now being told explicitly when an
    MCP server fails to connect (this repo's one MCP server, `.mcp.json`'s `github`
    entry, is a plain `stdio` process that can fail to launch). Reviewed and not
    applicable: `SendFeedback` and `feedbackDrafts` (host feedback-reporting feature, no
    plugin surface); the enhanced `spinnerTipsOverride` (`{id, text, cooldownSessions,
    priority}`, `tipsFile`, `label`) and `/claude-api cost-optimize` plus the `/claude-api`
    skill's Admin API coverage (this repo ships no custom tip config and no `claude-api`
    skill, same as every earlier cycle); the arrow-key/Enter input-sequence, non-Latin
    keyboard Ctrl-shortcut, and split mouse-report-text-insertion fixes, `/terminal-setup`
    overwriting Zed's `keymap.json` (no Zed integration here), `/rename`'s silent-confirm
    bug, `/compact`/"Summarize from here" system-prompt fix, the background-session
    "opening…" hang, `/install-github-app` SSH messaging, the version-less
    marketplace-cache-directory fix (`plugin-version.json` is this plugin's canonical,
    always-present version source — it is never installed version-less), Remote Control
    working-tree-diff reporting, self-hosted-runner status timing, first-run managed-
    gateway connectivity, cloud-session permission-mode display and container-restart
    silence, the plugin-marketplace control/invisible-character hardening (this repo's
    `marketplace.json` and `plugin.json` carry no such characters), the Sonnet 5
    auto-compact window widening to the full 1M context, terminal-hyperlink plain-text
    rendering, the prompt-footer PR-badge refresh-skip, and the three sign-in/analytics
    changes (managed-gateway analytics default, `surface=claude_code` identification,
    org sign-in exiting early on unreadable managed settings) — all host UI, terminal, or
    account/session infrastructure with no plugin-side surface.
  - `validated_against` advances to 2.1.247 by the same changelog + npm-registry method
    already used for this target (`verification_method` in `platform-targets.json`) —
    and, for the first time since the `[3.0.0]`–`[3.3.0]` refactor, this cycle's
    automation environment had a live `claude` CLI at exactly 2.1.247, so
    `claude plugin validate .` and `make agent:check` were run for real and both passed.
    (`.claude/skills/run-tamirs-superpowers/smoke.sh` and the aggregate `make test-hooks`
    loop did not complete in this environment — timing out well past their normal
    runtime — while every individual `tests/test-*.sh` file run directly passed; noted
    for Tamir as environment-specific test-runner flakiness to look at, not a plugin
    regression.)

- **Platform target: Claude Code 2.1.251** (from 2.1.247, extending the review above).
  Docs-only bump — no shipped plugin content changed beyond documentation. Reviewed
  2.1.248 through 2.1.251:
  - **2.1.248 / 2.1.250 — nothing adopted.** `--restricted`, `experimental.cacheTtl`
    agent-frontmatter field (no agent here needs a cache TTL narrower than the session
    default), self-hosted-runner client labeling, managed-settings load diagnostics,
    `/web-setup`'s `workflow`-scope warning, cross-session messaging on Bedrock/Vertex/
    Foundry, and the Workflow tool's smaller prompt footprint are all host/session
    behavior or org billing features with no plugin-side surface; 2.1.250 was bug fixes
    and reliability improvements only, per the official changelog.
  - **2.1.249 — no published entry** (version skipped in the official changelog).
  - **2.1.251 — two items adopted, one genuinely relevant with no change needed.**
    Adopted: `CLAUDE_CODE_SUBAGENT_MODEL` now sets only the *default* subagent model
    instead of overriding every spawn — an agent definition's own `model:` field (every
    `agents/*.md` here pins one explicitly) and a per-spawn model now take precedence,
    documented in `CLAUDE.md`'s Subagents bullet next to the other subagent-reliability
    fixes; and the fix for background sessions/subagents being unable to edit files
    inside a git worktree they created themselves with `git worktree add`, documented in
    `rules/dev/git-worktree-agent-workflow.md` next to `EnterWorktree` and the
    objective/worker worktree model this repo's whole orchestration relies on. Also
    genuinely relevant, no change needed: the new `PreModelSwitch`/`PostModelSwitch` hook
    events and `SessionStart` resume hooks now receiving session staleness and re-cache
    cost are new host lifecycle surfaces this plugin's 25 hooks don't currently use —
    noted for Tamir's judgment rather than wired speculatively (see Future opportunities
    in PR #101 for the reasoning this pass follows). Reviewed and not applicable: the
    plugin-marketplace command path-traversal rejection (`plugin.json` declares no
    `commands` field, only `skills` paths, none pointing outside the plugin root); the
    Workflow-tool `scriptPath` permission-check-ordering fix (this plugin declares no
    Workflow-tool script); the Read/Write/Edit and Grep/Glob symlink-swap fixes (this
    repo's worktree/sensitive-file isolation is enforced by hooks —
    `enforce-worktree-edits.sh`, `guard-sensitive-files.sh` — not by `Read(...)` deny
    rules in settings); the project-level `.claude/settings.json` `env` restriction (this
    repo ships no project-level `.claude/settings.json`; `platforms/claude/settings.d/`
    renders the user-level `~/.claude/settings.json` instead, and its one `env` key,
    `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS`, isn't one of the restricted vars); the default
    commit-trailer change for non-Claude models (`templates/global-CLAUDE.md` states no
    hardcoded trailer text); and the remaining items (spend-limit UI, `/cost` prompt-cache
    line, `claude --help` subcommands, Remote Control streaming, `/effort` per-model
    memory, analytics/sign-in changes, and the large host-reliability fix list) — all host
    UI, terminal, CLI, or account/session infrastructure with no plugin-side surface.
  - `validated_against` advances to 2.1.251 by the changelog + npm-registry method; no
    live `claude` CLI was available in this cycle's automation environment, so
    `claude plugin validate .` / `make agent:check` were not re-run for real this cycle —
    `platform-targets.json`'s `verification_method` notes that the 2.1.247 cycle's
    live-CLI pass remains the most recent direct validation. `make validate`'s aggregate
    loop again did not complete inside this environment's time budget; the targeted
    checks relevant to this docs-only change (`jq` JSON validation on
    `platform-targets.json`, `check-platform-targets.sh`, `check-doc-claims.sh`,
    `check-version-truth.sh`) were run directly and passed.

- **Cursor 3.11 (+2026-08-27):** advance desktop/`validated_against` **3.16.29 → 3.18.9** and `changelog_date` **2026-08-19 → 2026-08-27**. Document Cloud Agent **Start from scratch** (no SCM), Origin **Create repo**, **browser port-forward preview**, and optional **Vercel publish**. Cursor-only.
- **Cursor 3.11 (+2026-08-19) / desktop 3.16.29:** re-pin desktop/`validated_against` **3.16.17 → 3.16.29** and advance `changelog_date` **2026-08-17 → 2026-08-19**. Adopt cloud-agent **Subscriptions** (PR/Slack/schedule wake-ups; auto-subscribe to PRs agents open), **Custom Modes** (pin any skill via ⌥⏎ / Alt+Enter from `/`), **subagents on isolated VMs**, Agent Window **`/goal`** (and native CreateGoal/UpdateGoal tools), and **non-interruptive steering** (follow-ups wait for the next tool call). Document Origin CLI/integrations from the prior rolling window. Cursor-only pins and install guide; other platform nightlies untouched.
- **`templates/global-CLAUDE.md` now pre-authorizes commits and pull requests.**
  The template gated *merging* behind an explicit instruction but said nothing
  about committing or opening a PR — so Claude Code's own default, *"Commit or
  push only when the user asks"*, went unanswered and an agent finishing a piece
  of freeform work stopped at an uncommitted worktree. It never surfaced inside
  `start-dev` / `worker-dev` / `deliver-dev`, because those skills commit and
  open PRs as part of their own instructions. The new bullet answers the default
  the same way the subagent authorization already answers
  *"Do not call the AgentTool unless the user requested it"*, and states the
  preconditions (branch in a worktree, repo gate green, PR body carrying the
  evidence). Merging stays gated, `pr-dev` exception intact.
