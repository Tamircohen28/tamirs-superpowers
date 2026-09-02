---
name: project-statusline-tmpdir-ci-flake
description: "tests/test-statusline.sh has an unexplained CI failure where its mktemp dir vanishes mid-run — four occurrences, five hypotheses killed, root cause still unknown"
metadata:
  node_type: memory
  type: project
---

**Open, unexplained.** Four CI jobs on `tamirs-superpowers`, all on 2026-09-02, failed with
`tests/test-statusline.sh`'s `$TMPROOT` (`/tmp/tmp.XXXXXXXXXX`) disappearing mid-run:

- run 33595749097 job 100138728086 on `aeb42caf` — **on `master`**, not a PR branch
- run 33597009636 attempt 1, jobs 100142384911 and 100142384940, on `9a7c916` — these are
  `Hook behavior tests` and `make validate`, i.e. **two separate runner VMs** in one run
- run 33599695141 job 100150431971, on a branch whose entire diff was `.claude/memory/*.md`

All on ubuntu-24.04 image `20260823.283.1`, runner 2.337.0. Attempt 2 of the same commit, unchanged,
went green, and greens and reds interleave inside one hour (05:36 green, 05:42 red, 05:49 green,
06:00 red, 06:30 green, 06:35 green, 06:37 red) — so it is neither deterministic nor a clean
fleet transient.

**Ruled out, with evidence — do not re-propose these:**

| Hypothesis | Why it is dead |
|---|---|
| The backgrounded watcher subshell inherits the suite's `trap … EXIT` and deletes the dir | Six trap/subshell variants on bash 3.2.57 and 5.3.15; the dir survived every one. Bash does **not** run an inherited EXIT trap in a subshell. |
| Introduced by the new test files (`test-session-init-staleness.sh`) | `aeb42caf` predates them. |
| Runner/image regression | Identical runner and image on the green runs. |
| `cleanup_stale_worktrees` orphan leak (`hooks/lib/worktree-common.sh`) | Its `rm: … Directory not empty` line appears on green runs too — a constant, not a trigger. |
| Something in-repo | Audited: every destructive path is anchored to `$WORKTREE_ROOT`, recomputed as `"${HOME}/.claude/worktrees"` (`hooks/lib/worktree-common.sh:4`); the retirement `find` needs depth 2 **plus** a `.git` entry; the only `find -delete` is `-type f`. An instrumented run of the real Makefile loop (`rm`/`rmdir`/`mktemp` shimmed) logged 982 roots created, 0 name reuses, **0 cross-suite touches**. |
| **"The dir sits empty and unreferenced for ~2s, so something reaps it"** | **This was the v3.6.0 fix and it is falsified.** Occurrence 4 vanished a `$TMPROOT` that had the `.keep` file in it, on a memory-only diff. |

**Current state (PR #115).** Two mechanism claims have now been written into this file as fact and
both were wrong — the inherited EXIT trap, then the empty-directory reaping. **Do not write a third
without a repro.** What is in the suite now discriminates rather than explains:

- a `SENTINEL` tmpdir, created and never touched — dies too → external sweeper, repo exonerated;
  survives → something targets this suite, and the `$TMPDIR` snapshot diff names every other casualty
- a truncated `ps` listing for detached `rm -rf` workers earlier suites deliberately `disown`
- a probe immediately after the 2s watchdog kill, halving the unknown window
- **recovery, not abort** — it recreates the dir and continues, warning loudly and again in the
  summary line — hard-failing would red-gate unrelated PRs to buy evidence the WARN block already
  captures.

Fixed alongside it: `tests/lib/harness.sh` cleaned up nothing (`harness_tmpdir` appended to an array
inside a `$( )` subshell, so the EXIT trap iterated an empty array) — that is what left ~140 stray
`tmp.*` dirs per CI run. Not the cause of the flake, but it was the noise on top of it.

**How to apply:** if it recurs, read the WARN block first — sentinel state and the casualty diff are
the whole point. Harvest that job's logs **before** re-running anything; see
[[feedback-verify-mechanism-claims]] on why a green re-run destroys evidence rather than producing
any. Unclaimed follow-up: a `SUPERPOWERS_WORKTREE_CLEANUP=0` guard so hook-invoking tests stop
leaving detached processes.
