---
name: orchestrate-dev
description: 'Use when an implementation request is bigger than one unit of work — a spec or plan file, a multi-part feature, a review doc with several items, ''implement all of this'', ''build X end to end'', ''do these N things'', ''orchestrate this'', ''run these in parallel'', ''split this across agents''. Plans a dependency-aware task graph, runs each task under a role (parallel workers where supported, sequentially where not), integrates onto ONE objective branch, and delivers ONE PR. A single small change is not orchestration — that falls through to start-dev.'
when_to_use: 'User says: implement this spec, build this feature end to end, do all of these, work through this plan/review doc, orchestrate this, split this across agents, run these tasks in parallel, coordinate workers on this objective — or hands over a plan.md / issue list / multi-item task that needs more than one unit of work.'
argument-hint: '[objective description, spec/plan file path, issue number, or existing objective id to resume]'
arguments: []
disable-model-invocation: false
user-invocable: true
allowed-tools:
- Bash
- Read
- Write
- Edit
- Glob
- Grep
- Agent
- Skill
- Monitor
disallowed-tools: []
model: claude-sonnet-4-6
effort: high
context: ''
agent: ''
hooks: {}
paths: []
shell: bash
metadata:
  updated-date: '2026-08-19'
  tamirs:
    visibility: public
    category: dev-workflow
    role: orchestrator
    capabilities:
      required:
      - skills
      - shell
      - git
      optional:
      - subagents
      - parallel_subagents
      - worktree_isolation
      - github_cli
      - background_tasks
    validation-tier: 2
    updated-date: '2026-08-19'
    tags:
    - orchestration
    - objective
    - task-graph
    - integration
    - workflow
---

# orchestrate-dev

Turn one user objective into a task graph, run it, integrate it, and deliver **one PR**.

Role contract: [`core/roles/orchestrator.md`](../../../core/roles/orchestrator.md). Policies inherited, never restated here: [`core/policies/safety.md`](../../../core/policies/safety.md), [`core/policies/git.md`](../../../core/policies/git.md), [`core/policies/validation.md`](../../../core/policies/validation.md), [`core/policies/delivery.md`](../../../core/policies/delivery.md).

## The two separations that make this work

| Separation | Meaning |
|---|---|
| Objective ≠ task | The user asked for one thing. It is *executed* as several. |
| Work unit ≠ delivery unit | A task ends at **commit + handoff**. Only the objective ends at a PR. |
| Role ≠ provider | A task needs an implementer; whichever harness is available plays that role. |

**Validation tier: 2 (integration).** This skill runs the integration gates. Tier 1 belongs to `worker-dev`; Tier 3 belongs to CI via `pr-dev`.

## Step 0 — decide whether to orchestrate at all

Orchestration has real cost: branches, worktrees, state files, an integration pass. Do not pay it for a small change.

Fall through to `start-dev` (single worker + delivery) when **all** of these hold:

- one coherent change, plausibly one commit or a short series;
- one write scope — no two independent areas of the tree;
- no ordering constraint between sub-parts;
- no separate specialist pass genuinely needed (tests written alongside is not a second task).

Orchestrate when **any** of these hold:

- the request names several deliverables ("do these four things", a plan file, a review doc);
- parts touch disjoint areas and could progress independently;
- a real dependency exists (schema before API before UI);
- a distinct role is genuinely needed after implementation (security review of new auth, perf review of a hot path);
- the change is large enough that one combined-diff review at the end is materially better than reviewing it as it is written.

Say which way you decided and why, in one sentence, before doing anything else. If you fall through, invoke `start-dev` and stop.

**The hand-off is one-directional.** `start-dev` has its own routing test that
can send multi-part work here; this fall-through is the opposite direction, and
the two must never bounce. When you delegate, say so explicitly:

> Not orchestration — single scope, no ordering constraint. Handing to
> `start-dev` as a simple task; the orchestration decision is already made, do
> not route back.

Once you have delegated, you are done: do not re-evaluate, do not re-enter, and
do not accept the same request back. If `start-dev` ever returns it, treat that
as a routing bug and finish the work on the simple path rather than looping.

## Step 1 — resolve the objective

| Input | Resolution |
|---|---|
| Free text | Slugify into an objective id (`^[a-z0-9][a-z0-9-]*$`) |
| Spec/plan file | Read it; the file is the source of tasks |
| Issue number | `gh issue view N --json title,body` |
| Existing objective id | **Resume** — go to Step 9 |

Always check for an existing objective first — this is the resume path:

```bash
S=skills/dev-workflow/_shared/scripts/objective-state.sh
bash $S active   # active objective id, or empty + exit 1 when there is none
bash $S list
```

`active` is what other skills use to tell whether an objective is already in
flight — `start-dev` calls it to suppress PR creation for work that belongs to
an objective. If it returns an id you did not expect, resolve that before
starting a second objective.

## Step 2 — inspect the repository, load its rules

Read `CLAUDE.md` / `AGENTS.md`, the repo's own rules files, and the test/lint commands actually defined (`Makefile`, `package.json` scripts, `pyproject.toml`). You are about to hand these commands to workers; guessing them wastes every worker's run.

## Step 3 — check capabilities before you promise concurrency

```bash
jq -r '.platforms | to_entries[] | "\(.key): subagents=\(.value.capabilities.subagents.status) parallel=\(.value.capabilities.parallel_subagents.status) worktrees=\(.value.capabilities.worktree_isolation.status)"' \
  core/capabilities/platforms.json
```

Read the entry for the platform you are running on. Then pick a mode:

| `subagents` | `parallel_subagents` | Mode |
|---|---|---|
| native | native | **Concurrent** — dispatch independent tasks together |
| native | unsupported/partial | **Serialized dispatch** — one subagent at a time |
| unsupported | — | **Sequential** — see [`references/sequential-fallback.md`](references/sequential-fallback.md) |

If the registry is missing or the platform has no entry, assume **sequential** and say so. Never claim parallelism you did not verify. Full rules: [`references/capability-gating.md`](references/capability-gating.md).

## Step 4 — build the task graph

Decompose into tasks with **disjoint write scopes**. Two tasks that may write the same file are not parallel — either merge them into one task or make one depend on the other. Method and worked examples: [`references/task-graph.md`](references/task-graph.md).

```bash
S=skills/dev-workflow/_shared/scripts/objective-state.sh
bash $S init auth-system --title "Implement authentication system"
bash $S task-add auth-system --role implementer  --scope 'src/auth/**'   --title "Auth core"
bash $S task-add auth-system --role implementer  --scope 'src/api/**'    --title "API routes"
bash $S task-add auth-system --role test-engineer --scope 'tests/auth/**' \
       --depends-on task-001,task-002 --title "Integration tests"
bash $S validate auth-system
```

`validate` fails when two concurrent tasks share write scope. Fix the graph, do not override it.

Assign roles from [`core/roles/README.md`](../../../core/roles/README.md). Reviewer roles are read-only — a reviewer task produces findings, and the **integrator** applies fixes unless you explicitly create a fix task.

## Step 5 — select providers

Provider is metadata, never identity: it appears in `task.provider`, never in a branch name or a path. Default is `current` — the harness you are already running in. Only route a role elsewhere when that provider is genuinely available and configured. **Never require a second AI subscription for the objective to complete.**

## Step 6 — create branches and worktrees

```
main
└── objective/<id>              ← integration branch, cut from base_branch
    ├── worker/<id>/001
    ├── worker/<id>/002
    └── worker/<id>/003
```

Worktrees live under `.agent-worktrees/<objective>/<task-id>/` (or the user-level equivalent). Use the shared resolver rather than raw `git worktree` so existing platform worktrees are not orphaned:

```bash
W=skills/dev-workflow/_shared/scripts/resolve-worktree.sh
bash $W --objective auth-system --integration        # objective/auth-system
bash $W --objective auth-system --task 001           # worker/auth-system/001
bash $W --list                                       # every agent worktree, both layouts
bash $S task-set auth-system task-001 --branch worker/auth-system/001 --worktree <path>
```

Create the integration worktree first — worker branches are cut from
`objective/<slug>`, not from the base branch. The resolver adopts an existing
legacy worktree (`.claude/.worktrees/…`, `.cursor/…`, `.codex/…`) for a slug
rather than creating a parallel one, so pre-existing work is never orphaned.

In sequential mode you may skip worker worktrees entirely and commit task-by-task directly onto the objective branch. Say that you are doing so.

## Step 7 — dispatch ready tasks

```bash
bash $S ready auth-system    # every task whose dependencies are completed
```

Every dispatched worker — subagent or your own sequential turn — runs the `worker-dev` skill and gets, verbatim:

- objective id and task id;
- the task's `scope[]` globs, stated as the **only** paths it may write;
- its worktree path and branch;
- the repo's Tier 1 command for that scope;
- the prohibitions: **no PR, no auto-merge, no merging main, no full repo suite**;
- the instruction to end with `handoff.sh emit`.

