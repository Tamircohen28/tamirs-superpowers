---
name: session-report
description: 'Use when the user asks about Claude token usage, session analytics, cache performance, or wants to know what''s consuming their Claude budget. Triggers: ''session report'', ''token usage'', ''how many tokens'', ''cache hit rate'', ''which project costs most'', ''claude analytics'', ''show my usage'', ''what am I spending on Claude'', ''most expensive session'', ''usage report'', ''claude stats'', ''token breakdown''. Also triggers for time-windowed queries like ''usage this week'', ''last 7 days'', ''usage since Monday''.'
when_to_use: User asks for usage analytics — 'show my Claude usage', 'token report', 'session report', 'cache hit rate', 'expensive prompts', 'subagent cost breakdown', 'what did I spend on Claude this week', 'usage breakdown by project'.
argument-hint: '[optional time window — e.g. ''7d'', ''30d'', ''since Monday'', ''24h'']'
arguments: []
disable-model-invocation: false
user-invocable: true
allowed-tools:
- Bash
- Read
- Edit
disallowed-tools: []
model: claude-sonnet-4-6
effort: medium
context: ''
agent: ''
hooks: {}
paths: []
shell: bash
metadata:
  capability: toolkit
  tags:
  - analytics
  - tokens
  - usage
  - report
  updated-date: '2026-06-16'
---

# Session Report

Generate a self-contained interactive HTML report of Claude Code session usage — tokens consumed, cache performance, subagent costs, skill invocations, and the single most expensive prompts — from the local `~/.claude/projects` transcripts.

## Why this skill exists

Claude Code stores full JSONL transcripts per project under `~/.claude/projects/`. Without tooling, finding where tokens are going requires manually parsing thousands of JSON lines. The bundled `analyze-sessions.mjs` script reads all transcripts in a configurable time window, aggregates by project/skill/subagent type, computes cache-hit rates, and surfaces the top prompts by raw token cost. The companion `template.html` renders this data as sortable tables with inline bar charts — no external CDN, no server, just a single HTML file. The model's job is to run the analysis, inject the JSON data blob, and write 3–5 human-readable findings into the anomalies and optimizations blocks.

## Workflow

### 0. Resolve the skill directory

Before running any script, locate the skill directory. Try in order:

1. Use `$CLAUDE_SKILL_DIR` if set
2. Use `$CLAUDE_PLUGIN_ROOT/skills/toolkit/session-report` if `$CLAUDE_PLUGIN_ROOT` is set
3. Resolve via: `find ~/.claude/plugins -path "*/toolkit/session-report/analyze-sessions.mjs" -print -quit | xargs dirname`

Assign the resolved path to `SKILL_DIR`. If none of the above produces a valid path with `analyze-sessions.mjs` present, stop and tell the user the plugin root could not be found.

### 1. Parse the time window from user input

If the user provided a time window (e.g. "7 days", "last week", "since Monday", "30d", "24h"), map it to the `--since` flag:

| User says | Flag |
|-----------|------|
| "last 7 days" / "this week" / "7d" | `--since 7d` |
| "last 24 hours" / "today" / "24h" | `--since 24h` |
| "last 30 days" / "this month" / "30d" | `--since 30d` |
| "since Monday" | `--since <ISO date of most recent Monday>` |
| nothing / "all time" | (no `--since` flag) |

Default to `--since 7d` if the user didn't specify.

### 2. Run the analyzer

```bash
node "$SKILL_DIR/analyze-sessions.mjs" --json --since 7d > /tmp/session-report.json
```

Capture stderr separately if debugging. Check that the exit code is 0 before proceeding.

**If node is not installed:** Tell the user to install Node.js (>= 18) and re-run.

**If `~/.claude/projects` doesn't exist or is empty:** Tell the user no transcripts were found. This is normal on a fresh install. The report cannot be generated without transcript data.

**If the JSON output is `{}` or has `overall.api_calls == 0`:** The time window produced no data. Ask the user if they want to widen the window (e.g. remove `--since` for all-time).

### 3. Read and internalize the JSON

Read `/tmp/session-report.json`. Key fields to review before writing findings:

| Field | What to look for |
|-------|-----------------|
| `overall.input_tokens.total` + `overall.output_tokens` | Baseline — denominates all percentages |
| `overall.input_tokens.pct_cached` | Flag if below 85% |
| `by_project` | Any single project >40% of total |
| `by_subagent_type` | Any type averaging >1M tokens/call |
| `by_skill` | Skills with high call counts and high per-call token cost |
| `top_prompts[0].total_tokens` | Any single prompt >2% of total tokens |
| `cache_breaks` | Clustering (same project, same time window) |
| `overall.subagent.calls` | 0 = no subagents used (normal for some workflows) |

If `overall.api_calls` is 0 or the JSON is empty, stop and report that no data was found for the requested window.

### 4. Copy the template to the output path

```bash
cp "$SKILL_DIR/template.html" "./session-report-$(date +%Y%m%d-%H%M).html"
```

Capture the exact output path — you will report it to the user at the end. Do NOT write to `/tmp/` — the user expects the file in the current working directory.

### 5. Inject data and write findings

