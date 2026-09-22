# Plugin eval suite

Behavior tests for this plugin, run with [`claude plugin eval`](https://code.claude.com/docs/en/plugin-evals)
(requires Claude Code ≥ 2.1.269). Each case is a realistic prompt plus graders; every case
runs twice — once with the plugin loaded and once without — so the headline number is **Δ**
(uplift), not raw pass rate.

This is **not** the same harness as `skills/toolkit/skill-creator/evals/evals.json`, which is
skill-creator's own trigger-accuracy format. The two coexist and are not interchangeable.

## What this suite covers

One flow: **`skill-creator`**. One suite, one flow — mixing skills would produce an average
that describes neither.

| Case | Tag | What it measures |
|---|---|---|
| `00-canary-can-write` | `canary` | That the plugin does not prevent Claude from writing a file at all |
| `01-new-skill-from-workflow` | `fire` | Builds a skill from a described process; description carries real trigger phrases |
| `02-research-skill-isolation` | `fire` | Picks `context: fork` + `agent:` for a research-shaped skill |
| `03-fix-weak-description` | `fire` | Repairs a skill that never auto-triggers, **and explains why** |
| `04-turn-this-into-a-skill` | `fire` | Multi-step workflow → structured skill directory |
| `05-external-distribution` | `fire` | Respects the six-field frontmatter limit for claude.ai upload |
| `06-neg-find-not-create` | `negative` | Must **not** fire when the user wants to *find* a skill |
| `07-neg-explain-only` | `negative` | Must **not** fire when the user wants an explanation |

## Running it

```bash
# Full suite.
claude plugin eval . --ablation with-without --runs 3 \
  --judge-model sonnet --allow-tools Write --threshold 0.8

# Fast subset while iterating on graders.
claude plugin eval . --tag canary --tag negative \
  --allow-tools Write --judge-model sonnet --threshold 0.8

# CI — pin both models so a model rollout isn't mistaken for a regression.
claude plugin eval . --trust-plugin --json results.json \
  --model claude-sonnet-5 --judge-model claude-haiku-4-5 \
  --allow-tools Write --threshold 0.8 --no-publish --max-cost-usd 30
```

Three things that are easy to get wrong:

- **`--allow-tools Write` is required.** `Write`, `Edit` and `Bash` cannot be granted by a
  case's `allowed_tools` **or** by a skill's own `allowed-tools` frontmatter. Only the
  operator grants them, and that grant reaches **both arms** — which is exactly what keeps Δ
  honest. Without it every authoring case scores 0 in both arms.
- **Use `--judge-model sonnet`.** The default judge is haiku, which marks
  correct-but-differently-formatted answers wrong.
- **Don't write cases under `.claude/`.** It is a protected path in the run sandbox and every
  write to it is denied, which looks exactly like the plugin failing. Cases here write to
  `skills/<name>/SKILL.md`.

Add `--keep-temp` to preserve a run's workspace and `trace.jsonl` for debugging.

### What a run consumes

Each "run" is a full `claude -p` child session, so the suite multiplies:
`cases × runs × 2 arms`, plus three judge votes per `llm` grader per run. `regex`,
`file_exists`, `tool_used` and `tool_order` graders are free.

On a **subscription login** nothing is billed — runs draw down your plan's usage limits, and
the figure the CLI prints is a list-price *estimate*, not an invoice. With an
`ANTHROPIC_API_KEY`, including in CI, the same runs bill for real; that is the one command
above worth a `--max-cost-usd` ceiling.

Measured: a 16-run pass (8 cases × 1 run × 2 arms) came to roughly $8 of estimated list price,
about **$0.50 per run**, so the full `--runs 3` suite is ≈ **$24**. Authoring cases dominate —
they read, write and reason; the negatives and the canary are cheap.

## What the suite currently reports

From the calibration pass (1 run per arm, `--judge-model sonnet`). These are **graded
measurements, not aspirations** — three of them are open findings about the plugin.

| Case | WITH | W/OUT | Δ |
|---|---|---|---|
| `canary-can-write` | 1.00 | 1.00 | 0.00 |
| `new-skill-from-workflow` | 1.00 | 1.00 | 0.00 |
| `research-skill-isolation` | 0.50 | 0.50 | 0.00 |
| `fix-weak-description` | 0.75 | 1.00 | **−0.25** |
| `turn-this-into-a-skill` | 1.00 | 0.86 | **+0.14** |
| `external-distribution` | 1.00 | 1.00 | 0.00 |
| `neg-find-not-create` | 1.00 | 1.00 | 0.00 |
| `neg-explain-only` | 0.67 | 1.00 | −0.33 → rubric fixed since |

Three findings worth acting on:

1. **`fix-weak-description` regresses (Δ −0.25).** Asked *"figure out why, and give me the
   fixed version"*, the no-plugin arm opens with *"Why it never fired: autodiscovery works off
   the frontmatter alone…"*. The with-plugin arm opens with a before/after table of what it
   changed and never explains the cause. The plugin answers the second half of the request
   well and drops the first. The grader is right; this is a real regression.
2. **`research-skill-isolation` fails `context: fork` in BOTH arms.** Asked for a skill that
   does its digging *"off to the side without cluttering up my main conversation"*, neither
   arm reaches for `context: fork` + `agent:`. skill-creator's frontmatter authority is its
   own `references/frontmatter-template.md`, and it does not steer toward the isolation
   fields. Δ 0.00 here means the plugin adds nothing on a feature it is well placed to know.
3. **`neg-explain-only` was a grader bug, not a plugin one.** The with-plugin answer said
   *"there is no matcher — skill selection is a model decision over the injected
   descriptions"*, which is a **more** precise account than the rubric's own phrasing, and the
   judge failed it for not matching the wording. The rubric now accepts any substantively
   correct framing. Recorded here because it is the failure mode the docs warn about: suspect
   the judge before the plugin when Δ goes negative on an `llm` grader.

Every rubric here was calibrated against real generated output on 2026-09-22. Re-calibrate
after any change to `skill-creator`, and treat the first run after such a change as a
calibration pass rather than a measurement.
