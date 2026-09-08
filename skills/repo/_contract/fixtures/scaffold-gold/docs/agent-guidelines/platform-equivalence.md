# Platform equivalence (fixture)

Capability parity, not file parity. The authoritative status for every target is
`core/capabilities/platforms.json`; this table is the human-readable substitute map for
the platforms that have no portable artifact of their own.

App-gold ships no `.claude-plugin/plugin.json` and is not installed as a plugin on any
target — every row below is a **non-plugin, project-level** convention instead of a
manifest-declared one.

| Feature | Claude Code | Cursor | Codex CLI |
|---------|-------------|--------|-----------|
| Hooks | `.claude/settings.json` `hooks` key (project-level, not `hooks/hooks.json` — that requires a plugin manifest app-gold does not ship) | soft guards via `.cursor/hooks.json`; third-party Claude hooks via `.claude/settings.json` are opt-in in Cursor Settings | unknown — the manifest `hooks` field requires a plugin manifest app-gold does not ship, and no non-plugin Codex hooks convention is documented |
| Subagents | `.claude/agents/*.md`, discovered with no plugin manifest required | folder discovery of `agents/` is unverified for this shape (see registry) | unknown — see registry |
| MCP | `.mcp.json` | `.mcp.json` (read directly; no plugin manifest required) | unknown — the manifest `mcpServers` field requires a plugin manifest app-gold does not ship |

Claude Desktop is a runtime surface of the Claude Code convention above, not a separate
format — see the registry for what is and isn't verified there.
