---
name: cleanup
description: 'Use when the user wants to clean up, tidy, or reset a GitHub repository — covers the full sweep: delete merged/stale remote branches, drive every open PR to merge-ready in parallel, remove idle local worktrees (rescuing uncommitted work), delete build/cache artifacts, and reset the local checkout to match remote. Invoke this whenever the user mentions repo cleanup, pruning branches, stale branches, worktree housekeeping, wiping build files, or syncing local to remote — even if they only mention one part of the sweep.'
when_to_use: 'User says: clean up the repo, prune merged branches, delete stale branches, clean local worktrees, tidy up open PRs, drive all PRs with pr-dev, reset local to remote, fresh clean environment, repo housekeeping, purge build files, sync local to remote, remove merged branches, wipe worktrees.'
argument-hint: '[--remote-only | --local-only | --dry-run] [repo path, defaults to cwd]'
arguments:
- flags
- target
disable-model-invocation: false
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
  updated-date: "2026-07-21"
  tamirs:
    visibility: public
    category: repo
    capabilities:
      required: [shell, git]
      optional: [github_cli, worktree_isolation]
    role: integrator
    updated-date: "2026-08-19"
    validation-tier: 3

---

## Live context
!`git rev-parse --show-toplevel 2>/dev/null && echo "repo root: $(git rev-parse --show-toplevel)" && git remote get-url origin 2>/dev/null || echo "not a git repo"`
!`gh auth status 2>&1 | head -1 || echo "gh: not available"`

# repo-cleanup

Full repository housekeeping: prune remote branches, drive open PRs in parallel via sub-agents, clean local worktrees, discard or rescue uncommitted work, and reset the local environment to a clean state matching remote.

## Why this skill exists

Repos accumulate cruft quickly — merged branches that weren't deleted, PRs that stalled, worktrees from old tasks, temp build files, and local checkouts that drifted from `main`. Doing this manually is error-prone and tedious. This skill sweeps all of it in one pass, asks for confirmation before any destructive action, and parallelizes PR work across sub-agents so the whole process finishes faster.

**Why this skill is model-invocable** (`disable-model-invocation: false`): cleanup is meant to be *orchestrated* — an operator points sub-agents (or a Workflow) at many repos and fans out one cleanup per repo. Gating a skill with `disable-model-invocation: true` also blocks that path, because a sub-agent invoking a skill is itself model invocation. So safety lives **inside** the skill — every destructive step shows a plan and waits for confirmation, and dry-run mode changes nothing — not in the invocation flag. The flag is reserved for skills that must *never* be invoked autonomously (internal companions), which cleanup is not.

## Scope flags

| Flag | Effect |
|------|--------|
| `--remote-only` | Run only Phase 1 (remote branches + PRs) |
| `--local-only` | Run only Phases 2–3 (worktrees + local reset) |
| `--dry-run` | Print every planned action without executing it |
| (none) | Full sweep — all phases |

Parse flags from args at startup. Default = full sweep.

## Headless / non-interactive use

For fan-out across many repos — one sub-agent (or Workflow stage) per repo — use the companion script instead of the interactive flow:

```bash
bash scripts/cleanup.sh [--dry-run] [--remote-only | --local-only] [--yes] [REPO_PATH]
```

`scripts/cleanup.sh` is the **provably-safe deterministic core** of this skill: it performs only the deletions that need no human judgment — remote branches fully merged into the default branch, auxiliary worktrees that are clean *and* merged/gone, git-ignored build/cache directories, and a fast-forward-only sync of the default branch. Anything requiring judgment — dirty worktrees, unpushed commits, unmerged branches, non-ignored files, a diverged default branch — is **reported and left untouched**.

- It is **dry-run by default**; it changes nothing unless `--yes` is passed.
- It never drives PRs, never rescues uncommitted work, and never drops anything a human would want to review.

The full interactive skill below remains the default for a single repo — it adds per-item confirmation, rescuing uncommitted work, and driving open PRs in parallel via `pr-dev`. Reach for the script when you need cleanup to run **unattended at scale**; reach for the skill when a human is in the loop.

## Startup checks

Before doing anything:
1. Confirm `gh auth status` succeeds — if not, stop and tell the user to run `gh auth login`.
2. Confirm cwd is a git repo with a remote. If not, stop.
3. Resolve `REPO` and `DEFAULT` once; reuse throughout:
   ```bash
   REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
   DEFAULT=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
   ```

