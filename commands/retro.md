---
description: Session retrospective — find friction (low quality, slowness/looping, repeated mistakes, missed parallelism/delegation) and propose rule/hook/skill/memory updates. Proposes, then waits for approval before writing.
---

# /retro — session postmortem & self-improvement

Analyze **this session's transcript** and turn its friction into durable improvements. Do NOT write
any files until I approve the proposal.

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
Ask me to approve, edit, or cut items. **Do not create or edit any files (especially hooks / settings.json) until I say yes.**

## 4. On approval
Make only the approved changes. Then list every file created/changed, what each does, and how to undo it. Remind me to commit `.claude/` config + the memory dir so it's reviewable and survives.
