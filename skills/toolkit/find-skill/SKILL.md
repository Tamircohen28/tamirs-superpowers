---
name: find-skill
description: 'Use when the user asks ''find a skill for X'', ''is there a plugin that does Y'', ''what skill should I use for Z'', ''recommend an agent for W'', ''compare skills for ...'', or ''search for a Claude Code skill''. Searches public skill and plugin marketplaces in real time and returns top N ranked matches. Trigger words: find skill, find plugin, skill for, plugin for, agent for, recommend skill, search skills, skill discovery, mcp server for, claude code plugin.'
when_to_use: User asks to find, recommend, or search for a skill, plugin, or agent — e.g. 'find a skill for code review', 'is there a plugin for X', 'recommend an agent for GitHub'.
argument-hint: '[what you need a skill or plugin for — e.g. ''PDF comparison'', ''PR review automation'']'
arguments: []
disable-model-invocation: false
user-invocable: true
allowed-tools:
- WebSearch
- WebFetch
- Bash
- Skill
disallowed-tools: []
model: claude-sonnet-4-6
effort: medium
context: ''
agent: ''
hooks: {}
paths: []
shell: bash
metadata:
  tamirs:
    visibility: public
    category: toolkit
    role: research-agent
    validation-tier: 0
    updated-date: '2026-08-19'
    capabilities:
      required:
        - skills
      optional:
        - shell
    tags:
      - toolkit
      - marketplace
      - discovery
      - search
      - skills
      - plugins
      - agents
      - configurable-sources
  capability: skill-discovery
  provider: developer-workflow
  agents: []
  updated-date: '2026-08-19'
---

# find-skill — real-time search across skill and plugin marketplaces

## Why this skill exists

The AI skill ecosystem is fragmented: several registries index MCP servers, and community
catalogs each cover different niches. Searching them manually wastes 20–30 minutes per query
and misses sources you don't think to check. This skill fans out searches in parallel,
normalises the results, and ranks them by both relevance to the query and absolute quality.

**The source list is configuration, not part of this skill.** Registries appear, get
acquired, and go dark; teams have private catalogues; some users do not want a given source
queried at all. So find-skill reads its sources from a JSON file it resolves at run time
(`references/sources.md` for the resolution order, `references/sources.json` for the bundled
default) and adding or removing a source never means editing these instructions.

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

### Step 2 — Load the source list, then fan out in parallel

**2a. Resolve sources.** Load the first file that exists and parses, per
`references/sources.md`:

1. `$FIND_SKILL_SOURCES` (env var pointing at a JSON file)
2. `.find-skill/sources.json` (this repo)
3. `~/.config/find-skill/sources.json` (this user)
4. `<skill-dir>/references/sources.json` (bundled default)

State which file answered in the opening plan line, so a user with an override can see it
took effect.

**2b. Select.** Query every entry with `"enabled": true`. Prioritise entries whose `covers`
array matches the query's constraints (an MCP query leads with `covers: ["mcp"]` sources),
but do not *exclude* the others — a wrongly-narrowed fan-out is the failure mode this skill
exists to avoid.

**2c. Fan out.** Issue **all** tool calls in a single message. Substitute the parsed intent
for `{query}`, URL-encoded for `WebFetch`.

If a source returns 429/5xx or is blocked, log it as a footnote — never silently drop. If a
`WebFetch` returns a client-rendered shell with no useful content, retry via that entry's
`fallback` when it has one.

If fewer than `defaults.min_sources` sources are enabled or reachable, still return results
but label them **degraded** and say which sources were missing. Never quietly return a
single-source answer as if it were a survey.

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

1. **Query every enabled source, and meet `defaults.min_sources`.** Below that floor the
   result is labelled degraded. Single-source results are never reliable and must never be
   presented as a survey.
1a. **Never hardcode a source in these instructions.** Sources live in the resolved JSON
   file. A registry added here instead of there is invisible to anyone with an override.
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
| User wants a private/internal skill | Note that the resolved source list is what was searched; point them at `references/sources.md` to add their internal registry rather than suggesting they search by hand |
| Resolved sources file is missing or unparseable | Fall through to the next file in the resolution order; if all fail, use the bundled default and say so |
| Fewer than `min_sources` sources reachable | Return results with a degraded banner naming the missing sources |

## What NOT to do

- **Do not search** for npm/pip packages, VS Code extensions, or general software — this skill is scoped to agent skills, MCP servers, and AI plugins.
- **Do not make up marketplace URLs** that you aren't sure exist. Use `WebSearch` to verify before `WebFetch`.
- **Do not use this skill** when the user already knows the skill name and just wants install instructions — give install instructions directly.
- **Do not use this skill** when the user wants to *create* a skill — use `skill-creator` instead.
- **Do not return results with no URL** — a skill recommendation without a link is useless.

## Quick reference — when to use which tool

| Signal in the query | Action |
|--------------------|--------|
| Specific marketplace named | Start with that source if it is in the resolved list; if it is not, say so and offer to add it via `references/sources.md` |
| MCP server mentioned | Prioritise sources whose `covers` includes `mcp` |
| A specific harness mentioned (Claude Code, Cursor, Codex, Gemini, OpenCode) | Prioritise sources whose `covers` includes `skills`/`plugins`, and record the harness in each candidate's `harness` field |
| No harness mentioned | Search all enabled sources equally |
| Query returns no results | Broaden: drop constraints one at a time, retry |
