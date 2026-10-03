# Task Grouping Reference Guide

Extended reference for grouping decisions in plan-dev. Load this file when dealing with
large specs (20+ items), ambiguous dependency graphs, or monorepo scenarios.

**Terminology:** what this guide calls a *phase* is a **task** in the objective/task model
(`core/workflow/task-schema.json`). The grouping advice is unchanged; only two things are:
a task is a work unit that ends at commit + handoff, **not** a PR, and the whole objective
normally ships as **one** PR. "Phase N depends on Phase M" is `depends_on: ["task-00M"]`,
and every task additionally carries a `scope[]` of writable globs, a `role`, and a
`validation_tier`.

---

## Dependency graph patterns

### Linear chain
When each phase strictly depends on the previous:

```
Phase 1: DB schema migration
Phase 2: Backend API (needs schema)
Phase 3: Frontend UI (needs API)
Phase 4: E2E tests (needs UI)
```

Always create in this order. Document the chain with `Depends on: Phase N`.

### Fan-out (parallelizable)
When multiple phases share a single prerequisite but are independent of each other:

```
Phase 1: Shared auth middleware (infra)
Phase 2: User profile feature  [Parallel-safe: yes, Depends on: Phase 1]
Phase 3: Dashboard feature     [Parallel-safe: yes, Depends on: Phase 1]
Phase 4: Notifications feature [Parallel-safe: yes, Depends on: Phase 1]
```

Mark phases 2–4 as `Parallel-safe: yes`. Multiple engineers can implement them simultaneously.

### Diamond dependency
Phase 3 depends on both Phase 1 and Phase 2 (which may be parallel):

```
Phase 1: API client refactor  [Parallel-safe: yes]
Phase 2: DB query optimization [Parallel-safe: yes]
Phase 3: Integration + tests  [Depends on: Phase 1, Phase 2]
```

---

## File-count heuristics

| Files touched | Recommendation |
|---|---|
| 1–3 files | Single phase (or group with adjacent changes) |
| 4–10 files | One phase, acceptable |
| 10–20 files | Consider splitting by sub-area or layer |
| 20+ files | Must split — use the fan-out pattern if possible |

---

## Risk isolation rules

Never mix these in one phase:

| Risk combination | Why it's dangerous |
|---|---|
| Risky refactor + new feature | If refactor introduces a bug, feature change obscures root cause |
| DB migration + business logic change | Rollback becomes complex — can't revert one without the other |
| Dependency upgrade + feature work | Hard to tell if regression came from upgrade or feature |
| Cross-team boundary changes | Different review queues; one team's merge can break the other |

Each of the above should be in its own phase.

---

## Label selection

Use exactly one of these primary labels per issue:

| Label | When to use |
|---|---|
| `feat` | Net-new capability visible to users or callers |
| `fix` | Corrects incorrect behavior (bug fix) |
| `refactor` | Internal restructuring; no behavior change |
| `chore` | Dependency updates, config changes, tooling |
| `docs` | Documentation only (no code change) |
| `test` | Adds or improves test coverage only |
| `ci` | CI/CD pipeline changes |

---

## Common anti-patterns to avoid

### The "while we're in there" phase
```
## Phase 2: Add user search
- [ ] Implement search endpoint
- [ ] Also refactor the entire user model while we're in there
- [ ] Also add pagination to unrelated endpoints
```
Fix: separate phases for search, model refactor, and pagination.

### The "future work" phase
```
## Phase 5: Misc improvements
- [ ] Performance
- [ ] Better error messages
- [ ] Polish
```
Fix: make each item concrete or defer to a backlog issue. Vague phases don't become issues.

### The circular dependency
```
Phase 1: Depends on Phase 3
Phase 3: Depends on Phase 1
```
Fix: extract the shared prerequisite into Phase 0.

---

## Monorepo considerations

When the repo has multiple packages/apps:

1. Changes to a shared package always go in an earlier phase than consumers.
2. Name the area as `packages/<name>` not just `frontend` or `backend`.
3. Note which workspace commands to run in Verification (`yarn workspace @app/api test`).

---

## When to fold items together vs split them into separate tasks

Fold several items into **one task** when:
- They are too small to isolate (< 30 min of work each)
- They must be reviewed together (tightly coupled logic)
- Splitting would create a meaningless "WIP" state in the codebase
- They write the same files — separate tasks over one scope conflict by construction

Give an item its **own task** when:
- It can progress independently of the others (disjoint `scope[]`, no dependency)
- A different role should do it (test-engineer, security-reviewer, …)
- It carries materially higher risk than its neighbours and should be reviewable on its own

Splitting into separate **objectives** — and therefore separate PRs — is a much stronger
step, reserved for the exceptions in `core/policies/delivery.md`: truly independent
deliverables, security isolation, deployment sequencing, an explicit user request, or an
objective past a size/risk threshold. When issues are exported, the same grouping applies:
one issue per task, all pointing at one objective.
