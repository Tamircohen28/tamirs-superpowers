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

## Three measurable trust gates (V5 Phase 4)

Three gates turn claims the repo used to make in prose — "the skills follow the Agent
Skills spec", "the plugin is cheap to load", "every skill has evals" — into numbers a CI
job asserts. Each one is designed to be seen failing: `tests/test-skill-budget.sh` plants
the condition every gate exists to catch and asserts it fires, beside the clean case.

| Gate | Tier | What it catches | Run | Lives in CI |
|---|:--:|---|---|---|
| Agent Skills reference validator | 2 | a `name` that is not the folder name, a name outside `[a-z0-9-]`/64 chars, a description over 1,024 chars, an undocumented frontmatter field | `bash scripts/check-skills-ref.sh` | `skill-contract` job, after `tests/test-skill-contract.sh` |
| Always-on token budget | 3 | the plugin's always-on context cost growing past a committed baseline or a hard ceiling | `bash scripts/check-token-budget.sh` | `plugin-validate` job (needs the Claude Code CLI with the plugin installed from the checkout) |
| Strict eval coverage | 2 | a public skill without positive-trigger, negative-trigger, behavior or (where it declares optional capabilities) fallback evals | `bash tests/test-skill-contract.sh --strict` | `skill-contract` job, as its own step |

Make targets: `check-skills-ref`, `check-token-budget`, `test-skill-contract-strict`.

### Agent Skills reference validator — `scripts/check-skills-ref.sh`

`scripts/validate-skill-frontmatter.py` is the executable form of this repo's own schema;
it is not the spec. `skills-ref` (the reference library behind agentskills.io, pinned at
`0.1.5` and run through `npx`) is, and it enforces three things ours does not: `name` must
equal the parent directory name and match the spec's character and length rules,
`description`/`compatibility` are measured against the spec's limits, and the frontmatter
is closed to the portable set (`name`, `description`, `license`, `compatibility`,
`metadata`, `allowed-tools`).

Two findings are expected on this tree today and are printed as `div` (divergence), not
failure: every skill ships Claude's documented extension fields (`effort`,
`user-invocable`, `context`, …), accepted only when each field is a top-level property in
`core/schemas/skill-frontmatter.json`; and five skills declare `compatibility` as the
platform → support-level map the schema deliberately requires where the spec wants a
string. Both are reported per skill on every run and `--spec-strict` promotes them to
failures; closing them is a schema decision, not a per-skill patch. Everything else the
validator reports fails the run. Offline, the script prints `skills-ref: SKIP (offline)`
and exits 0 — only when `npm ping` fails; any other inability to run the tool is an error,
so a missing network can never read as a passing validation. The script names a package
launcher, so it is pruned from the Claude distribution; it is a contributor/CI tool.

### Always-on token budget — `scripts/check-token-budget.sh` and `evals/budget.json`

`claude plugin details tamirs-superpowers` prints `Projected token cost` /
`Always-on: ~N tok`: the context every session pays before any skill fires (the name,
description and `when_to_use` of every skill and agent; hooks and MCP schemas are not
counted). The official marketplace highlights that figure to users once it reaches 2,000
tokens. `evals/budget.json` commits the last accepted measurement:

```json
{ "always_on_tokens": N, "ceiling": C, "tolerance_percent": 10,
  "measured_on": "<claude --version>", "measured_at": "YYYY-MM-DD", "note": "..." }
```

The script fails when the measured figure exceeds `ceiling`, or exceeds
`always_on_tokens` by more than `tolerance_percent`, or when the CLI output does not
contain exactly one `Always-on: ~N tok` line (a shape change fails loudly; nothing is ever
parsed as 0). It also refuses to measure an install that reads from a different checkout
than the one being checked. The ceiling sits at the measured figure rounded up to the
next 500 because the tree is already far above 2,000; the `note` field records that 2,000
is the figure to drive down to. **Update the baseline** in the same PR that changes the
cost, so the diff shows the number beside its cause:

```bash
bash scripts/check-token-budget.sh --update   # rewrites always_on_tokens, measured_on, measured_at
```

`--update` never raises the ceiling; lower it by hand as the cost comes down and never
raise it without a note. `--from <file>` reads a saved `claude plugin details` output
instead of the CLI, which is how the test exercises the gate on a machine without one.

### Strict eval coverage — `tests/test-skill-contract.sh --strict`

Without `--strict`, eval coverage is a report. With it, a public skill missing any of
positive-trigger, negative-trigger or behavior evals fails, and a skill that declares
`metadata.tamirs.capabilities.optional` must also carry a fallback eval: a case whose
prompt removes the optional capability and whose expected output is the degraded path the
skill's own body documents (its "Degrades" or "Fallback when … is missing" section), not a
refusal and not a claim of the capability it did not have. Coverage is detected from the
skill's `evals/evals.json` and `evals/trigger-evals.json`; a fallback eval is recognised by
the words it necessarily uses (`fallback`, `degrade`, `unsupported`, `not available`, …).
Add the missing eval; never satisfy the gate by dropping the optional capability.

## Anti-patterns

| Don't | Do |
|---|---|
| Run `make validate` in every worker | Tier 1 in workers, Tier 2 once at integration |
| Report a tier you skipped as passing | Report it as `skipped` with a reason |
| Claim CI passed because a local gate did | Tier 3 is independent by definition |
| Ship a script with no tier in its header | State the tier |
| Treat a red Tier 3 as a flake without evidence | Retry a *known* flake at most a bounded number of times; otherwise root-cause |
