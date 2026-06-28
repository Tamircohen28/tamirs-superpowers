# CLAUDE.md — tamirs-superpowers

Claude Code guidance for contributors working on this plugin.

## What this repo is

A Claude Code plugin (marketplace + bundled skills + hooks). It is **not** a Node/Python/Go app — there is no build step, no package.json, no compiled output. All content is Markdown, JSON, and Bash.

## Key file locations

| Path | Purpose |
|------|---------|
| `marketplace.json` | Marketplace manifest — declares this repo as a plugin marketplace |
| `.claude-plugin/plugin.json` | Plugin manifest — name, version, dependencies, statusLine |
| `.mcp.json` | MCP server stubs — fill env vars to activate |
| `statusline.sh` | Statusline script wired via `plugin.json` |
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

## Skill domains (22 skills total)

| Domain | Skills |
|--------|--------|
| `creative` | algorithmic-art, field-notebook-ui |
| `debugging` | targeted-debug |
| `dev-workflow` | plan-dev, pr-dev, start-dev |
| `documentation` | changelog-review, dark-terminal-doc, docs-review, platform-sync, platform-sync-claude, platform-sync-codex, platform-sync-cursor |
| `mcp` | mcp-builder, mcp-pagination |
| `toolkit` | find-skill, session-report, skill-creator |
| `repo` | cleanup, multi-agent-repo, repo-scaffold, repo-standards |

**Shared contract:** `skills/repo/_contract/` — canonical templates, scoring scripts, and gold fixtures (`scaffold-gold`, `scaffold-plugin-gold`). Profiles: `app-gold` (apps), `plugin-gold` (agent-kit repos with `canonical/`). `repo-scaffold --type plugin` and `repo-standards` both consume it; `make test-repo-contract` enforces alignment. **User guide:** [docs/user/agent-kit.md](docs/user/agent-kit.md).

## User-invocable vs internal skills

Skills can be restricted to internal use (invoked by other skills only, never by the user typing `/skill-name`):

- `user-invocable: false` — blocks user `/skill-name` invocation; the skill can still be called by another skill via the `Skill` tool
- `disable-model-invocation: true` — prevents the model from auto-triggering the skill based on context

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
