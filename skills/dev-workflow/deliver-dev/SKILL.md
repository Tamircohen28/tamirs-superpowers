---
name: deliver-dev
description: 'Use when an objective is integrated and needs to become a delivery — ''deliver this objective'', ''ship it'', ''open the PR for objective X'', ''all tasks are done, create the PR'', ''turn the integration branch into a PR''. Runs the final combined-diff review and the full Tier 2 / pre-PR gates, pushes the objective branch, opens exactly ONE pull request, applies the repository''s merge policy (auto-merge is policy, not an invariant), and hands the GitHub lifecycle to pr-dev. Not for driving an already-open PR — that is pr-dev.'
when_to_use: 'User or orchestrator says: deliver objective <id>, ship this objective, open the PR for this work, all workers are done — create the PR, turn objective/<slug> into a pull request, run the pre-PR gates and deliver.'
argument-hint: '<objective-id> (or omit to infer from the current objective/<slug> branch)'
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
- Skill
disallowed-tools: []
model: claude-sonnet-4-6
effort: high
context: ''
agent: ''
hooks: {}
paths: []
shell: bash
metadata:
  updated-date: '2026-08-19'
  tamirs:
    visibility: public
    category: dev-workflow
    role: integrator
    capabilities:
      required:
      - skills
      - shell
      - git
      - github_cli
    validation-tier: 2
    updated-date: '2026-08-19'
    tags:
    - delivery
    - pr
    - integration
    - gates
    - workflow
---

# deliver-dev

Convert an **integrated objective** into a delivery unit: one reviewed, validated, pushed PR.

Role contract: [`core/roles/integrator.md`](../../../core/roles/integrator.md). Policies inherited, not restated: [`core/policies/delivery.md`](../../../core/policies/delivery.md), [`core/policies/git.md`](../../../core/policies/git.md), [`core/policies/validation.md`](../../../core/policies/validation.md).

**Validation tier: 2 (integration / pre-PR).** Tier 3 is CI's job, driven by `pr-dev` after this skill hands over.

## Where this sits

```
workers → handoffs → integration branch → [deliver-dev] → ONE PR → pr-dev → merge
```

`deliver-dev` is the *only* place a PR is created for an objective. Workers do not deliver.

## Step 1 — resolve the objective and refuse a premature delivery

```bash
S=skills/dev-workflow/_shared/scripts/objective-state.sh
bash $S show <objective-id>
bash $S integrate-ready <objective-id>
```

If `ready` is `false`, stop and report the blocking tasks. Delivering a half-integrated objective produces a PR that misrepresents the work — worse than delivering nothing.

With no argument, infer the objective from the current branch (`objective/<slug>`). If the branch is not an objective branch and no objective state exists, this is not an orchestrated objective: use `start-dev`'s delivery path or `pr-dev` directly, and say so.

Confirm you are on the integration branch, and that every worker branch listed in the task files is actually merged into it:

```bash
git branch --show-current
for b in $(bash $S tasks <objective-id> | jq -r '.[].branch // empty'); do
  git merge-base --is-ancestor "$b" HEAD && echo "merged: $b" || echo "NOT MERGED: $b"
done
```

## Step 2 — final combined-diff review

Review the whole objective as one diff against the base branch — not the worker diffs, which have already been reviewed individually and cannot show composition problems.

```bash
git diff --stat "$(bash $S show <objective-id> | jq -r .base_branch)"...HEAD
```

Check, in this order:

1. **Completeness** — does the objective's stated title/goal actually hold in this diff? Anything promised and missing gets said out loud, not quietly dropped.
2. **Coherence** — duplicated helpers from two workers, two names for one concept, an interface one task built and another ignored.
3. **Leftovers** — debug prints, commented-out code, TODOs added during the run, stray scratch files.
4. **Handoff followups** — read every handoff; blocking followups must be resolved or explicitly deferred in the PR body.
5. **Scope** — files touched that no task declared. Explain each one or revert it.

```bash
bash skills/dev-workflow/_shared/scripts/handoff.sh list <objective-id>
```

Fixes at this stage belong to you (the integrator) and are committed to the integration branch.

