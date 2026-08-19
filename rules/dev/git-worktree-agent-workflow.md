---
alwaysApply: false
globs: [".agent-worktrees/**/*", ".claude/.worktrees/**/*", ".cursor/.worktrees/**/*", ".codex/.worktrees/**/*"]
---

# Git Worktree Agent Workflow

Multiple agents — Claude Code, Cursor, Codex, Gemini CLI, OpenCode, background subagents — may work on this repo simultaneously. Git worktrees give each unit of work its own working directory and branch without agents trampling each other.

**The identity of a worktree is the objective and the task, not the harness that happens to run it.** Provider is metadata. It never belongs in the path or the branch name except as a debugging aid.

Related canonical policy: [`core/policies/git.md`](../../core/policies/git.md) (branch/commit/push invariants), [`core/policies/delivery.md`](../../core/policies/delivery.md) (when work becomes a PR), [`core/policies/validation.md`](../../core/policies/validation.md) (which tier runs where).

---

## The model

One **objective** = one user-facing goal = (by default) one PR.
An objective decomposes into zero or more **worker tasks**, plus exactly one **integration** working tree where the workers' commits are composed and reviewed together.

```text
main
└── objective/<slug>              ← integration branch
    ├── worker/<slug>/001
    ├── worker/<slug>/002
    └── worker/<slug>/003
```

```text
.agent-worktrees/
└── <objective-slug>/
    ├── integration/              ← objective/<slug>
    ├── task-001/                 ← worker/<slug>/001
    ├── task-002/
    └── task-003/
```

`.agent-worktrees/` may also live outside the repository (a user-level path such as `~/.agent-worktrees/<repo>/<objective>/…`). Both layouts are supported; the repo-local one must stay git-ignored.

An objective with a single trivial task does not need worker worktrees at all — one integration worktree is a complete, valid setup. Do not manufacture parallelism that the objective does not have.

### What each worktree is for

| Worktree | Branch | Ends at | Validation tier |
|----------|--------|---------|-----------------|
| `task-NNN` | `worker/<slug>/NNN` | implementation → targeted validation → **commit + handoff** | Tier 1 |
| `integration` | `objective/<slug>` | workers composed → cross-worker review → full validation → **PR** | Tier 2 |

A worker task **must not** open a PR, merge, or push to the default branch. Work unit is not delivery unit. Delivery happens once, from the integration worktree, under [`core/policies/delivery.md`](../../core/policies/delivery.md).

---

## Why worktrees

A git worktree is a separate checked-out directory linked to the same `.git` store. Agents in different worktrees:

- never conflict on branch checkout (each worktree has its own `HEAD`);
- never produce index lock errors (`index.lock` is per-worktree);
- never trample uncommitted changes in the main working tree;
- can run and commit in parallel without coordination.

A branch can be checked out in only **one** worktree at a time. If another agent holds it, branch from the same base instead of waiting.

---

## Rule: never commit from the user's main checkout

Every agent that creates a branch and makes commits **must** do so inside a dedicated worktree. The repo's main checkout (wherever the user cloned it) is reserved for the human and for read-only operations — browsing, reviewing, driving delivery from the default branch.

---

## Creating worktrees

Prefer the shared resolver over hand-rolled paths:

```bash
skills/dev-workflow/_shared/scripts/resolve-worktree.sh --objective <slug> --task 001
skills/dev-workflow/_shared/scripts/resolve-worktree.sh --objective <slug> --integration
```

It resolves the correct path, understands legacy layouts (below), and prints a machine-readable result for orchestration. Manual equivalent:

```bash
git fetch origin
DEFAULT_BRANCH=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')
DEFAULT_BRANCH="${DEFAULT_BRANCH:-main}"

# Integration worktree — created once per objective, first.
git worktree add ".agent-worktrees/<slug>/integration" -b "objective/<slug>" "origin/${DEFAULT_BRANCH}"

# Worker worktrees — branched from the integration branch, not from origin.
git worktree add ".agent-worktrees/<slug>/task-001" -b "worker/<slug>/001" "objective/<slug>"
```

Deriving the default branch via `git` keeps this working without `gh`; see [`gh-cli-preference.md`](gh-cli-preference.md). If `gh` is available, `gh repo view --json defaultBranchRef --jq .defaultBranchRef.name` is equivalent.

### Naming

| Thing | Form | Example |
|-------|------|---------|
| Objective slug | kebab-case, no provider, no platform | `auth-system` |
| Integration branch | `objective/<slug>` | `objective/auth-system` |
| Worker branch | `worker/<slug>/NNN` | `worker/auth-system/002` |
| Worktree dir | `.agent-worktrees/<slug>/{integration,task-NNN}` | `.agent-worktrees/auth-system/task-002` |

