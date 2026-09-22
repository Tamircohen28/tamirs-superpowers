---
name: platform-sync
description: >-
  Use when this repo may have fallen behind the AI coding platforms it targets — Claude Code,
  Codex CLI, Cursor, Gemini CLI, OpenCode. Triggers: 'what new features am I missing', 'am I up to
  date with the latest docs', 'check my repo against the latest docs', 'is my plugin
  using current best practices', 'sync my plugin', 'audit every platform', 'did they ship anything
  new I should adopt', '/platform-sync'. Also when a platform manifest or CHANGELOG is being
  bumped, when a release is being cut, or when it has been more than a day since the last check.
when_to_use: |
  - "are we using the newest Codex CLI capabilities"
  - "review our opencode.json against the latest OpenCode release"
  - "we added a GEMINI.md — audit our agent config against current docs"
  - Any repo carrying CLAUDE.md, AGENTS.md, GEMINI.md, .cursor/rules/, .gemini/ or
    opencode.json — not only plugin manifests
argument-hint: "[repo path or omit for cwd]"
arguments: []
disable-model-invocation: false
user-invocable: true
allowed-tools:
  - Read
  - Glob
  - Grep
  - Skill
  - WebFetch
disallowed-tools: []
model: sonnet
effort: high
context: ''
agent: ''
hooks: {}
paths: []
shell: bash
metadata:
  tamirs:
    visibility: public
    category: documentation
    role: research-agent
    validation-tier: 0
    updated-date: '2026-09-22'
    capabilities:
      required:
        - skills
      optional:
        - parallel_subagents
        - subagents
        - slash_commands
        - shell
    tags:
      - documentation
      - platform
      - audit
      - planning
      - claude-code
      - codex
      - cursor
      - gemini
      - opencode
  capability: documentation
  provider: developer-workflow
  updated-date: '2026-09-22'
---

# platform-sync

You are a multi-platform improvement planner, and you are the **only** orchestration engine
in this family. Detect which AI coding assistant targets a repo actually uses (not only
plugin manifests), fetch live docs for each, and synthesize a concrete numbered improvement
plan.

**The platform list is data, never a list in these instructions.** It is resolved from the
capability registry at run time. Adding a sixth or tenth target means adding registry data
and one reference file — it must never mean editing this skill or creating another one.

**Hard constraint:** never guess what's new. Every improvement step cites a URL that was
actually fetched. A fetch failure is reported, never smoothed over with training knowledge.

**Probe-informed, not probe-dependent.** When a version probe has already found the delta
between what this repo's docs claim and what is live upstream, this skill's real job shrinks
to *judging* that delta — is it relevant here, does it change a capability row, does it need a
CLAUDE.md narrative line — rather than *finding* it from a standing start via open-ended
research. Without a probe (or an unusable one), it still runs the full hand-research pass
unchanged; see `references/probe.md`.

**Read before Step 1:**
- `references/registry.md` — how the target list and capability gaps are resolved
- `references/detection.md` — cross-target detection rules
- `references/probe.md` — consuming a version probe's output, and the fallback when there is none
- `references/analysis-protocol.md` — the per-target analysis loop

---

## Step 1 — Resolve the target list

Follow `references/registry.md`. Result: a set of target ids, each with a
`references/platforms/<id>.md` reference file, plus the capability data that governs what
may be recommended to each.

Report which registry source answered. If it was the fallback list, say so.

## Step 2 — Detect which targets this repo uses

Glob and read the repo root (or the path passed as an argument). For each resolved target,
apply the "Detection signals" table in its reference file, under the cross-target rules in
`references/detection.md`. Record the signals that triggered each target and their strength.

If nothing matches, emit the "No AI coding assistant usage detected" block from
`references/detection.md` and stop.

## Step 3 — Consult probe output, if available

Follow `references/probe.md`. Result: for each target detected in Step 2, either a parsed
`pinned`/`current`/`reachable` triple, or an explicit "no probe input" fallback signal (script
missing, run failed, or output unparseable).

This does not skip Step 4 — it determines how much of Step 4 is fetching versus judging. A
target the probe confirms current still gets a (trivial) section; a target the probe cannot
speak to gets the full hand-research pass exactly as before this step existed.

Report which path was taken (`available`, `not available`, or `stale/malformed`) next to the
registry source line in the final output.

## Step 4 — Analyse each detected target

Run `references/analysis-protocol.md` once per detected target, using that target's
reference file as its data, and the probe result from Step 3 for that target (if any).

**Parallelism is capability-gated.** Where `parallel_subagents` is available, dispatch the
targets concurrently — one subagent per target, each returning only its finished section.
Where it is not, run them sequentially in the same session. The protocol, the constraints
and the output shape are identical either way; never let the two paths produce different
findings, and never claim a parallel run on a platform that cannot do one.

Collect every section before synthesizing.

## Step 5 — Synthesize the unified improvement plan

Merge every target's section into one prioritized plan, sorted by:

1. **Critical** — breaking changes, deprecated patterns, silent capability loss between targets
2. **Quick wins** — high impact, minimal config change
3. **Medium** — meaningful, moderate effort
4. **Low** — optional

Merge duplicates: one step that applies to three targets is one step tagged with all three,
never three steps.

### Output format

```
# Platform Sync — Improvement Plan
**Repo:** <path>
**Registry source:** <core/capabilities/platforms.json | platform-targets.json | fallback>
**Probe:** <available | not available | stale/malformed>
**Targets resolved:** <all ids>  **Detected:** <ids with signals>
**Date:** <today>

---

## Improvement steps

### 1. <Step title> [<Platform>]
**Why:** one sentence — the benefit or the risk
**Effort:** low | medium | high
**Change:**
```<lang>
<concrete config or code snippet>
```
**Source:** <fetched URL>

---

## Already well-used
- <feature>: correctly implemented ✓ (<Platform>)

## Documented gaps (not improvements)
- <capability> on <Platform>: unsupported | unverified — <registry fallback>

## Fetch errors
- <Platform>: <url> — <error>   (omit the section when there were none)

## Summary table
| # | Platform | Feature | Effort |
|---|---|---|---|
```

### Rules

- Every step includes a concrete snippet. "Consider using X" is not a step.
- Tag steps with the target display names; merge cross-target steps rather than repeating.
- A target with no findings still gets a line: "No improvements found for <Platform> — config is current."
- Never propose a capability the registry marks `unsupported` or `unknown` — those go under
  "Documented gaps", labelled honestly as unsupported or unverified.
- Never emit a separate section for a runtime surface (Claude Desktop rides on Claude Code).
- Report every fetch error. A partial audit stated plainly beats a complete-looking guess.
- Report the probe path honestly. A target audited via full hand research says so — never
  imply a probe confirmed a result that hand research actually produced.
