---
name: start-dev
description: 'Use when the user wants to implement, build, code, or ship a task that will result in commits and a pull request — given a GitHub issue number, free-text task description, or spec file. Triggers: ''implement issue #N'', ''start coding X'', ''build the feature'', ''work on this spec'', ''create a PR for this'', ''ship issue #N'', ''code up the feature'', ''begin implementation of X''.'
when_to_use: implement, build, start coding, begin implementation, work on, create PR for, ship, code up — followed by an issue number (#N), a task description, or a spec/plan file path
argument-hint: '[issue number(s) e.g. #42, free-text task description, or path/to/spec.md]'
arguments: []
disable-model-invocation: false
user-invocable: true
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
disallowed-tools: []
model: claude-sonnet-4-6
effort: high
context: ''
agent: ''
hooks: {}
paths: []
shell: bash
metadata:
  capability: developer-workflow
  tags:
  - implementation
  - worktree
  - pr
  - workflow
  updated-date: '2026-06-30'
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

### Step 1.5 — Load Resume (issue-linked)

When working from a GitHub issue number, read the Resume block before coding:

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
SHARED_DIR="$REPO_ROOT/skills/dev-workflow/_shared/scripts"
bash "$SHARED_DIR/parse-issue-resume.sh" <issue_number>
```

- Surface **Next**, **Decisions**, and **Blocked** to the user
- If `blocked` is not `none` or empty → stop and report
- Use **Branch** from Resume when resuming mid-task (skip branch derivation if set)

### Step 2 — Set up workspace

**Skip if already on a feature branch inside a worktree** (i.e., `git status` works and the branch is not `main`/`master`/`develop`).

Derive a short, slug-style branch name from the task:
- `feat/add-rate-limiting`
- `fix/null-pointer-on-login`
- `chore/upgrade-eslint`

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
SHARED_DIR="$REPO_ROOT/skills/dev-workflow/_shared/scripts"
BRANCH="feat/your-slug-here"   # or from Resume block when resuming

WT_JSON="$(bash "$SHARED_DIR/resolve-worktree.sh" "$REPO_ROOT" "$BRANCH")"
WORKTREE="$(echo "$WT_JSON" | jq -r .worktree_path)"
PLATFORM="$(echo "$WT_JSON" | jq -r .platform)"

echo "Platform: $PLATFORM — worktree: $WORKTREE"
```

All file edits happen inside `$WORKTREE`, not in the main checkout. Paths follow `.<platform>/.worktrees/<slug>/` per `rules/dev/git-worktree-agent-workflow.md`.

### Step 3 — Implement

For each task or logical unit:
1. `Read` the files to be modified before editing
2. Apply changes with `Edit` or `Write`
3. Commit immediately after each logical unit:

```bash
git -C "$WORKTREE" add -p   # stage selectively
git -C "$WORKTREE" commit -m "$(cat <<'EOF'
feat(auth): add rate limiting to login endpoint

Closes #258

Co-Authored-By: Claude <noreply@anthropic.com>
EOF
)"
```

One commit per task or closely related change. Do not batch unrelated changes into a single commit.

### Step 4 — Validate

Use the bundled `scripts/detect-stack.sh` to identify which validation commands apply to this repo, then run each one:

```bash
cd "$WORKTREE"

# Detect commands for this repo's stack
SKILL_DIR="$(dirname "$0")"   # or use $CLAUDE_SKILL_DIR if available
CMDS=$(bash "$SKILL_DIR/scripts/detect-stack.sh" .)

if [ -z "$CMDS" ]; then
  echo "No validation commands detected — check README or package.json scripts manually."
else
  while IFS= read -r cmd; do
    echo "Running: $cmd"
    eval "$cmd"
  done <<< "$CMDS"
fi
```

`detect-stack.sh` covers: Makefile (`make validate` / `make test`), Node/TS (`npm test`, `npm run lint`, `npx tsc --noEmit`), Python (`pytest`), Go (`go test ./...`, `go vet`), Rust (`cargo test`, `cargo clippy`), Ruby (`bundle exec rspec`).

Fix every failure before proceeding. Do not push broken code. Do not use `--no-verify` or skip tests because the user says "it's urgent".

### Step 5 — Push and open PR

```bash
git -C "$WORKTREE" push -u origin HEAD
```

Read `references/pr-templates.md` in this skill directory to choose the right PR body template (feature/bug-fix/spec-task/multi-issue/chore). Fill in all `[…]` placeholders — never leave them literally in the PR body.

```bash
# Build Closes lines for each linked issue (omit if no issue number)
CLOSES="Closes #42"   # adjust per actual issue number(s)

gh pr create \
  --title "feat(auth): add rate limiting to login endpoint" \
  --body "$(cat <<EOF
## Summary
Added a token-bucket rate limiter to POST /login. Prevents brute-force attacks by returning 429 after 5 failed attempts per IP per minute.

## Changes
- Added token-bucket rate limiter to \`POST /login\`
- Configurable via \`RATE_LIMIT_MAX\` env var (default: 5 req/min)

## Test plan
- [ ] Hit /login 6+ times in a minute — 6th request returns 429 with Retry-After header
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
On rate limit or pause: run /switch-dev handoff #N before switching platforms
```

See `skills/dev-workflow/switch-dev/references/platform-capabilities.md` for staying on the same platform longer (Codex `/goal`, Cursor `/multitask`, Claude subagents).

## Hard rules

- **Never push directly to the default branch** (`main`, `master`, `develop`). Always use a feature branch.
- **Never skip Step 4 validation**, even if the user says "just push it" or "it's urgent". Run the checks.
- **Never commit with `git add .`** blindly — always stage selectively with `git add -p` or by naming specific files to avoid committing secrets or build artifacts.
- **Never make architectural decisions silently** — if the implementation requires a choice that changes the public API, schema, or module structure, surface it and ask before coding.
- **Never create the worktree inside a path that already exists** — `resolve-worktree.sh` resumes existing paths.
- **Never merge or close the PR** — that is the job of `/pr-dev`.
- **Commit messages must follow conventional commits** (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`).

## What NOT to do

| Wrong | Right |
|---|---|
| `git add . && git commit -m "wip"` | Stage specific files; use a descriptive conventional commit |
| Push to `main` directly | Create a branch; open a PR |
| Skip validation because tests are "probably fine" | Run the stack's test/lint commands; fix failures |
| Open the PR with title "Fix stuff" | Write an imperative-mood title: "fix: prevent null dereference in login handler" |
| Create a worktree in an arbitrary path | Use `resolve-worktree.sh` → `.<platform>/.worktrees/<slug>` |
| Batch all changes into one giant commit | One commit per logical unit |

## Quick reference

| Situation | Action |
|---|---|
| Already on a feature branch | Skip Step 2; implement directly |
| Issue is blocked by another | Surface the blocker; do not start implementation |
| Multiple issues in one PR | Add `Closes #N` per issue in PR body; group related commits |
| Validation script not found | Check `package.json` scripts, `Makefile`, `README` for project-specific commands |
| Worktree already exists | `resolve-worktree.sh` resumes; `cd` into returned path |
| Tests fail after changes | Fix the failures; never `--no-verify` or skip |

## Scope boundary

This skill ends at an open PR. It does NOT:
- Merge the PR (use `/pr-dev`)
- Monitor CI (use `/pr-dev`)
- Rebase or resolve conflicts after review
