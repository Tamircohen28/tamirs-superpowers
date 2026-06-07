---
name: task-audit
description: "Audit a completed development task or branch — review git diff quality, commit conventions, test coverage of changed files, leftover TODO/FIXME markers, and overall PR readiness. Use after finishing an implementation task to verify quality before requesting review."
when_to_use: "User asks to audit, review, or quality-check a completed task or branch — phrases like 'audit this work', 'is this ready for review', 'check my PR', 'task-audit', 'review what I built', 'how's the code quality', or any request to assess a branch before opening or merging a PR."
argument-hint: "[branch name or PR number — defaults to current branch]"
model: claude-sonnet-4-6
allowed-tools:
  - Bash
  - Read
  - Grep
  - Glob
metadata:
  capability: task-quality-audit
  tags:
    - audit
    - quality
    - code-review
    - pr-readiness
    - testing
  updated-date: "2026-06-07"
---

# task-audit

Inspect a completed branch's changes end-to-end and produce a structured `task-audit.md` report that flags quality gaps, missing tests, leftover work markers, and PR-readiness issues — before a human reviewer sees it.

## Why this skill exists

After finishing a task it's easy to miss leftover TODOs, skip tests for changed code, or write commits that make review harder. This skill runs a deterministic sweep before review — catching issues that are cheap to fix now and expensive after a reviewer flags them.

## Input

One optional argument: a branch name, PR number, or nothing (defaults to current branch).

| Form | Example |
|------|---------|
| Current branch (default) | (no argument) |
| Branch name | `feat/add-user-auth` |
| PR number | `#258` or `258` |

## What the audit covers

Seven dimensions, each producing 0+ findings with severity `CRITICAL` / `WARNING` / `INFO` / `PASS`:

| # | Dimension | What it asks |
|---|-----------|--------------|
| 1 | Diff scope | Is the change focused? Are there unrelated modifications mixed in? |
| 2 | Commit quality | Do commits follow conventional commit format? Are messages descriptive? |
| 3 | Test coverage | Do changed source files have corresponding test changes? |
| 4 | Leftover markers | Are TODO, FIXME, HACK, XXX, or debug statements left in changed lines? |
| 5 | Breaking changes | Does the diff change public interfaces or APIs without a migration note? |
| 6 | Documentation sync | If user-facing behavior changed, are docs/README updated? |
| 7 | PR readiness | Is the branch current with base? Any conflicts? CI green? |

Severities:
- **CRITICAL** — blocks merge (leftover debug in production path, broken API with no migration)
- **WARNING** — should fix but won't break anything (no tests, unclear commit)
- **INFO** — nice-to-have (minor style, single small commit could be better-named)
- **PASS** — dimension checked, no issue

## Workflow

### Step 1 — Resolve the target

```bash
# Default: current branch
BRANCH=$(git branch --show-current)
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name 2>/dev/null || echo "main")
BASE="$DEFAULT_BRANCH"

# If PR number given
if [[ "$1" =~ ^#?[0-9]+$ ]]; then
  PR_NUMBER="${1#\#}"
  PR_INFO=$(gh pr view $PR_NUMBER --json headRefName,baseRefName --jq '{head: .headRefName, base: .baseRefName}')
  BRANCH=$(echo $PR_INFO | jq -r .head)
  BASE=$(echo $PR_INFO | jq -r .base)
fi

echo "Branch: $BRANCH  Base: $BASE"
git fetch origin $BASE 2>/dev/null || true
```

### Step 2 — Collect diff facts

```bash
# Files changed
git diff --name-status origin/$BASE...$BRANCH

# Commit history
git log --oneline origin/$BASE...$BRANCH

# Stats
git diff --stat origin/$BASE...$BRANCH
```

### Step 3 — Run each dimension

**Dimension 1 — Diff scope:**

```bash
CHANGED=$(git diff --name-only origin/$BASE...$BRANCH)
echo "$CHANGED" | wc -l
# Flag if >3 distinct top-level directories changed with no obvious theme
echo "$CHANGED" | sed 's|/.*||' | sort -u
```
Flag as WARNING if the diff spans unrelated areas with no connecting feature.

**Dimension 2 — Commit quality:**

