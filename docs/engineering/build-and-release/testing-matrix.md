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

`make test-hooks` runs every `tests/test-*.sh`:

| Test | Proves |
|---|---|
| `test-statusline.sh` | the statusline renders and **never blocks on stdin** |
| `test-check-done-tiers.sh` | the done-check respects tier boundaries |
| `test-concurrency-guard.sh` | the agent-concurrency guard (`protect-other-branches.sh` + `lib/agent-claim.sh`) stops two agents claiming the same branch |
| `test-worktree-objective.sh` | the objective-aware worktree lifecycle: `capture-task-slug.sh` stands down under an active objective; `enforce-worktree-edits.sh` accepts both layouts |
| `test-integrator-carveout.sh` | the integrator carve-out in `protect-other-branches.sh` — the integrator may touch worker branches, nobody else may |
| `test-skill-contract.sh` | the per-skill contract, plus the eval-coverage report |
| `test-orchestration.sh` | the orchestration state machine transitions correctly |
| `test-opencode-adapter.sh` | `.opencode/agent/` matches `agents/`; adapter and registry agree |
| `test-gemini-adapter.sh` | the Gemini extension manifest is well-formed and consistent |

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
| OpenCode | `jq empty opencode.json`, `make opencode-agents-check`, `tests/test-opencode-adapter.sh` | `opencode debug skill` |
| Claude Desktop | (none — GUI) | manual: install, confirm a skill loads |

Desktop is the honest gap: CI cannot exercise a GUI, so its verification is a documented
manual checklist in [the install guide](../../user/install/claude-desktop.md), and its
unverified capabilities stay `unknown` in the registry rather than being assumed.

## 5. CI jobs

`.github/workflows/ci.yml`, all on `ubuntu-latest` (**never `self-hosted`**):

| Job | What it runs |
|---|---|
| shellcheck | `make lint` |
| Hook behavior tests | `make test-hooks` |
| Validate JSON | every `*.json` parses |
| Validate SKILL.md frontmatter | the portable schema validator |
| Secret scan | no credential ever lands in the tree |
| `claude plugin validate` | the Claude manifest, skills, agents, hooks |
| Repo contract | `make test-repo-contract` |
| Manifest/tag version alignment | manifests vs the cut release tag |
| Platform targets co-change | `platform-targets.json` must move when repo skills do |
| HOL plugin scanner | third-party scan |

Manifest/tag alignment reports a **warning**, not a failure, when a release is pending: the
tag provably cannot exist at merge time, so failing there was a race, not a signal.

## 6. Local parity

```bash
make validate            # the full local gate — Tier 2
make lint                # shellcheck only
make test-hooks          # behavior tests
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
