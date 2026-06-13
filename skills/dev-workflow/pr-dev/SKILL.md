---
name: pr-dev
description: "Use when the user wants to drive a PR through review and merge: address unresolved review threads, fix CI failures, get approval, squash-merge, and clean up. Triggers on phrases like 'finish this PR', 'address review comments', 'ship/land/close the PR', 'handle review', 'merge after review', 'fix CI and merge'."
when_to_use: "User says: finish this PR, address comments, ship/land/merge the PR, close out PR, handle review feedback, fix CI and merge, squash-merge, clean up PR branch — or provides a PR number and asks to drive it to done."
argument-hint: "[PR number]"
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
  - Agent
  - Skill
metadata:
  capability: developer-workflow
  tags:
    - pr
    - review
    - merge
    - workflow
    - ci
    - squash
    - ship
    - land
  updated-date: "2026-06-13"
---

## Live context
!`gh pr view --json number,title,state,headRefName,reviewDecision,mergeable 2>/dev/null | jq -r '"PR #\(.number): \(.title) [\(.state)] branch:\(.headRefName) reviews:\(.reviewDecision) mergeable:\(.mergeable)"' 2>/dev/null || echo "no open PR on current branch — provide a PR number"`
!`git branch --show-current 2>/dev/null | sed 's/^/current branch: /' || true`

# PR Dev — Drive a Pull Request to Done

Address every unresolved review thread, fix CI, confirm merge readiness, then (after explicit user approval) squash-merge and clean up the branch.

## Why this skill exists

Manually driving a PR to merge is error-prone: reviewers leave threads that get forgotten, CI results go stale between checks, and branches fall behind base. Naive approaches — reading cached PR state, skipping unresolved threads, or merging as soon as CI is green — all cause regressions or rework. This skill enforces a strict, state-safe workflow: always re-fetch live state, resolve every thread with a typed response, poll CI until genuinely green, and gate the merge on an explicit human approval.

## Input

Parse `$ARGUMENTS` as the PR number. If empty, detect from current branch:
```bash
gh pr view --json number --jq .number
```
If no PR found, ask the user for a PR number and stop.

## Required execution flow

### 1. Fetch fresh PR state

**Never rely on cached state.** Always re-fetch live before any action:

```bash
PR_NUMBER=<number>
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
OWNER=${REPO%/*}
REPO_NAME=${REPO#*/}

gh pr view $PR_NUMBER --json title,state,headRefName,baseRefName,body,mergeable
gh pr checks $PR_NUMBER

# Fetch unresolved review threads via GraphQL
gh api graphql -f query='
  query($owner: String!, $repo: String!, $number: Int!) {
    repository(owner: $owner, name: $repo) {
      pullRequest(number: $number) {
        reviewThreads(first: 50) {
          nodes {
            id
            isResolved
            comments(first: 1) {
              nodes { body author { login } }
            }
          }
        }
      }
    }
  }
' -F owner="$OWNER" -F repo="$REPO_NAME" -F number=$PR_NUMBER
```

### 2. Address each unresolved review thread

For EACH unresolved thread, follow this decision tree exactly:

| Assessment | Reply shape | Code action |
|---|---|---|
| Agree | "Fixed: \<what changed and why it's better\>" | Apply the change |
| Partially agree | "Partially addressed: \<what changed\> but \<what kept and why\>" | Apply partial change |
| Disagree | "Keeping as-is: \<reasoning based on code/architecture\>" | No code change |

After replying, resolve the thread:
```bash
gh api graphql -f query='
  mutation($threadId: ID!) {
    resolveReviewThread(input: {threadId: $threadId}) {
      thread { isResolved }
    }
  }
' -F threadId="<THREAD_ID>"
```

Commit all fixes in one batch after addressing all threads:
```bash
git add <specific-files-changed>
git commit -m "fix: address PR review comments

Co-Authored-By: Claude <noreply@anthropic.com>"
git push
```

### 3. Validate CI — poll until green

Do not use `--watch` (times out on slow CI). Run a polling loop instead:

```bash
MAX_LOOPS=30
loop=0
while [ $loop -lt $MAX_LOOPS ]; do
  loop=$((loop + 1))
  echo "=== CI poll $loop/$MAX_LOOPS ==="

  gh pr checks $PR_NUMBER --json name,state,conclusion 2>/dev/null \
    | jq -r '.[] | "\(.conclusion // .state)\t\(.name)"' | sort

  FAILED=$(gh pr checks $PR_NUMBER --json conclusion \
    --jq '[.[] | select(.conclusion == "failure" or .conclusion == "timed_out")] | length' 2>/dev/null || echo 0)
  PENDING=$(gh pr checks $PR_NUMBER --json state \
    --jq '[.[] | select(.state == "pending" or .state == "queued" or .state == "in_progress")] | length' 2>/dev/null || echo 0)

  if [ "$PENDING" -eq 0 ] && [ "$FAILED" -eq 0 ]; then
    echo "All checks passed."
    break
  fi

  if [ "$PENDING" -gt 0 ]; then
    echo "$PENDING check(s) still running — waiting 60s..."
    sleep 60
    continue
  fi

  # One or more checks failed — diagnose before deciding
  echo "$FAILED check(s) failed — diagnosing..."
  break
done
```

