---
name: pr-dev
description: "Use when the user wants to actively drive a PR to completion — address every review thread, fix CI failures, and reach the merge-ready state (then stop and wait for explicit approval). Triggers on phrases like 'finish this PR', 'address review comments', 'ship/land/close the PR', 'drive PR to merge', 'fix CI and merge', 'clean up this PR'."
when_to_use: "User says: finish this PR, address comments, ship/land/merge the PR, drive the PR, handle review feedback, fix CI and merge, squash-merge, clean up PR branch — or provides a PR number/URL and asks to drive it to done."
argument-hint: "[PR number, PR URL, or omit to infer from current branch]"
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
  - Monitor
  - Skill
metadata:
  capability: pr-drive
  tags:
    - pr
    - review
    - ci
    - merge
    - workflow
    - github
  updated-date: "2026-06-16"
---

# pr-dev

Actively drive a pull request from open → review addressed → CI green → merge-ready, then stop and wait for explicit user approval before merging.

## Why this skill exists

After a PR is opened, the work is staying on top of CI failures, reviewer feedback, and merge conflicts. A one-shot "check and report" approach leaves the PR stalled when a simple retry or two-line fix would have unblocked it — and stops too early when CI is still queued or review threads trickle in.

This skill runs a **persistent drive loop**: it re-fetches state before every decision, addresses review threads one by one, fixes branch-related CI failures, retries flakes, and keeps looping until the PR is unambiguously ready or it hits something it cannot safely resolve without you.

It stops at exactly two conditions:

- **Ready** — all CI green + 0 unresolved threads → asks for explicit `approved` before touching `gh pr merge`
- **Blocked** — something requires human judgment → surfaces the issue clearly and stops

## Inputs

Accept any of the following (resolve once at startup, then reuse throughout):

| Input | Resolution |
|-------|-----------|
| No argument | Infer from current branch: `gh pr view --json number -q .number` |
| PR number `42` | Use directly |
| PR URL | Extract number from URL |

If no PR can be resolved, ask and stop.

## Hard rules

- **Never rely on cached PR state** — re-fetch before each major decision.
- **Never stop because a single poll returns idle** — CI may still be queued.
- **Never push to any branch other than the PR head branch.**
- **Never prefix commits with `[skip ci]`** — required checks must run.
- **Never post a review reply without first stating the reply text in the conversation** — the user can see it and redirect before it's posted.
- **Never fix flaky/infra failures by changing tests or CI config** unless logs prove the failure is branch-related.
- **Never retry a flaky run more than 3 times** — escalate to user.
- **Never merge without the user explicitly typing `approved` in this conversation.**
- **Never use `gh pr merge --admin`** unless the user explicitly authorizes it in this conversation.
- **Always restart the loop immediately after pushing a fix** — a push is not a terminal outcome.
- **Stop only when:** ready (merge gate, wait for `approved`) OR blocked (surface to user, stop).

## Core workflow

### 1. Resolve the PR

```bash
PR=$(gh pr view --json number -q .number)   # or user-provided number/URL
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
HEAD=$(gh pr view "$PR" --repo "$REPO" --json headRefName -q .headRefName)
```

### 2. Drive loop

```
loop:
  state = fetch fresh PR state (gh pr view + gh pr checks)
  if PR merged/closed → report; STOP (terminal)

  # --- Review threads ---
  threads = fetch unresolved review threads
  for each unresolved thread:
    read the comment; assess: agree / partial / disagree
    state reply text in conversation (always — user can redirect before posting)
    post reply via gh api
    if agreed/partial: apply code fix; commit; push
    resolve thread via gh api
  if any thread required a push → restart loop immediately

  # --- CI ---
  checks = gh pr checks "$PR" --repo "$REPO"
  if any check failing:
    fetch logs → classify (table below)
    if branch-related → patch, commit, push; restart loop
    if flaky AND retries < 3 → gh run rerun --failed; increment retry; restart loop
    if flaky AND retries ≥ 3 → surface to user; STOP (blocked)
    if infra/unrelated → surface to user; STOP (blocked)
  if any check pending/queued:
    wait (cadence below); restart loop

  # --- Readiness gate ---
  if all checks green AND 0 unresolved threads AND PR mergeable:
    print readiness summary (see Output section)
    STOP — wait for user to type `approved`

  sleep(cadence); restart loop
```

### 3. Fetch fresh state

```bash
gh pr view "$PR" --repo "$REPO" \
  --json number,title,state,mergeable,mergeStateStatus,\
reviewDecision,statusCheckRollup,headRefOid,headRefName
```

Get unresolved threads:

```bash
gh api graphql -f query='
  query($owner:String!,$repo:String!,$pr:Int!) {
    repository(owner:$owner, name:$repo) {
      pullRequest(number:$pr) {
        reviewThreads(first:50) {
          nodes { id isResolved isOutdated comments(first:5) {
            nodes { body author { login } } } } } } } }' \
  -f owner=OWNER -f repo=REPO -F pr="$PR" \
  --jq '.data.repository.pullRequest.reviewThreads.nodes
        | map(select(.isResolved == false and .isOutdated == false))'
```

### 4. Address a review thread

For each unresolved thread:

