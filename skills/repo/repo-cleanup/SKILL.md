---
name: repo-cleanup
description: 'Use when the user wants to clean up a GitHub repository — delete merged or stale remote branches, drive open PRs to completion via sub-agents, remove unused local worktrees, recover or discard uncommitted local work, delete build/temp files, and reset the local environment to match remote. Triggers: repo cleanup, clean up branches, prune branches, delete merged branches, clean local worktrees, tidy repo, repo hygiene, fresh local env, clean my repo, stale branches.'
when_to_use: 'User says: clean up the repo, prune merged branches, delete stale branches, clean local worktrees, tidy up open PRs, run pr-dev on all open PRs, reset local to remote, fresh clean environment, repo housekeeping, purge build files, sync local to remote.'
argument-hint: '[--remote-only | --local-only | --dry-run] [repo path, defaults to cwd]'
arguments:
- flags
- target
disable-model-invocation: true
user-invocable: true
allowed-tools:
- Bash
- Read
- Agent
- Skill
- Glob
- Grep
disallowed-tools: []
model: claude-sonnet-4-6
effort: high
context: ''
agent: ''
hooks: {}
paths: []
shell: bash
metadata:
  capability: repo
  tags:
  - repo-cleanup
  - branches
  - worktrees
  - hygiene
  - pr-dev
  - github
  updated-date: "2026-06-27"
---

## Live context
!`git rev-parse --show-toplevel 2>/dev/null && echo "repo root: $(git rev-parse --show-toplevel)" && git remote get-url origin 2>/dev/null || echo "not a git repo"`
!`gh auth status 2>&1 | head -1 || echo "gh: not available"`

# repo-cleanup

Full repository housekeeping: prune remote branches, drive open PRs, clean local worktrees, discard or rescue uncommitted work, and reset the local environment to a clean state matching remote.

## Why this skill exists

Repos accumulate cruft fast — merged branches that weren't deleted, PRs that stalled, worktrees from months-old tasks, temp build files, and local checkouts that have drifted from `main`. Doing this manually is error-prone and tedious. This skill runs all phases in one sweep, asking for confirmation before any destructive action, and runs PR work in parallel via sub-agents.

## Scope flags

| Flag | Effect |
|------|--------|
| `--remote-only` | Skip local cleanup (phases 2–3) |
| `--local-only` | Skip remote cleanup (phase 1) |
| `--dry-run` | Print every action without executing it |
| (none) | Full sweep — all phases |

Parse from args at startup. Default = full sweep.

## Phase 1 — Remote branch cleanup

### 1a. Discover branches to delete

```bash
# Get the repo owner/name
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
DEFAULT=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)

# Fetch all remote branches
gh api "repos/$REPO/branches" --paginate -q '.[].name' | sort > /tmp/rc_all_branches.txt

# Branches merged into default
git fetch --prune origin
git branch -r --merged "origin/$DEFAULT" \
  | grep -v "HEAD\|$DEFAULT\|main\|master" \
  | sed 's|origin/||' | sort > /tmp/rc_merged_branches.txt
```

A branch is a **delete candidate** when ANY of the following is true:
- It is fully merged into the default branch (`git branch -r --merged`)
- Its associated PR was merged and the branch was not auto-deleted
- It has no open PR and its last commit is older than 30 days

A branch is **safe to keep** when:
- It has an open (not merged, not closed) PR
- It matches a long-lived pattern: `main`, `master`, `develop`, `release/*`, `hotfix/*`
- The user has told you to keep it

### 1b. Show the plan and confirm

Before deleting anything, print the branch list:

```
Remote branch cleanup plan for <REPO>:
  DELETE (merged):
    - fix/old-thing  (merged 2026-06-01, no open PR)
    - chore/cleanup  (merged 2026-05-15, no open PR)
  DELETE (stale, no PR):
    - wip/experiment (last commit 2026-04-01, 87 days idle)
  KEEP (open PR):
    - feat/new-thing  → PR #42
  KEEP (long-lived):
    - develop

Proceed? (yes/no)
```

Wait for `yes` before deleting. On `no`, skip phase 1b but continue to 1c.

### 1c. Delete branches

For each confirmed delete candidate:

```bash
git push origin --delete "<branch>" 2>&1 || \
  gh api -X DELETE "repos/$REPO/git/refs/heads/<branch>"
```

Log each result: `Deleted: <branch>` or `Skipped (already gone): <branch>`.

### 1d. Drive open PRs

List open PRs:

```bash
gh pr list --repo "$REPO" --state open --json number,title,headRefName \
  --jq '.[] | "PR #\(.number): \(.title) (\(.headRefName))"'
```

If there are open PRs, spawn **one sub-agent per PR in parallel** to drive it via `pr-dev`. Each agent receives:

```
Drive PR #<N> in repo <REPO> to merge-ready. Use the pr-dev skill.
Stop at the readiness gate — do NOT merge. Report back: either
"ready" (all checks green, 0 threads) or "blocked: <reason>".
```

Collect results and report a summary table:

```
PR #41  ready — all checks green, 0 threads
PR #42  blocked — CI failing: test coverage threshold
PR #43  ready — addressed 2 review threads
```

