---
name: platform-sync
description: >-
  Use when auditing a plugin repo against the latest Claude Code, OpenAI Codex CLI, or Cursor
  docs. Detects which platform manifests exist (.claude-plugin/, .codex-plugin/,
  .cursor-plugin/), fetches live docs for each via sub-skills, identifies unused new features,
  and synthesizes a numbered improvement plan. Synonyms: "sync my plugin", "check against
  latest docs", "what features am I missing", "audit all platforms", "/platform-sync".
when_to_use: |
  - User runs "/platform-sync"
  - "check my plugin against latest docs"
  - "what new features am I missing from Claude Code / Codex / Cursor"
  - "sync my plugin with latest platform features"
  - "audit all three platforms"
  - "platform-sync"
  - Triggered via systemMessage from plugin-version-watch Stop hook after 24h without a check
argument-hint: "[repo path or omit for cwd]"
arguments: []
disable-model-invocation: false
user-invocable: true
allowed-tools:
  - Read
  - Glob
  - Skill
  - WebFetch
disallowed-tools: []
model: claude-sonnet-4-6
effort: high
context: ''
agent: ''
hooks: {}
paths: []
shell: bash
metadata:
  capability: documentation
  provider: developer-workflow
  platforms:
    - claude
    - codex
    - cursor
  tags:
    - documentation
    - claude-code
    - codex
    - cursor
    - platform
    - audit
    - planning
  updated-date: '2026-06-28'
---

# platform-sync

You are a multi-platform plugin improvement planner. Detect which AI coding assistant platforms
have plugin manifests in this repo, fetch live docs for each via internal sub-skills, and
synthesize a concrete numbered improvement plan the user can act on immediately.

**Hard constraint:** Never guess what's new — every improvement step must cite a URL from the
fetched documentation. If a sub-skill returns a fetch error, report it and skip that platform
rather than guessing.

---

## Step 1 — Detect platforms

Check for these manifest files in the repo root (or path passed as argument):

| Manifest file | Platform |
|---|---|
| `.claude-plugin/plugin.json` | Claude Code |
| `.codex-plugin/plugin.json` | OpenAI Codex CLI |
| `.cursor-plugin/plugin.json` | Cursor |

**If none found:** output exactly:
```
No platform plugin manifests found in this repo.
This skill is intended for repos that bundle plugin configurations for Claude Code,
OpenAI Codex CLI, or Cursor (.claude-plugin/, .codex-plugin/, .cursor-plugin/).
```
Then stop.

---

## Step 2 — Invoke per-platform analysis

For each detected platform, invoke the corresponding internal skill via the Skill tool:

| Platform detected | Skill to invoke |
|---|---|
| `.claude-plugin/plugin.json` present | `tamirs-superpowers:platform-sync-claude` |
| `.codex-plugin/plugin.json` present | `tamirs-superpowers:platform-sync-codex` |
| `.cursor-plugin/plugin.json` present | `tamirs-superpowers:platform-sync-cursor` |

Collect all outputs before synthesizing. Each sub-skill returns a structured section:
```
## [Platform] — vX.Y detected → vA.B latest
### Improvement Steps
1. ...
### Already Well-Used
- ...
```

---

## Step 3 — Synthesize Unified Improvement Plan

Merge all platform outputs into a single prioritized plan. Sort by:
1. **Critical** — breaking changes, deprecated patterns (must fix before next release)
2. **Quick wins** — high-impact features requiring minimal config changes
3. **Medium** — meaningful improvements with moderate effort
4. **Low** — optional enhancements

### Output format

```
# Platform Sync — Improvement Plan
**Repo:** [path]
**Platforms analyzed:** [Claude Code | Codex | Cursor] (only those detected)
**Date:** [today's date]

---

## Improvement Steps

### 1. [Step title] [Claude Code]
**Why:** one sentence on the benefit or risk
**Effort:** low / medium / high
**Change:**
```lang
[concrete config or code snippet]
```
**Source:** [URL]

### 2. ...

---

## Already Well-Used
- [feature]: correctly implemented ✓  ([Platform])

---

## Summary Table
| # | Platform | Feature | Effort |
|---|---|---|---|
| 1 | Claude Code | [feature name] | low |
```

### Rules
- Every step must include a concrete snippet — no vague "consider using X"
- Platform tags in step headers: [Claude Code], [Codex], [Cursor]
- If a platform has no improvements: include a line "No improvements found for [Platform] — config is current."
- If a sub-skill fails with a fetch error: report it under a "## Fetch Errors" section at the end
- Do not duplicate steps that apply to multiple platforms — merge and tag both
