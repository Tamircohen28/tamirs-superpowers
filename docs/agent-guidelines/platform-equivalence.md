# Platform capability equivalence

Maps **tamirs-superpowers** capabilities across the four supported targets: Claude Code, Cursor, Codex, and OpenCode.

Platform tool versions: [`../engineering/build-and-release/platform-targets.md`](../engineering/build-and-release/platform-targets.md).
Per-target install guides: [`../user/install/`](../user/install/README.md).

## Instructions

| Capability | Claude Code | Cursor | Codex | OpenCode |
|------------|-------------|--------|-------|----------|
| Repo policy | `CLAUDE.md` → `@AGENTS.md` | `.cursor/rules/*.mdc` → `AGENTS.md` | `AGENTS.md` | `AGENTS.md` |

## Skills

| Capability | Claude Code | Cursor | Codex | OpenCode |
|------------|-------------|--------|-------|----------|
| Bundled skills | `skills/` via `.claude-plugin/plugin.json` | same paths in `.cursor-plugin/plugin.json` | same paths in `.codex-plugin/plugin.json` | `skills.paths` in `opencode.json`, or a symlink into a scanned path |

OpenCode scans `.opencode/skills/`, `.claude/skills/`, and `.agents/skills/` (project and global) natively, and the scan **is** recursive — the domain-nested `skills/<domain>/<name>/SKILL.md` layout is discovered as-is. OpenCode's published docs claim otherwise; verified against 1.16.2 and 1.18.11 with `opencode debug skill`.

## Agents

| Capability | Claude Code | Cursor | Codex | OpenCode |
|------------|-------------|--------|-------|----------|
| Specialist agents | `agents/*.md` via the Agent tool | `agents/` auto-discovered from the plugin root | `agents/` at the repo root | `.opencode/agent/*.md` — generated adapters |

OpenCode validates agent frontmatter strictly and refuses to start on a bad field: `tools` must be an object of tool→boolean (not Claude's comma string) and `model` needs a provider prefix. `scripts/build-opencode-agents.sh` translates `agents/*.md` into `.opencode/agent/*.md`; the output is committed so a clone needs no build step. Regenerate with `make opencode-agents`; `make agent:check` fails on drift.

## MCP servers

| Capability | Claude Code | Cursor | Codex | OpenCode |
|------------|-------------|--------|-------|----------|
| Stubs | `.mcp.json` | `mcpServers` in `.cursor-plugin/plugin.json` | `mcpServers` in `.codex-plugin/plugin.json` + optional `.codex/config.toml` | manual — port entries into the `mcp` block of `opencode.json` |

Fill `${ENV_VAR}` placeholders locally — never commit tokens.

## Hooks / lifecycle automation

| Capability | Claude Code | Cursor | Codex | OpenCode |
|------------|-------------|--------|-------|----------|
| Worktree hooks | `hooks/hooks.json` (when present) | No native `hooks.json` — use scoped `.mdc` rules + session discipline | `hooks` field in `.codex-plugin/plugin.json` when Claude hooks ship | ❌ none — lifecycle automation is JS/TS plugin modules only |

**Cursor substitute:** enforce worktree and sensitive-file rules via contributor docs in `AGENTS.md` and path-scoped Cursor rules under `.cursor/rules/`.

**OpenCode gap:** OpenCode has no `hooks.json` equivalent. Its `"plugin"` config field takes JavaScript/TypeScript modules — a different mechanism from a skill bundle — so the worktree guards in `hooks/` do not port. Rely on `AGENTS.md` discipline there.

## Install and distribution

| Capability | Claude Code | Cursor | Codex | OpenCode |
|------------|-------------|--------|-------|----------|
| Standalone install from this repo | ✅ `/plugin marketplace add Tamircohen28/tamirs-superpowers` | ✅ Import from Repo | ✅ `codex plugin marketplace add Tamircohen28/tamirs-superpowers` | ✅ by path (symlink or `skills.paths`) |
| Marketplace manifest | `.claude-plugin/marketplace.json` / catalog | `.cursor-plugin/plugin.json` (+ `marketplace.json` for multi-plugin repos) | `.agents/plugins/marketplace.json` | ❌ no marketplace |
| Update mechanism | `/plugin update` — keyed on `version` | Auto Refresh re-reads the whole manifest | `codex plugin marketplace upgrade` | `git pull` |

## Claude-only features (documented asymmetry)

| Feature | Notes |
|---------|-------|
| Statusline | `.claude-plugin/plugin.json` `settings.statusLine` — Claude Code only |
| Plugin dependency resolution | Declared dependencies auto-install on Claude Code only |
| Full hook suite | Worktree guards, session init, notification hooks — Claude Code (and Codex via the `hooks` field) |

These are intentional; they do not block multi-platform skill and policy parity.
