# CLAUDE.md — tamir-library

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
| `skills/<topic>/<name>/SKILL.md` | Bundled skill definitions |

## Commands

```bash
make validate    # validate all JSON files and shellcheck all .sh files
make lint        # shellcheck only
make test        # same as validate
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
- **SKILL.md files must have valid YAML frontmatter** with at least `name` and `description` fields

## Adding a skill

1. Create `skills/<topic>/<skill-name>/SKILL.md`
2. Add frontmatter: `name`, `description`, `allowed-tools`
3. Update `README.md` skill count and table
4. Run `make validate`
