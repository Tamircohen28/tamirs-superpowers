# Tier 2 pre-PR gates

Read in Step 3 of `deliver-dev`.

Tier definitions: [`core/policies/validation.md`](../../../../core/policies/validation.md).
Tier 2's goal: **prove the workers composed correctly.** Each worker already
proved itself in isolation; nothing so far has proved that their changes work
*together*. That is what this run is for, and it is the last check under your
control before CI.

## The gate set

Run all of these on the integration branch, in this order — cheapest signal
first, so a formatting failure does not cost a full test run:

1. **Full lint** — the whole repo, not the changed files.
2. **Full typecheck** — the whole project graph. Cross-worker interface
   mismatches surface here and nowhere earlier.
3. **Full unit suite.**
4. **Integration tests relevant to the objective** — the ones that exercise the
   seams between what the workers built.
5. **Repo standards gate** — whatever the repository enforces about itself
   (schema validation, drift checks, docs claims, generated-file freshness).
6. **Build**, if the repo produces one.

The shared runner covers this for repos that follow the framework's layout:

```bash
bash skills/dev-workflow/_shared/scripts/run-pre-pr-gates.sh
```

Read what it actually ran. When it does not cover this repository, run the real
commands from `Makefile` / `package.json` / `pyproject.toml` and say which ones.

## In this repository

```bash
make validate            # shellcheck + JSON + frontmatter + contract test
```

## Failure protocol

| Failure | Action |
|---|---|
| Trivial and clearly yours (lint, format, import order) | Fix on the integration branch, re-run |
| Cross-worker interface mismatch | Fix as integrator; record it — the task graph missed a dependency |
| A worker's change is genuinely broken | Return to `orchestrate-dev` for a scoped fix task; do not rewrite the worker's design silently |
| Pre-existing failure, unrelated to the objective | Verify it fails on the base branch too, then record and proceed |
| Flaky | Re-run **once**. Twice-flaky is a finding, not noise — record it |

Never open the PR on a red gate. "CI will tell us" wastes a full CI cycle and
puts an unreviewable PR in front of a human.

## Evidence

The PR body's validation section and the objective's record both carry the
actual commands and results:

```
make validate                    pass
npm run test:integration         pass (42 tests)
npm run build                    pass
```

Do not write "all gates passed" without the list. A gate you skipped is
recorded as skipped, with the reason.

## What Tier 2 is not

- It is not CI. Tier 3 runs independently, on clean infrastructure, and is the
  final authority. Do not try to reproduce the whole CI matrix locally.
- It is not a review. The combined-diff review is Step 2 and happens first;
  green gates on an incoherent diff still means do not ship.
