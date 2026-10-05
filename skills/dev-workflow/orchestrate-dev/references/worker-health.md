# Worker health: commit per task, periodic check

Uncommitted work is lost work: a worker that dies, hits a limit or is restarted leaves nothing to resume from.

- Workers **commit as each task passes its targeted tests** (worker-dev Step 5), not at the end.
- The orchestrator runs `scripts/agent-health.sh` periodically (every few minutes while workers run) once per check; it lists every worktree of the repo, so read the row whose path matches each worker:

  ```bash
  bash scripts/agent-health.sh --repo <repo-root> --idle-min 20 --pile 10 --json
  ```

  Flags: `--idle-min N` (minutes without a write), `--pile N` (uncommitted-file threshold), `--json`, `--repo PATH`. Verdicts: `ok`, `uncommitted-pile`, `idle`, `no-commits`.

- Act on the verdict: **nudge** (SendMessage) any worker with `uncommitted-pile` ("commit what passes now"), or with `idle`/no write for ~20 min ("status? blocked?"). `no-commits` after a task should have finished means ask, then re-dispatch if the worker is gone. Do not fabricate a handoff for a silent worker.
