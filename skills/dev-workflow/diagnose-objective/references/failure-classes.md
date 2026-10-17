# Failure classes

Every class `scripts/objective-timeline.sh` can emit, with the rule that detects it, what
the evidence files must show before the finding is confirmed, the usual real-world cause,
and the one next command. Severity decides which finding becomes `first_cause` when several
share a timestamp: `critical` > `high` > `medium` > `low`; among equals, the earliest `at`
wins, then the lowest task id.

The vocabulary the classes are built on is the handoff status set — `completed`, `partial`,
`failed`, `blocked`, `cancelled` — and the seven invariants of
[`orchestration-state-machine.md`](../../../../docs/engineering/architecture/orchestration-state-machine.md).
Invariant 6, *no handoff ⇒ the task is failed*, is the one most of these classes are
restating from a different angle.

## The classes

### `task-completed-without-handoff` — critical

- **Rule:** `tasks/<id>.json` has `status: completed` and `handoffs/<id>.json` does not exist.
- **Evidence must show:** the task file; the absence of the handoff (list `handoffs/`).
- **Usual cause:** an orchestrator read the subagent's closing summary ("done, tests pass")
  and ran `task-set --status completed` itself. `hooks/subagent-handoff-check.sh` warns about
  exactly this at `SubagentStop`, but it is advisory.
- **Next:** `objective-state.sh task-set <id> <task> --status failed --bump-attempts`, then
  `/worker-dev <id> <task>`. A second failure means re-plan, not a third run.

### `worker-stopped-without-handoff` — high

- **Rule:** `status: running`, no handoff, and no rate-limit record matches the objective.
- **Evidence must show:** the task file; the worktree path if one is recorded (is it dirty?
  `git.dirty_worktrees` answers when git is present).
- **Usual cause:** the worker hit its turn limit or an error and returned `partial` in prose
  only; or the host killed it; or the session was closed. A `maxTurns`-truncated subagent is
  a common source — its output is marked partial by the host, but nothing wrote the file.
- **Next:** dirty worktree → `/switch-dev handoff objective=<id> <task>` so the uncommitted
  work gets a record first. Clean → `/worker-dev <id> <task>`.

### `rate-limit-death` — high

- **Rule:** as above, and `.dev-files/handoffs/rate-limit-*.json` (written by
  `hooks/rate-limit-handoff.sh` at `StopFailure`/`rate_limit`) names this objective, or names
  no objective but a branch belonging to it.
- **Evidence must show:** the record's `written_at`, `branch`, `uncommitted` and `resume`
  fields; the task file.
- **Usual cause:** exactly what it says. The hook can only write the record and tell the
  user; it cannot write the task's handoff, because that needs the worker's knowledge.
- **Next:** `/switch-dev handoff objective=<id> <task>` — the record's own `resume` field says
  the same. Then resume or re-run from the handoff that produces.

### `completed-without-validation` — high

- **Rule:** handoff `status: completed` with `validation[]` empty.
- **Evidence must show:** the handoff; its `summary` (does it *mention* tests that are not in
  `validation[]`? then the record is incomplete, not the work).
- **Usual cause:** the worker ran nothing, or ran tests and forgot `--validation`. Either way
  it is a claim with no evidence, and the integrator cannot tell which.
- **Next:** `/worker-dev <id> <task>` to run Tier 1 and re-emit honestly.

### `completed-with-failing-validation` — high

- **Rule:** handoff `status: completed` and at least one `validation[].result == "fail"`.
- **Evidence must show:** the failing entry's `command` and `output_excerpt`.
- **Usual cause:** "the failure is pre-existing / unrelated". The honest status was `partial`
  with a followup, so the integrator could decide.
- **Next:** `/worker-dev <id> <task>`.

### `integrated-around-partial` — critical

- **Rule:** handoff status is `partial`, `failed` or `blocked`, and either the task is marked
  `completed` or the objective moved to `integrating`/`reviewing`/`delivering`/`completed`.
- **Evidence must show:** the handoff's `summary` and blocking `followups[]`; `objective.json`
  status and `updated`.
