---
name: skill-creator
description: "Use when creating or improving a Claude Code skill (SKILL.md), fixing a skill that isn't triggering, optimizing its description, or running skill evals/benchmarks. Triggers: 'make this a skill', 'turn this into a skill', 'write a SKILL.md', 'my skill isn't triggering', 'skill keeps missing', 'add evals to my skill', 'benchmark my skill', 'improve this skill', 'create a new skill for X'."
when_to_use: "User wants to create a new SKILL.md from scratch, improve or rewrite an existing skill, fix a skill that under- or over-triggers, add test cases or evals, run a skill benchmark, or optimize the description for triggering accuracy. Key phrases: 'make this a skill', 'skill isn't triggering', 'write a skill', 'add evals', 'benchmark this skill', 'improve the description'."
argument-hint: "[skill name or path to SKILL.md]"
model: claude-sonnet-4-6
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
metadata:
  capability: meta
  tags:
    - skill
    - authoring
    - evals
    - triggering
  updated-date: "2026-06-16"
---

# Skill Creator

## Why this skill exists

Claude Code skills are the primary mechanism for capturing and reusing complex workflows. A poorly written skill either never triggers (bad description), or triggers but produces inconsistent results (bad body). Most naive attempts at skill creation produce thin SKILL.md files with vague descriptions and no test coverage — they feel done but fail in practice. This skill provides the full create → test → evaluate → improve loop to get skills to production quality.

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

### 3. Write the SKILL.md

Fill in the frontmatter first:

- **name**: kebab-case, matches directory name
- **description**: Start with "Use when..." — triggering conditions only. Include synonyms, error message fragments, command names. Skills undertrigger by default — lean slightly pushy. Under 500 chars.
- **model**: `claude-sonnet-4-6` unless there is a specific reason for another
- **allowed-tools**: exhaustive list of every tool the skill body actually uses
- **when_to_use**: 3-5 concrete trigger phrases a user would type
- **metadata.updated-date**: today's date

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

Workspace layout: `<skill-name>-workspace/` as a sibling to the skill directory, organized as `iteration-1/`, `iteration-2/`, etc. Within each iteration: `eval-<name>/with_skill/outputs/` and `eval-<name>/without_skill/outputs/` (or `old_skill/outputs/` when improving an existing skill).

### Step 1 — Spawn all runs in the same turn

For each test case, spawn two subagents simultaneously (with-skill AND baseline). Do not do with-skill first and baseline later.

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

When each subagent completes, a notification includes `total_tokens` and `duration_ms`. Save immediately to `timing.json` in the run directory — this data is not persisted elsewhere:

```json
{
  "total_tokens": 84852,
  "duration_ms": 23332,
  "total_duration_seconds": 23.3
}
```

### Step 4 — Grade, aggregate, launch viewer

**Grade**: Spawn a grader subagent per `agents/grader.md`. Save results to `grading.json`. Required fields: `text`, `passed`, `evidence` (not `name`/`met`/`details`). For assertions checkable programmatically, write and run a script.

**Aggregate**:
```bash
python -m scripts.aggregate_benchmark <workspace>/iteration-N --skill-name <name>
```

**Analyst pass**: Read `agents/analyzer.md` → look for non-discriminating assertions (always pass), high-variance evals (flaky), time/token tradeoffs.

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

After the skill body is finalized, optimize the description for triggering accuracy.

### Step 1 — Generate trigger eval queries

Create 20 queries: 8-10 should-trigger, 8-10 should-not-trigger. Save as JSON:

```json
[
  {"query": "the user prompt", "should_trigger": true},
  {"query": "adjacent task that seems related but isn't", "should_trigger": false}
]
```

Queries must be realistic and specific — include file paths, column names, company context, casual phrasing, typos. The negative cases should be genuine near-misses (adjacent domain, ambiguous phrasing), not obviously unrelated requests.

### Step 2 — Review with user

```bash
# Read template, inject data, open for user review
# Replace __EVAL_DATA_PLACEHOLDER__ with the JSON array (no quotes — it's a JS var)
# Replace __SKILL_NAME_PLACEHOLDER__ and __SKILL_DESCRIPTION_PLACEHOLDER__
open /tmp/eval_review_<skill-name>.html
```

The user edits queries, toggles should-trigger, then clicks "Export Eval Set". Check `~/Downloads/eval_set.json` (or `eval_set (1).json` if multiple).

### Step 3 — Run the optimization loop

```bash
python -m scripts.run_loop \
  --eval-set <path-to-trigger-eval.json> \
  --skill-path <path-to-skill> \
  --model <model-id-from-system-prompt> \
  --max-iterations 5 \
  --verbose
```

Use the model ID from your system prompt — triggering tests must match the model the user actually runs. The loop: 60/40 train/test split → evaluate current description (3 runs per query) → propose improvements → re-evaluate → repeat up to 5 times. Returns `best_description` selected by test score.

Tail output periodically to give the user iteration progress updates.

### Step 4 — Apply the result

Update `description` in SKILL.md frontmatter with `best_description`. Show the user a before/after diff and report the accuracy scores.

---

## Hard Rules

- **Never add `user-invocable: false` or `disable-model-invocation: true` unless the skill is genuinely internal** — these block user invocation permanently.
- **Never hardcode absolute paths** (`/Users/<name>/`) in SKILL.md; use `$CLAUDE_SKILL_DIR`, `$CLAUDE_PLUGIN_ROOT`, or relative paths.
- **Always run the eval viewer before evaluating outputs yourself** — human review must happen before model revision.
- **Always spawn with-skill and baseline subagents in the same turn** — sequential spawning gives misleading timing comparisons.
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

## Environment-Specific Notes

| Feature | Claude Code | Claude.ai | Cowork/headless |
|---|---|---|---|
| Subagents | Yes | No — run inline, one at a time | Yes |
| Baseline runs | Yes | Skip | Yes |
| Browser viewer | Yes | No display — show inline | Use `--static <path>` |
| Quantitative benchmarks | Yes | Skip | Yes |
| Description optimization (`run_loop.py`) | Yes | Skip — needs `claude -p` CLI | Yes |
| Packaging (`package_skill.py`) | Yes | Yes | Yes |

**Updating an existing skill on Claude.ai:** The installed skill path may be read-only. Copy to `/tmp/skill-name/`, edit there, package from the copy, and direct the user to the resulting `.skill` file.

---

## Reference Files

| File | Purpose |
|---|---|
| `agents/grader.md` | Instructions for grader subagent |
| `agents/comparator.md` | Blind A/B comparison between two outputs |
| `agents/analyzer.md` | Benchmark result analysis patterns |
| `references/schemas.md` | JSON schemas for evals.json, grading.json, benchmark.json |
| `assets/eval_review.html` | Template for trigger eval review UI |
