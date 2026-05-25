---
name: user-find-skill
description: "Search the leading skill / agent / plugin marketplaces in real time and rank the top N matches for a user query. Use when the user asks 'find a skill for X', 'is there a plugin that does Y', 'what skill should I use to Z', 'recommend an agent for W', 'compare skills for ...'. Queries Anthropic claude-plugins-official, OpenAI Codex Directory, Gemini CLI Extensions, Smithery, mcp.directory, VoltAgent/awesome-agent-skills, wshobson/agents, obra/superpowers, mattpocock/skills, and Claude marketplace aggregators. Returns a numbered list with a match score (0-100), a quality score (0-10), name, description, and URL. Trigger words: 'find skill', 'find a plugin', 'skill for', 'plugin for', 'agent for', 'recommend a skill', 'search skills'."
allowed-tools:
  - WebSearch
  - WebFetch
  - Bash
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
  updated-date: "2026-05-19"
---

# /find-skill — search engine across skill / agent / plugin marketplaces

A meta-skill that takes a natural-language query and returns the top N matching skills from across every leading marketplace, ranked by how well they match the query *and* how high-quality they are.

## Why this skill exists

The skill / plugin ecosystem fractured fast: Anthropic has its own marketplace, OpenAI has another, Google has Gemini Extensions, Smithery is the largest open registry, and there are at least half a dozen community catalogs (VoltAgent, wshobson, obra, mattpocock, ClaudePluginHub, claudemarketplaces.com). Finding the right skill means searching all of them and judging quality from incomplete signals. Doing it by hand wastes 20-30 minutes per query and misses sources you don't think to check.

This skill mechanises the search: parallel queries against every canonical source, normalised scoring, ranked output.

## Invocation

```
/find-skill [N] <user prompt>
```

- **N** (optional, default `10`): integer 1-50. How many results to return.
- **user prompt**: free-form description of what the user wants the skill to do.

Examples:
- `/find-skill code review for python`
- `/find-skill 5 generate release notes from git commits`
- `/find-skill compare PDFs and find differences`

If the first token after `/find-skill` is an integer 1-50, treat it as `N`. Otherwise, default `N=10` and treat the whole rest as the query.

## Workflow (follow this order)

### Step 1 — Parse the request

Identify:

1. **N** — the requested number of results (default `10`).
2. **Primary intent** — one or two-word capability label (e.g. "code review", "PDF diff", "release notes generator").
3. **Constraints** — language / framework / harness mentioned (Python, Claude Code, Codex, Cursor, MCP, etc.).
4. **Disqualifiers** — anything the user explicitly rules out ("not paid", "no OAuth", "not Atlassian").

Echo a one-line plan to the user before searching, e.g.:

> Searching 8 marketplaces for "Python code review skills" — returning top 5 ranked by match + quality.

### Step 2 — Search every source in parallel

Use a **single message with multiple tool calls** to fan out queries. Each source has its own preferred entry point — see `references/sources.md` for the canonical list and URL templates. Always cover:

| # | Source | Tool to use |
|---|---|---|
| 1 | Anthropic `claude-plugins-official` (marketplace.json) | `WebFetch` on the raw GitHub JSON |
| 2 | Claude marketplaces aggregator | `WebFetch` on `claudemarketplaces.com` search |
| 3 | OpenAI Codex Plugin Directory | `WebSearch` + `WebFetch` `developers.openai.com/codex/plugins` |
| 4 | Gemini CLI Extensions Gallery | `WebFetch` `geminicli.com/extensions/browse` |
| 5 | Smithery | `WebFetch` `smithery.ai/search?q=<query>` |
| 6 | mcp.directory | `WebFetch` `mcp.directory/search?q=<query>` |
| 7 | VoltAgent/awesome-agent-skills | `WebFetch` GitHub README, grep for query terms |
| 8 | wshobson/agents | `WebFetch` `docs/agent-skills.md`, `docs/plugins.md` |
| 9 | obra/superpowers | `WebFetch` repo README + `skills/` index |
| 10 | mattpocock/skills | `WebFetch` repo README |
| 11 | Plain WebSearch fallback | `WebSearch` `"claude code skill" "<query>"` |

If any source returns 429 / 5xx / blocked, log it once at the end as a footnote — never silently drop. If `WebFetch` returns a page shell with no useful content (client-rendered marketplace UI), retry with `WebSearch` keyed to the same domain.

### Step 3 — Normalise candidates

For every candidate returned by any source, build a row with these fields:

| Field | Source | Notes |
|---|---|---|
| `name` | marketplace listing | canonical slug / plugin name |
| `description` | marketplace listing | first 100-160 chars of description, no markdown |
| `url` | source | direct link to the skill page or repo |
| `author` | listing or repo owner | "Anthropic", "wshobson", company name, etc. |
| `harness` | listing tag or URL pattern | Claude / Codex / Gemini / Cursor / MCP-only |
| `stars` | GitHub API or scraped | star count if available |
| `installs` | marketplace listing | install count if available |
| `last_update` | listing or repo | ISO date if available |
| `tags` | listing | category, language, etc. |

Deduplicate by URL. If the same skill appears in two marketplaces, keep one row but record both URLs (prefer the official one).

### Step 4 — Score every candidate

Two independent scores. Full rubric and worked examples are in `references/scoring.md`. Summary:

**Match score (0-100)** — how well the skill fits the query.

