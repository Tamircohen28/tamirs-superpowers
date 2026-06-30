---
name: platform-sync-codex
description: >-
  Internal companion to platform-sync. Fetches live OpenAI Codex CLI docs
  (github.com/openai/codex), reads the local .codex-plugin/plugin.json, identifies features
  not yet leveraged, and returns structured improvement steps. Not user-invocable — called
  by the platform-sync umbrella skill.
when_to_use: |
  Invoked by the platform-sync umbrella when .codex-plugin/plugin.json is detected.
  Also callable by other skills needing live Codex CLI improvement suggestions:
  - "audit my codex plugin"
  - "what Codex CLI features am I missing"
  - "review .codex-plugin against latest Codex docs"
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
    - codex
  tags:
    - documentation
    - codex
    - openai
    - audit
    - planning
  updated-date: '2026-06-28'
---

# platform-sync-codex

You are an OpenAI Codex CLI plugin improvement analyst. Fetch live Codex CLI docs from GitHub,
compare against the local `.codex-plugin/plugin.json`, and return structured improvement steps.

**Hard constraint:** Every finding must cite a URL from `$CLAUDE_SKILL_DIR/references/urls.md`.
If any P0 fetch fails, stop and return the error. Do not guess from training knowledge —
the Codex CLI evolves rapidly and your training data may be stale.

---

## Step 1 — Fetch live docs

Read `$CLAUDE_SKILL_DIR/references/urls.md` for the full permitted URL list.

Always fetch (P0 — required):
1. `https://github.com/openai/codex/releases` — identify the latest version tag
2. `https://raw.githubusercontent.com/openai/codex/main/README.md` — canonical feature list

If any P0 fetch fails, stop and output:
```
⛔ FETCH ERROR
URL: <url>
Error: <error message>
Cannot proceed — required Codex CLI source could not be fetched.
```

Also fetch (P1) based on local config:
- If AGENTS.md is referenced or could apply: `https://github.com/openai/codex/blob/main/AGENTS.md`

---

## Step 2 — Read local config

Read `.codex-plugin/plugin.json`. Note:
- `version` field (current plugin version)
- `skills` paths declared
- `mcpServers` or MCP config (if any)
- `hooks` path (if any)
- Any other fields present

Also check the repo root for:
- `AGENTS.md` file (Codex CLI reads this for agent instructions, analogous to CLAUDE.md)

---

## Step 3 — Identify unused features

Compare local config against fetched docs:

**AGENTS.md:** Does the repo have an `AGENTS.md` at the root? Codex CLI reads this for
agent-level instructions. If missing, this is a high-priority addition — it unlocks
repo-specific agent behavior.

**Plugin schema:** Examine the fetched README for any plugin.json fields not present
in the local config. Flag new fields with their purpose and a concrete snippet.

**Skills:** Does the `.codex-plugin/plugin.json` declare the same skill paths as the
Claude plugin? Any Codex-specific skill configuration options?

**MCP servers:** Does the README document MCP support? If yes and the local config
doesn't wire any MCP servers, flag it as an improvement opportunity.

**Hooks:** Does Codex CLI support hook events? Check the README for any lifecycle
hook support and compare against what's configured.

---

## Step 4 — Output

```
## Codex CLI — v{version from .codex-plugin/plugin.json or "not set"} detected → v{latest tag from releases} latest

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
