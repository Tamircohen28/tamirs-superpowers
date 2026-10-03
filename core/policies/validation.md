# Policy: validation tiers

The old workflow over-validated every worker and then validated the same thing
again in CI. Four explicit tiers replace that. **Every skill and every script
must declare which tier it invokes** — in its frontmatter, its header comment,
or its documented contract. A validation step whose tier is unstated is a bug.

## Tier 0 — edit-time

- Syntax checks where they are cheap (`jq empty`, YAML parse, `bash -n`).
- Formatter or linter on the touched file, when it is near-instant.

**Goal:** catch a typo before it becomes a failed run. Nothing here may take
noticeable time.

## Tier 1 — worker

- Tests directly relevant to the changed code.
- Targeted lint/typecheck over the task's `scope[]`.
- **No unconditional full-repository suite.**

**Goal:** prove this worker's contribution is sane. Not to prove the repository
is green — that is not knowable from inside one task, and paying for it in
every task is what made workers slow.

A task may opt into a heavier check when its `scope[]` genuinely warrants it
(a shared core module, a generated-file contract). That is a per-task decision
recorded in the task, not a blanket default (`safety.md`, configurable policy).

## Tier 2 — integration

- Full lint and typecheck.
- Full unit suite, where the suite's runtime makes that reasonable.
- Integration tests relevant to the combined objective.
- The repo standards gate.
- Combined-diff review (`core/roles/reviewer.md`).

**Goal:** prove the workers compose correctly. This is the first point at which
"the repository is green" is a meaningful claim.

## Tier 3 — delivery / CI

- Independent CI verification — run by CI, not by an agent asserting it.
- Expensive cross-platform, build, and security tests.
- Release checks (version/manifest alignment, changelog, tag).

**Goal:** final authority. CI's result outranks any local claim.

## Declaring a tier

Scripts declare the tier in their header comment:

```bash
#!/usr/bin/env bash
# validate-roles.sh — role/agent/schema consistency check.
# Validation tier: 0 (static parse + consistency; no test execution).
```

Skills declare it in their body, in the section that runs validation.

## Reporting

Only commands that actually ran may be reported, with real results
(`safety.md`, invariant 7). A tier that was deliberately skipped is reported as
skipped with a reason — not omitted, and not reported as passing.
