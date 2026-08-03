# tamirs-superpowers

A multi-platform agent plugin for the four supported targets — Claude Code, Cursor, Codex, and OpenCode — that bundles 27 skills, 6 specialist agents, smart worktree hooks, and MCP server stubs. It is **not** a Node/Python/Go app — there is no build step, no `package.json`, no compiled output. All content is Markdown, JSON, and Bash.

Worktree hooks and the statusline do not port to OpenCode; see [`docs/user/install/opencode.md`](docs/user/install/opencode.md#what-does-not-port). The machine-readable target list is [`platform-targets.json`](docs/engineering/build-and-release/platform-targets.json).

**Install (all platforms)** — from a clone:

```bash
make install   # bootstrap Claude settings + agents
make update    # refresh plugin + agents
make uninstall # remove agents + uninstall plugin when possible
```

**Claude Code (marketplace)** — `tamirs-plugins` catalog:

```
/plugin marketplace add Tamircohen28/plugins
/plugin install tamirs-superpowers@tamirs-plugins
```

**Cursor / Codex** — enable via `.cursor-plugin/plugin.json` or `.codex-plugin/plugin.json` (same `skills/` tree).

## Working agreements

- Validate after every change: `make validate` (shellcheck + JSON lint + frontmatter + `make test-repo-contract`)
- **Version bump after shipped changes:** Claude Code uses `plugin.json` `version` as the update cache key — commits without a bump do not reach installed users (`/plugin update` reports "already at latest"). After changing `skills/`, `hooks/`, `agents/`, manifests, or `scripts/`, bump the three versioned plugin manifests together (`opencode.json` has no version field), update `CHANGELOG.md` + `README.md` badges, refresh anything the change falsified — documented skill counts, `platform-targets.json`, `docs/user/install/<target>.md` — open a PR, then run the Release workflow to tag `vX.Y.Z` and verify the tag contains the change. See [`rules/dev/plugin-version-bump.md`](rules/dev/plugin-version-bump.md) and [versioning.md](docs/engineering/build-and-release/versioning.md).
- Commit format: `<type>(<scope>): <description>` — types: `feat`, `fix`, `chore`, `docs`, `refactor` — scopes: `skills`, `hooks`, `marketplace`, `ci`, `docs`
- Never add `runs-on: [self-hosted]` to any CI workflow — use `ubuntu-latest`
- Never commit secrets or tokens — `.mcp.json` uses `${ENV_VAR}` placeholders only
- Never add Wix-internal references (internal domains, private GitHub orgs, internal tooling names)

## Repository expectations

- All JSON files must be valid — checked by `make validate`
- All `.sh` files must pass `shellcheck` — checked by `make lint`
- Every `SKILL.md` must include all 16 official Claude Code frontmatter fields plus `metadata.updated-date` — validated by `scripts/validate-skill-frontmatter.py`
- No install step for plugin **content** — use `make install` to bootstrap Claude machine settings and agents

## Key files

| Path | Purpose |
|------|---------|
| `.claude-plugin/plugin.json` | Claude Code plugin manifest |
| `.cursor-plugin/plugin.json` | Cursor plugin manifest (skills + MCP; no hooks) |
| `.codex-plugin/plugin.json` | Codex plugin manifest (skills + hooks + MCP) |
| `rules/dev/*.md` | Canonical contributor rules (all agents) |
| `hooks/hooks.json` | Hook event wiring (Claude Code + Codex) |
| `hooks/lib/worktree-common.sh` | Shared bash helpers for all worktree hooks — do not modify without shellchecking |
| `skills/<domain>/<name>/SKILL.md` | Bundled skill definitions — grouped by domain |
| `skills/repo/_contract/` | Shared repo scaffold/standards contract (not a skill) |
| `Makefile` | `install`, `update`, `uninstall`, `validate`, `lint`, `test`, `test-repo-contract` |
| `scripts/install.sh` | Bootstrap `~/.claude/settings.json` + agents (`make install`) |
| `scripts/update.sh` | Refresh plugin + agents (`make update`) |
| `scripts/uninstall.sh` | Remove installed artifacts (`make uninstall`) |
| `scripts/statusline.sh` | Claude Code footer statusline (wired via `plugin.json`) |

## Contributor rules (`rules/dev/`)

| Rule | Applies when |
|------|----------------|
| `dev-files-workspace.md` | Session plans/reviews — use `.dev-files/` only |
| `git-worktree-agent-workflow.md` | Branch work — one task per worktree under `.<agent>/.worktrees/` |
| `skill-quality-standards.md` | Authoring or editing `skills/**/SKILL.md` |
| `gh-cli-preference.md` | CI scripts, hooks, dev-workflow skill scripts |
| `user-facing-script-standards.md` | User-facing or skill helper scripts |
| `plugin-version-bump.md` | After shipped plugin changes — bump manifests, changelog, per-target install docs, release tag |

Cursor loads thin adapters from `.cursor/rules/*.mdc` pointing at these files. Claude Code loads `rules/dev/` directly. Codex reads `AGENTS.md` plus `rules/dev/` when contributing.

## Off-limits

- Never modify `hooks/lib/worktree-common.sh` without running shellcheck and testing both `capture-task-slug.sh` and `worktree-create.sh`
- Never commit to `main` directly — always use a feature branch and PR
- Never add a `marketplace.json` to this repo — it is published through the separate `Tamircohen28/plugins` catalog
- Never hand-write a `SKILL.md` from scratch — use the `skill-creator` skill to ensure evals, references, and quality standards are met

## Cloud and headless agent runbook

Applies to **Cursor Cloud**, **Codex sandboxes**, **Claude Code remote sessions**, and CI — any non-interactive shell working on this repo.

This repo is Markdown/JSON/Bash — there is **no app server, dev server, or build output**. "Running" it means exercising the validation harness and runtime scripts:

| Check | Command |
|-------|---------|
| Full validation | `make validate` (shellcheck + JSON + SKILL.md frontmatter + repo-contract + manifest/tag alignment) |
| Repo-standards gate | `make repo-standards-gate` (multi-platform repos — runs before push/PR via `start-dev` / `pr-dev`) |
| Plugin health (7 categories) | `bash .claude/skills/run-tamirs-superpowers/smoke.sh </dev/null` |
| Statusline render (Claude Code) | `echo '<session-json>' | bash scripts/statusline.sh` |

**Gotchas (all platforms):**

- `scripts/statusline.sh` reads JSON from **stdin** (`input=$(cat)`). With no piped input it blocks forever in non-interactive shells. Always pipe JSON in or redirect stdin. Because `smoke.sh` invokes the statusline with inherited stdin, run the smoke test as `smoke.sh </dev/null`.
- `shellcheck` is required for `make lint`/`make validate` shell coverage; if absent, those targets **silently skip** shellcheck instead of failing. Install via system package manager (`apt`, `brew`, etc.) — not bundled in the repo.
- The smoke test reports one expected `WARN` (hardcoded `/Users/` path in `skills/toolkit/skill-creator/SKILL.md`) — known, documented; health is OK when `FAIL: 0`.
- `make check-manifest-versions` fetches git tags; works offline against the current checkout but needs network to compare against the latest release tag.

**Platform-specific addenda:**

| Platform | Where to read more |
|----------|-------------------|
| Claude Code | [`CLAUDE.md`](CLAUDE.md) — marketplace cache, statusline wiring, project memory, remote sessions |
| Cursor | `.cursor-plugin/plugin.json` + `.cursor/rules/*.mdc`; Cloud agents boot in a fresh Linux VM — ensure `shellcheck` and PyYAML (`pip install -r scripts/requirements-validate.txt`) are present |
| Codex | `.codex-plugin/plugin.json` + optional `.codex/config.toml`; this file (`AGENTS.md`) and `rules/dev/` are the canonical policy sources |
