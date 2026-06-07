---
name: start-dev
description: "Start development — create worktree, implement tasks, validate, push, and open a PR. Use when the user has approved a plan or wants to begin coding from a GitHub issue, task description, or spec file. Covers everything from 'here's what to build' to 'PR is open for review'."
when_to_use: "User says to start, begin, implement, build, code, or work on a task — typically with an issue number, task description, or path to a spec — and expects commits and a PR at the end."
argument-hint: "[issue number(s), task description, or file path to spec]"
model: claude-sonnet-4-6
allowed-tools:
  - Bash
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - WebFetch
  - WebSearch
  - Agent
metadata:
  capability: developer-workflow
  tags:
    - implementation
    - worktree
    - pr
    - workflow
  updated-date: "2026-06-07"
---

# start-dev

Full implementation flow: set up workspace, implement all tasks, validate, push, and open a PR.

## Input

Parse `$ARGUMENTS` as one of:
- GitHub issue number(s) (e.g. `#258` or `258 259 260`)
- A task description to implement directly
- A file path to a spec or plan

If empty, ask what to implement and stop.

## Required execution flow

### 1. Understand the work

- If given issue numbers: `gh issue view <number>`
- If given a description or file: read and parse tasks from it

### 2. Set up workspace

Skip if already on a feature branch inside a worktree.

Derive a short branch name from the task (e.g. `feat/add-user-auth`, `fix/null-pointer-login`):

```bash
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null || echo "main")
git fetch origin
git worktree add .claude/worktrees/<branch-name> -b <branch-name> origin/$DEFAULT_BRANCH
```

All editing must happen inside the worktree directory, not the main checkout.

### 3. Implement

For each task:
1. Read the files that need modification
2. Make the changes
3. Commit with conventional commit format:
   ```
   <type>(<scope>): <description>

   Co-Authored-By: Claude <noreply@anthropic.com>
   ```

One commit per task or logical unit. Group only tightly related micro-changes.

### 4. Validate

Run whatever validation is appropriate for this repo:

```bash
# JavaScript / Node
[ -f package.json ] && (npm test 2>/dev/null || yarn test 2>/dev/null || pnpm test 2>/dev/null || true)
[ -f package.json ] && (npm run lint 2>/dev/null || yarn lint 2>/dev/null || true)
[ -f package.json ] && (npm run typecheck 2>/dev/null || yarn typecheck 2>/dev/null || true)

# Python
[ -f pyproject.toml ] || [ -f setup.py ] && (pytest 2>/dev/null || python -m pytest 2>/dev/null || true)

# Go
[ -f go.mod ] && go test ./... 2>/dev/null || true

# Make
[ -f Makefile ] && (make test 2>/dev/null || true)
```

Fix any failures before pushing.

### 5. Push and open PR

```bash
git push -u origin HEAD
```

Detect the default branch if not already known, then open PR:
```bash
ISSUES=""
# If issue number(s) were given, add "Closes #N" for each
gh pr create \
  --title "<concise imperative title matching the task>" \
  --body "$(cat <<'EOF'
## Summary
<what was changed and why — 2-3 sentences>

## Changes
- <key change 1>
- <key change 2>

## Test plan
- [ ] <how to verify the feature/fix works>
- [ ] All existing tests pass

${ISSUES}

🤖 Generated with [Claude Code](https://claude.ai/code)
EOF
)"
```

### 6. Report

Print:
- Files changed and commits made
- Validation outcome
- PR URL
- Suggested next step: "Wait for CI + review, then run `/pr-dev <PR number>`"

## What this skill does NOT do

- Make architectural decisions without asking
- Push directly to the default branch
- Merge the PR (use `/pr-dev` for that)
- Skip validation even if the user asks to "just push"
