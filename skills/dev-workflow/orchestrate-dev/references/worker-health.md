# Worker health: commit per task, periodic check

Uncommitted work is lost work: a worker that dies, hits a limit or is restarted leaves nothing to resume from.

- Workers **commit as each task passes its targeted tests** (worker-dev Step 5), not at the end.
- The orchestrator runs `scripts/agent-health.sh` periodically (every few minutes while workers run) once per check; it lists every worktree of the repo, so read the row whose path matches each worker:

  ```bash
  bash scripts/agent-health.sh --repo <repo-root> --idle-min 20 --pile 10 --json
  ```

  Flags: `--idle-min N` (minutes without a write), `--pile N` (uncommitted-file threshold), `--json`, `--repo PATH`. Verdicts: `ok`, `uncommitted-pile`, `idle`, `no-commits`.

- Act on the verdict: **nudge** (SendMessage) any worker with `uncommitted-pile` ("commit what passes now"), or with `idle`/no write for ~20 min ("status? blocked?"). `no-commits` after a task should have finished means ask, then re-dispatch if the worker is gone. Do not fabricate a handoff for a silent worker.

## The lines every worker brief carries

Stalls are prevented in the brief, not only detected afterwards. Every dispatch includes, verbatim:

- **Never end a turn waiting on a notification.** Watch a long run's log with a bounded `until` loop
  (a deadline, 20-second checks), then act on its last line.
- **Commit each piece as it passes** its targeted check; do not hold finished work for the next piece.
- **Iterate on a small corpus** (one suite file, a reduced fuzz corpus); the full suite runs once, at
  integration or in CI.
- **One heavy suite at a time on the machine.** Suites that spawn thousands of hook processes take a
  machine-wide lock (`tests/lib/heavy-lock.sh` here); never start one beside another worker's.

Why: on 2026-11-05/06 about a dozen worker turns ended "waiting for the notification" (10–60 minutes
each until nudged), one worker re-ran a 12-minute suite six times, and parallel heavy suites starved the
fail-closed safety hooks until every shell command was blocked.

