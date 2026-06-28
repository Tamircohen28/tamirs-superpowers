---
name: platform-sync-cursor
description: >-
  Internal companion to platform-sync. Fetches live Cursor docs (docs.cursor.com), reads
  the local .cursor-plugin/plugin.json, identifies new Cursor features not yet used, and
  returns structured improvement steps. Not user-invocable — called by the platform-sync
  umbrella skill.
when_to_use: |
  Invoked by the platform-sync umbrella when .cursor-plugin/plugin.json is detected.
  Also callable by other skills needing live Cursor improvement suggestions:
  - "audit my cursor plugin"
  - "what Cursor features am I missing"
  - "review .cursor-plugin against latest Cursor docs"
argument-hint: "[none]"
arguments: []
disable-model-invocation: true
user-invocable: false
allowed-tools:
  - Read
  - WebFetch
disallowed-tools: []
model: claude-sonnet-4-6
effort: medium
context: ''
agent: ''
hooks: {}
paths: []
shell: bash
metadata:
  capability: documentation
  provider: developer-workflow
  platforms:
    - cursor
  tags:
    - documentation
    - cursor
    - audit
    - planning
  updated-date: '2026-06-28'
---

# platform-sync-cursor

You are a Cursor plugin improvement analyst. Fetch live Cursor docs, compare against the
local `.cursor-plugin/plugin.json`, and return structured improvement steps.

**Hard constraint:** Every finding must cite a URL from `$CLAUDE_SKILL_DIR/references/urls.md`.
If any P0 fetch fails, stop and return the error. Do not guess from training knowledge.

---

## Step 1 — Fetch live docs

Read `$CLAUDE_SKILL_DIR/references/urls.md` for the full permitted URL list.

Always fetch (P0 — required):
1. `https://docs.cursor.com/changelog` — latest version and new features

If P0 fetch fails, stop and output:
```
⛔ FETCH ERROR
URL: <url>
Error: <error message>
Cannot proceed — required Cursor source could not be fetched.
```

Then fetch P1 docs based on local config:

| Local config contains / missing | Fetch URL |
|---|---|
| .cursorrules file or rules config | `https://docs.cursor.com/context/rules` |
| MCP servers | `https://docs.cursor.com/tools/mcp` |
| Extensions / plugin fields | `https://docs.cursor.com/extensions` |
| Model pinning | `https://docs.cursor.com/ai/models` |

---

## Step 2 — Read local config

Read `.cursor-plugin/plugin.json`. Note:
- `version` field
- `skills` paths declared
- `mcpServers` config (if any)
- Any other fields

Also check the repo root for Cursor-specific files:
- `.cursorrules` (legacy rules file)
- `.cursor/rules/` directory (modern scoped rules)
- `.cursor/mcp.json` (Cursor MCP config)

---

## Step 3 — Identify unused features

**Cursor Rules:** Is the repo using `.cursor/rules/` directory (modern, supports per-path
scoping with glob frontmatter) rather than the legacy `.cursorrules` flat file? If using
the legacy format, recommend migration.

**MCP:** Does the changelog indicate Cursor MCP support is available? If the local config
doesn't wire any MCP servers, flag it as an improvement opportunity.

**Model config:** Are models pinned or configured in the plugin? Have new models become
available that would improve output for this plugin's use case?

**Context features:** Any new codebase indexing, doc integration, or context attachment
features not yet leveraged by the plugin config?

**Skills / commands:** Any Cursor-specific skill or command config options not yet used?

---

## Step 4 — Output

```
## Cursor — v{version from .cursor-plugin/plugin.json or "not set"} detected → latest (from changelog)

### Improvement Steps
1. [Feature name] — [one sentence why it applies to this repo]
   Config:
   ```json
   [concrete copy-pasteable snippet]
   ```
   Effort: low / medium / high
   Source: [URL]

2. ...

### Already Well-Used
- [feature]: [brief note] ✓
```

Return this section only — the platform-sync umbrella merges it with other platforms.
