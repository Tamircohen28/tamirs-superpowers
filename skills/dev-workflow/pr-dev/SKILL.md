---
name: pr-dev
description: "Manage PR lifecycle — fetch fresh PR state, address every unresolved review thread, fix CI, get user approval, then squash-merge and clean up. Use when the user wants to drive a PR through review and merge."
when_to_use: "User asks to handle, finish, ship, merge, address review on, or close out a PR — invoked as /pr-dev or with phrases like 'finish this PR', 'address comments', 'merge after review', 'clean up the PR'."
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
  updated-date: "2026-06-07"
---

## Live context
!`gh pr view --json number,title,state,headRefName,reviewDecision,mergeable 2>/dev/null | jq -r '"PR #\(.number): \(.title) [\(.state)] branch:\(.headRefName) reviews:\(.reviewDecision) mergeable:\(.mergeable)"' 2>/dev/null || echo "no open PR on current branch — provide a PR number"`
!`git branch --show-current 2>/dev/null | sed 's/^/current branch: /' || true`

# pr-dev

Drive a pull request through review and merge: address every unresolved thread, fix CI, validate readiness, then (after explicit user approval) squash-merge and clean up.

## Input

Parse `$ARGUMENTS` as the PR number. If empty, detect from current branch:
```bash
gh pr view --json number --jq .number
```
If no PR found, ask for the PR number and stop.

## Required execution flow

### 1. Fetch fresh PR state

**Never rely on cached state.** Always re-fetch live:

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

For EACH unresolved review thread:

1. **Read** the comment carefully — understand what's being asked
2. **Assess** — decide: `agree`, `partially agree`, or `disagree`
3. **Reply** with the canonical shapes:
   - **Agree**: "Fixed: <what you changed and why it's better>"
   - **Partially agree**: "Partially addressed: <what you changed> but <what you kept and why>"
   - **Disagree**: "Keeping as-is: <reasoning based on code/architecture>"
4. **Fix code** if you agreed or partially agreed
5. **Resolve the thread**:
   ```bash
   gh api graphql -f query='
     mutation($threadId: ID!) {
       resolveReviewThread(input: {threadId: $threadId}) {
         thread { isResolved }
       }
     }
   ' -F threadId="<THREAD_ID>"
   ```

Commit and push all fixes after addressing all threads:
```bash
git add -A
git commit -m "fix: address PR review comments

Co-Authored-By: Claude <noreply@anthropic.com>"
git push
```

### 3. Validate CI

**Poll until all required checks pass** — do not rely on `--watch` (it times out on slow CI). Run a polling loop instead:

```bash
MAX_LOOPS=30
loop=0
while [ $loop -lt $MAX_LOOPS ]; do
  loop=$((loop + 1))
  echo "=== CI poll $loop/$MAX_LOOPS ==="

  # Snapshot current check states
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

  # Failures — diagnose before sleeping
  echo "$FAILED check(s) failed — diagnosing..."
  break
done
```

**On failure** — diagnose, fix, and re-enter the loop:

1. Get failing run IDs:
   ```bash
   gh pr checks $PR_NUMBER --json name,conclusion,detailsUrl \
     --jq '.[] | select(.conclusion == "failure") | "\(.name): \(.detailsUrl)"'
   ```

2. Read the failure log (extract `<run-id>` from the URL):
   ```bash
   gh run view <run-id> --log-failed
   ```

3. Classify and act:
   - **Flaky / transient failure** → retry first, then re-poll:
     ```bash
     gh run rerun <run-id> --failed
     ```
   - **Real code failure** → fix, commit, push, then re-poll:
     ```bash
     git add <files>
     git commit -m "fix: <what broke and why>

     Co-Authored-By: Claude <noreply@anthropic.com>"
     git push
     ```
   - **Same check fails twice after retry** → stop. Report the failure to the user with the log excerpt and ask how to proceed.

**Terminal conditions** — escalate to the user immediately if:
- 30 poll iterations reached (≈30 min wall clock)
- PR is closed or merged externally
- The same check fails twice after a `--failed` retry (not transient)

Repeat the polling loop until all required checks are green.

### 4. Validate merge readiness

Confirm ALL of:
- [ ] All required CI checks green
- [ ] No unresolved review threads (re-fetch to confirm)
- [ ] PR is up to date with base branch

Print: **"PR is ready for your approval. Reply `approved` to merge."**

### 5. STOP and wait for approval

**Do NOT proceed until the user explicitly writes "approved" in this conversation.**

### 6. Merge and clean up

Squash-merge and delete the branch:
```bash
gh pr merge $PR_NUMBER --squash --delete-branch
```

Close any linked issues (extract `Closes #N` / `Fixes #N` from PR body):
```bash
gh issue close <number> --comment "Shipped in PR #$PR_NUMBER"
```

Pull the updated default branch and remove the worktree:
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
- Issue(s) closed: <list or none>
- <default-branch> updated
```

## Hard rules

- **Never use `--admin` to force merge** unless the user explicitly authorizes it — it bypasses required status checks.
- **Never skip CI.** If checks are failing, fix them before merging.
- **Never merge without user approval.** The stop in step 5 is non-negotiable.
