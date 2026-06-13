---
alwaysApply: false
globs: [".claude/.worktrees/**/*", ".cursor/.worktrees/**/*"]
---

# Git Worktree Agent Workflow

Multiple agents (Claude Code, Cursor, background subagents) may work on this repo simultaneously. Use git worktrees to guarantee isolation — each agent gets its own working directory and branch without affecting others.

---

## Why worktrees

A git worktree is a separate checked-out directory linked to the same `.git` store. Agents in different worktrees:
- Never conflict on branch checkout (each worktree has its own `HEAD`)
- Never produce index lock errors (`index.lock` is per-worktree)
- Never trample uncommitted changes in the main working tree
- Can run and commit in parallel without coordination

---

## Rule: one task = one worktree

Every agent that creates a branch and makes commits **must** do so inside a dedicated worktree, not the main checkout.
Every dedicated worktree **must** be created under the agent-specific root:

```
.<agent_name>/.worktrees/<worktree-name>
```

Examples:

- Claude Code: `.claude/.worktrees/<worktree-name>`
- Cursor: `.cursor/.worktrees/<worktree-name>`
- Any other agent `<agent_name>`: `.<agent_name>/.worktrees/<worktree-name>`

Exception: the repo's main checkout (wherever the user cloned the repo) is reserved for the human user and for read-only operations (browsing, reviewing, running `/finish-development`).

---

## Creating a worktree

```bash
# From the repo root (main working tree)
git fetch origin
git worktree add .<agent_name>/.worktrees/<worktree-name> -b <branch-name> origin/master
```

Convention for the worktree path:
```
.<agent_name>/.worktrees/<area>-<issue-number>-<short-description>
# e.g. .cursor/.worktrees/cursor-54-symlink-rules
```

`.<agent_name>/.worktrees/` must be git-ignored — worktrees must never appear as untracked files in the main working tree.

---

## Working inside a worktree

All git operations (commit, push, status, log) run normally inside the worktree directory. The worktree has its own index and working files but shares objects and refs with the main repo.

```bash
cd .<agent_name>/.worktrees/<worktree-name>
# implement, stage, commit, push as normal
git add plugin/commands/pm-feedback.md
git commit -m "feat: ..."
git push -u origin <branch-name>
```

---

## Checking out an existing branch

If the branch already exists on the remote:

```bash
git worktree add .<agent_name>/.worktrees/<worktree-name> <branch-name>
```

If not yet local:

```bash
git worktree add .<agent_name>/.worktrees/<worktree-name> --track -b <branch-name> origin/<branch-name>
```

A branch can only be checked out in **one** worktree at a time. If another agent has it, create a new branch from the same base instead.

---

## Cleaning up

Remove the worktree after the PR is merged:

```bash
# From the repo root
git worktree remove .<agent_name>/.worktrees/<worktree-name>
# If the worktree has no uncommitted changes it is deleted immediately.
# Use --force only if you are certain the work is no longer needed.
```

Prune stale worktree metadata:

```bash
git worktree prune
```

---

## .gitignore entry

All `.<agent_name>/.worktrees/` roots must remain in `.gitignore`. Do not commit worktree directories.

---

## Coordination between agents

| Situation | Action |
|-----------|--------|
| Two agents need different features | Each creates its own branch + worktree |
| Two agents need the same branch | Only one agent works on it; the other waits or takes a new branch |
| Agent crashes mid-task | Human runs `git worktree remove --force .<agent_name>/.worktrees/<name>` to clean up |
| Unsure if a worktree is in use | `git worktree list` from the repo root |

---

## Claude Code shortcut

Claude Code's `EnterWorktree` tool automates worktree creation and cleanup. Prefer it over manual `git worktree add` when running inside Claude Code:

```
EnterWorktree(name: "54-symlink-rules")
```

`EnterWorktree` places its worktree under `.claude/.worktrees/<name>`. The path must stay git-ignored. The tool switches the session's working directory automatically and cleans up on session exit if no changes were made.

Use `.<agent_name>/.worktrees/` for manual worktrees (Cursor, shell, any agent without the `EnterWorktree` tool).
