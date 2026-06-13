---
name: session-report
description: "Use when the user wants token usage, cache stats, skill costs, or session analytics from Claude Code. Triggers: 'session report', 'token usage', 'how many tokens', 'cache hit rate', 'which project costs most', 'claude analytics'."
argument-hint: "[optional time window — e.g. '7d', '30d', 'since Monday']"
allowed-tools:
  - Bash
  - Read
  - Edit
when_to_use: "User asks for usage analytics — 'show my Claude usage', 'token report', 'session report', 'cache hit rate', 'expensive prompts', 'subagent cost breakdown'."
model: claude-sonnet-4-6
metadata:
  capability: meta
  tags:
    - analytics
    - tokens
    - usage
    - report
  updated-date: "2026-06-13"
---

# Session Report

Generate a self-contained interactive HTML report of Claude Code session usage — tokens consumed, cache performance, subagent costs, skill invocations, and the single most expensive prompts — from the local `~/.claude/projects` transcripts.

## Why this skill exists

Claude Code stores full JSONL transcripts per project under `~/.claude/projects/`. Without tooling, finding where tokens are going requires manually parsing thousands of JSON lines. The bundled `analyze-sessions.mjs` script reads all transcripts in a configurable time window, aggregates by project/skill/subagent type, computes cache-hit rates, and surfaces the top prompts by raw token cost. The companion `template.html` renders this data as sortable tables with inline bar charts — no external CDN, no server, just a single HTML file. The model's job is to run the analysis, inject the JSON data blob, and write 3–5 human-readable findings into the anomalies and optimizations blocks.

## Workflow

### 1. Run the analyzer

Locate the skill scripts using the skill directory environment variable or by resolving relative to this file. Default window: last 7 days. Override with `--since <window>`.

```bash
# Last 7 days (default)
node "$CLAUDE_SKILL_DIR/analyze-sessions.mjs" --json --since 7d > /tmp/session-report.json

# Last 24 hours
node "$CLAUDE_SKILL_DIR/analyze-sessions.mjs" --json --since 24h > /tmp/session-report.json

# All-time
node "$CLAUDE_SKILL_DIR/analyze-sessions.mjs" --json > /tmp/session-report.json
```

If `$CLAUDE_SKILL_DIR` is not set, resolve the path from the plugin root. The script is at `skills/meta/session-report/analyze-sessions.mjs` relative to the plugin root.

### 2. Read and internalize the JSON

Read `/tmp/session-report.json`. Key fields to review before writing findings:

| Field | What to look for |
|-------|-----------------|
| `overall.input_tokens.total` + `overall.output_tokens` | Baseline — denominates all percentages |
| `overall.cache_hit_rate` | Flag if below 85% |
| `by_project` | Any single project >40% of total |
| `by_subagent_type` | Any type averaging >1M tokens/call |
| `by_skill` | Skills with high call counts and high per-call token cost |
| `top_prompts` | Any single prompt >2% of total tokens |
| `cache_breaks` | Clustering (same project, same time window) |

### 3. Copy the template to the output path

```bash
cp "$CLAUDE_SKILL_DIR/template.html" "./session-report-$(date +%Y%m%d-%H%M).html"
```

Capture the exact output path — you will report it to the user at the end.

### 4. Inject data and write findings

Use `Edit` (not `Write`) to preserve the template's CSS and JS.

**a) Inject the raw JSON data blob**

Replace the contents of:
```html
<script id="report-data" type="application/json">
```
...with the full contents of `/tmp/session-report.json`. The page JS renders everything (tables, bars, drill-downs) from this blob automatically.

**b) Write the anomalies block**

Fill `<!-- AGENT: anomalies -->` with 3–5 findings. Exact markup per finding:
```html
<div class="take bad"><div class="fig">41%</div><div class="txt"><b>cc-monitor</b> consumed 41% of the week across just 3 sessions</div></div>
<div class="take good"><div class="fig">92%</div><div class="txt"><b>Cache hit rate</b> healthy at 92% — no action needed</div></div>
<div class="take info"><div class="fig">7</div><div class="txt"><b>repo-polish</b> was the most-invoked skill (7 calls, 3.2% of total)</div></div>
```

CSS class reference:

| Class | Color | Use for |
|-------|-------|---------|
| `.take.bad` | Red | Waste, anomalies, disproportionate cost |
| `.take.good` | Green | Healthy signals, goals met |
| `.take.info` | Blue | Neutral facts, context |

The `.fig` is one short value: a `%`, a count, or a multiplier like `12×`. Express token figures as a **% of total tokens** wherever possible. Name the subject (project/skill/prompt) in `<b>` inside `.txt`.

Look for these patterns:
- A single project or skill consuming >35% of total tokens
- Cache hit rate below 85%
- A single prompt exceeding 2% of all tokens
- Subagent types averaging >1M tokens/call
- Cache breaks clustering in the same project within a short window

**c) Write the optimizations block**

Fill `<!-- AGENT: optimizations -->` (near the bottom) with 1–4 suggestions tied to specific data rows:
```html
<div class="callout">/weekly-status spawned 7 subagents for 8.1% of total — consider scoping to fewer parallel agents or reducing the transcript window.</div>
```

### 5. Report the saved path

Tell the user the exact path to the saved HTML file. Do not open or render it inline.

```
Saved: ./session-report-20260613-1430.html
```

## Hard rules

- **Never rewrite the template from scratch.** Use `Edit` to patch the two agent blocks and the data script tag only. All other markup, CSS, and JS must remain untouched.
- **Never omit the JSON injection.** An empty `<script id="report-data">` will render a blank page.
- **Express token figures as % of total**, not raw counts, in the anomaly narrative. Raw counts are already in the table.
- **Do not invent findings.** Every anomaly sentence must reference an actual field value from the JSON (a project name, a number, a rate).
- **Cap embedded data if needed.** If the JSON exceeds 2 MB, trim `top_prompts` and `cache_breaks` to 100 entries each before embedding. They should already be capped by the script.
- **Use the correct output filename pattern** `session-report-$(date +%Y%m%d-%H%M).html` — never overwrite a previous report.
- **Do not hardcode absolute user paths** in commands. Always use `$CLAUDE_SKILL_DIR` or resolve relative to the plugin root.

## What NOT to do

- **Do not skip the analyzer step and hallucinate numbers.** Always run `analyze-sessions.mjs --json` first.
- **Do not write the report to a temp path.** The user expects the file in the current working directory.
- **Do not add new HTML sections.** The template layout is fixed; only the two agent comment blocks and the data tag are yours to fill.
- **Do not round all figures to round numbers** — that signals hallucination. Use the actual decimal from the JSON (`41.2%`, not `41%`).
- **Do not use `Write` to save the report.** `Write` would discard the template's CSS/JS. Always `cp` first, then `Edit`.

## Quick-reference: anomaly detection checklist

```
[ ] cache_hit_rate < 85%   → .take.bad finding
[ ] any project  > 35% of total   → .take.bad finding
[ ] any prompt   > 2% of total    → .take.bad finding
[ ] any subagent type avg > 1M tokens/call → .take.bad finding
[ ] cache_breaks clustering in same project → .take.info or .take.bad
[ ] cache_hit_rate > 92%   → .take.good finding
[ ] well-distributed projects (no outlier) → .take.good finding
```