- **Usual cause:** the orchestrator treated the task list as a checklist instead of reading
  the handoffs before integration (orchestrate-dev Step 9).
- **Next:** `/orchestrate-dev <id>` — decide: re-plan, drop the task, or narrow the objective.

### `shared-branch` — high

- **Rule:** two or more task files name the same `branch`.
- **Evidence must show:** both task files; the handoffs' `commits[]` (do they overlap?).
- **Usual cause:** a copy-pasted dispatch prompt, or `task-set --branch` run with the wrong
  task id. Both workers' commits land on one branch and neither handoff's commit list is
  trustworthy.
- **Next:** `/orchestrate-dev <id>` — fix the graph, then re-integrate.

### `dependency-order-violation` — high

- **Rule:** a task is `running` or `completed` while a task in its `depends_on` is not
  `completed`.
- **Evidence must show:** both task files; the dependent's handoff `summary` (did it build on
  a stub?).
- **Usual cause:** dispatch from a hand-maintained list instead of `objective-state.sh next`.
- **Next:** `/orchestrate-dev <id>`.

### `integration-behind-workers` — high (needs git)

- **Rule:** the integration branch exists and a `completed` task's branch has commits not
  reachable from it, while the objective is at or past `integrating`.
- **Evidence must show:** `git rev-list <integration>..<branch>` — the script already counted;
  the report quotes the number.
- **Usual cause:** a worker committed after the integrator merged (a late fix), or one branch
  was never merged.
- **Next:** `/orchestrate-dev <id>` to integrate the missing commits.
- **Without git:** not checked; the report says so under Evidence.

### `task-state-stale` — medium

- **Rule:** a handoff exists but the task's `status` is not the matching terminal state
  (`completed`→`completed`, `partial`→`failed`, `failed`/`blocked`/`cancelled`→same).
- **Evidence must show:** the handoff and the task file.
- **Usual cause:** the worker emitted the handoff and the orchestrator never ran `task-set`.
  Harmless by itself, but `ready`, `next` and `integrate-ready` all answer wrongly until fixed.
- **Next:** `objective-state.sh task-set <id> <task> --status <matching>`, then
  `/orchestrate-dev <id>`.

### `stuck-running` — medium

- **Rule:** one task is `running` and every other task is terminal.
- **Evidence must show:** the task file; its worktree if any.
- **Usual cause:** the same event as `worker-stopped-without-handoff` or `rate-limit-death`,
  which are reported alongside and outrank it. On its own (handoff present) it is
  `task-state-stale` seen from the other side.
- **Next:** as for the higher-severity finding on the same task.

### `scope-escape` — medium

- **Rule:** a handoff `files_changed[].path` matches none of the task's `scope[]` globs.
- **Evidence must show:** the handoff; `handoff.sh` only writes this with `--force`.
- **Usual cause:** a worker needed a change outside its scope and made it instead of
  recording a followup.
- **Next:** `/orchestrate-dev <id>` — the integrator reviews the escape or it becomes a task.

### `objective-blocked` — medium

- **Rule:** `objective.json` `status: blocked`.
- **Evidence must show:** `notes`, and the newest handoff's `summary`.
- **Next:** `/orchestrate-dev <id>` with the decision made.

### `handoff-without-task` — low

- **Rule:** a handoff names a `task_id` with no task file.
- **Usual cause:** a typo in a task id, or a task deleted after its worker ran.
- **Next:** `/orchestrate-dev <id>`.

### `unparseable-state-file` — high

- **Rule:** a task or handoff file is not valid JSON.
- **Next:** fix the file by hand, then `objective-state.sh validate <id>`.

## No finding

A clean objective still gets a report. `next_command` then depends on `objective.status`:
`completed`/`abandoned` → nothing; every task terminal → `/orchestrate-dev <id>` to
integrate; otherwise `/orchestrate-dev <id>` to resume dispatch from the state files. If the
user insists the objective failed and the files show nothing, the failure happened outside
recorded state — a PR, CI, a human step — and the report says exactly that rather than
inventing a class.
