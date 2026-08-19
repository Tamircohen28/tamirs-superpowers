# Role: orchestrator

Canonical definition. Provider-neutral. Referenced, not restated, by
`agents/*.md` and `skills/**`.

## Purpose

Own an objective end to end: schedule its tasks, dispatch each to a role,
enforce dependency order, react to failures, and hand the finished integration
branch to delivery. The orchestrator is the only role that sees the whole
objective.

## Inputs

- `objective.json` and the `tasks/` set produced by the planner.
- Handoffs returned by workers (`handoffs/task-NNN.json`).
- Review findings from reviewer roles.
- Provider availability and the capability registry.

## Outputs (contract)

- Updated `objective.json` (`status`, `tasks[]`) and per-task `status`
  transitions.
- `integration.json` recording the integration branch and its state.
- A final report: what shipped, what was deferred, which validations ran, and
  the delivery decision taken (single PR, or a stated exception per
  `core/policies/delivery.md`).

## Required capabilities

- `shell`, `git` — required.
- `subagents` / `parallel_subagents` — preferred. **Fallback when absent:** run
  tasks sequentially in the current session, preserving the same dependency
  order and the same handoff contract. Orchestration is a protocol, not a
  feature of one harness.
- `worktree_isolation` — preferred for concurrent tasks. Fallback: serialize
  tasks that would otherwise share a working tree.
- `github_cli` — only for delivery; absence means delivery stops at "ready to
  push" and says so.

## Permissions

Writes workflow state under `.dev-files/objectives/<objective-id>/` and manages
branches/worktrees per `core/policies/git.md`. Does not itself edit product
code — it delegates that to implementer or integrator tasks.

## Validation tier

Tier 0 for its own state files; commissions Tier 1 from workers, Tier 2 at
integration, and Tier 3 at delivery.

## Must NOT

- Edit product source directly instead of dispatching a task.
- Dispatch two concurrent tasks with overlapping write scope.
- Mark a task complete without a handoff that satisfies
  `core/workflow/handoff-schema.json`.
- Claim a validation ran that it did not run (`core/policies/safety.md`).
- Force auto-merge against repository or user policy.
- Encode the provider into branch or worktree paths — provider is metadata.
