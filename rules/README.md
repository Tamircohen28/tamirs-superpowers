# Canonical rules

Every contributor rule in this repo lives here **once**. Platform files (`CLAUDE.md`, `AGENTS.md`, `.cursor/rules/*.mdc`, `.codex/`, `.gemini/`, `.opencode/`) are **thin adapters**: they either point at a rule in this directory, or they contain something genuinely specific to that platform. They never restate a rule — a restated rule drifts.

```text
core/policies/     ← what is always true (safety, git, validation, delivery)
core/roles/        ← what a unit of work needs done (role != provider)
core/workflow/     ← the objective / task / handoff JSON schemas
core/capabilities/ ← what each provider can actually do (snake_case ids)
core/providers/    ← how a role resolves to a provider
rules/dev/         ← how contributors work in THIS repo   ← you are here
<platform files>   ← thin adapters into the above
```

`core/` is the portable framework. `rules/dev/` is this repository's contributor policy expressed on top of it. When the two overlap, `core/` wins.

---

## The rules

| Rule | Applies when | Covers |
|------|--------------|--------|
| [`dev-files-workspace.md`](dev/dev-files-workspace.md) | Always (`alwaysApply: true`) | Where session artifacts and objective/task/handoff state live; the `.dev-files/objectives/` layout; the gitignore-by-default / opt-in-to-commit policy |
| [`plugin-version-bump.md`](dev/plugin-version-bump.md) | Always (`alwaysApply: true`) | One canonical version in `plugin-version.json`; `check-version-truth.sh --sync`; release tagging; never move a version backwards |
| [`git-worktree-agent-workflow.md`](dev/git-worktree-agent-workflow.md) | Branch work, any agent | Objective/worker/integration worktrees and branches; provider is metadata; legacy platform worktrees stay understood and are never orphaned |
| [`cross-platform-handoff.md`](dev/cross-platform-handoff.md) | Handing work between providers or sessions | The handoff contract; local-first state; GitHub issues as an optional mirror |
| [`gh-cli-preference.md`](dev/gh-cli-preference.md) | Anything touching GitHub | `gh` as an optional feature dependency; explicit degradation; `gh` over GitHub MCP in dev context |
| [`github-repository-policy.md`](dev/github-repository-policy.md) | Governing a GitHub repository: rulesets, required checks, Actions concurrency | Rulesets over classic protection; `~DEFAULT_BRANCH` never a literal; why strict status checks are deliberately off; per-repo required contexts; which workflows may be cancelled. Policy data: [`config/github/repository-policy.json`](../config/github/repository-policy.json) |
| [`user-facing-script-standards.md`](dev/user-facing-script-standards.md) | Authoring any script | CLI contract; macOS/Linux portability; Windows declared unsupported (WSL2/Git Bash); non-interactive + non-blocking stdin; dependency tiers; machine-readable output |
| [`skill-quality-standards.md`](dev/skill-quality-standards.md) | Authoring or editing `skills/**/SKILL.md` | The portable skill standard and its platform extensions; schema at [`core/schemas/skill-frontmatter.json`](../core/schemas/skill-frontmatter.json) |

---

## Hard invariants vs configurable policy

Both are real; only one is negotiable. [`core/policies/safety.md`](../core/policies/safety.md) is the authoritative list — this section orients you to the distinction.

**Hard invariants.** Never relaxed, never argued with, never overridden by a task instruction, a skill, or another agent:

- never commit secrets;
- never silently bypass a required security check;
- never modify unrelated user work;
- never destroy uncommitted work;
- never push directly to a protected default branch unless the repo is explicitly configured to allow it;
- never use `--no-verify` as routine automation;
- never fake validation success;
- never claim a platform feature works without evidence.

**Configurable policy.** Sensible defaults that a repo, an objective, or a user may change — stating that they are being changed:

- every task gets its own PR (default: **no** — one objective, one PR);
- every worker runs the full test suite (default: **no** — Tier 1 is targeted; Tier 2 is full);
- every PR auto-merges (default: **no** — delivery is explicit);
- every branch is fully updated before merge;
- every skill carries Claude-specific frontmatter fields (default: **no** — the portable schema is canonical, Claude fields are an extension).

If you are about to write "must" into a rule, check which list it belongs on. Demoting an invariant needs a spec change; demoting a policy needs only a stated reason.

---

## Adapter map

Which platform file thins into which canonical source. A change to canonical content must never be copied into these — only referenced.

`platforms/<id>/adapter.yaml` is the machine-readable index of each target's adapter — id, manifest path, and a coarse capability summary pointing at `core/capabilities/platforms.json`. Add one when adding a target.

| Platform file | Thins into |
|---------------|-----------|
| `AGENTS.md` | Entrypoint for every non-Claude provider → all of `rules/dev/` + `core/policies/` |
| `CLAUDE.md` | Claude Code / Claude Desktop specifics (marketplace cache, statusline, project memory, subagents) → everything else by reference |
| `.cursor/rules/dev-files-workspace.mdc` | `rules/dev/dev-files-workspace.md` |
| `.cursor/rules/git-worktree-agent-workflow.mdc` | `rules/dev/git-worktree-agent-workflow.md` |
| `.cursor/rules/cross-platform-handoff.mdc` | `rules/dev/cross-platform-handoff.md` |
| `.cursor/rules/plugin-version-bump.mdc` | `rules/dev/plugin-version-bump.md` |
| `.cursor/rules/skill-quality-standards.mdc` | `rules/dev/skill-quality-standards.md` |
| `.cursor/rules/gh-cli-preference.mdc` | `rules/dev/gh-cli-preference.md` |
| `.cursor/rules/user-facing-script-standards.mdc` | `rules/dev/user-facing-script-standards.md` |
| `.cursor/rules/skill-frontmatter.mdc` | `core/schemas/skill-frontmatter.json` |
| `.cursor/rules/commit-conventions.mdc` | `core/policies/git.md` |
| `.cursor/rules/hooks-guide.mdc` | `rules/dev/user-facing-script-standards.md` §7 |
| `.cursor/rules/plugin-structure.mdc` | `AGENTS.md` (repo shape) |
| `.cursor/rules/skills-guide.mdc` | `rules/dev/skill-quality-standards.md` |
| `.codex/config.toml` | Codex runtime settings only; policy comes from `AGENTS.md` |
| `.gemini/` + `gemini-extension.json` | Gemini CLI extension wiring; policy comes from `AGENTS.md` |
| `.opencode/` + `opencode.json` | OpenCode wiring; agent definitions generated from canonical `agents/` |

Every rule in `rules/dev/` has exactly one `.cursor/rules/<same-basename>.mdc`; `tests/contract/cursor.sh` enforces that mapping, and `rules/README.md` is excluded as an index. Drift between an adapter and its canonical source is a build failure, not a style issue: `bash scripts/check-agent-drift.sh .` and `bash scripts/check-feature-equivalence.sh .` are wired into `make validate`.

---

## Adding or changing a rule

1. Write it **once**, here.
2. If a platform needs to see it, add or update a *pointer* in that platform's adapter — never a copy.
3. Decide which list it belongs on (invariant vs policy) and say so in the rule.
4. Run `make validate`.
