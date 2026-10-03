# Description Optimization

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

Use the model ID from your system prompt — triggering tests must match the model the user
actually runs. Never hardcode a model id here; a pinned id tests a model the user does not
have.

**`run_loop.py` shells out to the `claude` CLI**, so description optimisation runs on Claude
Code only. Where that CLI is absent, say so and stop: the skill body and its portable
frontmatter are still fully authorable and validatable, and the description can be reviewed
by hand against the trigger eval set. Do not simulate the loop's accuracy scores. The loop: 60/40 train/test split → evaluate current description (3 runs per query) → propose improvements → re-evaluate → repeat up to 5 times. Returns `best_description` selected by test score.

Tail output periodically to give the user iteration progress updates.

### Step 4 — Apply the result

Update `description` in SKILL.md frontmatter with `best_description`. Show the user a before/after diff and report the accuracy scores.
