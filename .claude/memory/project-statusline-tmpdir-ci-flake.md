---
name: project-statusline-tmpdir-ci-flake
description: "tests/test-statusline.sh has an unexplained CI failure where its mktemp dir vanishes mid-run — mitigated in v3.6.0, root cause never found"
metadata:
  node_type: memory
  type: project
---

**Open, unexplained.** Three CI jobs on `tamirs-superpowers` failed with `tests/test-statusline.sh`'s
`$TMPROOT` (`/tmp/tmp.XXXXXXXXXX`) disappearing mid-run:

- run 33595749097 job 100138728086 on `aeb42caf` — **on `master`**, not a PR branch
- run 33597009636 attempt 1, jobs 100142384911 and 100142384940, on `9a7c916`

All on ubuntu-24.04 image `20260823.283.1`, runner 2.337.0. Attempt 2 of the same commit, unchanged,
went green.

**Ruled out, with evidence — do not re-propose these:**

| Hypothesis | Why it is dead |
|---|---|
| The backgrounded watcher subshell inherits the suite's `trap … EXIT` and deletes the dir | Six trap/subshell variants on bash 3.2.57 and 5.3.15; the dir survived every one. Bash does **not** run an inherited EXIT trap in a subshell. |
| Introduced by the new test files (`test-session-init-staleness.sh`) | `aeb42caf` predates them. |
| Runner/image regression | Identical runner and image on the green runs. |
| `cleanup_stale_worktrees` orphan leak (`hooks/lib/worktree-common.sh`) | Its `rm: … Directory not empty` line appears on green runs too — a constant, not a trigger. |
| Something in-repo | No code here can delete a bare `/tmp/tmp.*`; every destructive target is under `$HOME/.claude/…` or the script's own mktemp output. `scripts/statusline.sh` has no `rm`/`mktemp`/`find`/`trap`. |

**What was done (v3.6.0, PR #108):** not a fix — a mitigation. The suite's ~2s watchdog self-test was
the only place in `tests/` leaving a tmpdir *empty and unreferenced*; the other eight tmpdir-using
suites write a child within milliseconds. So `: > "$TMPROOT/.keep"` removes that distinguishing
property, and a `[ -d "$TMPROOT" ]` check before first use turns a recurrence into one named failure
with `ls -ld /tmp` attached instead of five bogus "timed out" cases.

**How to apply:** if it recurs, the log now names it directly. Harvest that job's logs **before**
re-running anything — see [[feedback-verify-mechanism-claims]] on why a green re-run destroys the
evidence rather than producing any. An unclaimed follow-up exists: a `SUPERPOWERS_WORKTREE_CLEANUP=0`
guard so hook-invoking tests stop leaving detached processes.
