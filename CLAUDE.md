# CLAUDE.md — tamirs-superpowers

Claude Code guidance for contributors working on this plugin.

## What this repo is

A Claude Code plugin (marketplace + bundled skills + hooks). It is **not** a Node/Python/Go app — there is no build step, no package.json, no compiled output. All content is Markdown, JSON, and Bash.

## Agent contributors

See [`AGENTS.md`](AGENTS.md) for working agreements, allowed commands, and contributor policies applicable to all agents (Claude Code, Cursor, Codex).

## Key file locations

| Path | Purpose |
|------|---------|
| `.claude-plugin/plugin.json` | Plugin manifest — name, version, dependencies, statusLine |
| `.mcp.json` | MCP server stubs — fill env vars to activate |
| `scripts/` | User-facing scripts (`install.sh`, `update.sh`, `uninstall.sh`, `statusline.sh`) |
| `hooks/hooks.json` | Hook event wiring (PreToolUse, SessionStart, etc.) |
| `hooks/*.sh` | Hook scripts |
| `hooks/lib/worktree-common.sh` | Shared bash helpers for all worktree hooks |
| `skills/<domain>/<name>/SKILL.md` | Bundled skill definitions — grouped by domain |
| `.claude/memory/` | Project memory (lessons, feedback, project facts) — see below |

## Commands

```bash
make validate           # shellcheck + JSON + frontmatter + contract test
make test-repo-contract # assert scaffold-gold (app-gold) + scaffold-plugin-gold (plugin-gold)
make lint               # shellcheck only
make test               # same as validate
```

There is no install step — this is a plugin, not a standalone tool.

## Cloud and remote sessions

Shared runbook (validate, smoke test, stdin gotchas): see **Cloud and headless agent runbook** in [`AGENTS.md`](AGENTS.md).

Claude Code–specific notes:

- **Marketplace cache:** installed copy lives under `~/.claude/plugins/cache/tamirs-plugins/tamirs-superpowers/<version>/`. Pushing commits without a manifest bump does not update installed users — run `/plugin marketplace update tamirs-plugins` then `/plugin update tamirs-superpowers@tamirs-plugins` after releases.
- **Statusline:** wired via `.claude-plugin/plugin.json` `settings.statusLine` → `scripts/statusline.sh`. Test with piped JSON: `echo '<session-json>' | bash scripts/statusline.sh`.
- **Project memory:** versioned backup in `.claude/memory/`; session copy under `~/.claude/projects/-Users-<you>-Projects-tamirs-superpowers/memory/` (see Project memory below).
- **Remote / headless:** same validation commands as AGENTS.md; hooks in `hooks/hooks.json` apply in Claude Code sessions only.

## Commit convention

```
<type>(<scope>): <description>

Co-Authored-By: Claude <noreply@anthropic.com>
```

Types: `feat`, `fix`, `chore`, `docs`, `refactor`
Scopes: `skills`, `hooks`, `marketplace`, `ci`, `docs`

## Hard constraints

- **Never add `runs-on: [self-hosted]`** to any CI workflow — use `ubuntu-latest`
- **Never commit secrets or tokens** — `.mcp.json` uses `${ENV_VAR}` placeholders only
- **Never add Wix-internal references** (internal domains, private GitHub orgs, internal tooling names)
- **Never modify `hooks/lib/worktree-common.sh`** without running shellcheck and testing both `capture-task-slug.sh` and `worktree-create.sh`
- **SKILL.md files must have valid YAML frontmatter** with all 16 official Claude Code fields plus `metadata.updated-date` — see `skills/toolkit/skill-creator/references/frontmatter-template.md`; CI runs `scripts/validate-skill-frontmatter.py`
- **Version sync:** whenever `.claude-plugin/plugin.json` version is bumped, `.codex-plugin/plugin.json` and `.cursor-plugin/plugin.json` must be bumped to the same version in the same commit. Check all three before opening a release PR.
- **Version bump required for marketplace delivery:** Claude Code treats `plugin.json` `version` as the update cache key. New skills, hooks, or other shipped changes **must** include a semver bump (PATCH/MINOR/MAJOR per [versioning.md](docs/engineering/build-and-release/versioning.md)) or installed users stay on the cached copy. `/reload-plugins` does not fetch from GitHub. See [`rules/dev/plugin-version-bump.md`](rules/dev/plugin-version-bump.md).

