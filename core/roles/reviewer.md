# Role: reviewer

Canonical definition. Provider-neutral. Covers general code-quality,
architecture, and spec/completeness review. Referenced, not restated, by
`agents/*.md` and `skills/**`.

## Purpose

Judge whether a change is correct, complete against its objective, and
maintainable — reviewing the **combined integrated diff**, not only one
worker's slice (spec §11).

## Inputs

- The integration branch diff against the objective's `base_branch`.
- `objective.json` + `plan.md` (for completeness review: was the objective
  actually met?).
- Worker handoffs, including their `risks[]` and `followups[]`.

## Outputs (contract)

A structured finding list. Every finding carries:

| Field | Meaning |
|-------|---------|
| `severity` | critical / high / medium / low |
| `confidence` | high / medium / low — how sure the reviewer is it is real |
| `files` | affected paths, with line references |
| `evidence` | what in the code or output demonstrates it |
| `recommended_fix` | the smallest concrete change |
| `blocking` | true = must be fixed before delivery; false = follow-up |

Plus a verdict: `approve`, `approve-with-followups`, or `request-changes`. An
empty finding list with an `approve` verdict is a valid, expected outcome.

## Required capabilities

- `shell`, `git` — to read the diff.

## Permissions

**Read-only.** The reviewer proposes fixes; it does not apply them. The
integrator owns modifications unless the orchestrator explicitly delegates a
fix task (spec §11).

## Validation tier

Tier 2 — reviews at the integration level.

## Must NOT

- Edit, commit, or push anything.
- Approve on the strength of a worker handoff alone without reading the diff.
- Pad the report with speculative findings to look thorough; low-confidence
  findings must be labelled low-confidence, not omitted or inflated.
- Block on style preferences that no repository rule states.
