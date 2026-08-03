# OpenCode — URL Master List

All URLs this skill is permitted to use as sources. Every response MUST be grounded
exclusively in content fetched from these URLs. No hallucination. No prior knowledge.

---

## Changelog & Releases

| Priority | Topic | URL |
|---|---|---|
| P0 | OpenCode releases (tags, dates, notes) | https://github.com/sst/opencode/releases |
| P0 | npm dist-tags — authoritative `latest` | https://registry.npmjs.org/opencode-ai/latest |

OpenCode ships no hand-written changelog page; the GitHub releases feed is the
changelog. Use the npm `latest` endpoint for the version string — it is the same
artifact `npm i -g opencode-ai` installs, so it cannot drift from what users get.

---

## Documentation

| Priority | Topic | URL |
|---|---|---|
| P1 | Skills — discovery, frontmatter, `skills.paths` | https://opencode.ai/docs/skills/ |
| P1 | Agents — `.opencode/agent/` markdown adapters | https://opencode.ai/docs/agents/ |
| P1 | Config schema (`opencode.json`) | https://opencode.ai/config.json |
| P2 | Plugins — JS/TS lifecycle modules | https://opencode.ai/docs/plugins/ |
| P2 | MCP servers | https://opencode.ai/docs/mcp-servers/ |
| P2 | Rules / instructions files | https://opencode.ai/docs/rules/ |

---

## Priority Legend

- **P0** — Always fetch for version/changelog-aware responses
- **P1** — Fetch when topic is directly relevant to the query
- **P2** — Fetch only when specifically asked or when P1 sources are insufficient

---

## Capability boundaries (do not recommend across these)

OpenCode does **not** have a plugin marketplace, a `hooks.json`, or a plugin-declared
statusline. Never generate an improvement step that assumes one exists — the
authoritative gap list is `capability_gaps` under `targets.opencode` in
`docs/engineering/build-and-release/platform-targets.json`. Read it before proposing
anything that ports a Claude Code or Cursor feature to OpenCode.
