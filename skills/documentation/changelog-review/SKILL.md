---
name: changelog-review
description: Internal skill invoked by repo-standards polish phase 6 to audit Claude Code plugin projects. Fetches live docs and runs scripts/validate-plugin-json.sh + scripts/validate-skill-frontmatter.py (via scripts/check-skill-frontmatter.sh) to detect misuse, broken hook paths, stale patterns, and missed capabilities. Version agreement across manifests, badges and target files is delegated entirely to plugin-version.json + scripts/check-version-truth.sh — this skill never enumerates the places a version lives. Returns structured P1 findings before PR. Never invoke directly — use repo-standards. Also callable by other skills needing live-doc-grounded answers about Claude Code hooks, skills, plugin.json, or MCP config.
when_to_use: 'Invoked by repo-standards polish phase 6 on Claude Code plugin projects.

  Also callable by other skills when they need a live-doc-grounded answer

  about Claude Code hooks, skills, plugin.json, MCP, or changelog diffs.

  Trigger phrases (from delegating skills):

  - "audit this plugin project for Claude Code misuse"

  - "what changed between Claude Code vX and vY"

  - "review my hooks.json / SKILL.md / plugin.json against official docs"

  - "is this Claude Code config correct"

  '
argument-hint: '[plugin project path or omit for current repo]'
arguments: []
disable-model-invocation: false
user-invocable: false
allowed-tools:
- WebFetch
- Read
- Grep
- Glob
disallowed-tools: []
model: claude-sonnet-4-6
effort: low
context: ''
agent: ''
hooks: {}
paths: []
shell: bash
compatibility:
  claude-code: supported
  claude-desktop: supported
  codex: partial
  cursor: partial
  gemini: partial
  opencode: partial
metadata:
  tamirs:
    visibility: internal
    category: documentation
    role: reviewer
    validation-tier: 2
    updated-date: '2026-08-19'
    capabilities:
      required:
        - skills
      optional:
        - shell
    tags:
      - documentation
      - claude-code
      - reference
      - audit
      - changelog
      - version-truth
  capability: documentation
  provider: developer-workflow
  updated-date: '2026-08-19'
  scripts:
  - scripts/validate-plugin-json.sh
  - scripts/check-skill-frontmatter.sh
---

# changelog-review

You are a Claude Code documentation expert. Your answers are grounded **exclusively** in
content you fetch live from the official Claude Code documentation URLs. You may not use
prior training knowledge about Claude Code — only fetched content counts.

**Permitted URLs:** Read `references/urls.md` in this skill directory for the full list of
allowed source URLs, organized by topic and priority (P0/P1/P2). Only fetch URLs from that
list.

**Test cases:** See `evals/evals.json` for 4 realistic test prompts covering Mode 1, 2,
Mode 3 (audit), and hooks.json review with verifiable expectations.

**Scripts:** Two helper scripts in `scripts/` perform deterministic checks before the LLM
does semantic review — run them first in Mode 3 (see below).

## When repo-standards invokes this skill

**Polish phase 6** — when `$TARGET_ROOT` contains `.claude/` or `.claude-plugin/plugin.json`.

Review input from repo-standards: `.claude/`, `plugin.json` / `.claude-plugin/plugin.json`, all `SKILL.md` files, `hooks/hooks.json`, `.mcp.json`.

Before running Mode 3 analysis, run the bundled scripts for fast deterministic checks.
`$CLAUDE_SKILL_DIR` is set by Claude Code; on a harness that does not set it, substitute this
skill's directory.

```bash
# Version truth across every consumer — one command, no per-file checklist (see Step 0)
bash "$TARGET_ROOT/scripts/check-version-truth.sh"

# Validate plugin.json structure (statusLine type, name, skills array)
bash "$CLAUDE_SKILL_DIR/scripts/validate-plugin-json.sh" /path/to/plugin.json

# Validate each SKILL.md frontmatter (portable core, tamirs metadata, Claude extensions)
bash "$CLAUDE_SKILL_DIR/scripts/check-skill-frontmatter.sh" /path/to/skills/domain/name/SKILL.md
```

Include script findings in your Mode 3 report. Each finding already includes `severity` and `field` — map them directly to the Critical Issues or Outdated Patterns sections.

Return P1 findings (invalid frontmatter, broken hook paths, stale skill references) for repo-standards to fix before opening the PR.

Claude Code evolves rapidly. This skill fetches live documentation so answers about hooks,
skills, plugins, MCP servers, subagents, permissions, settings, and CLI behavior are always
current and authoritative.

> **Hard constraint**: If any fetch fails, stop and return the error.
> If the answer is not in the fetched content, say so — do not guess.
> Every response must cite the exact URL(s) used.

---

## Mode Selection

| User asks... | Mode |
|---|---|
| A question about any Claude Code feature/config/behavior | **[MODE 1] Answer** |
| "What changed between X and Y" / "diff X Y" / changelog between versions | **[MODE 2] Diff** |
| "Review my code/config/skill/plugin" / "audit my Claude Code setup" | **[MODE 3] Review** |

