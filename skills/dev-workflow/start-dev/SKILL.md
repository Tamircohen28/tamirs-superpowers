---
name: start-dev
description: "Use when the user says to start, begin, implement, build, code, or work on a task — typically with a GitHub issue number, task description, or path to a spec/plan — and expects commits and a PR at the end. Triggers on: 'implement issue #N', 'build the auth feature', 'start coding this', 'work on this spec', 'begin development', 'create a PR for this'."
when_to_use: "implement, build, start, begin, code, work on, create PR for, ship — followed by an issue number, task description, or spec file path"
argument-hint: "[issue number(s), task description, or file path to spec]"
model: claude-sonnet-4-6
effort: high
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
  - Skill
metadata:
  capability: developer-workflow
  tags:
    - implementation
    - worktree
    - pr
    - workflow
  updated-date: "2026-06-13"
---

## Live context
!`git branch --show-current 2>/dev/null | sed 's/^/current branch: /' || echo "not a git repo"`
!`gh repo view --json defaultBranchRef --jq '"default branch: \(.defaultBranchRef.name)"' 2>/dev/null || true`
!`gh issue list --state open --limit 5 --json number,title --jq '.[] | "  #\(.number): \(.title)"' 2>/dev/null | head -5 || true`

# start-dev

Full implementation flow: workspace setup → implement → validate → push → open PR.

## Why this skill exists

Starting development on a GitHub issue requires a sequence of non-obvious decisions: which branch to create from, whether a git worktree is needed, how to scope commits, what validation to run for this repo's stack, and how to write a PR description that will actually get reviewed. Doing this ad-hoc produces messy histories, skipped validation, and PRs that reviewers bounce back. This skill enforces the complete flow in one invocation.

## Input

Parse `$ARGUMENTS` as one of:
- GitHub issue number(s): `#258` or `258 259 260`
- A free-text task description: `"Add rate limiting to the /login endpoint"`
- A file path to a spec or plan: `path/to/plan.md`

If `$ARGUMENTS` is empty, ask "What do you want to implement?" and stop.

## Workflow

### Step 1 — Understand the work

```bash
# For a GitHub issue:
gh issue view 258

# For multiple issues:
gh issue view 258 259 260

# For a spec file — read it with the Read tool, then extract task list
```

Confirm your understanding in one sentence before proceeding. If the issue is ambiguous or blocked by another issue, surface that immediately.

### Step 2 — Set up workspace

**Skip if already on a feature branch inside a worktree** (i.e., `git status` works and the branch is not `main`/`master`/`develop`).

Derive a short, slug-style branch name from the task:
- `feat/add-rate-limiting`
- `fix/null-pointer-on-login`
- `chore/upgrade-eslint`

```bash
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null || echo "main")
BRANCH="feat/your-slug-here"

git fetch origin
git worktree add .claude/worktrees/$BRANCH -b $BRANCH origin/$DEFAULT_BRANCH
```

All file edits happen inside `.claude/worktrees/$BRANCH/`, not in the main checkout.

### Step 3 — Implement

For each task or logical unit:
1. `Read` the files to be modified before editing
2. Apply changes with `Edit` or `Write`
3. Commit immediately after each logical unit:

```bash
git -C .claude/worktrees/$BRANCH add -p   # stage selectively
git -C .claude/worktrees/$BRANCH commit -m "$(cat <<'EOF'
feat(auth): add rate limiting to login endpoint

Closes #258

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

One commit per task or closely related change. Do not batch unrelated changes into a single commit.

### Step 4 — Validate

Auto-detect the stack and run the appropriate checks:

```bash
cd .claude/worktrees/$BRANCH

# JSON/Markdown/plugin repos
[ -f Makefile ] && make validate 2>/dev/null || make test 2>/dev/null || true

# Node / JavaScript / TypeScript
if [ -f package.json ]; then
  npm test 2>/dev/null || yarn test 2>/dev/null || pnpm test 2>/dev/null || true
  npm run lint 2>/dev/null || yarn lint 2>/dev/null || true
  npm run typecheck 2>/dev/null || npx tsc --noEmit 2>/dev/null || true
fi

# Python
[ -f pyproject.toml ] || [ -f setup.py ] && (pytest 2>/dev/null || python -m pytest 2>/dev/null || true)

# Go
[ -f go.mod ] && go test ./... 2>/dev/null || true

# Rust
[ -f Cargo.toml ] && cargo test 2>/dev/null || true
```

Fix every failure before proceeding. Do not push broken code.

### Step 5 — Push and open PR

```bash
git -C .claude/worktrees/$BRANCH push -u origin HEAD
```

```bash
# Build Closes lines for each linked issue
CLOSES="Closes #258"   # adjust per actual issue number(s)

gh pr create \
  --title "feat: add rate limiting to login endpoint" \
  --body "$(cat <<EOF
## Summary
[2-3 sentences: what changed and why]

## Changes
- Added token-bucket rate limiter to \`POST /login\`
- Configurable via \`RATE_LIMIT_MAX\` env var (default: 5 req/min)

## Test plan
- [ ] Hit /login 6+ times in a minute — 6th request returns 429
- [ ] All existing auth tests pass

$CLOSES

🤖 Generated with [Claude Code](https://claude.ai/code)
EOF
)"
```

### Step 6 — Report

Print a concise summary:

```
Files changed: src/auth/login.ts, tests/auth.test.ts
Commits: 2
Validation: PASS (npm test, npm run lint)
PR: https://github.com/owner/repo/pull/42
Next: wait for CI + review, then run /pr-dev 42
```

## Hard rules

- **Never push directly to the default branch** (`main`, `master`, `develop`). Always use a feature branch.
- **Never skip Step 4 validation**, even if the user says "just push it" or "it's urgent". Run the checks.
- **Never commit with `git add .`** blindly — always stage selectively with `git add -p` or by naming specific files to avoid committing secrets or build artifacts.
- **Never make architectural decisions silently** — if the implementation requires a choice that changes the public API, schema, or module structure, surface it and ask before coding.
- **Never create the worktree inside a path that already exists** — check first with `ls .claude/worktrees/$BRANCH 2>/dev/null`.
- **Never merge or close the PR** — that is the job of `/pr-dev`.
- **Commit messages must follow conventional commits** (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`).

## What NOT to do

| Wrong | Right |
|---|---|
| `git add . && git commit -m "wip"` | Stage specific files; use a descriptive conventional commit |
| Push to `main` directly | Create a branch; open a PR |
| Skip validation because tests are "probably fine" | Run the stack's test/lint commands; fix failures |
| Open the PR with title "Fix stuff" | Write an imperative-mood title: "fix: prevent null dereference in login handler" |
| Create a worktree in an arbitrary path | Always use `.claude/worktrees/<branch-name>` |
| Batch all changes into one giant commit | One commit per logical unit |

## Quick reference

| Situation | Action |
|---|---|
| Already on a feature branch | Skip Step 2; implement directly |
| Issue is blocked by another | Surface the blocker; do not start implementation |
| Multiple issues in one PR | Add `Closes #N` per issue in PR body; group related commits |
| Validation script not found | Check `package.json` scripts, `Makefile`, `README` for project-specific commands |
| Worktree already exists | `git worktree list` to find it; `cd` into it; continue |
| Tests fail after changes | Fix the failures; never `--no-verify` or skip |

## Scope boundary

This skill ends at an open PR. It does NOT:
- Merge the PR (use `/pr-dev`)
- Monitor CI (use `/babysit-pr`)
- Rebase or resolve conflicts after review
