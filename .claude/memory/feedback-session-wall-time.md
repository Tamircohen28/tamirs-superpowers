---
name: feedback-session-wall-time
description: "User called multi-hour sessions unreasonable (2026-11-06; retro approved). The rules that bound wall time: read the directory after a release, cap review at 2 rounds, iterate on small corpora, one heavy suite at a time, ask for authority up front, overlap review, simulate merges"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 24913b40-9931-473f-97b4-0cc26fdc1a9e
  modified: 2026-11-06T05:28:06.444Z
---

On 2026-11-06 the user said "Why every session takes hours? This is unreasonable" and ran /retro
on a session that took ~12 h where ~4 h was reachable (four PRs + CI rebuild + seven-hook rewrite
+ directory edition + four releases). Under an hour is realistic per piece, not for that scope.

**Why it took hours (measured):** an un-checked release (5.5.1 was refused by the directory within
the hour; ~3 h then went into a hook rewrite for a hold it had already dropped); 5–6 Codex rounds
on three PRs at ~30 min CI each; agents ending turns waiting on notifications (~12 stalls);
heavy suites run concurrently (a 2-min suite took 18, the 5-s fail-closed hooks blocked the
shell ~20 min, twice); one worker re-running the 12-min fuzz suite ~6 times (~3 h); review and
integration held behind the last worker; parallel PRs colliding after merge (3 rebases, 2 extra
CI rounds, because a new gold fixture landed beside rules that apply to every fixture).

**How to apply:**
- After every release that moves the `claude` tag, read the directory portal's version status
  (~10 min later) before planning any more directory work. See [[project-directory-verified-org-refusal]].
- Two review rounds per PR from the first push; then merge with a tracked issue for anything
  non-blocking. Count rounds, do not judge them.
- Workers iterate on a small corpus (`FUZZ_MUTATING=300`, one suite file) and run the full
  suite once, at integration or in CI.
- One heavy suite at a time on the machine: `tests/lib/heavy-lock.sh` enforces it for the fuzz
  and guard suites; workers run narrow checks only; CI is the full gate.
- Every worker brief: watch long runs with a bounded until-loop, commit each piece as it passes,
  never end a turn waiting on a notification.
- At the start of a multi-PR batch, ask once for standing merge and release authority.
- Start review, integration and a draft PR as soon as the first tasks commit.
- Before opening each PR and after each merge, simulate the merge locally (`git merge-tree`,
  then `make test-repo-contract`); merge PRs that add rules before PRs that add fixtures.
- Small coupled work: do it directly, not as an objective. Related: [[feedback-orchestration-speed]].