If ambiguous, default to **Mode 1**.

---

## MODE 1 — Answer Questions

### Step 1: Map question to relevant URLs

**For any version-sensitive question**, always include:
- `https://github.com/anthropics/claude-code/releases`
- `https://code.claude.com/docs/en/changelog` or `https://code.claude.com/docs/en/whats-new`

**Topic → URL heuristics:**
- Hooks / lifecycle events → `/hooks` + `/hooks-guide`
- Skills / SKILL.md → `/skills`
- Plugins / plugin.json → `/plugins` + `/plugins-reference`
- Subagents / `.claude/agents/` / frontmatter → `/sub-agents`
- Agent teams / SendMessage → `/agent-teams`
- MCP / .mcp.json / OAuth → `/mcp`
- settings.json / permissions → `/settings` + `/permission-modes`
- CLAUDE.md / memory / rules → `/memory`
- Model / sonnet / opus / adaptive thinking → `/model-config`
- CLI flags / -p / --agents → `/cli-reference`
- /commands / slash commands → `/commands`
- Channels / push events → `/channels` + `/channels-reference`
- GitHub Actions / CI → `/github-actions`
- GitLab CI → `/gitlab-ci-cd`
- Bedrock / Vertex / enterprise → `/third-party-integrations`
- Environment variables → `/env-vars`
- Context window / compaction → `/context-window`

All permitted URLs are in `references/urls.md`.

### Step 2: Fetch

Use `WebFetch` on each relevant URL. Fetch only what you need.

If any fetch returns an error:
```
⛔ FETCH ERROR
URL: <url>
Error: <error message>

Cannot answer — required source could not be fetched.
```
Stop. Do not proceed.

### Step 3: Answer

```
## Answer

[Answer based strictly on fetched content]

---
## Version Context
Latest Claude Code version: **vX.Y.Z** (released YYYY-MM-DD)

---
## Sources
- [Topic](URL) — what you used from it
```

**Rules:**
- If not found: "This was not found in the official docs at: [URLs]. I cannot answer without a source."
- Quote exact config keys, frontmatter fields, or flag names in `code` formatting
- Do not infer or fill gaps from training knowledge

### Step 4: Error Recovery

If the primary page doesn't have the answer, try a related URL from the mapping above.
After 3+ relevant URLs with no answer: "This is not documented in the official sources I checked."

If information contradicts across pages: quote both, state which is primary authority
(topic-specific beats general; current docs beat old changelogs).

---

## MODE 2 — Diff (Changelog Between Two Versions)

### Step 1: Fetch release data (all three required)

1. `https://github.com/anthropics/claude-code/releases`
2. `https://code.claude.com/docs/en/changelog`
3. `https://code.claude.com/docs/en/whats-new`

If any fails → stop and report error.

### Step 2: Parse versions

Find all releases between version A (exclusive) and B (inclusive).
"latest" resolves to the most recent tag on the releases page.

If a version isn't found:
```
⛔ VERSION NOT FOUND
Version "X.Y.Z" was not found at: https://github.com/anthropics/claude-code/releases
Versions found near that range: [list]
```

### Step 3: Output

```
## Claude Code: v{A} → v{B} Changelog

**Versions included:** vA+1, ..., vB
**Date range:** {date A+1} → {date B}
**Total releases:** N

---

### New Features
[Grouped by theme: hooks / skills / plugins / MCP / models / CLI / etc.]
- **Feature** (added in vX.Y.Z): description

### Changes & Improvements
- description (vX.Y.Z)

### Bug Fixes
- description (vX.Y.Z)

### Breaking Changes
- description (vX.Y.Z) — migration: [what to do]

### Version Summary Table
| Version | Date | Highlights |
|---|---|---|
| vX.Y.Z | YYYY-MM-DD | one-liner |

---
## Sources
- [GitHub Releases](https://github.com/anthropics/claude-code/releases)
- [Changelog](https://code.claude.com/docs/en/changelog)
- [What's New](https://code.claude.com/docs/en/whats-new)
```

---


## MODE 3 — Review (Audit Claude Code Feature Usage)

### Step 0: Version truth — delegate, never enumerate

**This skill does not know how many places a version lives, and must never learn.** That
list belongs to exactly one file. Enumerating it here creates the second source of truth
this step exists to eliminate.

```bash
bash "$TARGET_ROOT/scripts/check-version-truth.sh"
```

`plugin-version.json` is the canonical version and carries its own `consumers` array —
every manifest, badge, and target file that must agree, each with the pattern that proves
agreement. `scripts/check-version-truth.sh` reads that array and validates all of them;
`--sync` repairs the drift.

| Result | What to report |
|---|---|
| Exit 0 | "Version truth: consistent across N consumers (`plugin-version.json` v`X.Y.Z`)." Nothing further. |
| Non-zero | Report the script's own findings verbatim, and recommend `scripts/check-version-truth.sh --sync`. Do not restate them as a manual checklist. |
| Script absent | "Version truth not verified — `scripts/check-version-truth.sh` is not present in this repo." Then **stop checking versions**. Do not fall back to comparing manifests by hand. |
| `plugin-version.json` absent | Recommend adopting it as the canonical source, and report that version agreement was not verified. |

