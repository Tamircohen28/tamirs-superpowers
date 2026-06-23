# tamirs-superpowers

A Claude Code plugin that bundles 16 skills, smart worktree hooks, and MCP server stubs. It is **not** a Node/Python/Go app — there is no build step, no `package.json`, no compiled output. All content is Markdown, JSON, and Bash.

Install via the `tamirs-plugins` marketplace catalog:
```
/plugin marketplace add Tamircohen28/plugins
/plugin install tamirs-superpowers@tamirs-plugins
```

## Working agreements

- Validate after every change: `make validate` (shellcheck + JSON lint + full SKILL.md frontmatter audit)
- Commit format: `<type>(<scope>): <description>` — types: `feat`, `fix`, `chore`, `docs`, `refactor` — scopes: `skills`, `hooks`, `marketplace`, `ci`, `docs`
- Never add `runs-on: [self-hosted]` to any CI workflow — use `ubuntu-latest`
- Never commit secrets or tokens — `.mcp.json` uses `${ENV_VAR}` placeholders only
- Never add Wix-internal references (internal domains, private GitHub orgs, internal tooling names)

## Repository expectations

- All JSON files must be valid — checked by `make validate`
- All `.sh` files must pass `shellcheck` — checked by `make lint`
- Every `SKILL.md` must include all 16 official Claude Code frontmatter fields plus `metadata.updated-date` — validated by `scripts/validate-skill-frontmatter.py`
- No install step exists — this is a plugin, not a standalone tool

## Key files

| Path | Purpose |
|------|---------|
| `.claude-plugin/plugin.json` | Plugin manifest — name, version, dependencies, statusLine |
| `hooks/hooks.json` | Hook event wiring (PreToolUse, SessionStart, etc.) |
| `hooks/lib/worktree-common.sh` | Shared bash helpers for all worktree hooks — do not modify without shellchecking |
| `skills/<domain>/<name>/SKILL.md` | Bundled skill definitions — grouped by domain |
| `statusline.sh` | Statusline script wired via `plugin.json` |
| `.mcp.json` | MCP server stubs — fill env vars to activate |
| `Makefile` | `validate`, `lint`, `test` targets |

## Off-limits

- Never modify `hooks/lib/worktree-common.sh` without running shellcheck and testing both `capture-task-slug.sh` and `worktree-create.sh`
- Never commit to `main` directly — always use a feature branch and PR
- Never add a `marketplace.json` to this repo — it is published through the separate `Tamircohen28/plugins` catalog
- Never hand-write a `SKILL.md` from scratch — use the `skill-creator` skill to ensure evals, references, and quality standards are met