## Skill domains (25 skills total)

| Domain | Skills |
|--------|--------|
| `creative` | algorithmic-art, field-notebook-ui |
| `debugging` | targeted-debug |
| `dev-workflow` | decision, plan-dev, pr-dev, start-dev, switch-dev |
| `documentation` | changelog-review, dark-terminal-doc, docs-review, platform-sync, platform-sync-claude, platform-sync-codex, platform-sync-cursor |
| `mcp` | mcp-builder, mcp-pagination |
| `toolkit` | find-skill, retro, session-report, skill-creator |
| `repo` | cleanup, multi-agent-repo, repo-scaffold, repo-standards |

**Shared contract:** `skills/repo/_contract/` — canonical templates, scoring scripts, and gold fixtures (`scaffold-gold`, `scaffold-plugin-gold`). Profiles: `app-gold` (apps), `plugin-gold` (agent-kit repos with `canonical/`). `repo-scaffold --type plugin` and `repo-standards` both consume it; `make test-repo-contract` enforces alignment. **User guide:** [docs/user/agent-kit.md](docs/user/agent-kit.md).

## User-invocable vs internal skills

Skills can be restricted to internal use (invoked by other skills only, never by the user typing `/skill-name`):

- `user-invocable: false` — blocks user `/skill-name` invocation; the skill can still be called by another skill via the `Skill` tool
- `disable-model-invocation: true` — prevents the model from auto-triggering the skill based on context

**Invocation tiers** — pick the pair deliberately:

| Tier | `user-invocable` | `disable-model-invocation` | Examples |
|------|:---:|:---:|----------|
| User + auto-trigger (default) | `true` | `false` | plan-dev, start-dev, pr-dev, repo-standards, cleanup, retro |
| Explicit-only (slash, no auto) | `true` | `true` | switch-dev |
| Internal companion | `false` | `true` | docs-review, mcp-pagination, platform-sync-* |

**Gating warning:** `disable-model-invocation: true` also blocks **sub-agent and Workflow orchestration** — a sub-agent invoking a skill *is* model invocation, so a gated skill cannot be fanned out across sub-agents. Only gate a skill when it must *never* be invoked autonomously (internal companions, or a skill whose autonomous run would take an unwanted irreversible action with no confirmation). Prefer putting safety **inside** the skill over gating it: `cleanup` stays model-invocable with confirmation gates + dry-run + a script that only touches provably-safe targets; `retro` stays model-invocable because it only *proposes* changes and never writes without approval, so a mistimed auto-trigger costs nothing.

**Currently internal-only skills** (not user-invocable):
- `changelog-review` — used by `repo-standards` for Claude Code pattern audits
- `docs-review` — used by `repo-standards` for documentation quality sweeps
- `mcp-pagination` — used by `mcp-builder` for pagination guardrails
- `platform-sync-claude` — used by `platform-sync` for Claude Code improvement analysis
- `platform-sync-codex` — used by `platform-sync` for Codex CLI improvement analysis
- `platform-sync-cursor` — used by `platform-sync` for Cursor improvement analysis

**repo-standards is the primary user-invocable skill in the `repo` domain for existing repos** (alongside `multi-agent-repo`, `repo-scaffold`).

## Adding a skill

1. Create `skills/<domain>/<skill-name>/SKILL.md`
2. Add frontmatter per `skills/toolkit/skill-creator/references/frontmatter-template.md` (all 16 official fields + metadata)
3. If the skill is internal-only: add `user-invocable: false` and `disable-model-invocation: true`
4. Update `README.md` skill count and table
5. Run `make validate`

## Project memory

Session lessons are stored in **two places** — keep them in sync:

| Location | Purpose |
|----------|---------|
| `.claude/memory/` (this repo) | Versioned backup — survives machine changes, reviewable in PRs |
| `~/.claude/projects/-Users-<you>-Projects-tamirs-superpowers/memory/` | Auto-loaded by Claude Code each session |

**Restoring memory on a new machine:**
```bash
MEMORY_DIR=~/.claude/projects/-Users-$(whoami)-Projects-tamirs-superpowers/memory
mkdir -p "$MEMORY_DIR"
cp .claude/memory/* "$MEMORY_DIR/"
```

**After adding a new memory file:** commit it to `.claude/memory/` in this repo so it isn't lost.