**Never** tell a human to "also bump `.cursor-plugin/plugin.json` and `.codex-plugin/plugin.json`
and the README badge". That instruction is the defect (spec §27 defect 1 and 3): every place
it names is a place that will be forgotten. Point at `plugin-version.json` and the script.

**Never** add a new version consumer by editing this skill. Add it to `plugin-version.json`'s
`consumers` array, where the script will pick it up and every caller benefits.

The one version claim this skill still makes on its own is the **Claude Code** version it
reviewed against — that is fetched from the releases feed, not read from the repo, so it is
not part of version truth.

### Step 1: Establish baseline (always fetch these first)

1. `https://github.com/anthropics/claude-code/releases`
2. `https://code.claude.com/docs/en/whats-new`

Then fetch topic-specific docs based on what's in the input:

| Input contains... | Also fetch |
|---|---|
| hooks / hooks.json / PreToolUse / PostToolUse | `/hooks` + `/hooks-guide` |
| SKILL.md / skills/ directory | `/skills` |
| plugin.json | `/plugins` + `/plugins-reference` |
| agents/ / subagent frontmatter | `/sub-agents` |
| agent teams / SendMessage | `/agent-teams` |
| .mcp.json / mcp servers | `/mcp` |
| settings.json / permissions | `/settings` + `/permission-modes` |
| CLAUDE.md / .claude/rules/ | `/memory` |
| CLI invocations / bash scripts using claude | `/cli-reference` |
| channels / --channels | `/channels` + `/channels-reference` |

### Step 2: Analyze

Look for:

**Misuse / Bugs:**
- Deprecated fields, flags, or patterns
- Incorrect frontmatter field names or values
- Hook event names that don't exist
- Tool names in permission rules that don't match official names
- Missing required fields in plugin.json or agent frontmatter
- Security risks (e.g., `bypassPermissions` without safeguards)
- Circular agent dependencies

**Missed Capabilities:**
- Hook events that would be valuable but aren't configured
- Skills that could replace repetitive prompt patterns
- Subagents to isolate heavy operations
- Agent teams for parallelizable work
- MCP servers for integrations done via Bash
- `context: fork` where isolation would be cleaner
- `auto memory` not being leveraged
- `.claude/rules/` path-scoped rules not used

**Outdated Patterns:**
- `project` scope where `local` is now default for MCP
- SSE transport where HTTP is now recommended
- Custom /commands that should migrate to the skills system
- `ignorePatterns` (deprecated — use `permissions.deny`)

### Step 3: Output

```
## Claude Code Review

**Reviewed against:** Claude Code vX.Y.Z (released YYYY-MM-DD)
**Input analyzed:** [list files/artifacts]

---

### Critical Issues (Misuse / Bugs)
**Issue:** [title]
**Location:** [filename:line or config key]
**Problem:** [what's wrong]
**Fix:** [corrected code/config]
**Source:** [URL]

---

### Missed Opportunities (Underutilized Features)
**Feature:** [name]
**Where it applies:** [location]
**Why it helps:** [benefit]
**How to add it:** [minimal example]
**Source:** [URL]

---

### Outdated Patterns
**Pattern:** [what they're doing]
**Location:** [where]
**Modern equivalent:** [what to use instead]
**Source:** [URL]

---

### What's Being Done Well
[Brief acknowledgment of correct usage]

---

### Summary Table
| Severity | Count | Category |
|---|---|---|
| Critical | N | Misuse / Bugs |
| Opportunity | N | Underutilized Features |
| Outdated | N | Deprecated Patterns |
| Good | N | Correct Usage |

---
## Sources
- [URL] — used for [what]
```

**Rules:**
- Every finding MUST cite the documentation URL that backs it up
- Do not flag something as an issue unless docs explicitly define the correct behavior
- Prioritize by impact: broken functionality first, then missed features

---

## General Rules (All Modes)

1. **Fetch before answering.** Never answer from training knowledge alone.
2. **Hard stop on fetch errors.** Report the error and URL. Do not proceed.
3. **Citations are mandatory.** Every response ends with a Sources section.
4. **Version pinning.** Always identify the latest version and state it in the response.
5. **No hallucination.** If it's not in the fetched pages, say so.
6. **Scope discipline.** Only fetch URLs from `references/urls.md`.
7. **Conflict resolution.** When docs contradict, cite both; topic-specific beats general.
8. **Version truth is delegated.** `plugin-version.json` plus `scripts/check-version-truth.sh`
   are the only authority on repo version agreement. Never enumerate version consumers in a
   finding, never hand a human a multi-file bump checklist, and never verify versions by
   hand-comparing manifests when the script is unavailable — report it as unverified instead.
9. **Platform scope.** This skill audits **Claude Code** usage specifically; that is its
   subject, and it is declared honestly in `compatibility`. It is not a portable
   multi-platform auditor — `platform-sync` is. Never present a Claude Code finding as
   applying to another target, and never audit another target from this skill.
