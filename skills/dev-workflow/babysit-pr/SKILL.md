---
name: babysit-pr
description: "Use when the user asks Claude to monitor, watch, or babysit a GitHub pull request — phrases like 'babysit this PR', 'watch PR #N', 'monitor CI on my PR', 'keep an eye on this PR', 'wait for my PR to merge', 'handle review comments while I'm away'. Continuously polls review comments, CI check/workflow run state, and mergeability until the PR is merged/closed or user help is required. Diagnoses CI failures, retries likely-flaky failures (up to 3x), auto-fixes branch-related issues and pushes them, and surfaces new review comments promptly."
when_to_use: "User says: 'babysit this PR', 'watch PR #N', 'monitor CI', 'keep an eye on my PR', 'wait for merge', 'handle review comments for me'."
argument-hint: "[PR number, PR URL, or omit to infer from current branch]"
model: claude-sonnet-4-6
allowed-tools:
  - Bash
  - Read
  - Edit
  - Write
  - Monitor
metadata:
  capability: pr-monitoring
  tags:
    - pr
    - ci
    - monitoring
    - github
    - workflow
  updated-date: "2026-06-13"
---

# PR Babysitter

## Why this skill exists

After a PR is opened, the real work is staying on top of CI failures, reviewer feedback, and merge conflicts — often across minutes or hours. Manually refreshing GitHub tabs is tedious and error-prone; walking away means missing time-sensitive review requests or letting a flaky CI failure sit unretried. This skill runs a persistent monitor loop using native `gh` CLI commands so Claude can triage failures, push fixes, retry flakes, and surface review comments without the user watching.

A naive "check once and report" approach misses failures that arrive after the initial check, and leaves the PR stalled when a simple retry or two-line fix would have unblocked it.

## Inputs

Accept any of the following (resolve once at startup, then reuse throughout):

| Input | Resolution |
|-------|-----------|
| No argument | Infer from current branch: `gh pr view --json number -q .number` |
| PR number `42` | Use directly |
| PR URL | Extract number from URL |

## Core Workflow

### 1. Resolve the PR

```bash
# Infer from current branch
PR=$(gh pr view --json number -q .number)
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)

# Or from a number/URL provided by the user
PR=42
REPO=owner/repo
```

### 2. Snapshot current state

```bash
gh pr view "$PR" --repo "$REPO" \
  --json number,title,state,mergeable,mergeStateStatus,\
reviewDecision,statusCheckRollup,headRefOid,headRefName
```

### 3. Poll CI checks

```bash
# List all check runs for the head SHA
gh pr checks "$PR" --repo "$REPO" --watch

# Or get structured JSON for scripted inspection
gh api "repos/$REPO/commits/$(gh pr view $PR --repo $REPO --json headRefOid -q .headRefOid)/check-runs" \
  --jq '.check_runs[] | {name,status,conclusion,details_url}'
```

### 4. Diagnose a failed CI run

```bash
# Get the failed run ID
RUN_ID=$(gh run list --repo "$REPO" \
  --commit "$(gh pr view $PR --repo $REPO --json headRefOid -q .headRefOid)" \
  --json databaseId,conclusion --jq '.[] | select(.conclusion=="failure") | .databaseId' | head -1)

# Fetch failed-job logs
gh run view "$RUN_ID" --repo "$REPO" --log-failed

# Or per-job logs (faster, available before run finishes):
gh api "repos/$REPO/actions/runs/$RUN_ID/jobs" --jq \
  '.jobs[] | select(.conclusion=="failure") | {id,name,conclusion}'
JOB_ID=<id from above>
gh api "repos/$REPO/actions/jobs/$JOB_ID/logs" > /tmp/job-$JOB_ID.log
```

### 5. Classify the failure

| Signal in logs | Classification | Action |
|---------------|---------------|--------|
| Test/lint/compile error in a file touched by the PR | Branch-related | Patch, commit, push |
| `runner provisioning failed`, network timeout, registry error | Flaky/infra | Retry (max 3×) |
| Dependency outage, GitHub Actions infra error | Unrelated | Wait or stop for user |
| Ambiguous | Ambiguous | One manual diagnosis, then decide |

