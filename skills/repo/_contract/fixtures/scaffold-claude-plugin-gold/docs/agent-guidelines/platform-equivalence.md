# Platform equivalence (fixture)

Capability parity, not file parity. The authoritative status for every target is
`core/capabilities/platforms.json`; this table is the human-readable substitute map for
the one capability that genuinely has no portable artifact.

| Feature | Claude Code / Desktop | Cursor | Codex CLI | Gemini CLI | OpenCode |
|---------|----------------------|--------|-----------|------------|----------|
| Hooks | `hooks/hooks.json` | partial — scoped `.mdc` rules as substitute | `.codex-plugin/plugin.json` `hooks` field | unknown — manifest field loads but firing is unverified; claim nothing | unsupported — no `hooks.json`; guards move to skills + CI |
| Skills | `skills/` via manifest | `skills/` via manifest | `skills/` via manifest | `gemini-extension.json` | `opencode.json` `skills.paths` |
| MCP | `.mcp.json` via manifest | `.mcp.json` via manifest | `.mcp.json` via manifest | `gemini-extension.json` `mcpServers` | `opencode.json` `mcp` |

Cursor has no `hooks.json` — use rules as substitute. Claude Desktop is a runtime surface
of the Claude Code plugin, not a separate format: it needs no manifest of its own.
