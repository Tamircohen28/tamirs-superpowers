# Platform reference data — `claude-code`

Data consumed by the `platform-sync` engine (`references/analysis-protocol.md`).
This file contains **no orchestration logic** — only the facts the engine needs.

- **Display name:** Claude Code
- **Platform:** `claude` (display name "Claude") in `core/capabilities/platforms.json`. The
  registry is rooted at the platform; surfaces live under `.platforms.claude.surfaces`.
- **Registry id (surface):** `claude_code`, under `.platforms.claude.surfaces.claude_code`;
  `claude-code` in `platform-targets.json` and in a skill's `compatibility` block
- **Sibling surface:** `claude_desktop` — display name "Claude Desktop", **supported**, with
  its own measured capability rows. It carries `runtime_surface_of: claude_code` and consumes
  the same plugin artifact, so analyse the artifact once and note in the output that findings
  apply to both surfaces. Do **not** emit a second Claude Desktop section.

Claude is the one platform in the registry with no unverified surface — both of its
surfaces are supported.

Look either surface up with:

```bash
jq --arg p claude_code '(first(.platforms[]?.surfaces[$p]? | select(. != null)) // .platforms[$p]?)' \
   core/capabilities/platforms.json
```

## Detection signals

| Signal | Path / pattern | Strength |
|--------|----------------|----------|
| Plugin manifest | `.claude-plugin/plugin.json` | strong |
| Project memory | `CLAUDE.md` | strong |
| Scoped rules | `.claude/rules/*.md` | strong |
| Project skills | `.claude/skills/**/SKILL.md` | strong |
| Plugin skills tree | `skills/**/SKILL.md` + `hooks/hooks.json` | medium |
| Hooks only | `hooks/hooks.json` (Claude hook events) | medium |
| Subagents | `.claude/agents/*.md` or `agents/*.md` | medium |
| MCP stub | `.mcp.json` | weak |
| Slash commands | `commands/` directory | weak |

## Sources — P0 (fetch always; failure aborts this platform only)

| Topic | URL |
|---|---|
| GitHub releases | https://github.com/anthropics/claude-code/releases |
| Changelog | https://code.claude.com/docs/en/changelog |
| What's new | https://code.claude.com/docs/en/whats-new |

## Sources — P1 (fetch conditionally)

Base: `https://code.claude.com/docs/en/<topic>`

| Fetch when local config contains | Topic |
|---|---|
| `hooks/hooks.json` | `hooks`, `hooks-guide` |
| `skills/` tree | `skills` |
| `.claude-plugin/plugin.json` | `plugins`, `plugins-reference` |
| `agents/` or subagent references | `sub-agents` |
| agent-team usage or `SendMessage` | `agent-teams` |
| `.mcp.json` / MCP servers | `mcp` |
| `settings.json` | `settings`, `permission-modes` |
| `CLAUDE.md` or `.claude/rules/` | `memory` |

## Sources — P2 (only on explicit request)

| Topic | URL |
|---|---|
| Statusline | https://code.claude.com/docs/en/statusline |
| Output styles | https://code.claude.com/docs/en/output-styles |
| CLI reference | https://code.claude.com/docs/en/cli-reference |

## Local config to read

| Path | What to note |
|------|--------------|
| `.claude-plugin/plugin.json` | `version`, `skills`, `hooks`, `settings`, `commands` |
| `skills/**/SKILL.md` | Skill names, frontmatter tiers, tool usage |
| `.claude/skills/**/SKILL.md` | Project-scoped skills |
| `hooks/hooks.json` | Hook events, matchers, scripts |
| `.mcp.json` | Declared MCP servers |
| `CLAUDE.md` | Memory imports, commands, constraints |
| `.claude/rules/*.md` | Path-scoped rule patterns |
| `commands/` | Slash command definitions |
| `agents/*.md`, `.claude/agents/*.md` | Specialist subagents |

App repos without a plugin manifest: focus on `CLAUDE.md`, `.claude/rules/`,
`.claude/skills/`, `hooks/hooks.json`. Report the detected version as `project-only`.

## Feature-scan areas

- **Hook events** — events documented but absent from `hooks.json`.
- **Skill frontmatter** — new fields since the declared version (`context: fork`, `paths:`,
  invocation-tier flags, `effort` tiers). Cross-check against
  `core/schemas/skill-frontmatter.json`: a Claude-only field belongs in the Claude
  extension tier, never in the portable core.
- **Plugin manifest fields** — new `settings` options, new hook types.
- **Subagents** — multi-domain skill catalogue with no `agents/` directory.
- **Agent teams** — multi-agent work driven by Bash calls to `claude` instead.
- **MCP** — relevant servers not declared in `.mcp.json`.
- **Memory / rules** — new `CLAUDE.md` sections or path-scoped `.claude/rules/` overrides.

## Version detection

Declared: `.claude-plugin/plugin.json` → `version`, else `project-only`.
Latest: newest tag on the releases feed.

## Capability boundaries

None beyond the registry — Claude Code is the capability superset in this framework.
Do not treat that as licence to recommend a Claude-only pattern as a portable one.
