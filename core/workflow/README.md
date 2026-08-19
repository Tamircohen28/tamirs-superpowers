# Workflow state

Objective / task / handoff state for multi-agent work. **No database, no
service** — Git, local JSON files, and optionally GitHub issue state.

Three schemas live here:

| Schema | Describes |
|--------|-----------|
| [`objective-schema.json`](objective-schema.json) | One user objective — the default delivery unit |
| [`task-schema.json`](task-schema.json) | One unit of work inside an objective |
| [`handoff-schema.json`](handoff-schema.json) | What a task returns when it finishes |

## On-disk layout

```text
.dev-files/objectives/<objective-id>/
├── objective.json        # objective-schema.json
├── plan.md               # human-readable rationale from the planner
├── tasks/
│   ├── task-001.json     # task-schema.json
│   ├── task-002.json
│   └── task-003.json
├── handoffs/
│   ├── task-001.json     # handoff-schema.json
│   └── task-002.json
└── integration.json      # integration branch state, owned by the integrator
```

`<objective-id>` is the objective's `id`: lowercase slug, matching
`^[a-z0-9][a-z0-9-]*$`.

## Gitignored by default

`.dev-files/` is **not committed by default.** It is scratch coordination
state, it names local worktree paths, and it churns on every task transition.

A project that genuinely wants durable, reviewable workflow state can opt in by
un-ignoring `.dev-files/objectives/` in its own `.gitignore` — but that is an
explicit project decision, not the default. Nothing in the workflow depends on
this state being committed: it is rebuilt from `objective.json` plus the branch
graph on resume.

## Lifecycle

```text
planner      → objective.json + tasks/*.json          (status: draft → active)
orchestrator → dispatches ready tasks                 (task: ready → running)
implementer  → commit + handoffs/task-NNN.json        (task: running → completed)
integrator   → merges into integration branch,        (objective: integrating)
               writes integration.json
reviewer     → structured findings, fix loop          (objective: reviewing)
orchestrator → one PR                                 (objective: delivering → completed)
```

## Rules the schemas encode

- **A task ends at commit + handoff**, never at a PR. Delivery is an objective-
  level decision (`core/policies/delivery.md`).
- **`validation` lists only commands that actually ran.** A skipped entry must
  carry a `skip_reason`; an unrun command must not appear at all
  (`core/policies/safety.md`).
- **`files_changed` must fall inside the task's `scope[]`.** Work needed
  outside scope goes in `followups[]`.
- **Provider is metadata.** `task.provider` and `objective.provider_hints` are
  advisory; they never appear in a branch name or worktree path
  (`core/policies/git.md`).
- **`validation_tier`** names a tier from `core/policies/validation.md`:
  `edit` (0), `worker` (1), `integration` (2), `delivery` (3).

## Validating a state file

```bash
jq empty .dev-files/objectives/<id>/objective.json      # parses
bash scripts/validate-roles.sh                          # schemas parse; roles/agents agree
```

Full JSON Schema validation (`check-jsonschema`, `ajv`, or `python -m
jsonschema`) is optional tooling; the schemas are written to draft 2020-12 and
work with any of them.
