---
name: feedback-orchestration-speed
description: "Long multi-objective runs — overlap objectives early, cap review rounds, and work around GitHub outages instead of waiting"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 4d09d4e0-b2ec-46c3-8c1c-8cf1d67342b8
  modified: 2026-11-04T11:53:39.593Z
---

A 2026-11-03/04 session (ADR 004 permission levels → 3 PRs, 5.2.0 + 5.3.0) ran 13+ hours; the user was rightly frustrated. Most of the time was avoidable.

**Why:** objectives were run strictly one after another (each waited for the previous PR to reach master), every PR paid ~18 min local `make validate` + ~18 min CI, and Codex review rounds on the (since removed) permission guard's parser kept finding one new parsing edge per round (6 rounds), each costing a full CI cycle.

**How to apply:**
- Start dependent objectives *early* from the predecessor's integration head (early-start pattern) and rebase onto master after its squash merge; when the predecessor's tree equals master's, the rebased tree is identical and needs no re-validation.
- Combine small, disjoint follow-up objectives into one PR to save a CI + review cycle.
- For a security reviewer finding parser edges round after round: fix the *class*, cap at ~2 rounds, then merge and file a tracked hardening issue (done as #349).
- When a guard keeps losing to new parsing edges, replace the regexes with a table-driven model early: the regex patches on #348/#350 were all thrown away when the parsers landed in 5.3.1 (and the whole permission guard was removed in 6.0.0, ADR 006).
- During a GitHub outage (githubstatus PRs/Actions degraded): retry merges via `PUT /pulls/N/merge` with the full head SHA; if `pull_request` CI never triggers, `gh workflow run ci.yml --ref <branch>`. A `workflow_dispatch` run fails the manifest-alignment job by design (no `--manifests-only`); verify it locally in PR mode instead.
- Tests or reviewers that drive real hooks must point them at a temp HOME. `make test-hooks` now fingerprints the real `~/.config`/`~/.local/state` plugin dirs around every suite (`scripts/real-home-witness.sh`) and fails naming the leaking suite; a reviewer *agent* run outside make is not covered, so still check after one. Related: [[feedback-background-task-exit-codes]], [[feedback-probe-narrow-before-full-gate]].
- Never serialize review and integration behind the last worker (2026-11-05, user: "its all so slow"). As soon as the
  other tasks are committed: merge them onto the integration branch, push it as a **draft PR** so CI starts measuring,
  and start the reviewer on the committed code; fold the last worker in when it lands. Workers parking on a background
  task's completion notification is the other recurring stall — tell them up front to watch the log with a bounded
  until-loop and to commit each piece as it passes.
