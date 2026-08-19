---
name: worker-dev
description: 'Use when executing exactly ONE task inside an objective already planned by orchestrate-dev — dispatched as ''run task-002'', ''do your assigned task'', ''implement task-001 of objective X'', ''work this task and hand off'', or when resuming a task that has a task-NNN.json under .dev-files/objectives/. Implements the task inside its declared scope, runs Tier 1 targeted validation only, commits, and emits a structured handoff. It never opens a PR, never enables auto-merge, never merges main, and never runs the full repo suite. A whole user request is not a worker task — that is orchestrate-dev or start-dev.'
when_to_use: 'An orchestrator dispatched a single task: "run task-002 of objective auth-system", "implement your assigned scope and hand off", "do task-001 in this worktree", "resume task-003" — or the current worktree corresponds to a worker/<objective>/NNN branch with a task file on disk.'
argument-hint: '<objective-id> <task-id>'
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
    role: implementer
    capabilities:
      required:
      - skills
      - shell
      - git
      optional:
      - subagents
      - worktree_isolation
    validation-tier: 1
    updated-date: '2026-08-19'
    tags:
    - worker
    - task
    - handoff
    - validation
    - workflow
---

# worker-dev

Execute **one** task. End at commit + handoff. Nothing further.

Role contract for whichever role the task declares: [`core/roles/`](../../../core/roles/). Policies inherited, not restated: [`core/policies/safety.md`](../../../core/policies/safety.md), [`core/policies/git.md`](../../../core/policies/git.md), [`core/policies/validation.md`](../../../core/policies/validation.md).

## The prohibitions — read these first

This is the single most important behavioral change in this workflow. A worker **MUST NOT**:

- **Create a pull request.** Not "just a draft". Not "to be helpful". The objective gets one PR, opened by `deliver-dev`, after integration.
- **Enable auto-merge**, merge anything, or touch merge queues.
- **Merge or rebase onto `main`/the base branch.** Divergence is the integrator's problem, and a worker that merges main pollutes every other worker's diff.
- **Run the whole expensive repository suite.** Tier 1 is targeted validation of *your* change. The full suite runs once, at integration.
- **Write outside `scope[]`.** Anything you need elsewhere becomes a `followup` in your handoff — never an out-of-scope edit.
- **Touch another task's branch, worktree, or state files.**
- **Push, unless the objective's dispatch explicitly told you to.** Committing locally is the contract.

Why: a work unit is not a delivery unit. Every one of the above turns a coordinated objective into N uncoordinated deliveries — the exact failure this workflow exists to prevent.

**Validation tier: 1 (worker).** Targeted only.

## Step 1 — load the task

```bash
S=skills/dev-workflow/_shared/scripts/objective-state.sh
bash $S task-show <objective-id> <task-id>
bash $S show <objective-id>
```

From the task file, hold on to: `role`, `scope[]`, `validation_tier`, `branch`, `worktree`, `depends_on`. If there is no task file, you were not dispatched by an orchestrator — stop and ask whether this should be `start-dev` (single change, own delivery) or `orchestrate-dev` (a whole objective).

If `depends_on` names a task that is not `completed`, stop: the orchestrator dispatched out of order. Report it rather than guessing at half-built foundations.

Read the handoffs of your dependencies — they carry the decisions you must build on:

```bash
bash skills/dev-workflow/_shared/scripts/handoff.sh show <objective-id> task-001
```

## Step 2 — work in your worktree

```bash
cd "$(bash $S task-show <objective-id> <task-id> | jq -r '.worktree')"
git branch --show-current    # must equal the task's branch
bash $S task-set <objective-id> <task-id> --status running
```

If the task has no worktree, you are in sequential mode on the objective branch. That is fine and expected — the prohibitions above are unchanged.

## Step 3 — implement, inside scope

Before every edit, ask whether the path is inside `scope[]`. Scope is not bureaucracy: concurrent workers rely on disjoint scopes to avoid conflicts that no one can resolve later.

