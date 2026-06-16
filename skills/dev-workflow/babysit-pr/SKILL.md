---
name: babysit-pr
description: "Use for active, ongoing pull request management — when the user wants Claude to monitor, fix, and drive an existing PR to merge rather than perform a single task. Invoke when the user asks to babysit, watch, or ship a PR; address reviewer comments or respond to a reviewer; fix CI failures on a PR; resolve merge conflicts; retry flaky checks; or merge after approval. The defining signal is that the user wants automated PR lifecycle management — not one-off actions like creating a PR, reviewing code for bugs, or explaining a CI error. Trigger phrases: 'babysit PR #N', 'watch my PR', 'ship the PR', 'drive to merge', 'my PR is stuck', 'fix CI on my PR', 'address reviewer feedback', 'retry flaky CI', 'PR has merge conflicts'."
disable-model-invocation: true
when_to_use: "User says: 'babysit this PR', 'babysit PR #N', 'watch PR #N', 'monitor my PR', 'monitor CI', 'keep an eye on my PR', 'finish this PR', 'address review comments', 'merge after review', 'drive the PR to merge', 'ship this PR', 'clean up the PR', 'CI is failing on my PR', 'respond to the reviewer', 'my PR has merge conflicts', 'fix the merge conflict on my PR', 'retry the flaky CI', 'my PR is stuck waiting for CI', 'unblock my PR', 'the reviewer approved, merge it'."
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
metadata:
  capability: pr-lifecycle
  tags:
    - pr
    - ci
    - monitoring
    - review
    - merge
    - github
    - workflow
  updated-date: "2026-06-16"
---

# babysit-pr

Drive a pull request from open → green CI → review addressed → merged, or watch it continuously until merged/closed or user help is required.

## Why this skill exists

After a PR is opened, the work is staying on top of CI failures, reviewer feedback, and merge conflicts — often across minutes or hours. Manually refreshing GitHub is tedious; walking away means missing review requests or letting a flaky failure sit unretried.

This skill runs a persistent loop using `gh` CLI (and helper scripts in this skill directory) so Claude can triage failures, push fixes, retry flakes, address review threads, and — when the user wants to ship — squash-merge and clean up without them watching every tab.

## Modes

Pick the mode from user intent at startup:

| Mode | User intent | Behavior |
|------|-------------|----------|
| **Watch** | babysit, watch, monitor, keep an eye on | Fix branch-related CI; surface human review comments for approval before replying; keep looping until merged/closed or blocked |
| **Drive** | finish, ship, merge, address review, drive PR | Actively reply to and resolve every review thread (canonical templates), fix CI, validate readiness, **stop for explicit `approved`**, then squash-merge and clean up |

Both modes share the same monitoring loop, CI classification, and fix-push-restart behavior. Drive mode adds structured review replies, the merge-approval gate, and post-merge cleanup.

## Inputs

Accept any of the following (resolve once at startup, then reuse throughout):

| Input | Resolution |
|-------|-----------|
| No argument | Infer from current branch: `gh pr view --json number -q .number` |
| PR number `42` | Use directly |
| PR URL | Extract number from URL |

If no PR is found, ask for the PR number and stop.

## Hard rules

- **Never rely on cached PR state** — re-fetch before each major decision (`fetch-pr-state.sh` or `gh pr view`).
- **Never stop merely because a single poll returns idle** — CI may still be queued.
- **Never push changes to any branch other than the PR head branch.**
- **Never prefix commits with `[skip ci]`** — required status checks must run; skipping forces admin bypass merges.
- **Never post a reply to a human review comment without explicit user approval** (Watch mode always; Drive mode only after user confirms reply text if they asked to babysit first).
- **Never fix flaky/infra failures by changing code or CI config** unless logs prove the failure is branch-related.
- **Never retry a flaky run more than 3 times** — then report to the user.
- **Never run multiple concurrent watch loops for the same PR.**
- **Always restart monitoring in the same turn after pushing a fix** — a push is not a terminal outcome.
- **Never use `gh pr merge --admin`** unless the user explicitly authorizes it in this conversation.
- **Stop only when:** PR is merged/closed, OR user intervention is required and you cannot safely proceed, OR (Drive mode) merge + cleanup completed.

