---
name: platform-sync
description: >-
  Use when auditing any repo that uses Claude Code, OpenAI Codex CLI, or Cursor — plugin
  repos, app repos, or hybrids. Detects target usage via manifests, CLAUDE.md, AGENTS.md,
  .cursor/rules/, skills/, hooks/, and related signals; fetches live docs per target;
  identifies unused new features; synthesizes a numbered improvement plan. Synonyms: "sync my
  plugin", "check against latest docs", "what features am I missing", "audit all platforms",
  "/platform-sync".
when_to_use: |
  - User runs "/platform-sync"
  - "check my repo against latest Claude Code / Codex / Cursor docs"
  - "what new features am I missing"
  - "sync my plugin with latest platform features"
  - "audit all three platforms"
  - "platform-sync"
  - App repo with CLAUDE.md, AGENTS.md, or .cursor/rules/ — not only plugin manifests
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
  updated-date: '2026-06-30'
---

# platform-sync

You are a multi-platform improvement planner. Detect which AI coding assistant targets a repo
**actually uses** (not only plugin manifests), fetch live docs for each via internal
sub-skills, and synthesize a concrete numbered improvement plan.

**Hard constraint:** Never guess what's new — every improvement step must cite a URL from the
fetched documentation. If a sub-skill returns a fetch error, report it and skip that platform
rather than guessing.

**Detection reference:** Read `$CLAUDE_SKILL_DIR/references/detection.md` before Step 1.

---

## Step 1 — Detect targets

Glob and read the repo root (or path passed as argument). For each platform, check **all**
signals in `references/detection.md` — invoke a sub-skill when **any** signal matches.

| Platform | Sub-skill when detected |
|---|---|
| Claude Code | `tamirs-superpowers:platform-sync-claude` |
| Cursor | `tamirs-superpowers:platform-sync-cursor` |
| Codex CLI | `tamirs-superpowers:platform-sync-codex` |

Record which signals triggered each platform (e.g. `CLAUDE.md + skills/`).

**If no platform signals match:** output exactly:
```
No AI coding assistant usage detected in this repo.
platform-sync looks for Claude Code (CLAUDE.md, .claude-plugin/, skills/, hooks/),
Cursor (.cursor/rules/, .cursor-plugin/), or Codex (AGENTS.md, .codex-plugin/).
Add agent config for at least one platform, then re-run /platform-sync.
```
Then stop.

---

## Step 2 — Invoke per-platform analysis

For each detected platform, invoke the corresponding internal skill via the Skill tool.

Collect all outputs before synthesizing. Each sub-skill returns a structured section:
```
## [Platform] — vX.Y detected → vA.B latest
**Signals:** [list paths that triggered detection]
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
**Detection signals:** [per-platform path list]
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