Do not wait for CI to complete before moving to phase 2 — run phases 2 and 3 concurrently with the PR agents.

## Phase 2 — Local worktree cleanup

### 2a. List all worktrees

```bash
git worktree list --porcelain
```

Identify:
- **Main worktree** — the first entry (current checkout of the repo); never touch it
- **Auxiliary worktrees** — all others, typically under `~/.claude/worktrees/`

For each auxiliary worktree, check its status:

```bash
git -C "<worktree-path>" status --porcelain 2>/dev/null
git -C "<worktree-path>" log --oneline "origin/$(git -C '<worktree-path>' branch --show-current)..HEAD" 2>/dev/null
```

### 2b. Classify each worktree

| State | Classification | Action |
|-------|---------------|--------|
| Clean, branch merged | `stale-clean` | Auto-remove (no confirmation needed) |
| Clean, branch open PR exists | `pr-worktree` | Skip — let pr-dev sub-agent handle it |
| Clean, branch no PR, no recent commits | `stale-clean` | Auto-remove |
| Has uncommitted changes, <7 days old | `active-work` | Push + open PR, then remove |
| Has uncommitted changes, ≥7 days old | `stale-dirty` | Confirm before discarding |
| Has unpushed commits only | `ready-to-push` | Push branch; open/update PR; remove |

"Recent" = last commit in the past 7 days.

### 2c. Handle active work (uncommitted changes)

For each `active-work` worktree:

1. State what uncommitted work exists (file list + diff summary).
2. Ask: **push and open a PR, or discard?** Do not discard without explicit confirmation.
3. If push: commit with `wip: save uncommitted work from worktree cleanup`, push, open a draft PR.
4. Then remove the worktree.

For each `stale-dirty` worktree: always ask before discarding — state the branch name, age, and changed files.

### 2d. Remove clean or resolved worktrees

```bash
git worktree remove --force "<worktree-path>"
git worktree prune
```

Run `git worktree list` after to confirm clean.

## Phase 3 — Local environment reset

### 3a. Delete build and temp files

Scan the repo root for known build/cache patterns:

```bash
find . -maxdepth 3 \( \
  -name "node_modules" -o \
  -name ".next" -o \
  -name "dist" -o \
  -name "build" -o \
  -name ".cache" -o \
  -name "__pycache__" -o \
  -name "*.pyc" -o \
  -name ".tox" -o \
  -name "target" -o \
  -name ".gradle" \
\) -not -path "./.git/*" -prune -print
```

Show the list. Confirm before deleting anything. Skip paths that look hand-written (no `package.json` in parent = not a real `node_modules`).

If the repo has a `.gitignore`, cross-reference: prefer deleting only files/directories covered by `.gitignore` entries to avoid nuking intentional local-only assets.

### 3b. Sync local to remote

```bash
git fetch --prune origin
git checkout "$DEFAULT"
git pull --rebase origin "$DEFAULT"
```

If there are local commits on the default branch that aren't on remote:

```
Warning: local <DEFAULT> has N commit(s) not on remote:
  abc1234 "some commit message"
Push them, or reset to remote? (push/reset)
```

Wait for the user's answer before proceeding.

Final state check:

```bash
git status
git log --oneline -5
```

Report: `Local repo is clean and synced with origin/<DEFAULT>.`

## Output format

Keep updates brief — state-change only, not every poll.

```
[1/3] Remote cleanup — scanning branches...
  Merged (to delete): fix/old-thing, chore/cleanup
  Open PRs found: 2 → spinning up pr-dev sub-agents

[2/3] Local worktrees — found 3 auxiliary worktrees
  ~/.claude/worktrees/myrepo/feat-login  → stale-clean, removing
  ~/.claude/worktrees/myrepo/fix-bug     → active-work, 3 uncommitted files

[3/3] Environment reset — fetching and rebasing...
  ✓ Synced to origin/main (3 new commits)

Summary:
  Branches deleted: 3
  Worktrees removed: 2 (1 rescued → PR #51)
  PRs driven: 2 (ready: 1, blocked: 1)
  Build artifacts removed: .next/, dist/
  Local state: clean ✓
```

## Hard rules

- **Never delete the main/master/default branch** — check before any deletion.
- **Never force-push or reset the default branch** without explicit user instruction.
- **Never discard uncommitted work without confirmation** — always show what would be lost.
- **Always ask before deleting build artifacts** — the list can include intentional local directories.
- **Never remove the active worktree** (the main checkout) — only auxiliary worktrees from `git worktree list`.
- **Dry-run mode prints, never executes** — every shell command must be gated on `$DRY_RUN`.
- **Never use `--admin` for PR operations** — only standard merge paths.

## Dry-run mode

When `--dry-run` is set, replace every destructive command with a print:

```bash
DRY_RUN=true
dry() { echo "[dry-run] $*"; }

# instead of:  git push origin --delete "fix/old-thing"
# write:
$DRY_RUN && dry "git push origin --delete fix/old-thing" || git push origin --delete "fix/old-thing"
```

Print a final `Dry-run complete — no changes made.` at the end.