## Core workflow

### 1. Resolve the PR

```bash
PR=$(gh pr view --json number -q .number)   # or user-provided number/URL
REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
```

### 2. Fetch fresh state

**Always** start with the helper script (structured PR JSON, checks summary, unresolved threads):

```bash
bash "$CLAUDE_SKILL_DIR/scripts/fetch-pr-state.sh" "$PR"
```

For quick snapshots inside the loop:

```bash
gh pr view "$PR" --repo "$REPO" \
  --json number,title,state,mergeable,mergeStateStatus,\
reviewDecision,statusCheckRollup,headRefOid,headRefName
```

### 3. Monitoring loop

```
loop:
  snapshot = fetch-pr-state.sh (or gh pr view + gh pr checks)
  if PR merged/closed → report terminal state; STOP

  for each new human review comment/thread:
    Watch mode  → if actionable: patch + push; surface reply to user for approval
                  if needs answer only → surface; STOP for confirmation
    Drive mode  → read thread; assess agree/partial/disagree
                  reply (templates/review-reply.md.tmpl); fix code; resolve thread
                  (see "Address review threads" below)

  for each failed CI run:
    fetch logs → classify (table below)
    if branch-related → patch, commit, push, restart loop
    if flaky (retries < 3) → gh run rerun --failed; restart loop
    if flaky (retries ≥ 3) → report; STOP
    if unrelated → report; STOP

  if Drive mode AND green + mergeable + 0 unresolved threads:
    → merge readiness gate (below); may STOP for approval

  if green + no open review issues:
    emit one-time "CI green, watching…" update; continue

  sleep(cadence); goto loop
```

### 4. Poll CI checks

Quick wait:

```bash
gh pr checks "$PR" --repo "$REPO" --watch
```

Long CI cycles (5+ min) or parallel work — use the Monitor `until`-loop in `references/ci-monitor-loop.md`.

Structured inspection:

```bash
gh api "repos/$REPO/commits/$(gh pr view $PR --repo $REPO --json headRefOid -q .headRefOid)/check-runs" \
  --jq '.check_runs[] | {name,status,conclusion,details_url}'
```

### 5. Diagnose a failed CI run

```bash
RUN_ID=$(gh run list --repo "$REPO" \
  --commit "$(gh pr view $PR --repo $REPO --json headRefOid -q .headRefOid)" \
  --json databaseId,conclusion --jq '.[] | select(.conclusion=="failure") | .databaseId' | head -1)

gh run view "$RUN_ID" --repo "$REPO" --log-failed
```

### 6. Classify CI failures

| Signal in logs | Classification | Action |
|---------------|---------------|--------|
| Test/lint/compile error in a file touched by the PR | Branch-related | Patch, commit, push |
| `runner provisioning failed`, network timeout, registry error | Flaky/infra | `gh run rerun "$RUN_ID" --repo "$REPO" --failed` (max 3×) |
| Dependency outage, GitHub Actions infra error | Unrelated | Wait or stop for user |
| Ambiguous | Ambiguous | One manual diagnosis, then decide |

**Never patch flaky/infra failures by changing tests, CI config, or dependency pins** unless logs clearly connect to the PR branch.

### 7. Push a branch fix

```bash
git add -p                        # stage only relevant changes
git commit -m "fix: address CI failure (PR #$PR)

Co-Authored-By: Claude <noreply@anthropic.com>"
git push origin HEAD
```

### 8. Address review threads (Drive mode)

For **each** unresolved thread:

1. **Read** the comment — understand what's being asked
2. **Assess** — `agree`, `partially agree`, or `disagree`
3. **Reply** using shapes in `templates/review-reply.md.tmpl`:
   - **Agree**: "Fixed: \<what changed and why it's better\>"
   - **Partially agree**: "Partially addressed: \<changed\> but \<kept and why\>"
   - **Disagree**: "Keeping as-is: \<reasoning based on code/architecture\>"
4. **Fix code** if you agreed or partially agreed
5. **Resolve the thread**:

```bash
bash "$CLAUDE_SKILL_DIR/scripts/resolve-thread.sh" "<THREAD_ID>"
```

Commit and push all fixes after addressing threads (no `[skip ci]`).

