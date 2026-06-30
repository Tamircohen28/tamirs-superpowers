---
alwaysApply: false
globs: [".claude/.worktrees/**/*", ".cursor/.worktrees/**/*", ".codex/.worktrees/**/*"]
---

# Cross-Platform Agent Handoff

Hand off long-running work between **Claude Code**, **Cursor**, and **Codex** without losing task context. GitHub Issues hold structured **Resume** blocks; git branches and platform worktrees hold code state.

## When to hand off

- Rate limit on current platform
- Ending a session mid-task
- Intentional platform switch (e.g. UI work on Cursor)

Before switching: push commits, then run `/switch-dev handoff #N`.

## Resume block (required on agent tasks)

Every issue created by `plan-dev` or the `agent_task` template includes:

```markdown
## Resume
- **Done:** ...
- **Next:** ...
- **Decisions:** ...
- **Blocked:** none
- **Branch:** feat/...
- **Worktree:** .<platform>/.worktrees/...
- **Last agent:** cursor @ 2026-06-30T12:00:00Z

## Agent routing
- **Owner:** agent:any
- **Suggested platform:** any
```

Agents must update **Done**, **Next**, and **Last agent** before handoff.

## Labels

| Label | Meaning |
|-------|---------|
| `agent:claude` | Claude Code owns the issue |
| `agent:cursor` | Cursor owns the issue |
| `agent:codex` | Codex owns the issue |
| `agent:any` | Unassigned |

## Worktree paths

Per [`git-worktree-agent-workflow.md`](git-worktree-agent-workflow.md):

```
.<platform>/.worktrees/<slug>
```

Use `skills/dev-workflow/_shared/scripts/resolve-worktree.sh` — never hardcode `.claude/worktrees/` only.

## Skills

| Skill | Role |
|-------|------|
| `plan-dev` | Creates issues with Resume scaffold + `agent:any` |
| `start-dev` | Implements; loads Resume; platform worktree |
| `switch-dev` | `handoff`, `resume`, `status` modes |
| `pr-dev` | Suggests handoff when blocked on human input |

## Stay on one platform longer

See `skills/dev-workflow/switch-dev/references/platform-capabilities.md` for Codex `/goal`, Cursor `/multitask`, Claude subagents.

## Out of scope

No third-party handoff MCP servers or external orchestrators. Git + GitHub Issues only.
