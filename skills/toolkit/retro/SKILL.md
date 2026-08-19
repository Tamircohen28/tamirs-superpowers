---
name: retro
description: "Use when a session should become durable improvements (CLAUDE.md rules, hooks, memory, skills) — the user asks ('/retro', 'retrospective', 'postmortem', 'what went wrong', 'find friction', 'capture lessons', 'lessons learned', 'run a retro'), OR a session is wrapping up after notable friction (repeated failures, rework, multiple corrections) with no retro yet. Offer it proactively at session end; retro only proposes and never writes without approval, so offering is safe."
when_to_use: "User says '/retro', 'run a retrospective', 'what went wrong this session', 'find friction', 'postmortem', 'capture lessons', 'improve the workflow', 'add lessons to memory' — or the session is wrapping up after a rough stretch (repeated failures, rework, multiple corrections) and no retro has run."
argument-hint: "[none]"
arguments: []
disable-model-invocation: false
user-invocable: true
allowed-tools:
  - Read
  - Edit
  - Write
disallowed-tools: []
model: claude-sonnet-4-6
effort: high
context: ''
agent: ''
hooks: {}
paths: []
shell: bash
metadata:
  tamirs:
    visibility: public
    category: toolkit
    role: none
    validation-tier: 0
    updated-date: '2026-08-19'
    capabilities:
      required:
        - skills
      optional:
        - session_transcripts
        - subagents
        - hooks
    tags:
      - retro
      - session
      - postmortem
      - self-improvement
      - memory
      - orchestration
  capability: toolkit
  updated-date: '2026-08-19'
---

# /retro — session postmortem & self-improvement

Analyze **this session's transcript** and turn its friction into durable improvements. Do NOT write
any files until the user approves the proposal.

## Timing — when to self-trigger

A retro belongs at the **end** of a session. This skill is model-invocable so it can catch rough sessions the user forgot to review — but do not let it derail active work:

- **Mid-task:** if you notice a rough stretch while work is still in progress, do **not** launch a full retro. Finish the task first, then briefly offer one: *"This was a bumpy stretch — want a quick retro to capture the lessons?"*
- **Session wrap-up / user signals done:** proactively offer the retro when there was real friction (repeated failures, rework, multiple corrections) and none has run yet.
- **User asks explicitly:** run it now.

Because retro only *proposes* changes and never writes without approval, offering is always safe — the cost of a mistimed offer is one declined suggestion.

## 1. Friction report

Scan the session and bucket what went wrong.

### Execution friction

- **Low-quality output** — wrong/incomplete results, rework, claims made without verification.
- **Slowness / looping** — wasted time, redone work, the same approach retried without a success criterion.
- **Repeated mistakes** — anything that went wrong more than once.

### Orchestration friction

These are the failures that only show up in multi-agent work, and they are invisible unless
you look for them by name. Check each one explicitly — "no instances" is a valid, useful
answer, and a far better one than not having checked.

| Pattern | What it looks like | Why it costs |
|---|---|---|
| **Unnecessary PR fan-out** | Several PRs opened for what was one deliverable; workers opening PRs instead of committing and handing off | A work unit is not a delivery unit. N PRs mean N review cycles, N CI runs, and merge conflicts between siblings that a single integration branch would never have had. |
| **Missed parallelism** | Independent tasks run one after another; a single agent doing a broad read that several bounded agents could have split; dispatches issued in separate messages instead of one | Wall-clock time spent for nothing. Look for tasks with no dependency edge between them that still ran in sequence. |
| **Repeated full validation** | The whole test/lint/build suite run after every small edit, or by every worker on overlapping scopes | Tier 3 work done at tier 0 cost. Note which tier each run actually needed (spec §9) and how many runs were redundant. |
| **Provider-specific failures** | A step that worked on one platform and failed on another; a skill assuming subagents, hooks, a statusline or an artifact runtime that the running harness lacks; a capability claimed without a fallback | These are portability bugs, not bad luck. Name the capability and the platform; the fix is usually a capability gate, not a retry. |
| **Orchestration deadlocks** | Two agents waiting on each other; a worker blocked on a file another agent owns; an agent waiting on CI that its own harness may kill; a handoff that never arrived; a request written to a requests file that nobody read | Deadlocks are silent — the session just gets slower. Check every wait for who was supposed to end it. |

For each item give: **what happened** (1 line) · **root cause** (1 line) · **fix layer**
(hook / rule / memory / skill / command / policy).

Distinguish an **incident** from a **pattern**. One occurrence is an incident; propose a fix
only if the cost was real. Two or more is a pattern and deserves a durable change. Say which
you are looking at — inflating a single mishap into a permanent rule is how rule files rot.

## 2. Proposed changes table

Present a table: *Problem → Root cause → Fix layer → Exact change*. Route to the right layer:
- **Hooks** for absolutes that must happen every time (lint/format/verify gates, sensitive-file guards).
- **CLAUDE.md rules** for guidance/conventions/definition-of-done.
- **Memory** (`…/projects/<project>/memory/*.md` + `MEMORY.md` index) for distilled lessons — the SIGNAL, not a transcript replay.
- **Skills / slash commands** for repeatable multi-step workflows.

Keep it lean — propose the **smallest** change that fixes a problem that *actually occurred*. Don't invent rules for problems that didn't happen. Prefer hooks over advisory text when something must be enforced.

### Framework policy is proposed, never edited

Orchestration findings often point at framework policy — the role definitions in `core/`,
the capability registry, the rules under `rules/`, the validation tiers, the PR/delivery
policy. **This skill never modifies any of them.** It writes a proposal and stops.

| Finding points at | retro may | retro may NOT |
|---|---|---|
| Project memory, a project rule file, a repo hook | propose, then write on approval | write before approval |
| `core/**`, `rules/**`, the capability registry, validation tiers, delivery policy | propose only, as a written recommendation with its evidence | edit, even with approval — that is a deliberate change with its own review, not a retro side effect |

A retro that silently rewrites framework policy makes the framework unauditable: the next
session inherits a rule nobody decided on. State the recommendation, cite the sessions that
motivate it, and let a human open that change explicitly.

## 3. Stop and wait

Ask the user to approve, edit, or cut items. **Do not create or edit any files (especially hooks / settings.json) until they say yes.** Framework-policy items stay proposals regardless of the answer — approval routes them to a separate change, it does not authorise an edit here.

## 4. On approval

Make only the approved changes, and only in the layers this skill is allowed to write. Then list every file created/changed, what each does, and how to undo it. Remind the user to commit `.claude/` config + the memory dir so it's reviewable and survives machine changes.
