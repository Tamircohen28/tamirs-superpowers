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

## Skill domains (16 skills total)

| Domain | Skills |
|--------|--------|
| `creative` | algorithmic-art |
| `debugging` | targeted-debug |
| `dev-workflow` | babysit-pr, plan-dev, pr-dev, start-dev |
| `documentation` | changelog-review, dark-terminal-doc, docs-review |
| `mcp` | mcp-builder, mcp-pagination |
| `meta` | find-skill, session-report, skill-creator |
| `repo` | repo-polish, repo-review |

## User-invocable vs internal skills

Skills can be restricted to internal use (invoked by other skills only, never by the user typing `/skill-name`):

- `user-invocable: false` — blocks user `/skill-name` invocation; the skill can still be called by another skill via the `Skill` tool
- `disable-model-invocation: true` — prevents the model from auto-triggering the skill based on context

**Currently internal-only skills** (not user-invocable):
- `changelog-review` — used by `repo-polish` for Claude Code pattern audits
- `docs-review` — used by `repo-polish` for documentation quality sweeps
- `repo-review` — used by `repo-polish` for repository health audits
- `mcp-pagination` — used by `mcp-builder` for pagination guardrails

**repo-polish is the only user-invocable skill in the `repo` domain.**

## Adding a skill

1. Create `skills/<domain>/<skill-name>/SKILL.md`
2. Add frontmatter: `name`, `description`, `allowed-tools`
3. If the skill is internal-only: add `user-invocable: false` and `disable-model-invocation: true`
4. Update `README.md` skill count and table
5. Run `make validate`
