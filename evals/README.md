# Plugin eval suite

Behavior tests for this plugin, run with [`claude plugin eval`](https://code.claude.com/docs/en/plugin-evals)
(requires Claude Code ≥ 2.1.269). Each case is a realistic prompt plus graders; every case
runs twice — once with the plugin loaded and once without — so the headline number is **Δ**
(uplift), not raw pass rate.

This is **not** the same harness as `skills/toolkit/skill-creator/evals/evals.json`, which is
skill-creator's own trigger-accuracy format. The two coexist and are not interchangeable.

## What this suite covers

Two flows, in two numbered blocks, each with its own negatives. They are not averaged into
one number in anyone's head: read the per-case `Δ`, and filter with `--tag` when you only
want one flow.

**`00`–`07` — `skill-creator`.** Authoring and repairing skills.

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

**`10`–`13` — `dev-workflow`.** The implement → hand off → deliver chain: `start-dev`,
`worker-dev`, `pr-dev`. Cases `10` and `12` read GitHub through the plugin's bundled `github`
MCP server, answered by the mocks in [`mocks/`](mocks/README.md) (see
[GitHub-dependent cases and mocks](#github-dependent-cases-and-mocks)).

| Case | Tag | What it measures |
|---|---|---|
| `10-start-dev-from-issue` | `fire`, `github` | `start-dev` fires on "implement issue #N"; reads the issue; sets the work up as objective/worktree state under `.dev-files/` (or a named branch/worktree); writes nothing else into the checkout; opens no PR |
| `11-worker-dev-handoff` | `fire` | `worker-dev` fires for one task of an objective; writes only inside `scope[]`; ends at a handoff file whose `status` is one of `completed`/`partial`/`failed`/`blocked` and whose `validation[]` is evidence, not a claim; opens no PR |
| `12-pr-dev-drive-to-green` | `fire`, `github` | `pr-dev` fires on "get it green and merged"; reads the PR's checks; names the failing required check; **never merges while it is red** |
| `13-neg-plain-question` | `negative` | A plain `git merge` vs `git rebase` question must **not** fire any dev-workflow skill, in either arm, and must write nothing |

Case names in the first column are the directory names; `--case <glob>` matches the `name`
in each `prompt.md`, which drops the numeric prefix (`--case 'pr-dev-*'`).

## Running it

```bash
# Full suite.
claude plugin eval . --ablation with-without --runs 3 \
  --judge-model sonnet --allow-tools Write --threshold 0.8

# One flow.
claude plugin eval . --tag dev-workflow --allow-tools Write --threshold 0.8

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
  `skills/<name>/SKILL.md` and `.dev-files/…`.

Add `--keep-temp` to preserve a run's workspace and `trace.jsonl` for debugging.

`bash tests/test-evals-suite.sh` checks the suite's *shape* without a model call — every
case has a prompt and a grader, every `llm` grader has a rubric, no case names `.claude/`,
negatives are tagged, the table above lists every case directory, mocks have a README. It
runs as part of `make validate`; the nightly run is the only place the cases execute.

### What a run consumes

Each "run" is a full `claude -p` child session, so the suite multiplies:
`cases × runs × 2 arms`, plus three judge votes per `llm` grader per run. `regex`,
`file_exists`, `tool_used` and `tool_order` graders are free, and so are the `type: fixed`
mocks.

On a **subscription login** nothing is billed — runs draw down your plan's usage limits, and
the figure the CLI prints is a list-price *estimate*, not an invoice. With an
`ANTHROPIC_API_KEY`, including in CI, the same runs bill for real; that is the one command
above worth a `--max-cost-usd` ceiling.

Measured: a 16-run pass (8 cases × 1 run × 2 arms) came to roughly $8 of estimated list price,
about **$0.50 per run**, so the full `--runs 3` suite of the first eight cases is ≈ **$24**.
Authoring cases dominate — they read, write and reason; the negatives and the canary are
cheap. The four dev-workflow cases are unmeasured; at the same per-run figure a 24-run
`--runs 1` pass of all twelve cases is ≈ **$12**, which is why the nightly runs `--runs 1`
under a `--max-cost-usd 30` ceiling.

## GitHub-dependent cases and mocks

`10-start-dev-from-issue` and `12-pr-dev-drive-to-green` need an issue and a pull request to
read. The plugin's `.mcp.json` declares one MCP server, `github`, and `claude plugin eval`
never starts a plugin's real servers unless asked; instead it registers a substitute under
the same name and answers each tool from `mocks/github/<tool>.md`. The mocks ship a fixed
issue (`acme/webapp#42`, rate limiting on `/login`) and a fixed PR (`acme/webapp#87`, one
required check `test (ubuntu-latest)` failing on the current head). Mocked tools need no
`--allow-tools` grant and no token; [`mocks/README.md`](mocks/README.md) lists every file,
how to capture the real server's `_tools.json`, and how to record `.replay/` answers if an
agent-style mock is ever added.

The skills themselves reach GitHub through the `gh` CLI first. The suite grants no `Bash`, so
inside a run the only GitHub path is the mocked server — which is the point: the cases grade
what the skill does with the state it can read, not whether `gh` is installed.

**Two arms, one server.** The without-plugin arm has no `github` server at all (the server is
the plugin's), so a grader that can only pass with the mocked data would push `W/OUT` to 0
and inflate `Δ` for a reason that has nothing to do with the skill. Those graders —
`reads-issue`, `reads-checks` and every `tool_used: Skill` — are marked `arm: with-only` and
reported as plugin-fired indicators, not scored. The **scored** graders in `10`–`12` are
behaviour on either path: state under `.dev-files/` or a named worktree before any code;
nothing written outside scope; an honest handoff status; the failing check named **or** an
explicit "I could not read the checks from here, this is what I would read"; and never a
merge, push or PR that did not happen. A negative `Δ` on these cases therefore means the
plugin made the agent less honest or more eager to merge/open on a red or unvalidated
change — a real finding — while a `Δ` near zero with the indicators passing means the flow
ran and the baseline was honest too.

**The "server unavailable" path is graded, not excused.** `--mocks off` without a token, a
tool with no mock file, and the without-arm all leave the agent with no GitHub; each case's
`llm` grader spells out what passes on that path and what fails (a fabricated check name, a
claimed merge). Read the rubric before changing a mock: the PR snapshot's check names and
the failing test are what `names-failing-check` matches against.

## Running in CI

The suite runs **nightly**, never on pull requests: a keyed run bills for real, the result is
noisy at `--runs 1`, and a PR gate that costs $12 per push and flakes would be disabled
within a week. `.github/workflows/evals.yml` is that workflow; its shape:

- **Trigger:** `schedule` (nightly cron) and `workflow_dispatch` for a manual run. No
  `pull_request`, no `push`.
- **Install:** a pinned Claude Code CLI (`.claude-code-version` is the baseline this repo's
  docs are written against) via npm on `ubuntu-latest`. No `bubblewrap`/`socat` is needed
  because the run grants only `Write`; the moment a case needs `Bash`, the sandbox backend
  must be installed on the runner or every run is refused.
- **Credential:** the `ANTHROPIC_API_KEY` repository secret. Nothing else from the
  environment reaches a run (the harness allowlists `PATH`, locale, proxy and `ANTHROPIC_*`/
  `CLAUDE_CODE_*`/`EVAL_*` variables only).
- **Command:** exactly the CI line in [Running it](#running-it), plus `--runs 1`:

  ```bash
  claude plugin eval . --trust-plugin --json results.json \
    --model claude-sonnet-5 --judge-model claude-haiku-4-5 \
    --allow-tools Write --threshold 0.8 --no-publish --max-cost-usd 30 --runs 1
  ```

  `--trust-plugin` answers the first-run trust prompt a non-interactive job cannot. Both
  models are pinned so a model rollout is not mistaken for a plugin regression. Exit `1` (a
  case below threshold, a load error, or a run that ended on an API error) fails the job;
  exit `2` (the cost ceiling was hit — `results.json` carries `partial: true`) fails it too,
  and the step summary says which.
- **Artifact:** `results.json` is uploaded with `if: always()` so a failed or partial run
  still leaves its evidence; `evals/results/<timestamp>/report.html` goes with it.
- **Job summary:** the per-case `WITH`, `W/OUT` and `Δ` are read out of `results.json`
  (`cases[].name`, `cases[].aggregates.score`, `cases[].aggregates.delta`) with `jq` and
  appended to `$GITHUB_STEP_SUMMARY` as a table, so the number that matters is readable
  from the run page without opening the artifact. `partial`/`partialReason` and
  `aggregates.meanDelta` go above the table.
- **Pinning:** every `uses:` is pinned to a commit SHA with the tag in a trailing comment,
  as `scripts/check-action-pinning.sh` requires of every workflow in the tree.

Treat the first keyed run after a change to any skill under test — or to a rubric — as a
calibration pass, not a measurement (see below). The threshold is a floor on `WITH`, not on
`Δ`: a case whose `Δ` goes negative does not fail the job on its own, so read the summary
table, not only the job's colour.

## What the suite currently reports

From the calibration pass of `00`–`07` (1 run per arm, `--judge-model sonnet`, 2026-09-22).
These are **graded measurements, not aspirations** — three of them were open findings about
the plugin, and two have since been fixed at the source (below).

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

`10`–`13` have **no measurement yet**: they were written on 2026-10-17 without an API key and
have not executed. Their first nightly run is a calibration pass; expect to tighten a rubric
or two, and do not read their first `Δ` as a finding about the plugin.

Three findings from the calibration pass, and what was done about them:

1. **`fix-weak-description` regressed (Δ −0.25).** Asked *"figure out why, and give me the
   fixed version"*, the no-plugin arm opened with *"Why it never fired: autodiscovery works
   off the frontmatter alone…"*. The with-plugin arm opened with a before/after table of what
   it changed and never explained the cause — the plugin answered the second half of the
   request and dropped the first. The grader was right.
   **Fixed at the source (2026-10-17):** `skill-creator`'s Description Optimization section
   now says to diagnose before fixing — state the cause (selection is the model's decision
   over `description` alone; the body is never read at that point) before showing the
   rewritten frontmatter. The `explains-why` grader already grades substance, not wording,
   and is unchanged. Unverified until the next keyed run.
2. **`research-skill-isolation` failed `context: fork` in BOTH arms.** Asked for a skill that
   does its digging *"off to the side without cluttering up my main conversation"*, neither
   arm reached for `context: fork` + `agent:`. skill-creator's frontmatter authority is its
   own `references/frontmatter-template.md`, and it did not steer toward the isolation
   fields.
   **Fixed at the source (2026-10-17):** the template gained a "When to fork" decision rule
   — fork when the skill digs, scans or reads broadly and the conversation needs its
   findings rather than its transcript, or the user asks for the work "off to the side" —
   with the agent types to name (`Explore`, `Plan`, `general-purpose`, or a custom agent)
   and a worked `env-var-trace` skeleton, and `SKILL.md`'s `context / agent` note points at
   it. The `agent-set` grader was widened from a three-name list to "any non-empty agent
   name", because the template now legitimately allows a custom agent and the substance
   being graded is that an agent is named, not which one. Unverified until the next keyed
   run.
3. **`neg-explain-only` was a grader bug, not a plugin one.** The with-plugin answer said
   *"there is no matcher — skill selection is a model decision over the injected
   descriptions"*, which is a **more** precise account than the rubric's own phrasing, and the
   judge failed it for not matching the wording. The rubric now accepts any substantively
   correct framing. Recorded here because it is the failure mode the docs warn about: suspect
   the judge before the plugin when Δ goes negative on an `llm` grader.

Every rubric in `00`–`07` was calibrated against real generated output on 2026-09-22.
Re-calibrate after any change to a skill under test, and treat the first run after such a
change as a calibration pass rather than a measurement.
