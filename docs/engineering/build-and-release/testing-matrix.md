# Testing matrix

What runs, where it runs, which [validation tier](../architecture/validation-tiers.md) it
belongs to, and what it proves.

Everything here is bash + `jq` + (for frontmatter) `python3` with `pyyaml`. Nothing needs a
network, a platform CLI, or a paid account — checks that *can* use a CLI degrade to their
static form when it is absent.

---

## 1. Static repository tests — always run

| Check | Command | Tier | Proves |
|---|---|:--:|---|
| Shell lint | `make lint` (shellcheck `-S warning`) | 0 | every `.sh` is clean |
| JSON parse | part of `make validate` | 0 | every `*.json` parses |
| Skill frontmatter | `python3 scripts/validate-skill-frontmatter.py` | 0 | portable schema holds; Claude fields validated when present |
| Version truth | `bash scripts/check-version-truth.sh .` | 0 | every consumer agrees with `plugin-version.json` |
| Capability registry | `bash scripts/check-capability-registry.sh .` | 0 | `platforms.json` satisfies `schema.json` |
| Roles ↔ agents | `bash scripts/validate-roles.sh` | 0 | every `agents/*.md` declares an existing `role:` |
| Doc claims | `bash scripts/check-doc-claims.sh .` | 0 | skill counts and target coverage match the tree |
| Marketplace schema | `make check-marketplace-schema` | 0 | `extraKnownMarketplaces` is a record, not an array |
| Manifest versions | `make check-manifest-versions` | 0 | manifests agree with each other |
| Repo contract | `make test-repo-contract` | 1 | scaffold fixtures (`app-gold`, `plugin-gold`) still match |
| Roles/agents/schemas | `make validate-roles` | 0 | canonical roles, `agents/*.md`, and workflow schemas agree |
| Gemini adapter | `make check-gemini-adapter` · `make gemini-extension-check` | 0 | `.gemini/` mirror exists, is current, and matches the registry |

## 2. Behavior tests — always run

