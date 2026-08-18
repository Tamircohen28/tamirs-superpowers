---
name: feedback-multi-agent-file-ownership
description: Large parallel sub-agent fan-outs need strict file-ownership partitioning plus a request mailbox, because agents share one worktree filesystem
metadata:
  type: feedback
---

When fanning out many sub-agents on one task, partition work by **exclusive file
ownership**, not by topic. Give each agent an explicit "you own exactly these
paths, touch nothing else" list, and a `session-files/requests/<agent>.md`
mailbox for changes it needs in files it does not own. The orchestrator applies
mailbox requests centrally.

**Why:** sub-agents share a single worktree filesystem. Two agents editing the
same file does not produce a git conflict — it produces silent last-write-wins
data loss. Branch-level isolation does not help; the collision is at the file
level, before git ever sees it.

**How to apply:**
- Write one shared brief (non-negotiables, hard repo rules, "do NOT commit —
  the orchestrator commits") and have every agent read it first.
- Assign shared/contended files (Makefile, CI, manifests, README) to the
  orchestrator, never to a fan-out agent.
- Expect interface mismatches: agents write call sites against scripts that do
  not exist yet. Pin the CLI contract explicitly and early.
- Re-verify file state immediately before acting on any agent's report — in a
  busy worktree a `grep` result is stale within minutes.
- Beware mid-write races: `make` reading a file an agent is saving produces
  bogus syntax errors. Re-run before investigating.

Used successfully for the 13-agent portable-orchestration refactor (PR #90).
Related: [[project-admin-merge-personal-repo]]