```bash
git log --format="%s" origin/$BASE...$BRANCH
```
Check each message:
- Follows `<type>(<scope>): <description>` or similar convention?
- No "WIP", "temp", "fixup", "asdf", "test commit", "try again" messages?
- Multiple tiny "fix typo" squash-candidates?

**Dimension 3 — Test coverage:**

```bash
# Source files changed (exclude test, config, docs, lock files)
SOURCES=$(git diff --name-only origin/$BASE...$BRANCH \
  | grep -vE '\.(md|json|yaml|yml|lock|toml|txt|env)$' \
  | grep -vE '(test|spec|__test__|__spec__)' || true)

# Test files changed
TESTS=$(git diff --name-only origin/$BASE...$BRANCH \
  | grep -E '(test|spec|__test__|__spec__)' || true)

for src in $SOURCES; do
  base=$(basename "$src" | sed 's/\.[^.]*$//')
  echo "$TESTS" | grep -qi "$base" || echo "UNTESTED: $src"
done
```

**Dimension 4 — Leftover markers:**

```bash
git diff origin/$BASE...$BRANCH \
  | grep '^+' \
  | grep -v '^+++' \
  | grep -iE '(TODO|FIXME|HACK|XXX|console\.log|debugger|pry|binding\.pry|set_trace|breakpoint|print\("DEBUG)' \
  || true
```

Anything found here is at minimum WARNING; if it's in a production code path, CRITICAL.

**Dimension 5 — Breaking changes:**

Read the diff for:
- Removed or renamed exported functions/methods
- Changed function signatures (removed/reordered parameters)
- Modified config file schemas
- Changed API endpoint paths or response shapes

Flag as WARNING if found with no corresponding CHANGELOG or migration note.

**Dimension 6 — Documentation sync:**

```bash
DOC_CHANGES=$(git diff --name-only origin/$BASE...$BRANCH | grep -cE '\.(md|rst|txt)$' || echo 0)
SOURCE_CHANGES=$(git diff --name-only origin/$BASE...$BRANCH | grep -cvE '\.(md|rst|txt|json|yaml|yml|lock|toml)$' || echo 0)

if [ "$SOURCE_CHANGES" -gt 0 ] && [ "$DOC_CHANGES" -eq 0 ]; then
  echo "INFO: No documentation files changed — verify user-facing behavior is documented if applicable"
fi
```

**Dimension 7 — PR readiness:**

```bash
# Behind base?
BEHIND=$(git rev-list --count HEAD..origin/$BASE 2>/dev/null || echo 0)
[ "$BEHIND" -gt 0 ] && echo "WARNING: branch is $BEHIND commits behind origin/$BASE"

# CI checks (if PR exists)
if [[ "$1" =~ ^#?[0-9]+$ ]]; then
  gh pr checks ${1#\#} 2>/dev/null | grep -vE 'pass|success|✓' | grep -v '^$' || echo "PASS: all checks green"
fi
```

### Step 4 — Write the audit report

Write to `task-audit-${BRANCH}.md` (or `$CLAUDE_SESSION_FILES_DIR/task-audit.md` if set):

```markdown
# Task Audit: <branch>

**Audited:** <date>
**Base:** <base>  **Commits:** N  **Files changed:** N

## Overall: READY / NEEDS-WORK / BLOCKED

## Critical Issues
<findings with severity CRITICAL — if none: "None">

## Warnings
<findings with severity WARNING — if none: "None">

## Test Coverage Gaps
<untested source files — if none: "All changed files have corresponding test changes">

## Leftover Markers
<TODOs / debug statements in changed lines — if none: "None found">

## Info
<INFO findings>

## Passing
<dimensions with PASS verdict>
```

### Step 5 — Print summary to chat

```
Audited: <branch> (base: <base>)
Files changed: N | Commits: N
Critical: N | Warnings: N | Untested: N | Markers: N
Overall: READY / NEEDS-WORK
Report: task-audit-<branch>.md
```

## Hard rules

- **Read-only.** Only output is the audit report — never modify source files.
- **No fabrication.** Only flag issues supported by actual `git diff` output.
- **Don't expand scope.** Only read files that appear in the diff, not the whole codebase.
- **Severity is fixed** — do not invent new severity levels.
