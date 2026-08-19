# tests/

Every suite here is bash, hermetic, and non-interactive: temp directories cleaned
up by `trap`, no network, no `gh`, no writes outside the temp tree, and never a
read from stdin. A suite you can only run on a maintainer's laptop is not a test.

## Layout

| Path | What it is |
|------|------------|
| `test-*.sh` | Entrypoints. `make test-hooks` runs every one of them (`find tests -maxdepth 1`). |
| `lib/` | Sourced helpers — assertions, temp fixtures, portability shims, and two `gh` doubles: `fake-agent.sh`'s recording stub (orchestration sims — records argv, returns nothing) and `fake-gh.sh` (API-shaped tests — serves fixtures, records bodies, injects HTTP errors). Never executed directly. **Do not source both into one shell** — see below. |
| `orchestration/` | Scenario fragments sourced by `test-orchestration.sh`. |
| `contract/` | Per-platform contract suites, run by `contract/run.sh`. |
| `fixtures/github/` | Canned GitHub API responses served by `lib/fake-gh.sh`. One directory per scenario, each with a `README.md` naming what it represents. |

## Entrypoints

```bash
bash tests/test-orchestration.sh          # fake-agent orchestration simulation
bash tests/test-skill-contract.sh         # per-skill contract + eval-coverage report
bash tests/test-static.sh                 # static repository invariants
bash tests/test-docs.sh                   # docs tell the truth about the repo
bash tests/contract/run.sh [platform...]  # platform contract suites
bash tests/test-fake-gh.sh                # the fake-gh mock tests itself

# hook behaviour (pre-existing suites)
bash tests/test-check-done-tiers.sh
bash tests/test-concurrency-guard.sh
bash tests/test-integrator-carveout.sh
bash tests/test-worktree-objective.sh
bash tests/test-statusline.sh
bash tests/test-gemini-adapter.sh
bash tests/test-opencode-adapter.sh
```

`test-orchestration.sh` and `contract/run.sh` accept a subset as arguments:

```bash
bash tests/test-orchestration.sh delivery resume
bash tests/contract/run.sh gemini opencode
```

`test-skill-contract.sh`, `test-static.sh` and `test-docs.sh` accept `--strict`,
which promotes their advisory checks (eval-coverage gaps, link rot in docs still
being rewritten) to failures. CI runs them without `--strict` today; flip it on
per check once the corresponding gap is closed.

## The orchestration simulation

`test-orchestration.sh` is the centrepiece and it makes **no model calls**. Workers
are shell functions in `lib/fake-agent.sh` that produce exactly what a real worker
produces — a branch, a commit, a structured handoff — on command, including on
command badly (fail, escape scope, collide, block). The state machine under test is
the real one: `skills/dev-workflow/_shared/scripts/objective-state.sh` and
`handoff.sh`, driving real `git worktree` operations in a `mktemp -d` repo.

`gh` is replaced by a **recording shim** on `PATH`. It logs every invocation and
never reaches GitHub, which turns the central invariant into a counting assertion:

```
no worker creates a PR          →  gh_calls 'pr create' == 0 across the worker phase
one objective = one PR          →  gh_calls 'pr create' == 1 across the whole run
```

Scenarios:

| Scenario | Pins |
|----------|------|
| `parallel-workers` | three disjoint-scope workers; nothing reaches GitHub; overlapping scope is rejected by the graph validator |
| `dependencies` | a dependent task is never dispatched early, and integration waits for it |
| `failures` | a failed / out-of-scope / blocked worker leaves the objective valid and readable |
| `conflict` | conflicts are resolved by the integrator on `objective/*`, never on a worker branch |
| `review-retry` | reviewers are read-only and return structured findings; retry is bounded to one |
| `resume` | a `env -i` process rebuilds the whole run from disk alone |
| `delivery` | exactly one PR; a second delivery unit needs a stated exception |
| `sequential-equivalence` | the no-subagent path reaches the same final state as the parallel path |
| `no-worker-pr` | the shipped `SKILL.md` files require what the simulation proves |

### The two `gh` doubles do not compose

`lib/fake-agent.sh` and `lib/fake-gh.sh` both define `gh_calls` **and**
`fake_gh_install`, over different state. Sourcing both into one shell leaves
whichever loaded second in place, silently.

That is not a tidiness problem. `gh_calls` reading the wrong (or an empty) log
makes `gh_calls 'pr create'` return `0`, and **every "no worker created a PR"
assertion in the orchestration suite then passes without measuring anything** —
the single most important assertion in the refactor, reduced to a tautology.

So it is enforced, not just documented, in both source orders:

- `fake-agent.sh` aborts at source time if `fake-gh.sh` is already loaded.
- `test-orchestration.sh` asserts after sourcing that `gh_calls` and
  `fake_gh_install` still resolve to the fake-agent implementations.

Pick one double per suite. Orchestration sims want `fake-agent.sh`; anything
asserting on GitHub API shapes wants `fake-gh.sh`.

## Portability

macOS is the development machine (**bash 3.2**, BSD userland); CI is
`ubuntu-latest` (bash 5, GNU userland). A GNU-only spelling is green in CI and
broken for the maintainer, which is worse than an outright break because nothing
goes red. `rules/dev/user-facing-script-standards.md` §3 is the authority;
`tests/lib/portable.sh` is the implementation:

| Helper | Use instead of |
|--------|----------------|
| `portable_timeout <secs> <cmd...>` | `timeout` / `gtimeout` — **neither is installed on the dev machine.** Falls back to a pure-bash watchdog; returns `124` on expiry like GNU `timeout`. |
| `portable_timeout_impl` | — reports which implementation is active, for skip/failure messages |
| `portable_xargs0 <nul-list> <cmd...>` | `xargs -a` (GNU-only) |
| `portable_realpath` | `readlink -f` (GNU-only) |
| `portable_utc_now` | `date -d`, `date --iso-8601` (GNU-only) |
| `read_lines <array>` | `mapfile` / `readarray` (bash 4+) |

For "don't block on stdin", prefer bash's builtin `read -t` over any external
watchdog — it is always present. `scripts/statusline.sh` is the model.

`test-static.sh` enforces this across every shipped `.sh`, and understands the
BSD-first fallback idiom (`stat -f … || stat -c …`) rather than flagging it.

### Positive controls are mandatory for anything that scans

A scanner reports "clean" both when the repo is clean and when the scanner is
broken. That is not hypothetical here: this suite's secret, maintainer-path and
employer-reference scanners once used a GNU-only `xargs -a`, which BSD xargs
rejected and a trailing `|| true` swallowed — three security checks passed against
files they had never opened. Every scanner in `test-static.sh` is now run first
against a planted dirty fixture and must fire there. If you add a scanner, add its
control in the same commit, and make the control reuse the real pattern and the
real helper rather than reimplementing them.

## Adding a test

1. Assertions go through `ok` / `bad` / `judge` / `has` from `lib/harness.sh`, so
   every suite reports the same way and `make test-hooks` can treat them alike.
2. `set -uo pipefail` — **not** `-e`. The assertions are the control flow; a bare
   `-e` turns the first failing check into a truncated run with no summary.
3. Get temp space from `harness_tmpdir` (self-cleaning) and repos from
   `harness_new_repo` (hermetic identity, no global git config leaking in).
4. Nothing may depend on a CLI being installed. Use `harness_have` and `skip` with
   a reason naming the missing command.
5. `shellcheck -S warning --exclude SC2034` must be clean, and no GNU-only
   spellings — see Portability above. Never call `timeout` directly; it is not
   installed on the development machine.
6. Anything that greps for a bad pattern needs a positive control proving it fires.