1. **Read** the comment — understand what's asked
2. **Assess** in conversation: `agree`, `partially agree`, or `disagree`
3. **State the reply text** (always — user can redirect before posting):
   - **Agree**: "Fixed: \<what changed and why it's better\>"
   - **Partially agree**: "Partially addressed: \<changed\> but \<kept and why\>"
   - **Disagree**: "Keeping as-is: \<reasoning\>"
4. **Post the reply**:
   ```bash
   gh api "repos/$REPO/pulls/$PR/comments" \
     -X POST -f body="$REPLY_BODY" -f in_reply_to="$COMMENT_ID"
   ```
5. **Apply code fix** if agreed or partially agreed
6. **Resolve the thread**:
   ```bash
   gh api graphql -f query='
     mutation($id:ID!) { resolveReviewThread(input:{threadId:$id}) {
       thread { id isResolved } } }' \
     -f id="$THREAD_ID"
   ```

Commit and push all fixes after handling each thread. Never batch unrelated fixes in one commit.

### 5. Diagnose a CI failure

```bash
RUN_ID=$(gh run list --repo "$REPO" \
  --commit "$(gh pr view $PR --repo $REPO --json headRefOid -q .headRefOid)" \
  --json databaseId,conclusion \
  --jq '.[] | select(.conclusion=="failure") | .databaseId' | head -1)

gh run view "$RUN_ID" --repo "$REPO" --log-failed
```

### 6. Classify CI failures

| Signal in logs | Classification | Action |
|---------------|---------------|--------|
| Test/lint/compile error in a file the PR touches | Branch-related | Patch, commit, push; restart loop |
| `runner provisioning failed`, network timeout, registry error | Flaky/infra | `gh run rerun "$RUN_ID" --repo "$REPO" --failed` (max 3×) |
| Dependency outage, GitHub Actions infra error | Unrelated | Surface to user; STOP (blocked) |
| Ambiguous | Ambiguous | One manual diagnosis attempt; then decide |

### 7. Push a fix

```bash
git add -p                          # stage only relevant changes
git commit -m "fix: <what and why>

Co-Authored-By: Claude <noreply@anthropic.com>"
git push origin HEAD
```

Then **restart the loop immediately** — never stop after a push.

### 8. Wait for CI (long-running checks)

For checks expected to take 5+ minutes, avoid blocking the turn with a Monitor `until`-loop:

```bash
until gh pr checks "$PR" --repo "$REPO" \
  | grep -qvE 'pending|queued|in_progress'; do
  sleep 60
done
```

For shorter CI cycles, `gh pr checks "$PR" --watch` is sufficient.

### 9. Polling cadence

| State | Interval |
|-------|----------|
| CI pending / queued / running | 60 s |
| CI failing — fix just pushed | Immediate restart, no sleep |
| CI green, unresolved threads remain | 45 s |
| All green + 0 threads | Readiness gate — STOP |

### 10. Readiness gate

Confirm ALL before printing the readiness message:

- [ ] All CI checks green (no pending, no failing)
- [ ] 0 unresolved review threads
- [ ] `mergeStateStatus` is `CLEAN`
- [ ] PR is not behind the base branch

Print:

```
PR #N is ready to merge.
  ✓ N/N CI checks green
  ✓ 0 unresolved review threads
  ✓ Branch up to date with base

Reply `approved` to squash-merge and clean up.
```

**Do not merge until the user writes `approved` in this conversation.**

### 11. Merge and clean up (after `approved`)

```bash
gh pr merge "$PR" --squash --delete-branch
```

Close any issues linked in the PR body (`Closes #N`, `Fixes #N`):

```bash
gh issue close <number> --comment "Shipped in PR #$PR."
```

Switch off the PR branch locally if needed:

```bash
git checkout master && git pull
```

## Blocked state

When you cannot proceed without the user, stop with:

```
Blocked on PR #N — need your input:

Issue: <specific description>
Options:
  A) <option>
  B) <option>

Which do you prefer?
```

Do not silently stop, guess, or take a destructive action without confirmation.

## Anti-patterns

| Wrong | Right |
|-------|-------|
| Stop after one poll returns idle | Keep looping — CI may still be queued |
| Stop after pushing a fix | Restart loop immediately — a push is not done |
| Retry a flaky runner 10 times | Retry max 3×, then surface to user |
| Post a review reply without stating it first | State reply text in conversation; then post |
| Merge without explicit `approved` | Stop at readiness gate; wait |
| Patch CI config to silence a flaky test | Retry the flake; escalate if it persists |
| Batch unrelated fixes in one commit | One commit per logical fix |
| Fix merge conflicts on both branches | Rebase PR head onto base only; ask if unclear |

## Output format

- **Progress updates**: brief, only on state changes (not every poll)
- **On fix push**: `Pushed fix: <what> (SHA abc1234). Resuming loop.`
- **On retry**: `Retried flaky run (attempt N/3). Watching.`
- **On thread resolved**: `Thread "<snippet>": agreed / partial / disagree — replied and resolved.`
- **At readiness gate**: full readiness summary above; then stop
- **After merge**: one-line summary — SHA merged, checks passed, fixes pushed, retries used, issues closed
- Do not emit the post-merge summary while the loop is still running
