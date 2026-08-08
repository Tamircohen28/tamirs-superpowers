# Cross-Platform Agent Workflow

Hand off long-running development work between **Claude Code**, **Cursor**, and **Codex** without losing task context. This plugin uses **GitHub Issues** as shared task memory and **platform-scoped git worktrees** for code isolation.

## When to use handoff vs staying on one platform

| Situation | Action |
|-----------|--------|
| Rate limit on current model | `/switch-dev handoff #N` → open another platform |
| Same platform, want parallel work | Cursor `/multitask`, Claude subagents, Codex side chats |
| Same platform, hours-long task | Codex `/goal`, Cursor cloud agents |
| Ending session mid-task | Handoff first (hook reminds you on SessionEnd) |

See [platform capabilities](../../skills/dev-workflow/switch-dev/references/platform-capabilities.md) for first-party features per tool.

> **Claude Code ↔ Claude Code:** since Claude Code 2.1.224, sessions can message
> each other directly — `SendMessage` to a session on any of your machines,
> `ListAgents` to discover them (macOS and Linux). Since 2.1.225, `SendMessage`
> can also *start* a conversation with a Remote Control session on another
> machine by name (previously it could only reply after that session messaged
> first), and messages parked for a headless session are no longer held
> silently without notice or expiry. Useful for coordinating parallel Claude
> Code sessions live; messages to a session running with bypassed permissions
> are held for your approval (`crossSessionInbound` setting). This complements
> — not replaces — the handoff flow below, which is the only path that carries
> task state **across platforms** (Cursor, Codex, OpenCode) and across time via
> GitHub Issues.

## Pipeline

```
plan-dev  →  start-dev  →  pr-dev
     ↓           ↓
switch-dev handoff / resume (any time)
```

| Skill | Role |
|-------|------|
| `/tamirs-superpowers:plan-dev` | Phased GitHub issues with **Resume** + `agent:any` label |
| `/tamirs-superpowers:start-dev` | Platform worktree, implement, open PR |
| `/tamirs-superpowers:switch-dev` | `handoff`, `resume`, `status` across platforms |
| `/tamirs-superpowers:pr-dev` | Drive PR to merge |

## Resume block

Every agent-task issue includes:

```markdown
## Resume
- **Done:** ...
- **Next:** ...
- **Decisions:** ...
- **Blocked:** none
- **Branch:** feat/...
- **Worktree:** .cursor/.worktrees/feat-...
- **Last agent:** cursor @ 2026-06-30T12:00:00Z

## Agent routing
- **Owner:** agent:any
- **Suggested platform:** any
```

Agents update this before handoff. Git commits are the code checkpoint.

## Labels

| Label | Meaning |
|-------|---------|
| `agent:claude` | Claude Code owns the issue |
| `agent:cursor` | Cursor owns the issue |
| `agent:codex` | Codex owns the issue |
| `agent:any` | Unassigned |

## Worktree paths

Each platform uses its own worktree root (same branch, different checkout path):

| Platform | Path |
|----------|------|
| Claude Code | `.claude/.worktrees/<slug>` |
| Cursor | `.cursor/.worktrees/<slug>` |
| Codex | `.codex/.worktrees/<slug>` |

`start-dev` and `switch-dev` use `skills/dev-workflow/_shared/scripts/resolve-worktree.sh`.

## Walkthrough

### 1. Plan

```
/tamirs-superpowers:plan-dev add auth middleware
```

Approve the plan. Issues are created with Resume scaffold and `agent:any`.

### 2. Start on Claude Code

```
/tamirs-superpowers:start-dev #42
```

Work happens in `.claude/.worktrees/feat-auth-middleware/`.

### 3. Rate limited — hand off

```
/tamirs-superpowers:switch-dev handoff #42 cursor
```

Push commits first. Issue Resume updates; label becomes `agent:cursor`.

### 4. Resume on Cursor

```
/tamirs-superpowers:switch-dev resume #42
```

Opens `.cursor/.worktrees/feat-auth-middleware/`. Continue **Next** from the issue.

### 5. Finish

```
/tamirs-superpowers:pr-dev <PR_NUMBER>
```

## Status dashboard

```
/tamirs-superpowers:switch-dev status
```

Lists open `agent:*` issues and active platform worktrees.

## GitHub Projects (optional)

Manual columns work well:

`Ready` → `In Progress (claude)` / `In Progress (cursor)` / `In Progress (codex)` → `Review` → `Done`

Drag issues when switching platforms. No automation required.

## Issue template

Use **Agent task** when creating issues manually (`.github/ISSUE_TEMPLATE/agent_task.yml`).

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Branch already checked out elsewhere | Only one worktree per branch; hand off on one platform at a time |
| Stale Resume | Run `/switch-dev handoff #N` with current session context |
| Missing `agent:*` label | `gh issue edit #N --add-label agent:any` |
| Wrong worktree path | Run `resolve-worktree.sh` from repo root; check `git worktree list` |

## Related docs

- [Concepts — worktree hooks](concepts.md)
- [Skill reference — switch-dev](reference.md)
- Contributor rule: `rules/dev/cross-platform-handoff.md`
