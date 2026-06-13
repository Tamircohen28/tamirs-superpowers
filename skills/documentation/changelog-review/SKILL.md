---
name: changelog-review
disable-model-invocation: true
user-invocable: false
description: "Internal: audits Claude Code feature usage in a project against live official docs. Checks hooks, skills, plugins, MCP, settings, CLAUDE.md patterns for deprecations, misuse, and missed capabilities. Used by repo-polish. Not for direct user invocation — run repo-polish instead."
when_to_use: "Invoked automatically by repo-polish when the target project contains .claude/ config, plugin.json, hooks.json, SKILL.md, or .mcp.json files."
model: claude-sonnet-4-6
allowed-tools:
  - WebFetch
  - Read
  - Grep
  - Glob
metadata:
  capability: documentation
  provider: developer-workflow
  agents:
    - changelog-review
  platforms:
    - claude
  tags:
    - documentation
    - claude-code
    - audit
    - reference
  updated-date: "2026-06-13"
---

# changelog-review — Claude Code Pattern Audit

Internal skill invoked by `repo-polish`. Audits a project's Claude Code configuration against the latest live official documentation to surface bugs, deprecated patterns, and missed capabilities.

## Why this skill exists

Claude Code evolves rapidly — hook event names change, frontmatter fields are renamed, MCP transport defaults shift, and new features (agent teams, channels, `.claude/rules/`) land without broad awareness. A static audit using training knowledge produces false positives and misses recent deprecations. This skill fetches live docs first, then audits — so every finding is backed by a current authoritative source.

Naive approaches fail because: (1) training knowledge is frozen at a cutoff, (2) Claude Code's own docs are the ground truth, not secondary guides, and (3) deprecations accumulate silently between releases.

## Invocation contract

`repo-polish` calls this skill and passes the relevant project files in context. Expected inputs:
- Contents of `hooks/hooks.json` (if present)
- Contents of `.claude/settings.json` or `settings.json` (if present)
- Contents of `.mcp.json` (if present)
- Contents of any `SKILL.md` files (if present)
- Contents of `plugin.json` / `.claude-plugin/plugin.json` (if present)
- Contents of `CLAUDE.md` or `.claude/rules/` files (if present)

## Workflow

### Step 1: Fetch baseline docs (always required)

Fetch these two URLs first, regardless of what's in the input:

```
https://github.com/anthropics/claude-code/releases
https://code.claude.com/docs/en/whats-new
```

If any fetch fails, stop immediately and return:
```
FETCH ERROR
URL: <url>
Error: <message>

Cannot complete audit — required source could not be fetched.
```

### Step 2: Fetch topic-specific docs

Based on what's present in the input, fetch the relevant URL(s). Fetch only what you need.

| Input contains | URLs to fetch |
|---|---|
| `hooks.json` / `PreToolUse` / `PostToolUse` / hook event names | `https://code.claude.com/docs/en/hooks` + `https://code.claude.com/docs/en/hooks-guide` |
| `SKILL.md` / `skills/` directory / frontmatter fields | `https://code.claude.com/docs/en/skills` |
| `plugin.json` / `.claude-plugin/` | `https://code.claude.com/docs/en/plugins` + `https://code.claude.com/docs/en/plugins-reference` |
| `.claude/agents/` / subagent frontmatter | `https://code.claude.com/docs/en/sub-agents` |
| `SendMessage` / agent teams | `https://code.claude.com/docs/en/agent-teams` |
| `.mcp.json` / MCP server config | `https://code.claude.com/docs/en/mcp` |
| `settings.json` / `permissions` / `allowedTools` / `denyList` | `https://code.claude.com/docs/en/settings` + `https://code.claude.com/docs/en/permission-modes` |
| `CLAUDE.md` / `.claude/rules/` | `https://code.claude.com/docs/en/memory` |
| CLI invocations / `claude -p` / `--agents` flags | `https://code.claude.com/docs/en/cli-reference` |
| `--channels` / channels config | `https://code.claude.com/docs/en/channels` + `https://code.claude.com/docs/en/channels-reference` |

Full URL allowlist is in `references/urls.md`. Do not fetch URLs outside that list.

### Step 3: Analyze against fetched docs

Check for all three categories:

**Misuse / Bugs** — things that are actively broken or incorrect:
- Deprecated frontmatter field names (e.g., renamed keys between versions)
- Hook event names that no longer exist or were renamed
- Tool names in `allowedTools`/`denyList` that don't match official tool name strings
- Missing required fields in `plugin.json`, agent frontmatter, or `SKILL.md`
- `bypassPermissions` used without documented safeguards
- Circular subagent dependencies
- SSE transport where HTTP is now recommended for MCP

**Missed Capabilities** — unused features that would improve the project:
- Hook events that apply to this project's workflow but aren't configured
- `.claude/rules/` path-scoped rules instead of monolithic CLAUDE.md
- `context: fork` for operations that modify shared state
- Agent teams / `SendMessage` for parallelizable work being done sequentially
- MCP servers for integrations being done with raw `Bash` calls
- `auto memory` not configured when the project would benefit from it

**Outdated Patterns** — deprecated approaches:
- `ignorePatterns` (deprecated — use `permissions.deny`)
- `project` MCP scope where `local` is now the default
- Custom `/commands` that should migrate to the skills system
- Legacy `SSE` transport in `.mcp.json` instead of `http`

### Step 4: Output

Return structured audit results in this format:

```markdown
## Claude Code Audit

**Reviewed against:** Claude Code vX.Y.Z (released YYYY-MM-DD)
**Files analyzed:** [list each file checked]

---

### Critical Issues (Misuse / Bugs)
**Issue:** [title]
**Location:** [filename:key or line reference]
**Problem:** [what's wrong, quoting the relevant field/value]
**Fix:**
\`\`\`json
// corrected snippet
\`\`\`
**Source:** [URL]

---

### Missed Opportunities (Underutilized Features)
**Feature:** [name]
**Applies to:** [location or scenario]
**Benefit:** [why it helps]
**Minimal example:**
\`\`\`json
// minimal config to add
\`\`\`
**Source:** [URL]

---

### Outdated Patterns
**Pattern:** [what they're doing]
**Location:** [file/key]
**Modern equivalent:** [what to use instead]
**Source:** [URL]

---

### What's Correct
[One sentence per item — acknowledge correct usage]

---

### Summary
| Category | Count |
|---|---|
| Critical (broken/misuse) | N |
| Missed capabilities | N |
| Outdated patterns | N |
| Correct usage | N |

---
### Sources
- [URL] — used for [what]
```

## Hard rules

1. **Fetch before auditing.** Never flag an issue based on training knowledge alone — every finding must cite a fetched URL.
2. **Hard stop on fetch errors.** Report the error and URL; do not proceed with a partial audit.
3. **Citations are mandatory.** Every finding includes the documentation URL that backs it up.
4. **Do not flag uncertain issues.** If docs don't explicitly define the correct behavior, do not flag it as a bug.
5. **Identify the latest CC version.** Always state which version you audited against.
6. **Fetch only from the allowlist.** Only use URLs in `references/urls.md` — no external sources.
7. **Conflict resolution.** When docs contradict across pages, cite both; topic-specific docs beat general docs.

## What NOT to do

- **Do not answer general Claude Code questions.** This skill is an auditor, not a documentation chatbot. If invoked directly by a human asking "how do hooks work?", respond: "This is an internal audit skill. Run `/repo-polish` to trigger it on your project."
- **Do not produce findings without citations.** A finding with no URL is speculation, not an audit.
- **Do not skip the fetch step** because the answer "seems obvious" from training knowledge. Claude Code changes frequently.
- **Do not fetch URLs not in `references/urls.md`** — even plausible-looking official docs URLs.
- **Do not audit file types you weren't passed.** Only analyze what `repo-polish` explicitly included in the invocation context.

## Quick-reference: audit checklist

| File | Key fields to verify |
|---|---|
| `hooks/hooks.json` | Event names match official list; `matcher` regex valid; `command` paths exist |
| `settings.json` | `allowedTools` strings match official tool names; `denyList` not using deprecated `ignorePatterns` |
| `.mcp.json` | Transport is `http` not `sse`; scope is `local` not `project` (if applicable) |
| `plugin.json` | `name`, `version`, `description`, `statusLine` all present and schema-valid |
| `SKILL.md` | `name` matches directory; `description` starts with "Use when..."; `allowed-tools` exhaustive |
| `CLAUDE.md` | Consider splitting into `.claude/rules/` for path-scoped rules |
| `.claude/agents/*.md` | Required frontmatter: `name`, `description`, `model`, `allowed-tools` |