### 9. Check review comments (Watch mode)

```bash
gh api "repos/$REPO/pulls/$PR/reviews" \
  --jq '.[] | select(.state=="CHANGES_REQUESTED") | {user:.user.login,body}'

gh api "repos/$REPO/pulls/$PR/comments" \
  --jq '.[] | {user:.user.login,path,line,body}'
```

Patch actionable code; **surface suggested replies to the user** — do not post without confirmation.

### 10. Polling cadence

| State | Poll interval |
|-------|---------------|
| CI pending/failing | Every 60 seconds |
| CI green, PR open | Every 90 seconds |
| After any state change | Reset cadence immediately |
| PR merged or closed | Stop immediately |

### 11. Handle merge conflicts

When `mergeable=CONFLICTING` is detected in PR state:

1. **Identify conflicting files**:
```bash
gh pr view "$PR" --repo "$REPO" --json mergeable,mergeStateStatus
git fetch origin
git checkout "$BRANCH"
git merge origin/"$BASE_BRANCH" --no-commit --no-ff 2>&1 | grep "CONFLICT"
git merge --abort
```

2. **Rebase instead of merge** (preferred — keeps history clean):
```bash
git fetch origin
git rebase origin/"$BASE_BRANCH"
# resolve conflicts file by file
git add <resolved-file>
git rebase --continue
git push origin HEAD --force-with-lease
```

3. **Never force-push without `--force-with-lease`** — this guards against overwriting work pushed since your last fetch.

4. **If the conflict is in files you did NOT touch** in this PR: surface to user with a description of the conflicting files and stop — do not auto-resolve conflicts in code you haven't reviewed.

5. **After resolving and pushing**: restart the monitoring loop; the rebase triggers a new CI run.

### 12. Merge readiness (Drive mode only)

Confirm ALL of:

- [ ] All CI checks green
- [ ] No unresolved review threads (re-run `fetch-pr-state.sh`, expect 0 unresolved)
- [ ] No blocking status checks
- [ ] PR is up to date with base branch

Print: **"PR is ready for your approval. Reply `approved` to merge."**

**Do NOT merge until the user explicitly writes `approved` in this conversation.**

### 12. Merge and clean up (after `approved`)

```bash
gh pr merge "$PR" --squash --delete-branch
```

Close linked issues from the PR body (`Closes #N`):

```bash
gh issue close <number> --comment "Shipped in PR #$PR"
```

Clean up local environment:

```bash
bash "$CLAUDE_SKILL_DIR/scripts/cleanup-after-merge.sh" "$PR"
```

## Anti-patterns

| Wrong | Right |
|-------|-------|
| Stop after CI goes green because "it's probably fine" | Keep watching — review comments may arrive later |
| Retry a flaky runner failure 10 times | Retry max 3×, then report |
| Post "Fixed!" to a reviewer without user OK (Watch mode) | Patch code; surface reply for approval |
| Modify CI config to silence a flaky test | Retry the flake; escalate if it persists |
| End the turn after pushing a fix | Restart monitoring immediately in the same turn |
| Merge without explicit user `approved` (Drive mode) | Stop at readiness gate |
| Fix merge conflicts on both branches without asking | Only rebase/merge the PR head; ask if unclear |

## Output format

- **Progress updates**: brief, only on state changes (not every poll)
- **On first green**: `CI is all green (N/N checks). Watching for review comments.`
- **On fix push**: `Pushed fix for [issue] — resuming watch on new SHA.`
- **On merge (Drive)**: Final summary — SHA, checks passed, fixes pushed, retries used, issues closed, branches/worktree cleaned
- Do not emit the final summary while the loop is still running

## References

- `scripts/fetch-pr-state.sh` — fresh PR state + unresolved threads via GraphQL
- `scripts/resolve-thread.sh` — resolve a single review thread by ID
- `scripts/cleanup-after-merge.sh` — post-merge worktree + branch cleanup
- `templates/review-reply.md.tmpl` — canonical agree / partial / disagree reply shapes
- `references/ci-monitor-loop.md` — Monitor `until`-loop for long CI cycles with per-check notifications
- `references/edge-cases.md` — handling PR-already-merged, flaky retry exhaustion, multi-reviewer conflicts, and other edge cases