**Never patch flaky/infra failures by changing tests, CI config, or dependency pins** unless logs clearly connect to the PR branch.

### 6. Push a branch-related fix

```bash
# Make the fix, then:
git add -p                        # stage only relevant changes
git commit -m "fix: address CI failure (PR #$PR)"
git push origin HEAD
```

### 7. Retry a flaky failure

```bash
gh run rerun "$RUN_ID" --repo "$REPO" --failed
```

Track retries per run. Stop retrying after 3 attempts and ask the user.

### 8. Check review comments

```bash
# List unresolved review threads
gh api "repos/$REPO/pulls/$PR/reviews" \
  --jq '.[] | select(.state=="CHANGES_REQUESTED") | {user:.user.login,body}'

gh api "repos/$REPO/pulls/$PR/comments" \
  --jq '.[] | {user:.user.login,path,line,body,resolved:false}'
```

Address actionable human review comments by patching code and pushing. **Do not post automated replies to human review threads without explicit user confirmation.**

### 9. Resolve a review thread (after pushing the fix)

```bash
# Mark thread as resolved via GraphQL
gh api graphql -f query='
  mutation ResolveReviewThread($id: ID!) {
    resolveReviewThread(input: {threadId: $id}) {
      thread { isResolved }
    }
  }' -f id="<thread-node-id>"
```

### 10. Polling cadence

| State | Poll interval |
|-------|-------------|
| CI pending/failing | Every 60 seconds |
| CI green, PR open | Every 90 seconds (watch for new review comments) |
| After any state change | Reset cadence immediately |
| PR merged or closed | Stop immediately |

## Hard Rules

- **Never stop merely because a single poll returns idle** — CI may still be queued.
- **Never push changes to any branch other than the PR head branch.**
- **Never post a reply to a human review comment without explicit user approval.** Surface the comment and your suggested reply to the user, wait for confirmation.
- **Never fix flaky/infra failures by changing code or CI config** unless logs prove the failure is branch-related.
- **Never run multiple concurrent watch loops for the same PR** — keep one loop active at a time.
- **Always restart monitoring in the same turn after pushing a fix** — a push is not a terminal outcome.
- **Stop only when:** PR is merged/closed, OR user intervention is required and you cannot safely proceed.

## Anti-patterns

| Wrong | Right |
|-------|-------|
| Stop after CI goes green because "it's probably fine" | Keep watching — review comments may arrive later |
| Retry a flaky runner failure 10 times | Retry max 3×, then report to user |
| Post an automated reply to a reviewer saying "Fixed!" | Patch the code; surface to user for reply approval |
| Modify CI config to make a flaky test not run | Retry the flake; escalate if it persists |
| End the turn after pushing a fix | Restart monitoring immediately in the same turn |
| Fix merge conflicts on both branches without asking | Only rebase/merge the PR head; ask if unclear |

## Monitoring Loop (summary)

```
loop:
  snapshot = gh pr view + gh pr checks
  if PR merged/closed → report terminal state; STOP
  for each new review comment from humans:
    if actionable → patch, commit, push, resolve thread, restart loop
    if non-actionable/needs answer → surface to user; STOP for confirmation
  for each failed CI run:
    fetch logs → classify
    if branch-related → patch, commit, push, restart loop
    if flaky (retries < 3) → gh run rerun; restart loop
    if flaky (retries ≥ 3) → report; STOP
    if unrelated → report; STOP
  if green + mergeable + no review issues:
    emit one-time "CI green, ready to merge" update; continue watching
  sleep(cadence); goto loop
```

## Output Format

- **Progress updates**: brief, only on state changes (not every poll)
- **On first green**: `CI is all green (N/N checks). Watching for review comments.`
- **On fix push**: `Pushed fix for [issue] — resuming watch on new SHA.`
- **On merge**: Final summary including SHA, checks passed, fixes pushed, retries used, outstanding items

Do not emit the final summary while the loop is still running.
