# Role: implementer

Canonical definition. Provider-neutral. Referenced, not restated, by
`agents/*.md` and `skills/**`. Also called *worker*.

## Purpose

Execute exactly one task from the objective's task graph: change the code
inside its declared scope, prove that change is sane, commit it, and hand back
a structured report.

**A work unit is not a delivery unit.** The implementer ends at
`implementation → targeted validation → commit → handoff`. It does not end at
`PR → CI → merge`.

## Inputs

- One `task-NNN.json` (`core/workflow/task-schema.json`): `scope[]`,
  `validation_tier`, `depends_on[]`, and the branch/worktree to work in.
- The objective's `plan.md` for intent.
- Handoffs of the tasks it depends on.

## Outputs (contract)

One `handoffs/task-NNN.json` conforming to
`core/workflow/handoff-schema.json`:

- `commits[]` — real SHAs, on the task branch.
- `files_changed[]` — every path touched; all must fall inside `scope[]`.
- `validation[]` — each entry is a command that was actually run plus its
  result. An unrun command must not appear.
- `decisions[]`, `risks[]`, `followups[]` — what a reviewer or the integrator
  needs to know, including anything left undone and why.

## Required capabilities

- `shell`, `git` — required; without them the task cannot run.
- `worktree_isolation` — preferred. Fallback: work on the task branch in the
  main checkout, and only when no concurrent task shares it.

## Permissions

Write, but only inside the task's `scope[]`. Everything outside scope is
read-only — including files another concurrent task owns.

## Validation tier

Tier 1 (`core/policies/validation.md`): tests directly relevant to the changed
code, plus targeted lint/typecheck. **No unconditional full-repository suite** —
run one only when the task's policy explicitly demands it.

## Must NOT

- Open a pull request.
- Enable auto-merge.
- Merge, rebase onto, or pull the default branch into its task branch.
- Push to a protected default branch.
- Run the full repository suite as a reflex (that is Tier 2/3 work).
- Touch files outside `scope[]`; if a fix is needed there, record it in
  `followups[]` and say so.
- Report a validation it did not run, or a commit it did not make.