## Phase 1 — Remote branch cleanup

### 1a. Discover branches

```bash
git fetch --prune origin

# Branches fully merged into the default branch
git branch -r --merged "origin/$DEFAULT" \
  | grep -v "HEAD\|origin/$DEFAULT\|origin/main\|origin/master\|origin/develop\|origin/release" \
  | sed 's|  origin/||' | sort > /tmp/rc_merged.txt

# Branches with no open PR and last commit older than 30 days
gh api "repos/$REPO/branches" --paginate \
  --jq '.[] | select(.protected == false) | .name' | sort > /tmp/rc_all.txt
```

A branch is a **delete candidate** when ANY of the following is true:
- Fully merged into the default branch (appears in `git branch -r --merged`)
- Its associated PR is merged/closed and the branch was not auto-deleted
- No open PR exists for it and its last commit is older than 30 days

A branch is **safe to keep** when:
- It has an open (not merged, not closed) PR
- It matches a protected/long-lived pattern: `main`, `master`, `develop`, `release/*`, `hotfix/*`
- It is `protected` on GitHub

### 1b. Show the plan and confirm

Print the full classification before touching anything:

```
Remote branch cleanup plan for <REPO>:
  DELETE (merged into main):
    - fix/old-thing  (merged 2026-06-01)
    - chore/cleanup  (merged 2026-05-15)
  DELETE (stale, no open PR, 87 days idle):
    - wip/experiment (last commit 2026-04-01)
  KEEP (open PR #42):
    - feat/new-thing
  KEEP (protected / long-lived):
    - develop

Proceed with deletion? (yes/no)
```

Wait for `yes`. If the user says `no`, skip 1c and go directly to 1d.

### 1c. Delete confirmed branches

For each confirmed delete candidate:

```bash
git push origin --delete "<branch>" 2>&1 \
  || gh api -X DELETE "repos/$REPO/git/refs/heads/<branch>"
```

Log each result: `Deleted: <branch>` or `Skipped (already gone): <branch>`.

### 1d. Drive open PRs in parallel

```bash
gh pr list --repo "$REPO" --state open --json number,title,headRefName \
  --jq '.[] | "PR #\(.number): \(.title)"'
```

If there are **no open PRs**, report "No open PRs — skipping." and move on.

If there are open PRs, **spawn one sub-agent per PR** using the Agent tool, all in the same call so they run in parallel. Each agent's prompt:

```
You are driving PR #<N> in repo <REPO> to merge-ready.
Invoke the pr-dev skill (tamirs-superpowers:pr-dev) with PR number <N>.
Stop at the readiness gate — do NOT merge without explicit user approval.
Report back in one line: "PR #<N>: ready" or "PR #<N>: blocked — <reason>".
```

**Important**: spawn all PR sub-agents first, then immediately continue with Phases 2 and 3 yourself — don't wait for the PR agents to finish before proceeding locally. They run in the background while you do the local cleanup.

Collect results when all agents complete and include them in the final summary.

## Phase 2 — Local worktree cleanup

### 2a. List all worktrees

```bash
git worktree list --porcelain
```

The **first entry** is the main worktree (the current checkout). Never remove it. All other entries are auxiliary worktrees — these are what you clean up.

For each auxiliary worktree, gather its state:

```bash
# uncommitted changes
git -C "<path>" status --porcelain 2>/dev/null

# unpushed commits
BRANCH=$(git -C "<path>" branch --show-current 2>/dev/null)
git -C "<path>" log --oneline "origin/$BRANCH..HEAD" 2>/dev/null

# last commit date
git -C "<path>" log -1 --format="%ar" 2>/dev/null
```

### 2b. Classify each auxiliary worktree

| State | Label | Intended action |
|-------|-------|-----------------|
| Clean + branch merged into default | `stale-clean` | Auto-remove — safe, no data loss |
| Clean + open PR exists | `pr-worktree` | Skip — pr-dev sub-agent is already handling it |
| Clean + no PR + last commit >30 days | `stale-clean` | Auto-remove |
| Clean + no PR + last commit ≤30 days | `recent-clean` | Ask before removing |
| Has uncommitted changes | `dirty` | Always ask — show diff summary before acting |
| Has only unpushed commits | `ready-to-push` | Push branch, open/update PR, then remove |

### 2c. Handle worktrees that need a decision

For any `dirty` or `recent-clean` worktree, show the user what's there before asking:

```
Worktree: ~/.claude/worktrees/myrepo/feat-login
Branch: feat/login (last commit 3 days ago)
Uncommitted: 4 files changed

Modified:
  src/auth/login.ts (+42 -5)
  src/auth/session.ts (+12)
  ...

Options:
  push  — commit as "wip: save work from worktree cleanup", push, open draft PR
  skip  — leave this worktree untouched
  drop  — discard all changes and remove (IRREVERSIBLE)
```

Wait for the user's choice per worktree. Never drop without an explicit `drop` response.

For `ready-to-push` worktrees, push the branch and open/update a PR, then remove.

### 2d. Remove clean/resolved worktrees

```bash
git worktree remove --force "<path>"
git worktree prune
```

Verify with `git worktree list` that the list is now clean.

## Phase 3 — Local environment reset

### 3a. Delete build and temp files

Scan for known patterns (respecting `.gitignore` — prefer deleting only ignored dirs):

```bash
git ls-files --others --ignored --exclude-standard -z \
  | xargs -0 -I{} find "{}" -maxdepth 0 \( \
      -name "node_modules" -o -name ".next" -o -name "dist" -o \
      -name "build" -o -name ".cache" -o -name "__pycache__" -o \
      -name ".tox" -o -name "target" -o -name ".gradle" \
    \) -print 2>/dev/null
```

Or if `git ls-files` doesn't cover it, fall back to:

```bash
find . -maxdepth 3 \( \
  -name "node_modules" -o -name ".next" -o -name "dist" -o \
  -name "build" -o -name ".cache" -o -name "__pycache__" -o \
  -name ".tox" -o -name "target" -o -name ".gradle" \
\) -not -path "./.git*" -print
```

Show the list and ask: `Delete these? (yes/no/[list items to skip])`. Never delete without confirmation. Be conservative — skip anything that doesn't look like a generated artifact (e.g., a `build/` directory that contains hand-written source files).

### 3b. Sync local to remote

```bash
git checkout "$DEFAULT"
git fetch --prune origin
git pull --rebase "origin/$DEFAULT"
```

If local `$DEFAULT` has commits not on remote, show them and ask:

```
Warning: local <DEFAULT> has 2 commits not on remote:
  abc1234 "some message"
  def5678 "another commit"
Push them or reset to remote? (push/reset)
```

Wait for the answer. After syncing, run `git status` and confirm the branch is clean.

## Output format

Brief, state-change-only updates — not one line per command:

```
[Phase 1/3] Remote cleanup
  Scanning branches... found 5 total, 3 delete candidates
  Plan shown → user confirmed → deleted: fix/old-thing, chore/cleanup, wip/experiment
  Open PRs: 2 → PR agents spawned (#41, #43)

[Phase 2/3] Local worktrees
  Main worktree: skipped
  ~/.claude/worktrees/myrepo/feat-login  → stale-clean → removed
  ~/.claude/worktrees/myrepo/fix-bug     → dirty (4 files) → user chose push → PR #51 opened → removed
  ~/.claude/worktrees/myrepo/old-spike   → stale-clean → removed

[Phase 3/3] Local reset
  Build artifacts: .next/, dist/ → user confirmed → deleted
  Synced to origin/main (rebased 3 new commits)

PR agents completed:
  PR #41: ready — all checks green, 0 threads
  PR #43: blocked — CI failing (test coverage)

Summary:
  Remote branches deleted: 3
  Worktrees removed: 3 (1 rescued → PR #51)
  PRs driven: 2 (ready: 1, blocked: 1)
  Build artifacts removed: .next/, dist/
  Local state: clean ✓
```

## Hard rules

- **Never delete the default branch, `main`, `master`, `develop`, `release/*`, or any protected branch** — check `protected: true` in the GitHub API response before deleting anything.
- **Never discard uncommitted work without an explicit `drop` from the user** — always show the diff first.
- **Never remove the main worktree** (first entry in `git worktree list`).
- **Always ask before deleting build artifacts** — the generated-artifact list may contain intentional local directories.
- **Never force-push or hard-reset the default branch** without explicit instruction.
- **In dry-run mode, print every planned action with a `[dry-run]` prefix and execute nothing**. Before each destructive shell command, check if dry-run is active and skip it. Print `Dry-run complete — no changes made.` at the end.
- **If `gh` is unavailable, stop immediately** and tell the user — do not attempt partial cleanup with git alone.
