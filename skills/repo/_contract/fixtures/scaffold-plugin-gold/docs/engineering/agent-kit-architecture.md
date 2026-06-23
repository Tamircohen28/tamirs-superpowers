# Agent-kit architecture

This repo is an **agent-kit distribution** — one canonical source, multiple generated adapters.

## Layout

```
canonical/rules/     # tool-neutral policy (source of truth)
canonical/skills/    # portable SKILL.md folders
scripts/build.mjs    # generates dist/ + plugin skills
dist/codex/          # AGENTS.md for Codex / general agents
dist/cursor/         # .cursor/rules/*.mdc for Cursor
plugins/<name>/      # Claude Code plugin wrapper
.claude-plugin/marketplace.json
```

## Contributor workflow

1. Edit files under `canonical/` only — never edit `dist/` by hand.
2. Run `npm run build` to regenerate adapters.
3. Run `npm run validate` before opening a PR.
