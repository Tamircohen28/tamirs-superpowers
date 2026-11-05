# Platform equivalence (fixture)

Capability parity, not file parity. The authoritative status for every target is
`core/capabilities/platforms.json`; this table is the human-readable substitute map for
the capability a marketplace repo exists to exercise.

| Feature | Claude Code / Desktop | Cursor | Codex CLI | Gemini CLI | OpenCode |
|---------|----------------------|--------|-----------|------------|----------|
| Marketplace | `.claude-plugin/marketplace.json` | `.cursor-plugin/marketplace.json` | `.agents/plugins/marketplace.json` (also reads the Claude file) | partial — extensions gallery by GitHub topic, no catalog manifest | unsupported — no marketplace; plugins are npm packages named in `opencode.json` |
| Hooks | `hooks/hooks.json` inside a plugin | partial — scoped `.mdc` rules as substitute | `.codex-plugin/plugin.json` `hooks` field | unknown — claim nothing | unsupported |
| Skills | `plugins/<name>/skills` via the plugin's manifest | same | same | not shipped in this fixture | not shipped in this fixture |

Cursor has no `hooks.json` — use rules as substitute. Claude Desktop installs from the
Claude Code listing: it needs no manifest of its own.
