---
name: skill-creator
description: 'Use when creating or improving an Agent Skill (SKILL.md) for Claude Code, Cursor, Codex, Gemini CLI or OpenCode, fixing a skill that isn''t triggering, optimizing its description, or running skill evals/benchmarks. Writes portable skills first, then validates platform extensions. Triggers: ''make this a skill'', ''turn this into a skill'', ''write a SKILL.md'', ''my skill isn''t triggering'', ''skill keeps missing'', ''add evals to my skill'', ''benchmark my skill'', ''improve this skill'', ''create a new skill for X''.'
when_to_use: 'User wants to create a new SKILL.md from scratch, improve or rewrite an existing skill, fix a skill that under- or over-triggers, add test cases or evals, run a skill benchmark, or optimize the description for triggering accuracy. Key phrases: ''make this a skill'', ''skill isn''t triggering'', ''write a skill'', ''add evals'', ''benchmark this skill'', ''improve the description''.'
argument-hint: '[skill name or path to SKILL.md]'
arguments: []
disable-model-invocation: false
user-invocable: true
allowed-tools:
- Bash
- Read
- Write
- Edit
- Glob
- Grep
- WebFetch
- Skill
- Agent
disallowed-tools: []
model: claude-sonnet-4-6
effort: medium
context: ''
agent: ''
hooks: {}
paths: []
shell: bash
metadata:
  tamirs:
    visibility: public
    category: toolkit
    role: implementer
    validation-tier: 1
    updated-date: '2026-08-19'
    capabilities:
      required:
        - skills
        - shell
      optional:
        - subagents
        - parallel_subagents
        - background_tasks
    tags:
      - skill
      - authoring
      - evals
      - triggering
      - portable
      - schema
  capability: toolkit
  updated-date: '2026-08-19'
---

# Skill Creator

## Why this skill exists

Agent Skills are the primary mechanism for capturing and reusing complex workflows, and they
are consumed by more than one harness: Claude Code and Claude Desktop, Cursor, Codex CLI,
Gemini CLI and OpenCode all read `SKILL.md`. A poorly written skill either never triggers
(bad description), or triggers but produces inconsistent results (bad body). Most naive
attempts produce thin SKILL.md files with vague descriptions and no test coverage — they feel
done but fail in practice. This skill provides the full create → test → evaluate → improve
loop to get skills to production quality.

**Portable first.** Write the Agent Skills core that every harness reads, then add platform
extensions where they genuinely help. The reverse order — start from Claude's full field set
and hope it degrades — produces skills that carry a vendor's shape everywhere and still fail
on the platforms that ignore it.

## Assess where the user is

Before doing anything, determine which phase the user is in:

