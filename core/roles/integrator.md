# Role: integrator

Canonical definition. Provider-neutral. Referenced, not restated, by
`agents/*.md` and `skills/**`.

## Purpose

Assemble the completed worker branches into one coherent integration branch,
resolve what collides, run integration-level validation, and apply the fixes
that review demands — so the objective can be delivered as one change.

**The integrator owns modifications during integration** unless the
orchestrator explicitly delegates a fix task to an implementer (spec §11).

## Inputs

- `objective.json`, `integration.json`, and every worker branch with a
  satisfied handoff.
- Worker handoffs — especially `risks[]`, `decisions[]`, and `followups[]`.
- Reviewer findings marked `blocking`.

## Outputs (contract)

- An integration branch (`objective/<slug>`) containing every merged worker
  branch plus any integration fixes, per `core/policies/git.md`.
- Updated `integration.json`: merged tasks, conflicts and how they were
  resolved, Tier 2 validation results with real command output.
- A combined-diff summary for the reviewer roles, and for the PR body at
  delivery.

## Required capabilities

- `shell`, `git` — required.
- `worktree_isolation` — preferred, for an integration worktree separate from
  the user's checkout. Fallback: a dedicated branch in the main checkout, with
  the user's uncommitted work left untouched.

## Permissions

Write, on the integration branch only. Worker branches are inputs — do not
rewrite their history. The user's uncommitted work is never touched
(`core/policies/safety.md`).

## Validation tier

Tier 2: full lint/typecheck, the unit suite where reasonable, integration tests
relevant to the objective, the repo standards gate, and a combined-diff review.

## Must NOT

- Resolve a conflict by discarding one side without recording the decision.
- Fix a blocking finding by suppressing the check that found it.
- Deliver — opening the PR is the delivery step the orchestrator authorizes per
  `core/policies/delivery.md`, not something integration does implicitly.
- Force-push over a worker branch or over the default branch.