Never encode `claude`, `cursor`, `codex`, `gemini`, or `opencode` into a slug, branch, or directory. Which provider ran a task is recorded in the task/handoff state under `.dev-files/objectives/<id>/` — see [`dev-files-workspace.md`](dev-files-workspace.md) and [`cross-platform-handoff.md`](cross-platform-handoff.md). That is what lets a task start on one provider and finish on another without renaming anything.

---

## Working inside a worktree

All git operations run normally inside the worktree directory — it has its own index and working files, sharing objects and refs with the main repo.

```bash
cd .agent-worktrees/<slug>/task-001
# implement, stage, commit
git add skills/dev-workflow/pr-dev/SKILL.md
git commit -m "feat(skills): ..."
```

A worker ends by writing its handoff (see [`cross-platform-handoff.md`](cross-platform-handoff.md)). Pushing a worker branch is optional — useful for durability or for a remote reviewer, unnecessary for a local-only objective. Do not require a remote where none is needed.

### Composing workers into the integration worktree

```bash
cd .agent-worktrees/<slug>/integration
git merge --no-ff worker/<slug>/001 worker/<slug>/002
# Tier 2: full lint/typecheck, full suite, cross-worker review of the combined diff
make validate
```

Conflicts between workers are an integration-worktree problem, resolved there — never by rewriting another worker's branch.

---

## Legacy platform worktrees — understood, never orphaned

Earlier versions of this repo used platform-shaped paths:

```text
.claude/.worktrees/<name>
.cursor/.worktrees/<name>
.codex/.worktrees/<name>
```

Those remain **valid and supported**. Nothing migrates them destructively, and no tool may delete or move one on its own initiative.

- `resolve-worktree.sh` recognizes both layouts. Given an existing legacy worktree for a slug, it resolves to that worktree rather than creating a parallel new-layout one.
- `resolve-worktree.sh --list` enumerates every agent worktree it can see — new-layout and legacy — with its branch, objective (where known), and last commit date.
- `resolve-worktree.sh --migrate <path>` moves one legacy worktree into the new layout, in place, preserving uncommitted work. It is opt-in, one worktree at a time, and refuses to run on a dirty tree without an explicit confirmation flag.
- Claude Code's `EnterWorktree` tool and the `~/.claude/worktrees/<repo>/<slug>/` paths created by Claude Code hooks are a separate, external mechanism. They keep working; treat them as legacy-equivalent.

All of `.agent-worktrees/`, `.claude/.worktrees/`, `.cursor/.worktrees/`, and `.codex/.worktrees/` stay in `.gitignore`. Worktree directories are never committed.

---

## Cleaning up

Remove a worktree only when its work is committed and composed, or when the user says the work is abandoned. **Never** `--force` away a worktree with uncommitted changes to tidy up; rescuing uncommitted work is a hard invariant ([`core/policies/safety.md`](../../core/policies/safety.md)).

```bash
# Worker worktrees — after the integration branch contains their commits
git worktree remove .agent-worktrees/<slug>/task-001
git branch -d worker/<slug>/001

# Integration worktree — after the objective's PR merges
git worktree remove .agent-worktrees/<slug>/integration
git branch -D objective/<slug>
git remote prune origin
git worktree prune
```

When delivery ran through `pr-dev`, `cleanup-after-merge.sh` performs remote branch deletion, worktree removal, and local branch cleanup in one step. It requires `gh` for the remote half and degrades to local-only cleanup without it.

---

## Coordination between agents

| Situation | Action |
|-----------|--------|
| Two agents work on the same objective | Each takes its own `task-NNN` worktree + `worker/<slug>/NNN` branch |
| Two agents need the same file scope | Sequence them with `depends_on` in the task state; do not co-edit one worktree |
| Two agents need the same branch | Only one holds it; the other branches from the same base |
| Agent crashes mid-task | Its worktree and commits survive. Read its handoff (or its last commit) and resume in place — do not delete it |
| Unsure what exists | `resolve-worktree.sh --list`, or `git worktree list` from the repo root |

---

## Platform notes

Provider-specific ergonomics only — the model above is identical everywhere.

| Provider | Note |
|----------|------|
| Claude Code | `EnterWorktree` automates creation/cleanup and places worktrees under `.claude/.worktrees/<name>` (legacy layout, supported). Use it when it saves work; use `resolve-worktree.sh` when you need the objective layout |
| Cursor | No built-in worktree tool — create manually or via `resolve-worktree.sh` |
| Codex | No built-in worktree tool — same as Cursor |
| Gemini CLI | No built-in worktree tool — same as Cursor |
| OpenCode | No built-in worktree tool — same as Cursor |

Capability facts live in [`core/capabilities/platforms.json`](../../core/capabilities/platforms.json), not in this table; the table is a convenience. When they disagree, the JSON wins.
