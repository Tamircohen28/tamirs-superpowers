---
name: retro
description: "Use when the user types '/retro', 'retrospective', 'session retrospective', 'postmortem', 'what went wrong', 'find friction in this session', 'improve the workflow', 'capture lessons', 'lessons learned', or wants to turn session failures into durable improvements (CLAUDE.md rules, hooks, memory, skills). Also triggers for 'add lessons from this session', 'what should we improve', or 'run a retro'."
when_to_use: "User says '/retro', 'run a retrospective', 'what went wrong this session', 'find friction', 'postmortem', 'capture lessons from this session', 'improve the workflow', 'add lessons to memory'."
argument-hint: "[none]"
arguments: []
disable-model-invocation: true
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
  capability: toolkit
  tags:
    - retro
    - session
    - postmortem
    - self-improvement
    - memory
  updated-date: "2026-07-04"
---

# /retro — session postmortem & self-improvement

Analyze **this session's transcript** and turn its friction into durable improvements. Do NOT write
any files until the user approves the proposal.

## 1. Friction report

Scan the session and bucket what went wrong:
- **Low-quality output** — wrong/incomplete results, rework, claims made without verification.
- **Slowness / looping** — wasted time, redone work, the same approach retried without a success criterion.
- **Repeated mistakes** — anything that went wrong more than once.
- **Missed orchestration** — where a sub-agent or parallel execution should have been used but wasn't; or a sub-agent died at a long wait and the pattern was re-dispatched.

For each item give: **what happened** (1 line) · **root cause** (1 line) · **fix layer** (hook / CLAUDE.md rule / memory / skill / command).

## 2. Proposed changes table

Present a table: *Problem → Root cause → Fix layer → Exact change*. Route to the right layer:
- **Hooks** for absolutes that must happen every time (lint/format/verify gates, sensitive-file guards).
- **CLAUDE.md rules** for guidance/conventions/definition-of-done.
- **Memory** (`…/projects/<project>/memory/*.md` + `MEMORY.md` index) for distilled lessons — the SIGNAL, not a transcript replay.
- **Skills / slash commands** for repeatable multi-step workflows.

Keep it lean — propose the **smallest** change that fixes a problem that *actually occurred*. Don't invent rules for problems that didn't happen. Prefer hooks over advisory text when something must be enforced.

## 3. Stop and wait

Ask the user to approve, edit, or cut items. **Do not create or edit any files (especially hooks / settings.json) until they say yes.**

## 4. On approval

Make only the approved changes. Then list every file created/changed, what each does, and how to undo it. Remind the user to commit `.claude/` config + the memory dir so it's reviewable and survives machine changes.