## Step 3 — full pre-PR gates (Tier 2)

Run the repository's real gates, not a proxy for them:

```bash
bash skills/dev-workflow/_shared/scripts/run-pre-pr-gates.sh
```

When that script does not cover the repo, run its actual full lint, typecheck, unit suite, and the integration tests relevant to this objective. Details and the failure protocol: [`references/pre-pr-gates.md`](references/pre-pr-gates.md).

**A failing gate stops delivery.** Fix it on the integration branch and re-run, or return the objective to `orchestrate-dev` for a fix task. Never open a PR on a red local gate and hope CI disagrees.

Record the commands and their real output. "Gates passed" without the commands is a claim, not evidence.

## Step 4 — push the objective branch

```bash
git push -u origin "objective/<objective-id>"
```

Never force-push a branch that already has an open PR or review history unless the user asked for it.

## Step 5 — create exactly ONE PR

```bash
gh pr create --base "$BASE" --head "objective/<objective-id>" \
  --title "<objective title>" --body-file <(cat <<'BODY'
## Objective
<one-paragraph statement of what the user asked for>

## Tasks
| Task | Role | Scope | Status |
|------|------|-------|--------|
| task-001 | implementer | src/auth/** | completed |

## Validation
<Tier 2 commands actually run, with results>

## Decisions
<the decisions from the handoffs a reviewer needs>

## Risks / Deferred
<blocking followups deferred, and why>
BODY
)
```

The PR body is assembled from the handoffs — that is what they were collected for. Follow the repo's PR template when one exists (`.github/pull_request_template.md`).

One objective = one PR. A second PR requires an exception recorded on the objective:

```bash
bash $S set-delivery <objective-id> --strategy multi-pr --reason '<enumerated exception from core/policies/delivery.md>'
```

## Step 6 — apply the merge policy (do not assume auto-merge)

Auto-merge is a **policy**, not an invariant. Resolve it in this order and state which rule won:

1. explicit user instruction in this session;
2. `delivery.auto_merge` on the objective;
3. repository/user configuration (project rules, `CLAUDE.md`/`AGENTS.md`, branch protection requiring human review);
4. otherwise: enable auto-merge, which is this framework's default for a repo that permits it.

```bash
bash $S set-delivery <objective-id> --pr-url "$PR_URL" --auto-merge true|false
```

If the repository requires human approval, enabling auto-merge is still correct — it merges *after* approval — but say that a human review is the remaining gate. If auto-merge is disabled at the repo level, say it is unsupported here rather than pretending it was enabled.

## Step 7 — hand off to pr-dev

Update state, then hand over:

```bash
bash $S set-status <objective-id> delivering
```

Invoke `pr-dev` with the PR number. From here `pr-dev` owns the GitHub lifecycle: review threads, CI failures, flake retries, merge. Do not duplicate that loop here.

When the PR merges, mark the objective:

```bash
bash $S set-status <objective-id> completed
```

## Hard rules

- **One objective, one PR.** Exceptions are named and recorded, never assumed.
- **Never deliver an objective with open tasks.** `integrate-ready` is the gate.
- **Never open a PR on failing local gates.**
- **Never force auto-merge over repository or user policy.**
- **Never fabricate the validation section of a PR body.** Only commands that ran.
- Do not commit `.dev-files/` unless the project wants durable checked-in workflow state.

## Anti-patterns

| Don't | Do |
|---|---|
| One PR per worker branch | One PR for the objective |
| Skip the combined-diff review because each worker was reviewed | Composition bugs only appear in the combined diff |
| "Push and let CI find it" | Tier 2 locally first |
| Always `--auto` regardless of repo policy | Resolve the merge policy, then state it |
| Keep driving CI and review threads here | Hand to `pr-dev` |
| Deliver while a task is `failed` | Stop and report |

## Output format

```
Objective: <id> — <title>
Integration branch: objective/<id> (all N worker branches merged)
Combined-diff review: <fixes applied / clean>
Tier 2 gates: <commands + results>
PR: <url>
Merge policy: auto-merge enabled | disabled (<which rule decided>)
Handed to: pr-dev #<N>
Deferred: <followups carried out of this delivery>
```