| Situation | Start here |
|---|---|
| "I want to make a skill for X" | [Capture Intent](#1-capture-intent) |
| "Turn this conversation into a skill" | Extract from conversation history, then [Write SKILL.md](#3-write-the-skillmd) |
| "I already have a draft" | [Run and Evaluate](#running-and-evaluating-test-cases) |
| "My skill isn't triggering" | [Description Optimization](#description-optimization) |
| "The skill is wrong / produces bad output" | [Improve the Skill](#improving-the-skill) |

---

## Creating a Skill

### 1. Capture Intent

Extract answers — from conversation history first, then by asking the user:

1. What should this skill enable Claude to do?
2. When should it trigger? (exact phrases, contexts)
3. What is the expected output format?
4. Does it need test cases? (objectively verifiable outputs → yes; purely subjective/style → often no)

If the conversation already demonstrates the workflow (tools used, sequence, corrections), extract the pattern from it and confirm the gaps with the user before drafting.

### 2. Interview and Research

Clarify edge cases, input/output formats, example files, success criteria, and external dependencies. Do not write test prompts until this is resolved.

Use available MCP tools or subagents to research similar skills or relevant docs in parallel if helpful.

### 3. Write the SKILL.md — portable core first

The canonical contract is **`core/schemas/skill-frontmatter.json`**, and the executable form
is `scripts/validate-skill-frontmatter.py`. Read `references/frontmatter-template.md` for the
full field-by-field guide and skeletons. **Never invent a competing schema** — if something
seems missing, the schema is the place to change it.

Three tiers, written in this order:

**Tier 1 — portable core (required on every skill, every platform).**

```yaml
name: my-skill        # kebab-case, equals the directory name
description: >-       # what it does AND when to use it, ≤1536 chars
  Use when … Triggers: 'phrase one', 'phrase two'.
```

Optionally `license`, and `compatibility` when the skill is genuinely not universal.

**The trigger phrases must live in `description`.** On any platform without `when_to_use`,
`description` is the *only* trigger signal. A skill whose triggers exist only in the Claude
field is invisible to auto-invocation everywhere else — the single most common portability
bug in a skill.

**Tier 2 — `metadata.tamirs` (this framework's semantics).**

```yaml
metadata:
  tamirs:
    visibility: public | internal
    category: <domain dir under skills/>
    role: <role from core/roles/, or none>
    validation-tier: 0 | 1 | 2 | 3
    updated-date: 'YYYY-MM-DD'
    capabilities:
      required: [...]     # ids from core/capabilities/schema.json ONLY
      optional: [...]
```

Declare capabilities **honestly**: `required` means the skill cannot do its job without it
and must stop on a platform that lacks it; `optional` means there is a real fallback written
in the body. Padding `required` makes a working skill falsely unavailable; under-declaring
makes it fail silently. Every id must exist in the registry — invented ids fail validation
by design.

**Tier 3 — platform extensions (optional, never universally required).**

Claude Code fields (`when_to_use`, `argument-hint`, `arguments`, `user-invocable`,
`disable-model-invocation`, `allowed-tools`, `disallowed-tools`, `model`, `effort`,
`context`, `agent`, `hooks`, `paths`, `shell`) are permitted because every other harness
ignores unknown keys. Add the ones the skill actually uses. **Do not fill in all sixteen to
satisfy a validator** — that requirement no longer exists, and padding them communicates
nothing.

Key authoring notes:

- **name**: kebab-case, matches the directory name
- **description**: start with "Use when…" — triggering conditions only, never workflow
  description. Include synonyms, error-message fragments, command names. Skills undertrigger
  by default, so lean slightly pushy.
- **when_to_use** (Claude): 3–5 concrete phrases a user would type. An *addition* to
  `description`, never a replacement for its triggers.
- **allowed-tools**: exhaustive list of every tool the body actually uses
- **model**: omit unless there is a specific reason — a pinned model id ages
- **context / agent**: `''` unless `context: fork`, which requires a non-empty `agent`
- **user-invocable: false** requires `disable-model-invocation: true`

#### Validate across the tiers

```bash
# portable core enforced; metadata.tamirs validated when present
python3 scripts/validate-skill-frontmatter.py path/to/SKILL.md

# make the tamirs block mandatory (what CI runs for this repo's own skills)
python3 scripts/validate-skill-frontmatter.py --require-tamirs path/to/SKILL.md

# legacy gate: every official Claude field required, exactly as before the portable split
python3 scripts/validate-skill-frontmatter.py --profile claude-strict path/to/SKILL.md
```

`--profile claude-strict` exists so nothing that passed before the split regresses. It is not
the default, and it is not a reason to pad a new skill.

#### Per-platform extension validation

Portable validity is necessary, not sufficient. Before claiming a target in `compatibility`, check the skill's extensions against it — see **`references/platform-extensions.md`** for the per-target checklist and the rule that decides when a Claude-only field may stay in the canonical file.

#### Skill directory anatomy

```
skill-name/
├── SKILL.md          (required — frontmatter + instructions)
├── scripts/          (executable Python/Bash for deterministic tasks)
├── references/       (docs loaded into context as needed)
└── assets/           (templates, HTML, icons used in output)
```

#### Loading hierarchy

| Level | Content | When in context |
|---|---|---|
| Metadata | name + description | Always (~100 words) |
| SKILL.md body | Full instructions | When skill triggers |
| Bundled resources | scripts/, references/, assets/ | Explicitly loaded or executed |

Keep SKILL.md under 500 lines. If approaching that limit, split content into `references/` files and add explicit pointers in SKILL.md for when to read them.

#### Writing patterns

Use imperative form. Explain the *why* behind each instruction — models that understand reasoning generalize better than models following rigid rules.

For output templates, use exact markdown blocks:
```markdown
## Report structure
ALWAYS use this exact template:
# [Title]
## Executive summary
## Key findings
```

For examples:
```markdown
## Commit message format
Input: Added user authentication with JWT tokens
Output: feat(auth): implement JWT-based authentication
```

### 4. Write Test Cases

After drafting the skill, create 2-3 realistic test prompts. Share with the user for sign-off. Save to `evals/evals.json` (prompts only — no assertions yet):

```json
{
  "skill_name": "example-skill",
  "evals": [
    {
      "id": 1,
      "prompt": "User's actual task prompt",
      "expected_output": "Description of expected result",
      "files": []
    }
  ]
}
```

See `references/schemas.md` for the full schema including the `assertions` field added in the next step.

---

## Running and Evaluating Test Cases

This is one continuous sequence — do not stop partway.

### Capability check — do this before Step 1

The eval harness is the most capability-hungry part of this skill. Resolve each capability
against `core/capabilities/platforms.json` for the current platform, and pick the mode below.
Do **not** discover a missing capability halfway through a benchmark run.

| Capability | Have it | Missing — fallback |
|---|---|---|
| `parallel_subagents` | Spawn with-skill and baseline in the same turn (Step 1) | Run them sequentially, and **report the timing comparison as unreliable** — sequential runs share no scheduling conditions. Correctness comparison is still valid; timing is not |
| `subagents` | Isolated runs, clean per-run token accounting | Run inline in the current session. Token and duration figures are then session totals, not per-run — say so, and do not populate `timing.json` with numbers you cannot attribute |
| `background_tasks` | Launch the eval viewer as a server | Use `--static <path>` to write a standalone HTML file |
| `shell` | Everything below | Without shell there is no eval harness at all — author and validate the skill, and say plainly that evals could not be run |

**Never fabricate a benchmark.** If the platform cannot produce a number, the number is
absent, not estimated. A benchmark table with invented timings is worse than no table: it
looks like evidence.

Record the mode in `benchmark.json` under `run_mode` (`parallel-subagents`,
`sequential-subagents`, or `inline`) so a later reader knows what the numbers mean.

Workspace layout: `<skill-name>-workspace/` as a sibling to the skill directory, organized as `iteration-1/`, `iteration-2/`, etc. Within each iteration: `eval-<name>/with_skill/outputs/` and `eval-<name>/without_skill/outputs/` (or `old_skill/outputs/` when improving an existing skill).

### Step 1 — Spawn all runs in the same turn

For each test case, spawn two subagents simultaneously (with-skill AND baseline). Do not do
with-skill first and baseline later.

*Requires `parallel_subagents`.* Without it, follow the fallback from the capability check
above and mark the timing comparison unreliable — do not silently produce a timing table
from sequential runs.

**With-skill subagent prompt:**
```
Execute this task:
- Skill path: <absolute-path-to-skill-directory>
- Task: <eval prompt>
- Input files: <eval files, or "none">
- Save outputs to: <workspace>/iteration-<N>/eval-<name>/with_skill/outputs/
```

**Baseline subagent prompt:**
- New skill: no skill path, save to `without_skill/outputs/`
- Improving existing skill: snapshot first (`cp -r <skill-path> <workspace>/skill-snapshot/`), point baseline at snapshot, save to `old_skill/outputs/`

Write `eval_metadata.json` in each eval directory:
```json
{
  "eval_id": 0,
  "eval_name": "descriptive-name-not-eval-0",
  "prompt": "The user's task prompt",
  "assertions": []
}
```

### Step 2 — Draft assertions while runs are in progress

Do not wait idle. Draft quantitative assertions for each test case. Good assertions are objectively verifiable and have descriptive names. Subjective skills (writing style, design) → focus on qualitative review, not assertions.

Update `eval_metadata.json` and `evals/evals.json` with drafted assertions.

### Step 3 — Capture timing data on completion

*Requires `subagents`.* On Claude Code, a subagent completion notification carries
`total_tokens` and `duration_ms`. Save it immediately to `timing.json` in the run directory —
this data is not persisted anywhere else.

Where no such notification exists, **omit `timing.json` rather than filling it in**. A
missing file is a legible "not measured here"; a fabricated one silently corrupts every
comparison built on top of it. Note the omission in `benchmark.json` → `run_mode`.

```json
{
  "total_tokens": 84852,
  "duration_ms": 23332,
  "total_duration_seconds": 23.3
}
```

### Step 4 — Grade, aggregate, launch viewer

**Grade**: Spawn a grader subagent per `agents/grader.md` — or, without `subagents`, run
`agents/grader.md` inline as instructions in the current session. The grading contract is
identical; only the isolation differs, and grading does not depend on isolation the way
timing does. Save results to `grading.json`. Required fields: `text`, `passed`, `evidence` (not `name`/`met`/`details`). For assertions checkable programmatically, write and run a script.

**Aggregate**:
```bash
python -m scripts.aggregate_benchmark <workspace>/iteration-N --skill-name <name>
```

**Analyst pass**: Read `agents/analyzer.md` → look for non-discriminating assertions (always
pass), high-variance evals (flaky), time/token tradeoffs. Skip the time/token half of that
analysis when `run_mode` is not `parallel-subagents` — those numbers are not comparable, and
analysing them anyway manufactures conclusions from noise.

**Launch viewer**:
```bash
nohup python <skill-creator-path>/eval-viewer/generate_review.py \
  <workspace>/iteration-N \
  --skill-name "my-skill" \
  --benchmark <workspace>/iteration-N/benchmark.json \
  > /dev/null 2>&1 &
VIEWER_PID=$!
```

For iteration 2+, add `--previous-workspace <workspace>/iteration-<N-1>`.

**Headless/no-display environments**: Use `--static <output_path>` to write a standalone HTML file. Feedback downloads as `feedback.json` when the user clicks "Submit All Reviews".

Generate the viewer **before** evaluating outputs yourself — get results in front of the human first.

Tell the user: "Results are open in your browser. 'Outputs' tab: click through test cases and leave feedback. 'Benchmark' tab: quantitative comparison. Come back when you're done."

### Step 5 — Read feedback and improve

```bash
# feedback.json location after user submits review
cat <workspace>/iteration-N/feedback.json
```

```json
{
  "reviews": [
    {"run_id": "eval-name-with_skill", "feedback": "chart is missing axis labels", "timestamp": "..."},
    {"run_id": "eval-name-with_skill", "feedback": "", "timestamp": "..."}
  ],
  "status": "complete"
}
```

Empty feedback = the user was satisfied with that case. Focus on cases with specific complaints. Kill the viewer server when done:
```bash
kill $VIEWER_PID 2>/dev/null
```

---

## Improving the Skill

### How to think about improvements

1. **Generalize from feedback.** The skill runs at scale — do not make overly narrow fixes for specific test examples. If a pattern keeps failing, try a different framing or metaphor rather than adding another rigid constraint.

2. **Keep the prompt lean.** Read the run transcripts (not just final outputs) to find where the model spends time on unproductive steps. Remove skill instructions that cause those steps.

3. **Explain the why.** Model the reasoning behind each requirement rather than stacking MUST/NEVER rules. Models that understand intent generalize better.

4. **Bundle repeated work.** If all test runs independently wrote a similar helper script (`create_docx.py`, `build_chart.py`), put it in `scripts/` and tell the skill to use it.

### Iteration loop

After each improvement:
1. Apply changes to the skill
2. Rerun all test cases into `iteration-<N+1>/`
3. Launch reviewer with `--previous-workspace` pointing at the previous iteration
4. Wait for user review, read new feedback, improve again

Stop when:
- The user says they're satisfied
- All feedback is empty
- No meaningful progress across two iterations

---

## Description Optimization

After the skill body is finalized, optimize the `description` for triggering accuracy — this
is the field every platform reads, so it is where triggering is won or lost.

Full procedure (trigger eval set, review UI, the `run_loop.py` optimisation loop, and the
capability limits — it needs the `claude` CLI and is unavailable elsewhere) is in
**`references/description-optimization.md`**. Read it when you reach this phase.

## Hard Rules

- **Portable core first.** `name` + `description` are the contract every platform reads; the trigger phrases belong in `description`, not only in the Claude `when_to_use`.
- **Never require all 16 Claude fields.** They are optional extensions. Add the ones the skill uses; padding the rest communicates nothing and is no longer validated.
- **Never invent a schema.** `core/schemas/skill-frontmatter.json` is canonical. Extend it there, never around it.
- **Declare capabilities honestly.** `required` = the skill stops without it; `optional` = there is a real fallback in the body. Every id must exist in the registry.
- **Never claim `compatibility: supported` without evidence.** Use `partial`, or omit the row and say it is unverified.
- **Never fabricate a benchmark number.** Absent is a legitimate value; invented is not. Record `run_mode` so numbers are read correctly.
- **Never add `user-invocable: false` or `disable-model-invocation: true` unless the skill is genuinely internal** — these block user invocation permanently, and also block sub-agent and orchestration invocation.
- **Never hardcode absolute paths** (`/Users/<name>/`) in SKILL.md; use `$CLAUDE_SKILL_DIR`, `$CLAUDE_PLUGIN_ROOT`, or relative paths.
- **Always run the eval viewer before evaluating outputs yourself** — human review must happen before model revision.
- **Always spawn with-skill and baseline subagents in the same turn** where `parallel_subagents` exists — sequential spawning gives misleading timing comparisons. Where it does not exist, run sequentially and mark the timing comparison unreliable rather than presenting it as sound.
- **Capture `timing.json` from the task notification immediately** — it is not persisted anywhere else.
- **`grading.json` must use fields `text`, `passed`, `evidence`** — the viewer depends on exact field names; `name`/`met`/`details` will break the display.
- **Do not use `/skill-test` or any other testing skill** — this skill manages its own test execution.

## What NOT to Do

- Writing test prompts before understanding edge cases — leads to low-signal evals
- Spawning with-skill runs first and baseline runs after — invalidates timing comparison
- Adding MUST/NEVER rules without explaining the reason — models overgeneralize and break adjacent cases
- Making overly narrow skill edits that fix one test example but overfit — generalize the pattern instead
- Describing skill output/workflow in the `description` frontmatter field — description must be triggering conditions only

---

## Capability awareness — what runs where

Resolve these from `core/capabilities/platforms.json` for the platform in hand rather than
from the table below; the table is orientation, the registry is the answer.

| Feature | Capability it needs | Without it |
|---|---|---|
| Authoring + portable validation | `skills` | — this is the floor; it works everywhere |
| Parallel with-skill/baseline runs | `parallel_subagents` | Sequential; timing comparison unreliable, correctness still valid |
| Isolated runs, per-run token accounting | `subagents` | Inline; omit `timing.json` rather than inventing it |
| Browser eval viewer | `background_tasks` | `--static <path>` standalone HTML |
| Description optimisation (`run_loop.py`) | `shell` + the `claude` CLI | Not available — review the description by hand against the trigger eval set; do not simulate scores |
| Packaging (`package_skill.py`) | `shell` | Not available |

Two rules hold in every mode:

1. **Never claim a capability the platform does not have.** State the mode, state what it
   costs, proceed with the fallback.
2. **Never fabricate a measurement.** Absent is a legitimate value; invented is not.

**Read-only install paths.** Some surfaces install skills read-only. Copy to a writable
directory, edit and package from the copy, and hand the user the resulting artifact.

---

## Reference Files

| File | Purpose |
|---|---|
| `references/frontmatter-template.md` | The three-tier frontmatter contract, field by field, with skeletons |
| `references/platform-extensions.md` | Per-target extension validation checklist |
| `references/schemas.md` | JSON schemas for evals.json, grading.json, benchmark.json |
| `agents/grader.md` | Grading instructions — run as a subagent, or inline where subagents are unavailable |
| `agents/comparator.md` | Blind A/B comparison between two outputs |
| `agents/analyzer.md` | Benchmark result analysis patterns |
| `assets/eval_review.html` | Template for trigger eval review UI |