| Component | Max | What it measures |
|---|---:|---|
| Intent alignment | 40 | Does the skill actually do what the user asked? |
| Name relevance | 20 | Does the name contain the user's key terms? |
| Description overlap | 20 | Keyword / synonym overlap with description |
| Domain / tag match | 10 | Tags align with constraints (language, framework) |
| Capability completeness | 10 | Covers all asked-for sub-features |

**Quality score (0-10)** — how good the skill is in absolute terms.

| Component | Max | What it measures |
|---|---:|---|
| Author tier | 3.0 | Official vendor (3), known team (2), reputable indie (1.5), anonymous (0.5) |
| Adoption | 3.0 | >100k stars/installs (3) … <100 stars (0.5) |
| Recency | 2.0 | Updated <30d (2), <90d (1.5), <180d (1), <365d (0.5), older (0) |
| Quality artifacts | 2.0 | Has docs (0.5), tests/evals (0.5), CI (0.5), responsive issues (0.5) |

Cap match at 100, quality at 10. Round both to one decimal place.

### Step 5 — Rank and emit

Primary sort: **match score descending**. Tiebreak: **quality score descending**. Take the top N.

**Output exactly this format** (the user specified it):

```
1. <match> | <name> | <description> | <quality> | <url>
2. <match> | <name> | <description> | <quality> | <url>
...
```

- Match score is a number 0-100 with one decimal (e.g. `87.5`).
- Quality score is a number 0-10 with one decimal (e.g. `8.2`).
- Description is trimmed to ≤140 chars, single line, no markdown.
- URL is the canonical install or repo URL.

Render as a markdown table for readability while preserving the pipe-delimited contract:

```markdown
| # | Match | Name | Description | Quality | URL |
|---|------:|------|-------------|--------:|-----|
| 1 | 92.5  | wshobson/python-development | … | 8.7 | https://github.com/wshobson/agents/tree/main/plugins/python-development |
| 2 | 88.0  | mattpocock/tdd | … | 8.4 | https://github.com/mattpocock/skills/tree/main/skills/engineering/tdd |
```

Right after the table, add a one-line **why this ordering** note — name the top result's biggest match driver and biggest quality driver.

### Step 6 — Surface gaps and caveats

After the table, list:

- **Sources that failed** — any marketplace that 429'd or returned no usable content.
- **Candidates dropped** — anything with `match < 30` that nearly made the cut (so the user sees you considered it).
- **Trust caveats** — if any top-3 result has `author tier ≤ 0.5` or `last_update > 365 days`, call it out explicitly.

## Output contract (machine-parseable)

A consumer (CI, another agent, a wrapper script) might want to ingest this output. After the human-readable section, emit a fenced JSON block:

````
```json
{
  "query": "<original prompt>",
  "n": <int>,
  "generated_at": "<ISO8601>",
  "results": [
    {
      "rank": 1,
      "match": 92.5,
      "name": "wshobson/python-development",
      "description": "…",
      "quality": 8.7,
      "url": "…",
      "match_breakdown": {"intent": 38, "name": 18, "description": 19, "domain": 9, "capability": 8.5},
      "quality_breakdown": {"author": 2.5, "adoption": 2.8, "recency": 2.0, "artifacts": 1.4},
      "author": "wshobson",
      "harness": ["claude-code"],
      "last_update": "2026-05-12"
    }
  ],
  "sources_queried": ["anthropic-official", "smithery", "..."],
  "sources_failed": []
}
```
````

This block is optional for casual users but mandatory whenever the skill is invoked non-interactively (e.g. from a CI script, scheduled task, or another skill).

## Hard rules

1. **Always query at least 5 sources.** Single-source results are never reliable.
2. **Never invent a URL.** If you can't find a direct link, drop the candidate.
3. **Never invent star / install counts.** If a count isn't observable, set the corresponding quality component to its baseline (0.5).
4. **Never recommend a paywalled marketplace as the top result** when free / open-source alternatives exist at comparable quality. Note the paywall explicitly if you must include it.
5. **Cite every result** by URL. The user must be able to click straight to the source.
6. **Don't trust a single 4xx / 5xx as "skill doesn't exist."** A failed fetch is failed signal, not absence.
7. **No fabricated scores.** Every score must come from the rubric in `references/scoring.md`. Show your math in the JSON `match_breakdown` / `quality_breakdown` fields.

## Error handling

| Situation | What to do |
|---|---|
| User passes invalid N (negative, >50) | Clamp to `[1, 50]`, warn once. |
| Empty query after parsing N | Ask the user one clarifying question, then proceed. |
| All sources blocked / unreachable | Return whatever WebSearch finds + a clear "degraded" banner. |
| Zero candidates score ≥30 | Return empty results, list searched sources, suggest broader query terms. |
| User asks for a private / internal-only skill | Note that the search is over public marketplaces; suggest internal sources separately. |

## When NOT to use this skill

- The user already knows the skill name and just wants to install it — defer to install instructions directly.
- The user wants to *create* a new skill — use the `write-a-skill` / `skill-creator` family instead.
- The query is about non-skill software (npm packages, pip packages, Python libraries). This skill is scoped to *agent skills, MCP servers, and AI plugins*. Suggest a different tool.

## References

- `references/sources.md` — canonical marketplace URLs and how to query each.
- `references/scoring.md` — the full match-score and quality-score rubrics with worked examples.
- `references/examples.md` — five sample queries with the exact output the skill should produce.
- `references/tools.md` — `WebSearch` / `WebFetch` usage patterns specific to this skill (parallel fan-out, retry policy, output capping).
