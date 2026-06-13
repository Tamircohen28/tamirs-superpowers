---
name: find-skill
description: "Use when the user asks 'find a skill for X', 'is there a plugin that does Y', 'what skill should I use for Z', 'recommend an agent for W', 'compare skills for ...', or 'search for a Claude Code skill'. Searches public skill and plugin marketplaces in real time and returns top N ranked matches. Trigger words: find skill, find plugin, skill for, plugin for, agent for, recommend skill, search skills, skill discovery, mcp server for, claude code plugin."
allowed-tools:
  - WebSearch
  - WebFetch
  - Bash
  - Skill
when_to_use: |
  - "find a skill for code review"
  - "is there a plugin that generates release notes from git commits?"
  - "what skill should I use to compare PDFs?"
  - "recommend an agent for GitHub automation"
  - "search skills for Python testing"
model: claude-sonnet-4-6
metadata:
  capability: skill-discovery
  provider: developer-workflow
  agents: []
  platforms:
    - claude
  tags:
    - meta
    - marketplace
    - discovery
    - search
    - skills
    - plugins
    - agents
  updated-date: "2026-06-13"
---

# find-skill — real-time search across skill and plugin marketplaces

## Why this skill exists

The AI skill ecosystem is fragmented: Anthropic has an official marketplace, Smithery is the largest open registry, mcp.directory indexes MCP servers, and community catalogs (wshobson/agents, obra/superpowers, mattpocock/skills) each cover different niches. Searching them manually wastes 20–30 minutes per query and misses sources you don't think to check. This skill fans out searches in parallel, normalises the results, and ranks them by both relevance to the query and absolute quality.

## Invocation

```
/find-skill [N] <description of what you want the skill to do>
```

- **N** (optional, default `10`): integer 1–50. Number of results to return.
- If the first token after `/find-skill` is an integer 1–50, treat it as N. Otherwise default N=10 and treat the whole string as the query.

Examples:
```
/find-skill code review for python
/find-skill 5 generate release notes from git commits
/find-skill compare PDFs and find differences
```

## Workflow

### Step 1 — Parse the request

Extract:
1. **N** — result count (default 10, clamp to 1–50).
2. **Primary intent** — a one- or two-word capability label (e.g. "code review", "PDF diff", "release notes").
3. **Constraints** — language, framework, harness (Python, Claude Code, MCP, Cursor, etc.).
4. **Disqualifiers** — anything explicitly ruled out ("not paid", "no OAuth").

Echo a one-line plan before searching:
> Searching 6+ marketplaces for "Python code review skills" — returning top 5 ranked by match + quality.

### Step 2 — Fan out searches in parallel

Issue **all** tool calls in a single message. Cover at minimum:

| # | Source | How to query |
|---|--------|-------------|
| 1 | Smithery (largest open registry) | `WebFetch` `https://smithery.ai/search?q=<query>` |
| 2 | mcp.directory | `WebFetch` `https://mcp.directory/search?q=<query>` |
| 3 | wshobson/agents | `WebFetch` `https://raw.githubusercontent.com/wshobson/agents/main/README.md` |
| 4 | obra/superpowers (this repo) | `WebFetch` `https://raw.githubusercontent.com/obra/superpowers/main/README.md` |
| 5 | mattpocock/skills | `WebFetch` `https://raw.githubusercontent.com/mattpocock/skills/main/README.md` |
| 6 | Web fallback | `WebSearch` `"claude code skill" "<primary intent>"` |
| 7 | Anthropic marketplace JSON | `WebSearch` `site:github.com claude-code marketplace.json "<primary intent>"` |

If a source returns 429/5xx or blocked, log it as a footnote — never silently drop. If `WebFetch` returns a client-rendered shell with no useful content, retry that source with `WebSearch` targeting the same domain.

### Step 3 — Normalise candidates

For each candidate, extract:

| Field | Notes |
|-------|-------|
| `name` | canonical slug or plugin name |
| `description` | first 140 chars, plain text |
| `url` | direct link to skill page or repo path |
| `author` | repo owner or vendor name |
| `harness` | Claude / Codex / Gemini / MCP-only / universal |
| `stars` | GitHub star count if available, otherwise omit |
| `last_update` | ISO date if available |

