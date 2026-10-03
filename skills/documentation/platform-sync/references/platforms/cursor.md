# Platform reference data — `cursor`

Data consumed by the `platform-sync` engine (`references/analysis-protocol.md`).

- **Display name:** Cursor
- **Registry id:** `cursor` (same in the registry, in `platform-targets.json`, and in a skill's `compatibility` block)

## Detection signals

| Signal | Path / pattern | Strength |
|--------|----------------|----------|
| Plugin manifest | `.cursor-plugin/plugin.json` | strong |
| Project rules | `.cursor/rules/*.mdc` | strong |
| Legacy rules | `.cursorrules` | medium |
| MCP config | `.cursor/mcp.json`, or `mcpServers` in the plugin manifest | weak |

## Sources — P0 (fetch always; failure aborts this platform only)

| Topic | URL |
|---|---|
| Cursor changelog | https://docs.cursor.com/changelog |

## Sources — P1

| Fetch when local config contains / lacks | URL |
|---|---|
| `.cursorrules` or any rules config | https://docs.cursor.com/context/rules |
| MCP servers | https://docs.cursor.com/tools/mcp |
| General orientation | https://docs.cursor.com/ |

## Sources — P2

| Topic | URL |
|---|---|
| Extensions | https://docs.cursor.com/extensions |
| Model configuration | https://docs.cursor.com/ai/models |
| Codebase indexing | https://docs.cursor.com/context/codebase-indexing |
| Context files | https://docs.cursor.com/context/context-files |

## Local config to read

| Path | What to note |
|------|--------------|
| `.cursor-plugin/plugin.json` | `version`, `skills`, `mcpServers` |
| `.cursor/rules/*.mdc` | `alwaysApply`, `globs`, body pointers to `AGENTS.md` |
| `.cursorrules` | Legacy content — recommend migration to `.mdc` |
| `.cursor/mcp.json` | MCP servers |
| `AGENTS.md` | Whether the rules import canonical agent policy rather than duplicating it |

App repos without a Cursor manifest: report the declared version as `not set` and focus on
`.cursor/rules/`.

## Feature-scan areas

- **Rules format** — legacy `.cursorrules` flat file instead of `.cursor/rules/*.mdc` with
  per-path glob scoping.
- **Rule drift** — a `.mdc` rule that restates canonical policy instead of pointing at
  `AGENTS.md` is drift waiting to happen (spec §27 defect 7). Flag duplicated prose.
- **MCP** — servers wired for other targets but not for Cursor.
- **Model config** — pinned models that the changelog has superseded.
- **Context features** — new indexing/doc-attachment features not yet used.

## Version detection

Declared: `.cursor-plugin/plugin.json` → `version`, else `not set`.
Latest: the newest version named in the changelog.

## Capability boundaries

Cursor has no Claude-style `hooks.json` and no plugin-declared statusline. Check the
capability registry before porting a feature from another target.
