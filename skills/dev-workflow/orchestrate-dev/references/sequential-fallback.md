# Sequential execution — the no-subagent path

Read when the capability check in Step 3 of `orchestrate-dev` returns anything
other than native subagents, or when the user asks for a single-threaded run.

This is a **first-class execution mode**, not a degraded one. Most supported
harnesses cannot fan out work, and the methodology has to hold there. What
changes is concurrency. What does not change: the objective, the task graph,
the roles, the handoffs, the integration pass, the single PR.

```
objective
  → task-001 → handoff
  → task-002 → handoff
  → task-003 → handoff
  → integration → review → Tier 2 → ONE PR
```

## The loop

```bash
S=skills/dev-workflow/_shared/scripts/objective-state.sh
H=skills/dev-workflow/_shared/scripts/handoff.sh

while :; do
  TASK="$(bash $S next <objective-id>)"
  [ -z "$TASK" ] && break
  # 1. mark running
  # 2. run worker-dev for $TASK yourself, honouring its scope and prohibitions
  # 3. bash $H emit <objective-id> "$TASK" --status completed ...
  # 4. bash $S task-set <objective-id> "$TASK" --status completed
done
bash $S integrate-ready <objective-id>
```

`next` returns tasks in dependency order and promotes dependents automatically
as their prerequisites complete, so the loop terminates on a well-formed graph
and stalls visibly on a broken one (`next` empty while `integrate-ready` still
reports blocking tasks — that is a cycle or an unmet dependency; fix the graph).

## You are now both orchestrator and worker

Run each task under the `worker-dev` contract even though you are not a
separate process:

- respect `scope[]` — write nothing outside it, even though nothing stops you;
- run Tier 1 only for that task, not the full suite;
- commit before moving on;
- emit the handoff before starting the next task.

The discipline is the point. The handoff is what makes the run resumable and
the integration reviewable, and writing it forces you to state what you
actually validated.

## Context hygiene between tasks

A single session running every task accumulates the details of all of them,
which is exactly what causes late tasks to drift. Between tasks:

- summarise the finished task into its handoff, then stop referring to its
  internals;
- start the next task from its task file and its dependencies' handoffs, not
  from memory;
- if the session is compacted or cleared mid-objective, resume from
  `.dev-files/objectives/<id>/` — that is the whole point of the state model.

## Branches and worktrees in sequential mode

Two acceptable shapes:

| Shape | When | Note |
|---|---|---|
| Worker branches, merged at integration | Worktrees are available and tasks are big | Same as concurrent mode |
| Commit each task straight onto `objective/<id>` | Simplest; no worktree support | Say you are doing this; per-task commits keep the history readable |

Either way the objective branch is what gets delivered. Do not skip the
integration step just because there is nothing to merge — the combined-diff
review and Tier 2 still run.

## Serialized dispatch (subagents, no parallelism)

When the platform has subagents but not parallel ones, dispatch one worker at a
time and wait for each handoff. This gets the context isolation without the
concurrency. Treat it as sequential mode with a cleaner separation.

## What to tell the user

State the mode once, plainly:

> Running sequentially — this platform reports no subagent support, so the
> three tasks run one after another. Same objective, same single PR, longer
> wall-clock.

Never imply parallelism you did not have.