**On failure — diagnose, act, then re-enter the loop:**

1. Identify failing checks and their log URLs:
   ```bash
   gh pr checks $PR_NUMBER --json name,conclusion,detailsUrl \
     --jq '.[] | select(.conclusion == "failure") | "\(.name): \(.detailsUrl)"'
   ```

2. Read the failure log (extract `<run-id>` from the `detailsUrl`):
   ```bash
   gh run view <run-id> --log-failed
   ```

3. Classify and act:
   - **Transient / flaky failure** → retry, then re-enter the poll loop:
     ```bash
     gh run rerun <run-id> --failed
     ```
   - **Real code failure** → fix, commit, push, then re-enter the poll loop:
     ```bash
     git add <files>
     git commit -m "fix: <what broke and why>

     Co-Authored-By: Claude <noreply@anthropic.com>"
     git push
     ```
   - **Same check fails twice after retry** → stop. Show the user the log excerpt and ask how to proceed.

**Escalate to the user immediately when:**
- 30 poll iterations reached (≈30 min wall clock)
- PR is closed or merged externally during polling
- The same check fails on two consecutive `--failed` retries

### 4. Validate merge readiness

Confirm ALL of the following — re-fetch to get fresh state:

- [ ] All required CI checks are green (`conclusion == "success"`)
- [ ] No unresolved review threads (re-run the GraphQL query from step 1)
- [ ] PR is up to date with the base branch (`mergeable == "MERGEABLE"`)

Print: **"PR is ready for your approval. Reply `approved` to merge."**

### 5. STOP — wait for explicit user approval

**Do NOT proceed until the user writes "approved" in this conversation.** This is a hard gate.

### 6. Merge and clean up

Squash-merge and delete the branch atomically:
```bash
gh pr merge $PR_NUMBER --squash --delete-branch
```

Close any issues linked in the PR body (`Closes #N` / `Fixes #N`):
```bash
# Extract and close linked issues
gh pr view $PR_NUMBER --json body --jq '.body' \
  | grep -oE '(Closes|Fixes) #[0-9]+' \
  | grep -oE '[0-9]+' \
  | xargs -I{} gh issue close {} --comment "Shipped in PR #$PR_NUMBER"
```

Pull the updated default branch and prune the local worktree:
```bash
DEFAULT_BRANCH=$(gh repo view --json defaultBranchRef --jq .defaultBranchRef.name)
REPO_ROOT=$(git rev-parse --show-toplevel)
git -C "$REPO_ROOT" fetch origin
git -C "$REPO_ROOT" merge --ff-only origin/$DEFAULT_BRANCH 2>/dev/null || true
# Remove worktree if currently inside one
git worktree remove "$(pwd)" --force 2>/dev/null || true
git -C "$REPO_ROOT" worktree prune
```

### 7. Report

```
Done.
- PR #<number> merged (<title>)
- Branch <name> deleted (local + remote)
- Issue(s) closed: <list or "none">
- <default-branch> updated to <sha>
```

## Hard rules

- **Never use `--admin` to force-merge** unless the user explicitly authorizes it — bypasses required status checks.
- **Never skip CI.** Failing checks must be fixed or explicitly waived by the user before merging.
- **Never merge without the user typing "approved".** The stop in step 5 is unconditional.
- **Never use `git add -A` or `git add .`** — stage specific files to avoid accidentally committing secrets or unintended files.
- **Never resolve a thread without a reply.** Every resolved thread must have a typed response explaining the decision.
- **Never rely on cached PR state.** Always re-fetch before each decision point.

## What NOT to do

- **Do not squash-merge without checking for linked issues** — they stay open forever if you skip step 6's issue-close loop.
- **Do not assume CI passes just because it passed on a previous push** — new commits reset check status; re-poll after every push.
- **Do not resolve threads silently** — replying "Done" with no explanation breaks the reviewer's ability to verify the fix.
- **Do not fast-forward or rebase-merge by default** — squash keeps the default branch history clean; only deviate if the user asks.
- **Do not leave the worktree dangling** — always prune after merge, or the user will have leftover directories and `git worktree list` noise.

## Quick-reference: CI failure decision table

| Symptom | Action |
|---|---|
| `conclusion == "timed_out"` | `gh run rerun <id> --failed`, then re-poll |
| `conclusion == "failure"`, first time | Read log, fix code or retry if flaky |
| `conclusion == "failure"`, second time same check | Stop, report to user with log excerpt |
| `state == "pending"` or `"queued"` | Wait 60s, re-poll |
| All `conclusion == "success"` | Proceed to step 4 |
| PR closed/merged externally | Stop, report to user |