When the task genuinely cannot be completed inside its scope, you have three legitimate moves — pick one and say so:

1. do the in-scope part, record the rest as a **blocking followup**;
2. stop and report back to the orchestrator that the graph needs a new task;
3. if a dependency's handoff was wrong, say that explicitly rather than patching around it.

Silently editing outside scope is not one of them. `handoff.sh emit` will refuse it.

## Step 4 — Tier 1 validation

Run only what is relevant to your change:

- tests that exercise the files you touched;
- lint and typecheck **scoped to those files** where the tooling supports it;
- the build only if your change could plausibly break it.

Do not run the full suite. Do not run cross-platform matrices. Do not run CI locally. If the repo has no way to scope its tests, say so, run the narrowest thing that exists, and record it. Choosing the right command: [`references/tier-1-validation.md`](references/tier-1-validation.md).

Every command you run becomes a `--validation` entry with its real result. A command you did not run must not appear in the handoff.

## Step 5 — commit

One or a few focused commits on the task branch. Repo commit convention applies (`<type>(<scope>): <description>`). Never amend or rebase commits from another task.

```bash
git add <paths inside scope>
git commit -m "feat(auth): add argon2id password hashing"
git rev-parse --short HEAD
```

## Step 6 — emit the handoff

The handoff is your entire output. The integrator will never read your reasoning — only this file.

```bash
H=skills/dev-workflow/_shared/scripts/handoff.sh
bash $H emit auth-system task-001 --status completed \
  --summary "Password hashing + session issuance. Sessions are opaque tokens, not JWTs — see decision." \
  --branch worker/auth-system/001 \
  --commit a1b2c3d \
  --file 'src/auth/hash.ts:added' --file 'src/auth/session.ts:added' \
  --validation 'npm test -- src/auth|worker|pass|14 passed' \
  --validation 'npx tsc --noEmit -p src/auth|worker|pass' \
  --decision 'argon2id over bcrypt|OWASP 2024 guidance' \
  --risk 'no login rate limiting yet|medium|followup task' \
  --followup 'add login rate limiting|true|implementer'
bash $H validate auth-system task-001
bash $S task-set auth-system task-001 --status completed
```

If you would rather assemble the document yourself — a long summary, nested
decisions, anything awkward to pass as flags — write the JSON to a file and
install it with `handoff.sh write`, which applies the same checks:

```bash
bash $H write auth-system task-001 /tmp/handoff.json
bash $H read  auth-system task-001
```

Status honestly: `completed` only when the task's goal actually holds. Otherwise `partial`, `failed`, or `blocked` — with the reason in `summary`. A `completed` handoff with an empty `validation[]` is a warning for good reason: it is a claim with no evidence.

Include in `decisions` anything the integrator or a later task would otherwise have to reverse-engineer: a chosen approach, an interface another task will consume, a deviation from the plan.

## Step 7 — stop

Report to whoever dispatched you: task id, status, commits, what you validated, decisions, risks, followups. Then stop. Do not push, do not open a PR, do not start the next task, do not "helpfully" begin integration.

## Anti-patterns

| Don't | Do |
|---|---|
| `gh pr create` at the end | Emit the handoff; `deliver-dev` opens the one PR |
| merging the default branch in because the branch is behind | Leave it; the integrator handles divergence |
| `make test` / full suite "to be safe" | Targeted Tier 1 only |
| Fix a bug you noticed in another module | Record it as a followup |
| Report success in prose only | The handoff file is the deliverable |
| List a validation command you didn't run | Only real runs, with real results |
| Mark `completed` when a test still fails | `partial` or `failed`, with the reason |

## Output format

```
Task: <task-id> (<role>) of objective <id>
Scope: <globs>
Status: completed | partial | failed | blocked
Commits: <shas>
Tier 1: <commands + results>
Decisions: <the ones the integrator needs>
Risks / Followups: <…>
Handoff: .dev-files/objectives/<id>/handoffs/<task-id>.json
```