Mark tasks `running` on dispatch (`task-set --status running`). One retry per failed task (`--bump-attempts`); a second failure means re-plan the task, not re-run it.

## Step 8 — sequential fallback (first-class, not a footnote)

No subagents, or the user asked for a single-threaded run:

```
objective → task-001 → handoff → task-002 → handoff → … → integration
```

Same state model, same handoffs, same integration, same one PR — only the concurrency is gone. Loop `next` → run `worker-dev` yourself → `handoff.sh emit` → `task-set --status completed` until `next` is empty. Details, including context hygiene between tasks: [`references/sequential-fallback.md`](references/sequential-fallback.md).

## Step 9 — collect handoffs (and resume here after a restart)

```bash
bash skills/dev-workflow/_shared/scripts/handoff.sh list auth-system
bash $S tasks auth-system
bash $S integrate-ready auth-system
```

State lives entirely on disk under `.dev-files/objectives/<id>/`. After a crash, a `/clear`, or a new session, those three commands rebuild everything you knew. Never re-run a task whose handoff already exists — read it.

Read every handoff before integrating. Blocking followups and `risks` are input to the integration plan; a `partial` or `failed` handoff means decide (re-plan, drop the task, or narrow the objective) — never quietly integrate around it.

## Step 10 — integrate onto ONE branch

Merge worker branches into `objective/<id>` in dependency order. **Conflicts are resolved here, by the integrator, and nowhere else** — a worker never merges main and never resolves another worker's conflict.

On conflict: understand both sides from the two handoffs, resolve on the integration branch, and record the resolution. If the conflict shows the task graph was wrong (overlapping scope that `validate` did not catch), fix the graph before continuing.

```bash
bash $S set-status auth-system integrating
```

## Step 11 — review the combined diff

Review the **integrated** diff, not the individual worker diffs — that is where composition bugs live.

1. spec/completeness review — does the objective's stated goal actually hold?
2. code-quality review;
3. security or performance review when the diff warrants it;
4. fix loop — the integrator applies fixes, or you create a scoped fix task.

Reviewer findings are structured: severity, confidence, affected files, evidence, recommended fix, blocking or not. Blocking findings must be resolved before Step 12.

## Step 12 — integration validation (Tier 2)

Full lint, full typecheck, the unit suite, the integration tests relevant to this objective, and the repo standards gate — on the integration branch. This is the run that proves the workers *compose*; the workers only proved themselves. Record the commands you ran and their real results.

## Step 13 — deliver

```bash
bash $S set-status auth-system delivering
```

Invoke `deliver-dev` with the objective id. It runs the pre-PR gates, pushes, opens **one** PR, and hands the GitHub lifecycle to `pr-dev`.

Multiple PRs need a stated exception from `core/policies/delivery.md`, recorded on the objective:

```bash
bash $S set-delivery auth-system --strategy multi-pr --reason '<which enumerated exception>'
```

## Hard rules

- **One objective = one PR.** Exceptions must be named and recorded, not assumed.
- **No worker opens a PR.** If one did, that is a bug in the prompt you gave it — say so in the report.
- **Never claim a capability you did not check.** Missing capability → stated fallback, or plainly "this platform does not support that".
- **Never fabricate a handoff.** If a worker returned nothing, its task is `failed`, not `completed`.
- **Concurrent tasks never share write scope.** `objective-state.sh validate` is the gate.
- **The integrator owns modifications.** Reviewers are read-only.
- Do not commit `.dev-files/` unless the project explicitly wants durable checked-in workflow state.

## Anti-patterns

| Don't | Do |
|---|---|
| Spin up a DAG for a one-file fix | Fall through to `start-dev` |
| Let each worker open its own PR | Workers commit + hand off; one PR at the end |
| Review each worker diff and skip the combined one | Review the integrated diff |
| Run the full suite in every worker | Tier 1 in workers, Tier 2 once at integration |
| Silently degrade to sequential | Say which mode you are in and why |
| Re-run a task after a restart | Read its handoff from `.dev-files/` |
| Encode the provider in the branch name | Provider is `task.provider` metadata |

## Output format

```
Objective: <id> — <title>
Mode: concurrent | serialized | sequential  (reason: <capability finding>)
Tasks: N (P parallel, D dependent)
  task-001 implementer  src/auth/**   completed  worker/auth-system/001
  ...
Integration: objective/<id> — <conflicts resolved / none>
Review: <blocking findings resolved / none>
Tier 2: <commands run and their results>
Delivery: PR <url> (handed to pr-dev)
Deferred: <followups carried out of the objective>
```
