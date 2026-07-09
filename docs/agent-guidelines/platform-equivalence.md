# Platform capability equivalence

Maps Claude Code features to Cursor and Codex equivalents for **tamirs-superpowers**.

Platform tool versions: [`../engineering/build-and-release/platform-targets.md`](../engineering/build-and-release/platform-targets.md).

## Instructions

| Capability | Claude Code | Cursor | Codex |
|------------|-------------|--------|-------|
| Repo policy | `CLAUDE.md` → `@AGENTS.md` | `.cursor/rules/*.mdc` → `AGENTS.md` | `AGENTS.md` |

## Skills

| Capability | Claude Code | Cursor | Codex |
|------------|-------------|--------|-------|
| Bundled skills | `skills/` via `.claude-plugin/plugin.json` | same paths in `.cursor-plugin/plugin.json` | same paths in `.codex-plugin/plugin.json` |

## MCP servers

| Capability | Claude Code | Cursor | Codex |
|------------|-------------|--------|-------|
| Stubs | `.mcp.json` | `mcpServers` in `.cursor-plugin/plugin.json` | `mcpServers` in `.codex-plugin/plugin.json` + optional `.codex/config.toml` |

Fill `${ENV_VAR}` placeholders locally — never commit tokens.

## Hooks / lifecycle automation

| Capability | Claude Code | Cursor | Codex |
|------------|-------------|--------|-------|
| Worktree hooks | `hooks/hooks.json` (when present) | No native `hooks.json` — use scoped `.mdc` rules + session discipline | `hooks` field in `.codex-plugin/plugin.json` when Claude hooks ship |

**Cursor substitute:** enforce worktree and sensitive-file rules via contributor docs in `AGENTS.md` and path-scoped Cursor rules under `.cursor/rules/`.

## Claude-only features (documented asymmetry)

| Feature | Notes |
|---------|-------|
| Marketplace install | Claude Code: `/plugin marketplace add` — see README Quick Start |
| Statusline | `.claude-plugin/plugin.json` `settings.statusLine` — Claude Code only |
| Specialist agents | Claude Code Agent tool — not mirrored on Cursor/Codex |

These are intentional; they do not block multi-platform skill and policy parity.
