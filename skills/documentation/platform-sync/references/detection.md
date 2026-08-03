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

## OpenCode

| Signal | Path / pattern | Strength |
|--------|----------------|----------|
| Config file | `opencode.json` at repo root | strong |
| Agent adapters | `.opencode/agent/*.md` | strong |
| Plugin modules | `.opencode/plugin/*.{js,ts}` | medium |
| Config directory | `.opencode/` (any contents) | medium |
| Global config only | `~/.config/opencode/opencode.json` | weak — repo may rely on user config |

**Invoke:** `tamirs-superpowers:platform-sync-opencode` when **any** OpenCode signal is present.

> OpenCode has **no plugin manifest** — there is no `.opencode-plugin/plugin.json` to look
> for, and no marketplace entry. A repo that supports OpenCode is identified by
> `opencode.json` and `.opencode/`, not by a versioned manifest. Do not treat the absence
> of a manifest as absence of the target.

## No targets detected

If **no** signals match any platform, output:

```
No AI coding assistant usage detected in this repo.
platform-sync looks for Claude Code (CLAUDE.md, .claude-plugin/, skills/, hooks/),
Cursor (.cursor/rules/, .cursor-plugin/), Codex (AGENTS.md, .codex-plugin/), or
OpenCode (opencode.json, .opencode/).
Add agent config for at least one platform, then re-run /platform-sync.
```

Then stop — do not invoke sub-skills or guess.

## Sub-skill local config scope

Each sub-skill must read **all** detected local artifacts for its platform (not only
plugin manifests). See each sub-skill's "Read local config" step for the full file list.
