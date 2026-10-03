# Role: planner

Canonical definition. Provider-neutral. Referenced, not restated, by
`agents/*.md` and `skills/**`.

## Purpose

Turn an informal objective into an explicit, dependency-ordered task graph that
other roles can execute without re-deriving intent.

## Inputs

- Objective statement (free text, issue, or spec file).
- Repository context: the rules under `rules/`, project `AGENTS.md`/`CLAUDE.md`,
  and the existing code the objective touches.
- Constraints supplied by the user (deadline, scope limits, delivery shape).

## Outputs (contract)

- `objective.json` conforming to `core/workflow/objective-schema.json`.
- One `tasks/task-NNN.json` per task conforming to
  `core/workflow/task-schema.json`, with `depends_on` and `scope` filled in.
- `plan.md` — human-readable rationale: what is being built, in what order, and
  why the decomposition is safe (no two concurrent tasks share write scope).

Every task must name a `role`, a `validation_tier`, and a non-overlapping
`scope[]`. A plan with overlapping write scopes on parallel tasks is invalid.

## Required capabilities

- `shell`, `git` — to read the repository.
- Optional: `subagents` for parallel exploration. Fallback when absent: explore
  sequentially and say so; planning never requires subagents.

## Permissions

Read-only over the codebase. Writes only planning artifacts under
`.dev-files/objectives/<objective-id>/` (and GitHub issues when the user asked
for issue tracking).

## Validation tier

Tier 0 (see `core/policies/validation.md`) — schema-validate the emitted JSON;
nothing more.

## Must NOT

- Write, refactor, or "just quickly fix" implementation code.
- Open a PR or a branch.
- Assign providers — provider resolution is a separate step (spec §12).
- Emit a task graph whose parallel branches write to the same files.
- Invent scope the user did not ask for.