Use `Edit` (not `Write`) to preserve the template's CSS and JS.

**a) Inject the raw JSON data blob**

Replace the contents of:
```html
<script id="report-data" type="application/json">
```
...with the full contents of `/tmp/session-report.json`. The page JS renders everything (tables, bars, drill-downs) from this blob automatically.

If the JSON exceeds 2 MB, trim `top_prompts` and `cache_breaks` to 100 entries each before embedding. Parse the JSON in Bash, trim, re-serialize, then inject.

**b) Write the anomalies block**

Fill `<!-- AGENT: anomalies -->` with 3–5 findings. Exact markup per finding:
```html
<div class="take bad"><div class="fig">41.2%</div><div class="txt"><b>cc-monitor</b> consumed 41.2% of the week across just 3 sessions</div></div>
<div class="take good"><div class="fig">92.4%</div><div class="txt"><b>Cache hit rate</b> healthy at 92.4% — no action needed</div></div>
<div class="take info"><div class="fig">7</div><div class="txt"><b>repo-polish</b> was the most-invoked skill (7 calls, 3.2% of total)</div></div>
```

CSS class reference:

| Class | Color | Use for |
|-------|-------|---------|
| `.take.bad` | Red | Waste, anomalies, disproportionate cost |
| `.take.good` | Green | Healthy signals, goals met |
| `.take.info` | Blue | Neutral facts, context |

The `.fig` is one short value: a `%`, a count, or a multiplier like `12×`. Express token figures as a **% of total tokens** wherever possible — use the actual decimal from the JSON (`41.2%`, not `41%`). Name the subject (project/skill/prompt) in `<b>` inside `.txt`.

Look for these patterns:
- A single project or skill consuming >35% of total tokens → `.take.bad`
- Cache hit rate below 85% → `.take.bad`
- A single prompt exceeding 2% of all tokens → `.take.bad`
- Subagent types averaging >1M tokens/call → `.take.bad`
- Cache breaks clustering in the same project within a short window → `.take.info` or `.take.bad`
- Cache hit rate > 92% → `.take.good`
- Well-distributed projects (no outlier) → `.take.good`

If you find fewer than 3 anomalies, add `.take.info` neutral facts (total sessions, active hours, most-used skill) to reach 3 minimum.

**c) Write the optimizations block**

Fill `<!-- AGENT: optimizations -->` (near the bottom) with 1–4 suggestions tied to specific data rows:
```html
<div class="callout">/weekly-status spawned 7 subagents for 8.1% of total — consider scoping to fewer parallel agents or reducing the transcript window.</div>
```

Each suggestion must reference a specific project, skill, or prompt by name from the JSON. Do not write generic optimization advice.

### 6. Report the saved path

Tell the user the exact path to the saved HTML file. Do not open or render it inline.

```
Saved: ./session-report-20260616-1430.html
```

Optionally, summarize the top 2–3 findings in plain text so the user gets immediate value without opening the file.

## Hard rules

- **Never rewrite the template from scratch.** Use `Edit` to patch the two agent blocks and the data script tag only. All other markup, CSS, and JS must remain untouched.
- **Never omit the JSON injection.** An empty `<script id="report-data">` will render a blank page.
- **Express token figures as % of total** in the anomaly narrative. Raw counts are already in the table.
- **Do not invent findings.** Every anomaly sentence must reference an actual field value from the JSON (a project name, a number, a rate).
- **Use the correct output filename pattern** `session-report-$(date +%Y%m%d-%H%M).html` — never overwrite a previous report.
- **Do not hardcode absolute user paths** in commands. Always use `$SKILL_DIR` resolved in step 0.
- **Do not round figures to round numbers** — that signals hallucination. Use the actual decimal from the JSON.
- **Always check for zero-data before proceeding.** Do not inject an empty JSON blob and silently produce a blank report.

## What NOT to do

- **Do not skip the analyzer step and hallucinate numbers.** Always run `analyze-sessions.mjs --json` first.
- **Do not write the report to a temp path.** The user expects the file in the current working directory.
- **Do not add new HTML sections.** The template layout is fixed; only the two agent comment blocks and the data tag are yours to fill.
- **Do not use `Write` to save the report.** `Write` would discard the template's CSS/JS. Always `cp` first, then `Edit`.
- **Do not proceed if node is missing.** Give the user actionable install instructions instead.
- **Do not silently produce an empty report.** If data is zero or the window produces nothing, ask the user to widen the window.

## Quick-reference: anomaly detection checklist

```
[ ] cache_hit_rate < 85%             → .take.bad finding
[ ] any project  > 35% of total      → .take.bad finding
[ ] any prompt   > 2% of total       → .take.bad finding
[ ] any subagent type avg > 1M tok/call → .take.bad finding
[ ] cache_breaks clustering (same proj) → .take.info or .take.bad
[ ] cache_hit_rate > 92%             → .take.good finding
[ ] well-distributed projects        → .take.good finding
[ ] zero api_calls in window         → ask user to widen window, stop
[ ] node not found                   → give install instructions, stop
[ ] ~/.claude/projects missing       → explain fresh-install state, stop
```
