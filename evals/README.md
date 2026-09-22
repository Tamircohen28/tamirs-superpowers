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
| `03-fix-weak-description` | `fire` | Repairs a skill that never auto-triggers, and explains why |
| `04-turn-this-into-a-skill` | `fire` | Multi-step workflow → structured skill directory |
| `05-external-distribution` | `fire` | Respects the six-field frontmatter limit for claude.ai upload |
| `06-neg-find-not-create` | `negative` | Must **not** fire when the user wants to *find* a skill |
| `07-neg-explain-only` | `negative` | Must **not** fire when the user wants an explanation |

## Running it

Start here. This is the subset that produces meaningful signal today — see
[Known defect](#known-defect--why-the-fire-cases-currently-score-0).

```bash
# ~18 runs. The canary plus both negative cases.
claude plugin eval . --tag canary --tag negative \
  --allow-tools Write --judge-model sonnet --threshold 0.8
```

The full suite is a deliberate, occasional run — until the hook defect below is fixed, its
five `fire` cases score ~0 in both arms and tell you nothing about skill quality:

```bash
# ~48 runs.
claude plugin eval . --ablation with-without --runs 3 \
  --judge-model sonnet --allow-tools Write --threshold 0.8 --max-cost-usd 30
```

```bash
# CI — pin both models so a model rollout isn't mistaken for a regression.
claude plugin eval . --trust-plugin --json results.json \
  --model claude-sonnet-5 --judge-model claude-haiku-4-5 \
  --allow-tools Write --threshold 0.8 --no-publish --max-cost-usd 30
```

`Write` cannot be granted by a case's `allowed_tools` or by a skill's own `allowed-tools`
frontmatter — only the operator grants it, and that grant applies to **both arms**, which is
what keeps Δ honest.

Use `--judge-model sonnet`: the default judge is haiku, which marks correct-but-differently-
formatted output as wrong. Add `--keep-temp` to inspect a run's workspace and `trace.jsonl`.

### What a run actually costs

Each "run" is a full `claude -p` child session, so the suite multiplies fast:
`cases × runs × 2 arms`, plus three judge votes per `llm` grader per run. `regex`,
`file_exists`, `tool_used` and `tool_order` graders are free.

On a **subscription login** no card is charged — runs consume your plan's usage limits, and
the dollar figure the CLI prints is a list-price *estimate*, not a bill. With an
`ANTHROPIC_API_KEY`, including in CI, the same runs are billed for real.

Measured on this plugin: **≈ $0.58 per run** at list price, and runs with the plugin loaded
cost **2–4× more** than the no-plugin arm (canary: $0.07 without, $0.23 with).

## Known defect — why the `fire` cases currently score ~0

`hooks/enforce-worktree-edits.sh` denies **every** write in an eval sandbox, in both the
authoring cases and the canary.

The eval harness creates the sandbox home as a git repo (`home/.git`). The workspace `cwd`
sits inside it, so the hook's `is_git_repo` early-out does not fire and it demands a
registered worktree. But worktree isolation is unavailable in the harness
(`Agent isolation: worktree` → *"worktree isolation is unavailable in this session (plugin
evaluation harness)"*), no `Bash` is granted to create one by hand, and out-of-workspace
paths such as `~/.claude/worktrees/` are denied by the sandbox. The agent correctly refuses
to route around the guardrail and writes nothing.

Measured: `00-canary-can-write` scores **1.00 without the plugin and 0.00 with it — Δ −1.00**
on creating a one-word file.

This is not eval-specific. The hook has no degraded path, so it denies all writes in any git
repo where worktree creation fails — a CI checkout, a container, or a repo where
`git worktree add` is unavailable.

Until that is fixed, treat the `fire` cases as a **regression gate that is red by design**:
they document the defect reproducibly and will begin measuring skill quality, with no
rework, the moment the hook grows a degraded path.

Their graders have never been calibrated against real generated output, because no run has
produced any. Treat the first green run as a fresh calibration pass and expect to revise the
rubrics then.
