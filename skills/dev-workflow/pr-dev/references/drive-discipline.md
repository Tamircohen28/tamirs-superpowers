# Driving a PR: polling, merge gate, review batching

Detail behind four pr-dev rules. Read when you drive a PR as a sub-agent or when the repo has no required checks.

## 1. Poll your own PR — never idle

An agent driving a PR owns its progress. A notification may never arrive (it can cross with a merge, or be dropped), so **actively poll CI and review threads** with a bounded loop (`until`/Monitor, see `ci-monitor-loop.md`) instead of ending the turn "waiting".

- Every wait has a **deadline**: `timeout_ms` on Monitor, or a `SECONDS`-based cutoff in a plain `until` loop. Default bound: 30 min for CI, 10 min for a review round.
- Poll threads in the same loop as checks: `bash "$SKILL_DIR/scripts/fetch-pr-state.sh" ... "$PR"`. A push-then-wait that watches only CI misses a review that lands meanwhile.
- When a wait exceeds its bound, **stop waiting and report to the orchestrator** (or the user): PR, head SHA, which check or thread is outstanding, minutes waited. Do not extend the bound silently and do not merge around it.

## 2. Merge gate when the repo requires no checks

A ruleset with no required status checks will not stop a red merge. In that repo the gate is yours. Merge only when ALL hold on the **final head SHA** (re-fetch; the head after your last push):

- the `push` run **and** the `pull_request` run are each fully green (every job, none pending or cancelled-by-failure);
- zero unresolved review threads;
- the merge itself is authorized: explicit user say-so, or the active pr-dev exception in the repo/user rules. This gate narrows when a merge is allowed; it never grants permission to merge.

```bash
SHA=$(gh pr view "$PR" --json headRefOid -q .headRefOid)
gh run list --commit "$SHA" --json event,status,conclusion,name \
  --jq '.[] | select(.event=="push" or .event=="pull_request") | "\(.event) \(.name) \(.status)/\(.conclusion)"'
```

A missing `push` or `pull_request` run for the head counts as not green, not as skipped.

## 3. Pre-merge conditions are blocking review threads

If an orchestrator (or any owner) needs something true before merge, it **posts the condition as a review thread on the PR**, not as a chat message. The ruleset blocks merge until the thread is resolved, so the condition cannot cross with the merge. Driving agents treat such a thread like any other: satisfy it, reply, resolve. Only the poster (or the user) says "waive it".

## 4. Batch review threads

Triage **all open threads at once** per round: list them, group by owning sub-agent (or task), send **one message per owner** with every thread for that owner, collect the fixes, then make **one push per round**. One push per thread restarts CI each time and cancels in-flight runs.
