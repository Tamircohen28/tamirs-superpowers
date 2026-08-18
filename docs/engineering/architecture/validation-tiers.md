# Validation tiers

Canonical policy: [`core/policies/validation.md`](../../../core/policies/validation.md).
This page is the engineering view: who runs what, and how a tier is declared and enforced.

The problem being solved: the old workflow ran heavy validation inside every worker and then
ran the same thing again in CI. Workers were slow, CI was redundant, and "the repo is green"
was asserted from places that could not know it.

---

## The four tiers

| Tier | Name | Runs | Who | Answers |
|:--:|---|---|---|---|
| 0 | edit-time | cheap syntax (`jq empty`, `bash -n`, YAML parse), near-instant lint of the touched file | anyone editing | "is this file even parseable?" |
| 1 | worker | tests exercising the changed files, lint/typecheck scoped to `scope[]` | `worker-dev` | "is *this contribution* sane?" |
| 2 | integration | full lint + typecheck, unit suite, objective-relevant integration tests, repo standards gate, combined-diff review | `orchestrate-dev`, `deliver-dev` | "do the workers **compose**?" |
| 3 | delivery / CI | independent CI, cross-platform/build/security tests, release checks | CI, driven by `pr-dev` | final authority |

Tier 1 explicitly excludes an unconditional full-repository suite. "The repository is green"
is not knowable from inside one task, and paying for it in every task is what made workers
slow. A task may opt into a heavier check when its `scope[]` genuinely warrants it — a shared
core module, a generated-file contract — recorded per task, not as a blanket default.

CI's result outranks any local claim. A green local Tier 2 does not license merging past a
red Tier 3.

## Declaring a tier

**A validation step whose tier is unstated is a bug.**

Scripts declare it in the header comment:

```bash
#!/usr/bin/env bash
# validate-roles.sh — role/agent/schema consistency check.
# Validation tier: 0 (static parse + consistency; no test execution).
```

Skills declare it twice: in frontmatter as `metadata.tamirs.validation-tier` (`0`–`3`) and in
the body section that runs the validation. Tasks declare it as `validation_tier`
(`edit` | `worker` | `integration` | `delivery`) in `task-schema.json`, and each handoff
`validation[]` entry carries the tier it belongs to.

## Reporting rules

From [`core/policies/safety.md`](../../../core/policies/safety.md):

- Only commands that **actually ran** may be reported, with their real results.
- A deliberately skipped tier is reported as `skipped` **with a reason** — not omitted, and
  never reported as passing.
- A command that was not run must not appear in a handoff at all.

`handoff-schema.json` encodes this: `validation[].result` is `pass` | `fail` | `skipped`, and
`skipped` requires `skip_reason`.

## Where each tier lives in this repo

| Tier | Concrete commands |
|:--:|---|
| 0 | `jq empty <file>`, `bash -n <script>`, `python3 -c "import yaml; yaml.safe_load(...)"` |
| 1 | the repo's targeted test/lint invocation for the changed paths; `shellcheck` on a touched script |
| 2 | `make validate` (lint, hook tests, contract fixtures, manifest versions, platform equivalence, marketplace schema, doc claims, JSON parse, skill frontmatter) |
| 3 | `.github/workflows/ci.yml`, the release workflow, and per-platform CLI validation where a CLI exists |

The full picture of what runs where: [../build-and-release/testing-matrix.md](../build-and-release/testing-matrix.md).

## Anti-patterns

| Don't | Do |
|---|---|
| Run `make validate` in every worker | Tier 1 in workers, Tier 2 once at integration |
| Report a tier you skipped as passing | Report it as `skipped` with a reason |
| Claim CI passed because a local gate did | Tier 3 is independent by definition |
| Ship a script with no tier in its header | State the tier |
| Treat a red Tier 3 as a flake without evidence | Retry a *known* flake at most a bounded number of times; otherwise root-cause |
