# Building the task graph

Read when decomposing an objective in Step 4 of `orchestrate-dev`.

## The one rule that matters

**Concurrent tasks must not share write scope.**

Every other decomposition heuristic is negotiable. This one is not, because two
agents editing the same file produce a conflict that neither of them has the
context to resolve, and the integrator inherits a merge it cannot reason about.
`objective-state.sh validate` enforces it; when it fires, change the graph
rather than the validator.

## Decomposition method

1. **List the deliverables.** What must be true when the objective is done?
   One deliverable is usually one task; two deliverables in the same file are
   one task.
2. **Map each deliverable to the paths it writes.** If you cannot name the
   paths, you do not understand the task well enough to dispatch it — read the
   code first.
3. **Partition by write scope.** Overlapping scopes get merged into one task,
   or sequenced with `depends_on`.
4. **Add the ordering edges.** A depends on B when A needs B's *code*, not
   merely B's decision. A decision can be handed over in the plan; code cannot.
5. **Add specialist tasks only where they earn their place.** A security review
   of a new auth path earns it. A "review everything" task does not — the
   combined-diff review at integration already covers that.
6. **Validate.** `objective-state.sh validate <id>`.

## Scope patterns

| Situation | Scope |
|---|---|
| A module | `src/auth/**` |
| One file | `src/config.ts` |
| A module and its tests, same owner | `src/auth/**`, `tests/auth/**` |
| Docs for a feature | `docs/user/auth.md` |
| Anything that says "and maybe some other files" | Not a scope. Narrow it or split it. |

Shared files — `package.json`, a barrel `index.ts`, a central router, a
CHANGELOG — are the usual cause of an unpartitionable graph. Options, in order
of preference:

1. give the shared file to exactly one task;
2. make the shared edit its own small task that everything else depends on;
3. leave it to the integrator, and tell each worker to record the needed edit
   as a followup.

## Dependency patterns

```
# Independent — run together
task-001 implementer  src/auth/**
task-002 implementer  src/billing/**

# Layered — a real code dependency
task-001 implementer  db/migrations/**
task-002 implementer  src/api/**        depends_on task-001
task-003 implementer  src/ui/**         depends_on task-002

# Fan-in — tests over several modules
task-001 implementer   src/auth/**
task-002 implementer   src/api/**
task-003 test-engineer tests/**         depends_on task-001,task-002

# Specialist after the fact
task-004 security-reviewer  (read-only, no writes)  depends_on task-001
```

A dependency chain longer than three levels usually means the objective is two
objectives. Say so instead of building a deep pipeline.

## Sizing

- A task too small to justify its own branch belongs inside a neighbour.
- A task that cannot be described in one sentence of scope is two tasks.
- More than ~6 tasks in one objective: either the objective is too big for one
  PR (check `core/policies/delivery.md` for the size exception), or the
  decomposition is too fine.

## What a dispatched worker must be told

Verbatim, every time — a worker with a vague brief writes outside scope:

- objective id, task id, role;
- `scope[]`, as the only writable paths;
- branch and worktree;
- the repo's Tier 1 command for that scope;
- decisions from the handoffs of its dependencies;
- the prohibitions: no PR, no auto-merge, no merging main, no full suite;
- end with `handoff.sh emit`.