Deduplicate by URL. If the same skill appears in two sources, keep one row and note both sources.

### Step 4 — Score every candidate

**Match score (0–100)** — how well the skill fits the query:

| Component | Max | Measures |
|-----------|----:|---------|
| Intent alignment | 40 | Does it actually do what was asked? |
| Name relevance | 20 | Key terms in the name |
| Description overlap | 20 | Keyword/synonym overlap |
| Domain/tag match | 10 | Tags match constraints (language, framework) |
| Capability completeness | 10 | Covers all requested sub-features |

**Quality score (0–10)** — absolute quality of the skill:

| Component | Max | Measures |
|-----------|----:|---------|
| Author tier | 3.0 | Official vendor (3), known team (2), reputable indie (1.5), anonymous (0.5) |
| Adoption | 3.0 | >100k stars (3) … <100 stars (0.5) |
| Recency | 2.0 | Updated <30d (2), <90d (1.5), <180d (1), <365d (0.5), older (0) |
| Quality artifacts | 2.0 | Has docs (+0.5), tests (+0.5), CI (+0.5), responsive issues (+0.5) |

Cap match at 100 and quality at 10. Round both to one decimal.

### Step 5 — Rank and emit

Sort by **match score descending**, tiebreak by **quality score descending**. Take top N.

Output as a markdown table:

```markdown
| # | Match | Name | Description | Quality | URL |
|---|------:|------|-------------|--------:|-----|
| 1 | 92.5  | wshobson/python-dev | Static analysis + type checking for Python | 8.7 | https://github.com/wshobson/agents/... |
| 2 | 88.0  | mattpocock/tdd | Test-driven development workflow for any language | 8.4 | https://github.com/mattpocock/skills/... |
```

After the table, add one line explaining the top result's biggest match driver and quality driver.

### Step 6 — Surface gaps and caveats

After the table, list:
- **Sources that failed** — any marketplace that 429'd or returned no useful content.
- **Near-misses dropped** — candidates with match 20–29 that almost made the cut.
- **Trust caveats** — if any top-3 result has author tier ≤0.5 or last update >365 days, call it out.

## Hard rules

1. **Query at least 5 sources.** Single-source results are never reliable.
2. **Never invent a URL.** If you cannot find a direct link, drop the candidate.
3. **Never fabricate star or install counts.** If a count is not observable, set that quality component to its baseline (0.5).
4. **Never rank a paywalled marketplace first** when free/open-source alternatives exist at comparable quality. Note the paywall explicitly if included.
5. **Cite every result by URL.** The user must be able to click straight to the source.
6. **A single 4xx/5xx is not evidence of absence.** Failed fetch = failed signal, not "skill doesn't exist."
7. **Never fabricate scores.** Every number must come from the rubric above — show math in the reasoning if challenged.

## Error handling

| Situation | Action |
|-----------|--------|
| Invalid N (negative or >50) | Clamp to [1, 50], warn once |
| Empty query after parsing N | Ask one clarifying question, then proceed |
| All sources blocked | Return `WebSearch` results + a "degraded" banner |
| Zero candidates score ≥30 | Return empty results, list sources searched, suggest broader terms |
| User wants a private/internal skill | Note this searches public marketplaces; suggest checking internal repos separately |

## What NOT to do

- **Do not search** for npm/pip packages, VS Code extensions, or general software — this skill is scoped to agent skills, MCP servers, and AI plugins.
- **Do not make up marketplace URLs** that you aren't sure exist. Use `WebSearch` to verify before `WebFetch`.
- **Do not use this skill** when the user already knows the skill name and just wants install instructions — give install instructions directly.
- **Do not use this skill** when the user wants to *create* a skill — use `skill-creator` instead.
- **Do not return results with no URL** — a skill recommendation without a link is useless.

## Quick reference — when to use which tool

| Signal in the query | Action |
|--------------------|--------|
| Specific marketplace named (e.g. "on Smithery") | Start with that source, fan out to others |
| MCP server mentioned | Prioritise mcp.directory and Smithery |
| Claude Code / claude-code mentioned | Prioritise obra/superpowers, wshobson, mattpocock |
| No harness mentioned | Search all sources equally |
| Query returns no results | Broaden: drop constraints one at a time, retry |
