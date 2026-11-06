# Driving a PR: polling, merge gate, review batching

Detail behind four pr-dev rules. Read when you drive a PR as a sub-agent or when the repo has no required checks.

## 1. Poll your own PR — never idle

An agent driving a PR owns its progress. A notification may never arrive (it can cross with a merge, or be dropped), so **actively poll CI and review threads** with a bounded loop (`until`/Monitor, see `ci-monitor-loop.md`) instead of ending the turn "waiting".

- Every wait has a **deadline**: `timeout_ms` on Monitor, or a `SECONDS`-based cutoff in a plain `until` loop. Default bound: 30 min for CI, 10 min for a review round.
- Poll threads in the same loop as checks: `bash "$SKILL_DIR/scripts/fetch-pr-state.sh" ... "$PR"`. A push-then-wait that watches only CI misses a review that lands meanwhile.
- When a wait exceeds its bound, **stop waiting and report to the orchestrator** (or the user): PR, head SHA, which check or thread is outstanding, minutes waited. Do not extend the bound silently and do not merge around it.

## 2. Merge gate when the repo requires no checks

A ruleset with no required status checks will not stop a red merge. In that repo the gate is yours. Merge only when ALL hold on the **final head SHA** (re-fetch; the head after your last push):

- every workflow run that exists for that head SHA is fully green (every job, none pending or cancelled-by-failure), and at least one run exists. Judge the runs the workflow's triggers actually produce for the PR head: a repo whose CI triggers only on `pull_request`, or whose `push` trigger is limited to the default branch, never produces a `push` run on a PR branch, so demanding one would make the gate unpassable;
- zero unresolved review threads;
- the merge itself is authorized: explicit user say-so, or the active pr-dev exception in the repo/user rules. This gate narrows when a merge is allowed; it never grants permission to merge.

```bash
SHA=$(gh pr view "$PR" --json headRefOid -q .headRefOid)
gh run list --commit "$SHA" --json event,status,conclusion,name \
  --jq '.[] | "\(.event) \(.name) \(.status)/\(.conclusion)"'
```

No runs at all for the head counts as not green, not as skipped. A run that should exist but has not appeared yet (just pushed) means wait, not merge. A trigger that does not fire for a PR branch is not a missing run.

## 3. Pre-merge conditions are blocking review threads

If an orchestrator (or any owner) needs something true before merge, it **posts the condition as a review thread on the PR**, not as a chat message. The ruleset blocks merge until the thread is resolved, so the condition cannot cross with the merge. Driving agents treat such a thread like any other: satisfy it, reply, resolve. Only the poster (or the user) says "waive it".

## 4. Batch review threads

Triage **all open threads at once** per round: list them, group by owning sub-agent (or task), send **one message per owner** with every thread for that owner, collect the fixes, then make **one push per round**. One push per thread restarts CI each time and cancels in-flight runs.

## 5. Cap automated review at two rounds

A **review round** is one pass of an automated reviewer (for example the Codex connector) over a
pushed head: the PR opening, marking it ready, or an `@codex review` comment. Count rounds from the
first push and print the count with every readiness summary (`review round 2 of 2`).

- Rounds 1 and 2: fix every real finding, push once per round, request the next round.
- After round 2: fix what blocks (a P1, a broken build, a wrong verdict), merge on green CI, and file
  every remaining non-blocking finding as one tracked issue that names the PR. Do not request round 3.

Why: on 2026-11-05/06 three PRs ran 5–6 rounds each at ~30 minutes of CI per round; the two-round
advice existed and was applied only at round five. Each round past two found narrower cases of the same
class, and every one of them fit in a follow-up issue.

