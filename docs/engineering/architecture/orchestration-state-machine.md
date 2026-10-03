# Orchestration state machine

Three entities, three state machines, one directory of JSON files. No database, no service.

Schemas: [`core/workflow/`](../../../core/workflow/README.md) —
[`objective-schema.json`](../../../core/workflow/objective-schema.json),
[`task-schema.json`](../../../core/workflow/task-schema.json),
[`handoff-schema.json`](../../../core/workflow/handoff-schema.json). All draft 2020-12.

---

## On-disk layout

```text
.dev-files/objectives/<objective-id>/
├── objective.json        # objective-schema.json
├── plan.md               # planner rationale, for humans
├── tasks/task-001.json   # task-schema.json, one per task
├── handoffs/task-001.json# handoff-schema.json, written when a task ends
└── integration.json      # integration branch state, owned by the integrator
```

`<objective-id>` matches `^[a-z0-9][a-z0-9-]*$`. `.dev-files/` is gitignored by default: it
is scratch coordination state that names local worktree paths and churns on every
transition. Nothing depends on it being committed — it is rebuildable from `objective.json`
plus the branch graph. A project that wants durable, reviewable state may un-ignore
`.dev-files/objectives/` deliberately.

---

## Objective states

Required fields: `id`, `title`, `base_branch`, `integration_branch`, `status`, `tasks`.

```text
draft ──► active ──► integrating ──► reviewing ──► delivering ──► completed
             │            │              │             │
             └────────────┴──────────────┴─────────────┴──► blocked ──► active
             └──────────────────────────────────────────────► abandoned
```

| State | Meaning | Owner |
|---|---|---|
| `draft` | Task graph being built; nothing dispatched | planner |
| `active` | Tasks dispatching and running | orchestrator |
| `integrating` | Worker branches merging onto the integration branch | integrator |
| `reviewing` | Combined-diff review and fix loop | reviewer → integrator |
| `delivering` | Tier 2 passed; PR being opened | integrator (`deliver-dev`) |
| `completed` | PR open and handed to `pr-dev` | — |
| `blocked` | Cannot proceed without a decision | orchestrator |
| `abandoned` | Terminal; explicitly dropped | user |

`delivery.strategy` is one of `single-pr` (default), `multi-pr`, `direct-commit`, or `none`.
Anything other than `single-pr` must record `delivery.exception_reason` naming which
enumerated exception from [`core/policies/delivery.md`](../../../core/policies/delivery.md)
applies.

## Task states

Required fields: `id`, `role`, `depends_on`, `scope`, `validation_tier`, `status`.

```text
pending ──► ready ──► running ──► completed
   │                     │
   │                     ├──► failed ──► ready        (one retry, --bump-attempts)
   │                     └──► blocked ──► ready
   └────────────────────────► cancelled
```

- `pending` → `ready` when every task in `depends_on` is `completed`.
- `running` → `completed` **only when a handoff file exists.** A task with no handoff is
  `failed`, never `completed` — fabricating a handoff is the one unrecoverable lie in this
  workflow.
- A second failure means **re-plan** the task, not re-run it.

`role` is one of the ten canonical roles; `provider` is one of `current` (default), `claude`,
`codex`, `cursor`, `gemini`, `opencode` — metadata only, never part of an identity.
`validation_tier` is `edit` | `worker` | `integration` | `delivery`.

**`scope[]` is load-bearing.** Concurrent tasks must have disjoint write scopes;
`objective-state.sh validate` fails a graph that violates this, and that is fixed by
re-planning, not overriding. `files_changed` in the handoff must fall inside `scope[]`.

## Handoff

Required fields: `task_id`, `status` — one of `completed`, `partial`, `failed`, `blocked`,
`cancelled`.

| Field | Contract |
|---|---|
| `files_changed[]` | `added` / `modified` / `deleted` / `renamed`, each inside `scope[]` |
| `validation[]` | Only commands that **actually ran**: `tier` (edit/worker/integration/delivery) and `result` (`pass`/`fail`/`skipped`). A `skipped` entry carries a `skip_reason`; an unrun command must not appear at all |
| `followups[]` | Work needed outside scope — the only legitimate destination for it |
| `risks[]` | `critical` / `high` / `medium` / `low`, input to the integration plan |

The handoff is the task's entire output. The integrator reads handoffs and never the
worker's reasoning.

---

## Transitions in practice

```bash
S=skills/dev-workflow/_shared/scripts/objective-state.sh

bash $S init <id> --title "..."          # → draft
bash $S task-add <id> --role implementer --scope 'src/**' --title "..."
bash $S validate <id>                     # disjoint-scope gate
bash $S ready <id>                        # tasks whose deps are completed
bash $S task-set <id> task-001 --status running
bash $S integrate-ready <id>              # every task terminal?
bash $S set-status <id> integrating
bash $S set-delivery <id> --strategy multi-pr --reason '<enumerated exception>'
```

## Resume semantics

Because every transition is a file write, resume is a read:

```bash
bash $S list                              # every objective and status
bash $S show <id>; bash $S tasks <id>
bash skills/dev-workflow/_shared/scripts/handoff.sh list <id>
```

Those three commands rebuild everything the orchestrator knew. A task whose handoff exists is
**never re-run**; re-running duplicates commits and invalidates the integration plan the
other tasks were built against. Because no state names a provider, an objective started under
one platform resumes under another from the same files and branches.

## Invariants

1. A task ends at commit + handoff. Only the objective ends at a PR.
2. Concurrent tasks never share write scope.
3. Reviewers are read-only; the integrator applies fixes.
4. Conflicts are resolved at integration, by the integrator, nowhere else.
5. Only commands that ran are reported; skips are reported as skips, with a reason.
6. No handoff ⇒ the task is `failed`.
7. Provider never appears in a branch name, worktree path, or state directory name.

## Validating state

```bash
jq empty .dev-files/objectives/<id>/objective.json
bash scripts/validate-roles.sh          # schemas parse; roles and agents agree
```

Full JSON Schema validation (`check-jsonschema`, `ajv`, `python -m jsonschema`) is optional
tooling — the schemas work with any of them.
