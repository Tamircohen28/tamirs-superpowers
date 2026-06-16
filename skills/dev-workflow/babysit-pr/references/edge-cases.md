# Edge Cases — babysit-pr

Reference for uncommon but important PR lifecycle situations.

---

## PR Already Merged or Closed

**Detection:**
```bash
gh pr view "$PR" --json state --jq .state
# Returns: MERGED, CLOSED, or OPEN
```

**Behavior:**
- `MERGED` → report the merge SHA, the merge time, and who merged it; then STOP — there is nothing to babysit.
- `CLOSED` (without merge) → report that the PR was closed without merging; ask the user if they want to re-open or open a new one; then STOP.

Never enter the monitoring loop for a non-OPEN PR.

---

## Flaky CI Retry Exhaustion (≥ 3 retries)

After 3 failed retries of `gh run rerun --failed`, the failure is no longer considered transient:

1. Print the name of the check that keeps failing and a summary of its last log output.
2. State: "This check has failed 3 times on identical infra errors. Manual investigation is needed."
3. Suggest the user file a GitHub Actions support ticket or check their runner quota.
4. **STOP** — do not retry a 4th time.

Never modify CI YAML, test fixtures, or dependency pins to suppress a runner-provisioning failure.

---

## Multi-Reviewer Scenarios

When multiple reviewers have left comments or requested changes:

**Watch mode:**
- Surface *all* unresolved threads grouped by reviewer:
  ```
  Reviewer A (2 threads): [summary]
  Reviewer B (1 thread): [summary]
  ```
- Do not reply to any thread without user approval — even if another reviewer's thread on the same line was already addressed.

**Drive mode:**
- Address threads from *all* reviewers, not just the first one.
- After fixing, push once (batch all fixes into one commit per reviewer pass, not one per thread).
- Use `fetch-pr-state.sh` after each push to confirm all threads are now resolved — a reviewer can add new threads while you're fixing others.

**Conflicting reviewer opinions:**
- If reviewer A says "use X" and reviewer B says "use Y" on the same code, **do not silently pick one**.
- Surface the conflict to the user: "Reviewers A and B disagree on [file:line]. A wants X; B wants Y. How should I proceed?"

---

## PR is Behind Base Branch (Not Conflicting)

`mergeStateStatus=BEHIND` but `mergeable=MERGEABLE` means the PR branch is outdated but has no actual conflicts.

**Action (Drive mode):**
```bash
gh pr update-branch "$PR" --repo "$REPO"
# Or equivalently:
git fetch origin
git checkout "$BRANCH"
git rebase origin/"$BASE_BRANCH"
git push origin HEAD --force-with-lease
```

Prefer `gh pr update-branch` when available — it triggers GitHub's merge-queue-compatible rebase without a local checkout. Fall back to local rebase if `gh pr update-branch` is not available (older gh versions).

After updating, restart the monitoring loop — a new CI run will be triggered.

---

## Reviewer Approves Mid-Watch (Watch Mode)

If a reviewer approves (`reviewDecision=APPROVED`) while in Watch mode:

- Surface to the user: "Reviewer X approved the PR. CI is [status]. Reply `ship it` or `approved` if you'd like me to merge."
- **Do NOT auto-merge in Watch mode** — explicit user intent is required.
- Transition to Drive merge flow only after the user confirms.

---

## Ghost CI Checks (Never Leave Pending)

Occasionally GitHub shows checks in `pending` indefinitely (cancelled jobs, stale workflow runs).

**Detection:** If a check has been `pending` for > 30 minutes without any log activity:
```bash
gh api "repos/$REPO/actions/runs/$RUN_ID" --jq '{status, created_at, updated_at}'
```

If `updated_at` is > 30 minutes old and `status=in_progress`, the run may be stuck.

**Action:**
- Cancel and re-trigger:
  ```bash
  gh run cancel "$RUN_ID" --repo "$REPO"
  gh run rerun "$RUN_ID" --repo "$REPO"
  ```
- If re-trigger also stalls, surface to user: "Check [name] appears stuck (no activity for 30 min). You may need to re-push or manually re-run via GitHub UI."
