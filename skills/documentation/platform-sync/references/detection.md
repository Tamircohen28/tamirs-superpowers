# Platform detection — platform-sync

Detect which AI coding assistant **targets** a repo uses before invoking sub-skills.
A repo may use zero, one, or many targets. Scan the repo root (or path argument) for
**any** signal below — manifests are the strongest signal but not required.

## Claude Code

| Signal | Path / pattern | Strength |
|--------|----------------|----------|
| Plugin manifest | `.claude-plugin/plugin.json` | strong |
| Project memory | `CLAUDE.md` | strong |
| Scoped rules | `.claude/rules/*.md` | strong |
| Project skills | `.claude/skills/**/SKILL.md` | strong |
| Plugin skills tree | `skills/**/SKILL.md` + `hooks/hooks.json` | medium |
| Hooks only | `hooks/hooks.json` (Claude hook events) | medium |
| MCP stub | `.mcp.json` | weak |
| Slash commands | `commands/` directory | weak |

**Invoke:** `tamirs-superpowers:platform-sync-claude` when **any** Claude Code signal is present.

## Cursor

| Signal | Path / pattern | Strength |
|--------|----------------|----------|
| Plugin manifest | `.cursor-plugin/plugin.json` | strong |
| Project rules | `.cursor/rules/*.mdc` | strong |
| Legacy rules | `.cursorrules` | medium |
| MCP config | `.cursor/mcp.json` or `mcpServers` in plugin manifest | weak |

**Invoke:** `tamirs-superpowers:platform-sync-cursor` when **any** Cursor signal is present.

## OpenAI Codex CLI

| Signal | Path / pattern | Strength |
|--------|----------------|----------|
| Plugin manifest | `.codex-plugin/plugin.json` | strong |
| Agents file | `AGENTS.md` at repo root | strong |
| Codex config | `.codex/` or `codex.config.*` | medium |

**Invoke:** `tamirs-superpowers:platform-sync-codex` when **any** Codex signal is present.

## No targets detected

If **no** signals match any platform, output:

```
No AI coding assistant usage detected in this repo.
platform-sync looks for Claude Code (CLAUDE.md, .claude-plugin/, skills/, hooks/),
Cursor (.cursor/rules/, .cursor-plugin/), or Codex (AGENTS.md, .codex-plugin/).
Add agent config for at least one platform, then re-run /platform-sync.
```

Then stop — do not invoke sub-skills or guess.

## Sub-skill local config scope

Each sub-skill must read **all** detected local artifacts for its platform (not only
plugin manifests). See each sub-skill's "Read local config" step for the full file list.
