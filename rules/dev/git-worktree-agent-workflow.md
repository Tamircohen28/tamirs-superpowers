---
alwaysApply: false
globs: [".claude/.worktrees/**/*", ".cursor/.worktrees/**/*", ".codex/.worktrees/**/*"]
---

# Git Worktree Agent Workflow

Claude Code, Cursor, Codex, and background subagents may work on this repo simultaneously. Use git worktrees to guarantee isolation — each agent gets its own working directory and branch without affecting others.

## Platform roots

| Platform | Agent root | Worktree path |
|----------|------------|---------------|
| Claude Code | `.claude/` | `.claude/.worktrees/<worktree-name>` |
| Cursor | `.cursor/` | `.cursor/.worktrees/<worktree-name>` |
| Codex | `.codex/` | `.codex/.worktrees/<worktree-name>` |
| Other agent `<name>` | `.<name>/` | `.<name>/.worktrees/<worktree-name>` |

General pattern:

```
.<agent_name>/.worktrees/<worktree-name>
```

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
Every dedicated worktree **must** be created under that agent's root (see table above).

Exception: the repo's main checkout (wherever the user cloned the repo) is reserved for the human user and for read-only operations (browsing, reviewing, driving `/pr-dev` from the default branch).

---

## Creating a worktree

```bash
# From the repo root (main working tree)
git fetch origin
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null || echo main)
git worktree add .<agent_name>/.worktrees/<worktree-name> -b <branch-name> "origin/${DEFAULT_BRANCH}"
```

Convention for the worktree path:

```
.<agent_name>/.worktrees/<area>-<issue-number>-<short-description>
# e.g. .cursor/.worktrees/cursor-54-symlink-rules
# e.g. .codex/.worktrees/codex-12-pr-dev-cleanup
```

All `.<agent_name>/.worktrees/` roots must be git-ignored — worktrees must never appear as untracked files in the main working tree.

---

## Working inside a worktree

All git operations (commit, push, status, log) run normally inside the worktree directory. The worktree has its own index and working files but shares objects and refs with the main repo.

```bash
cd .<agent_name>/.worktrees/<worktree-name>
# implement, stage, commit, push as normal
git add skills/dev-workflow/pr-dev/SKILL.md
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

After the PR is merged, delete the **remote** branch, then remove the worktree and local branch:

```bash
# From the repo root — prefer letting gh delete the branch at merge time:
gh pr merge <PR_NUMBER> --squash --delete-branch

# If the PR was already merged without --delete-branch, delete the remote explicitly:
git push origin --delete <branch-name>

# Remove the agent worktree (use the correct <agent_name> for your platform)
git worktree remove .<agent_name>/.worktrees/<worktree-name>
# If the worktree has no uncommitted changes it is deleted immediately.
# Use --force only if you are certain the work is no longer needed.

# Delete the local branch and prune stale refs
git branch -D <branch-name>
git remote prune origin
```

When driving a PR with `pr-dev` (Claude Code `/tamirs-superpowers:pr-dev`, Cursor/Codex plugin skill of the same name), run `cleanup-after-merge.sh` after merge — it performs remote deletion, worktree removal, and local branch cleanup in one step.

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
| Two agents need different features | Each creates its own branch + worktree under its platform root |
| Two agents need the same branch | Only one agent works on it; the other waits or takes a new branch |
| Agent crashes mid-task | Human runs `git worktree remove --force .<agent_name>/.worktrees/<name>` to clean up |
| Unsure if a worktree is in use | `git worktree list` from the repo root |

---

## Platform shortcuts

### Claude Code

Claude Code's `EnterWorktree` tool automates worktree creation and cleanup. Prefer it over manual `git worktree add` when running inside Claude Code:

```
EnterWorktree(name: "54-symlink-rules")
```

`EnterWorktree` places its worktree under `.claude/.worktrees/<name>`. The path must stay git-ignored. The tool switches the session's working directory automatically and cleans up on session exit if no changes were made.

Claude Code hooks may also create global worktrees under `~/.claude/worktrees/<repo>/<slug>/` — that path is separate from repo-local `.<agent>/.worktrees/` above.

### Cursor

Cursor has no built-in worktree tool. Always create worktrees manually under `.cursor/.worktrees/` before editing tracked files from an agent session.

### Codex

Codex has no built-in worktree tool. Always create worktrees manually under `.codex/.worktrees/` before editing tracked files from an agent session.

### Shell and other agents

Use `.<agent_name>/.worktrees/` for any agent without a platform shortcut (manual `git worktree add`).