`make test-hooks` runs every `tests/test-*.sh` (`find tests -maxdepth 2`, sorted under
`LC_ALL=C`; 91 suites today), and `make test-hooks SHARD=i/n` runs one deterministic slice of
that list — see [Shards](#shards) below.

| Test | Proves |
|---|---|
| `test-statusline.sh` | the statusline renders and **never blocks on stdin** |
| `test-check-done-tiers.sh` | the done-check respects tier boundaries |
| `test-concurrency-guard.sh` | the agent-concurrency guard (`protect-other-branches.sh` + `lib/agent-claim.sh`) stops two agents claiming the same branch |
| `test-worktree-objective.sh` | the objective-aware worktree lifecycle: `capture-task-slug.sh` stands down under an active objective; `enforce-worktree-edits.sh` accepts both layouts |
| `test-worktree-hint.sh` | the worktree hint is emitted once per repo per session and names its repo; the slug is `issue-N`/`task-NNN` or date plus session id, never prompt text (#337) |
| `test-integrator-carveout.sh` | the integrator carve-out in `protect-other-branches.sh` — the integrator may touch worker branches, nobody else may |
| `test-skill-contract.sh` | the per-skill contract, plus the eval-coverage report |
| `test-orchestration.sh` | the orchestration state machine transitions correctly |
| `test-opencode-adapter.sh` | `.opencode/agents/` matches `agents/`; adapter and registry agree |
| `test-gemini-adapter.sh` | the Gemini extension manifest is well-formed and consistent |
| `test-setup.sh` | `scripts/setup.sh`: `plan` never writes, `apply` is idempotent by content comparison, the plugin-disable warning counts correctly, prompts never read stdin, `remove` is symmetric. Every case runs against a `mktemp -d` fake `HOME` and asserts the real `~/.claude` was untouched |
| `test-renderers.sh` | the four machine-level renderers (codex, cursor, gemini, opencode) — marker blocks, merge-not-clobber, and a hermetic apply → re-apply → remove round trip |
| `test-capture.sh` | `scripts/capture-config.sh`: classification, secret refusal, and that nothing is adopted without an explicit decision |
| `test-skill-suggest.sh` | the suggestion hook uses `additionalContext`, keys its cache per repo, and suggests once per skill per session — the three defects that made its predecessor inert |
| `test-hook-stdin.sh` | a suite-wide sweep: **every** hook returns promptly whatever stdin does |
| `test-docs.sh` · `test-static.sh` | documentation and static repository tests — see §1 and below |
| `test-hook-conformance.sh` | one scenario corpus (a plain checkout; an active objective with a task worktree) replayed through every wired hook under the Claude Code, Codex, Cursor and Gemini dialects, judging exit codes, one-JSON-object stdout, each host's key vocabulary (never `followup_message` on Cursor), stderr traces, timeouts, selectivity, and that `enforce-worktree-edits.sh` and `guard-sensitive-files.sh` give the same answer on every host in that host's dialect |
| `hooks/test-codex-contract.sh` · `test-cursor-lifecycle.sh` · `test-gemini-hooks.sh` | the per-host hook suites: captured Codex payloads (`fixtures/codex/`) with Codex's Stop-family JSON rule and 3-second clamps; Cursor's ten wired events (`fixtures/cursor/`) with its documented output shape per event; the generated Gemini hooks file, policies and `hooks/gemini-wrap.sh` translation |
| `test-dist.sh` · `test-claude-dist.sh` | every per-host distribution builds and passes its check, and a planted finding of each class makes the check fail |
| `test-opencode-v2.sh` · `test-antigravity-adapter.sh` · `test-agents-skills.sh` | the OpenCode 2 configuration, plugin and permissions vocabulary; the Antigravity adapter's closed schema; the `.agents/skills` mirror |
| `test-skill-budget.sh` · `test-evals-suite.sh` | the always-on token budget gate: the checkout's offline estimate held to `evals/budget.json` on every shard, the CLI's chars/4 fallback recognised, a stale `chars_per_token` caught; and the skills-ref gate (hermetic through saved CLI output; the live case self-skips without the CLI); the static shape of the `claude plugin eval` suite under `evals/` |
| `test-shards.sh` | the shard partition: every suite in exactly one shard, the union of `1/n … n/n` is the full list, `1/1` is today's list in today's order, and the Makefile consumes the script rather than its own `find` |

### Shards

`scripts/ci/shard-suites.sh i/n` is the single source of the partition. Suite `k` (0-based
in the sorted list) lands in shard `(k mod n) + 1`: a round-robin by name, so every suite
runs in exactly one shard and the union of `1/n … n/n` is the whole list. `make test-hooks`
consumes the script, never its own `find`, so a local shard and a CI shard run the same
suites; without `SHARD` the target is `1/1`, the whole list, unchanged. The real-home
witness still brackets every suite inside a shard.

```bash
bash scripts/ci/shard-suites.sh 2/4   # print the suites in shard 2 of 4
make test-hooks SHARD=2/4             # run that shard
```

Balance is by **count, not seconds** (23/23/23/22 for `n=4` today). The heavy suites land
where the sorted order puts them: `test-static` in 1/4 (measured at 246 s for the whole
shard), `test-permission-fuzz` in 2/4, `test-permission-guard` in 3/4,
`test-security-regressions` and `test-toolkit-gates` in 4/4. Until the batch judge for the
permission guard lands (objective `ci-speed`, task-001), shard 2/4 is the long pole: the
fuzz suite alone is 746 s on the 4-core runner, so the matrix is bounded by that one suite
rather than by the count. Adding or renaming a `tests/test-*.sh` re-partitions every shard.
That is by design — there is no hand-kept list to go stale — but it means a new heavy suite
can move the long pole without anyone touching CI. Re-size `n` from the per-suite timing
table after task-001 lands, not from the count.

Under `make test-hooks` every suite receives `SUPERPOWERS_SHELLCHECK_DONE=1`, so
`test-static` skips its own shellcheck pass: `make lint` is the gate's one pass, and both the
CI `shellcheck` job and `validate-rest` run it. Standalone `bash tests/test-static.sh` still
shellchecks, which is how the CI static job invokes it.

## 3. Orchestration simulations

`tests/orchestration/scenario-*.sh` exercise the workflow without invoking a model:

| Scenario | Proves |
|---|---|
| `scenario-parallel-workers.sh` | independent tasks run concurrently and integrate |
| `scenario-sequential-equivalence.sh` | **the sequential path produces the same result as the parallel one** |
| `scenario-dependencies.sh` | dependency ordering is respected |
| `scenario-conflict.sh` | conflicts surface at integration, not in a worker |
| `scenario-failures.sh` | a failed task retries once, then re-plans |
| `scenario-resume.sh` | an interrupted objective resumes from disk without re-running tasks |
| `scenario-review-retry.sh` | blocking findings loop until resolved |
| `scenario-delivery.sh` | one objective produces one PR |
| `scenario-no-worker-pr.sh` | **no worker ever opens a PR** |

## 4. Platform contract tests

Split deliberately: schema/contract assertions always run; live-CLI validation runs only
where the CLI exists.

| Platform | Always | With the CLI present |
|---|---|---|
| Claude Code / Desktop | `jq empty .claude-plugin/plugin.json`, `jq empty hooks/hooks.json`, `jq empty .mcp.json`, marketplace schema | `claude plugin validate .`; local `--plugin-dir` load |
| Codex | `jq empty .codex-plugin/plugin.json`, `jq -e '.hooks'`, `jq empty .agents/plugins/marketplace.json`, `test -f .codex/config.toml` | Codex plugin install smoke test |
| Cursor | `jq empty .cursor-plugin/plugin.json`, `.cursor/rules/` presence via `make check-platform-targets` | marketplace import, by hand |
| Gemini CLI | `jq empty gemini-extension.json`, version consumer alignment, `tests/test-gemini-adapter.sh`, `make check-gemini-adapter`, `make gemini-extension-check` | `gemini extensions link .` and a real session. **`gemini extensions validate` is not sufficient evidence** — it only parses the manifest and reports success even when the context file is absent |
| OpenCode | `jq empty opencode.json`, `make opencode-agents-check`, `tests/test-opencode-adapter.sh` | `opencode debug config` (per-skill discovery is not verifiable from the CLI on 2.x) |
| Claude Desktop | (none — GUI) | manual: install, confirm a skill loads |

Desktop is the honest gap: CI cannot exercise a GUI, so its verification is a documented
manual checklist in [the install guide](../../user/install/claude-desktop.md), and its
unverified capabilities stay `unknown` in the registry rather than being assumed.

## 5. CI jobs

`.github/workflows/ci.yml`, all on `ubuntu-latest` (**never `self-hosted`**):

| Job | What it runs |
|---|---|
| shellcheck | `make lint`, plus the orphan-hook-script warning |
| make test-hooks (shard i/4) | one shard of the behavior tests, `make test-hooks SHARD=i/4`; a four-leg matrix with `fail-fast: false` so every shard reports |
| make validate minus the suites | `make -o test-hooks validate`: every prerequisite and every recipe line of the gate except `test-hooks` |
| make validate (full local-parity gate) | the aggregator — the required context. `needs` the matrix and the job above, runs on `if: always()`, exits 1 unless both results are `success` |
| Orchestration simulation | `bash tests/test-orchestration.sh` |
| Skill contract | `tests/test-skill-contract.sh`, then `--strict`, then the Agent Skills reference validator |
| Static repo + docs tests | `tests/test-static.sh` (shellchecks, standalone), `tests/test-docs.sh`, the repository-description count check (warns) |
| Platform contract (gemini, opencode) | the per-platform adapter suite, contract half only |
| Validate JSON | every `*.json` parses |
| Validate SKILL.md frontmatter | the portable schema validator |
| Secret scan | no credential ever lands in the tree |
| `claude plugin validate` | the marketplace manifest (`.`); `make test-mods` (`claude plugin test`, `mod/*.test.tsx` against the engine); a plugin install from the checkout held to the token budget |
| Claude-only distribution | `build-claude-dist.sh` then `check-claude-dist.sh` |
| Per-host distributions | every generator's `--check`, `make check-dists`, `tests/test-dist.sh` |
| Repo contract (scaffold-gold) | `make test-repo-contract` |
| Repo contract (this repo) | `make assert-contract` |
| Manifest/tag version alignment | manifests vs the cut release tag |
| Platform targets co-change | `platform-targets.json` must move when repo skills do |
| HOL plugin scanner | third-party scan |

Manifest/tag alignment reports a **warning**, not a failure, when a release is pending: the
tag provably cannot exist at merge time, so failing there was a race, not a signal.

### Why the aggregator exists

`config/github/repository-policy.json` requires the context `make validate (full
local-parity gate)` on every pull request, and the live ruleset copies it. A context is a
check's display name, and a name no workflow produces blocks every merge forever. Splitting
the gate into a matrix therefore could not rename the check, and a matrix leg cannot be the
check either: each leg reports under its own name. So the job id `full-validate` keeps its
name and owns no work of its own any more. It `needs` both the matrix and
`validate-rest`; it runs on `if: always()`, so a failed or cancelled dependency still makes
it red instead of leaving a context that never reports; and its one step exits 1 unless
`needs.validate-shards.result` and `needs.validate-rest.result` are both `success` — a
matrix result is `success` only when every leg is. The policy file and the ruleset did not
change.

`validate-rest` is `make -o test-hooks validate`, not a second list of targets. `-o` marks
`test-hooks` as already up to date, so make runs the gate's prerequisite list and its recipe
body exactly as the Makefile states them, minus that one target. Nothing in the workflow
restates the Makefile, so a check added to `validate` reaches CI with no workflow edit.

## 6. Local parity

```bash
make validate            # the full local gate — Tier 2
make lint                # shellcheck only
make test-hooks          # behavior tests, every suite
make test-hooks SHARD=2/4    # one shard of them (what one CI matrix leg runs)
make -o test-hooks validate  # the gate minus the suites (what CI's validate-rest runs)
make test-repo-contract  # contract fixtures
make doctor              # environment health, not a test
```

`make validate` is CI parity for everything that does not need a platform CLI. Run it before
opening a PR; run the platform CLI checks for whichever platform you touched.

## What is deliberately not tested here

- **GUI surfaces** (Claude Desktop) — manual checklist, and `unknown` in the registry.
- **Live model behavior** — orchestration scenarios simulate the state machine, not the LLM.
- **Third-party platform internals** — a capability is `unknown` until this repo measures it.
  That is the honesty rule, and it is why the matrix has gaps instead of guesses.

---

<p align="center"><a href="https://github.com/Tamircohen28">Have a Question?</a>&nbsp;·&nbsp;<a href="https://github.com/Tamircohen28/tamirs-superpowers/issues/new/choose">Open an Issue</a></p>
