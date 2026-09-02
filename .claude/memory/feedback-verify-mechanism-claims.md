---
name: feedback-verify-mechanism-claims
description: "A hypothesis that explains all the evidence is still a hypothesis — state mechanism and state claims as unverified until executed, not just success claims"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 0ecd4a1e-ed87-4ea9-a55d-5727b73b1a29
  modified: 2026-09-01T22:00:28.585Z
---

Three times in one session (2026-09-01) I asserted a **verifiable fact** as settled without
running the cheap verification that was sitting right there:

| Claim, stated as fact | How it died |
|---|---|
| "The watcher subshell inherits the EXIT trap; its `exit 0` deletes `$TMPROOT`" | My own 6-variant repro on bash 3.2.57 and 5.3.15 — the temp dir survived every time. Bash does not run an inherited EXIT trap in a subshell. |
| "The schema leaves rule `parameters` unconstrained, so adding a key is safe" | `check-github-policy.sh` rejected the edit with the exact JSON pointer. I had matched a `"parameters": {"type":"object"}` belonging to a different `$def`. |
| "Gate green" | The log's own line read `EXIT=2` with 17 failing assertions. I pushed on a failed gate and reported it as passing. |

**Why:** the existing rule — *"Never claim success without evidence"* — governs claims of
**success**. These were claims of **mechanism** ("the bug is X because bash does Y") and of
**state** ("the schema allows Z", "the gate passed"). The rule did not name those, so they
slipped through in the register of fact.

The first one is the instructive one. It explained the *entire* failure shape: three watchdog
self-tests pass, then every case touching the temp dir dies, and the self-test is the one thing
that forces the watcher's `exit 0` path. Accounting for all the evidence felt like confirmation.
It was not.

**And the replacement explanation was wrong too.** I then recorded "one-off runner flake, proven
by re-running the same commit unchanged and watching it go green". A green re-run proves the
failure is *intermittent* — it proves nothing about frequency or cause, and "proven" was the
wrong word for it. It later turned out to be three occurrences across two commits, one of them on
`master` itself, and the root cause is still unknown. Note the shape: the second-order claim was
made in the very act of correcting the first-order one, which is exactly when the guard is down.

**A green re-run is not evidence, it is the destruction of evidence** — it overwrites the failed
job's logs. Do not re-run a flaky CI job "to check" before collecting what the failed run holds.

**How to apply:** before writing a causal or state claim as fact, ask *what would run in under a
minute to settle this* — a minimal repro, the repo's own checker, one API read, a re-run. If such
a check exists, run it. If it does not, write the claim as a hypothesis and label it: "likely",
"consistent with", "untested". Never let a hypothesis enter a report, a commit message or a PR
body in the voice of a finding.

Corollary that worked the same session: before recording a GitHub ruleset default as canonical, I
read the field across 12 repositories first. That is the shape to copy.

Related: [[feedback-background-task-exit-codes]] for the specific trap behind the third row, and
[[feedback-fetch-before-audit]] for a state claim that came from stale local data.
