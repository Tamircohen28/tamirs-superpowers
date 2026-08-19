---
name: plan-dev
description: 'Use when the user wants to convert an informal task, feature request, spec, or review doc into a structured implementation plan before any code is written. User''s intent is organization and sequencing — phases, dependency ordering, and GitHub issues that make work trackable and reviewable. Invoke for: ''plan this'', ''break into phases'', ''create issues for'', ''decompose this spec'', ''turn into tickets'', ''what order should I tackle these'', ''help me organize this work'', ''structure this feature'', ''plan-dev''. This is distinct from architecture analysis of existing code, how-to questions, or direct coding requests — the output is a roadmap, not code.'
when_to_use: 'User wants to plan or structure development work into phases and create GitHub issues — invoked as /plan-dev or when the user says: ''plan this'', ''break this into phases'', ''create issues for this'', ''decompose this spec/task'', ''structure this feature'', ''what order should I do this in'', ''turn this into tickets'', ''help me organize this work'', ''I have a review doc with N items help me organize it''.'
argument-hint: '[task description, file path to spec/review doc, or GitHub issue URL/number]'
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
- WebSearch
- Agent
disallowed-tools: []
model: claude-sonnet-4-6
effort: high
context: ''
agent: ''
hooks: {}
paths: []
shell: bash
metadata:
  tamirs:
    visibility: public
    category: dev-workflow
    role: planner
    updated-date: '2026-08-19'
    validation-tier: 0
    capabilities:
      required:
        - shell
        - git
      optional:
        - github_cli
        - subagents
    tags:
      - planning
      - objective
      - task-dag
      - decomposition
      - workflow
  capability: developer-workflow
  tags:
  - planning
  - phases
  - github-issues
  - decomposition
  - workflow
  - tickets
  - spec
  updated-date: '2026-07-09'
---

## Live context
!`git branch --show-current 2>/dev/null | sed 's/^/current branch: /' || echo "not a git repo"`
!`gh repo view --json defaultBranchRef,nameWithOwner --jq '"repo: \(.nameWithOwner) | default branch: \(.defaultBranchRef.name)"' 2>/dev/null || true`
!`gh issue list --state open --limit 5 --json number,title --jq '.[] | "  open issue #\(.number): \(.title)"' 2>/dev/null | head -5 || true`

# plan-dev

Turn a raw task, spec, or review doc into **one objective and a dependency-aware task DAG** — reviewed by the user before anything is written down.

## Why this skill exists

Jumping from "here's a big task" straight to code loses sequencing: risky changes land beside safe ones, reviewers get unrelated diffs, and nothing is trackable. The older version of this skill fixed that but baked in a second problem — it treated **one phase = one GitHub issue = one PR**. That is wrong for most real objectives: it fragments a single user goal into many PRs, many CI runs, and no place where the combined diff is ever reviewed.

So the output changed. The plan is now an **objective plus a task graph**: each task declares what it depends on, which files it may write, which validation tier it runs, and which role should do it. That is exactly what `orchestrate-dev` needs to run tasks in parallel and what `deliver-dev` needs to ship them as **one** PR. GitHub issues are still available — as an **export**, for when the work needs to be visible to people outside the session.

## Validation tier

Tier 0. This skill writes plan state; it runs no tests, makes no commits, and pushes nothing.

## Input

Parse `$ARGUMENTS` as one of:
- Free-text task or feature description
- File path to a spec, review doc, or requirements file
- A GitHub issue URL or number to decompose into sub-tasks
- A bullet list of fixes or changes

If empty, prompt: "What should I plan? Paste a task description, file path, or GitHub issue URL."

## Required execution flow

### 1. Fetch and read the input

**GitHub issue number or URL:**
```bash
gh issue view <number> --json title,body,labels,comments
```
`gh` is optional. If it is unavailable, ask the user to paste the issue text rather than guessing at it.

**File path:** read the file fully before proceeding.
**Other URL:** use WebFetch.

Classify each piece of work:

| Field | Options |
|---|---|
| **Type** | `feat`, `fix`, `chore`, `docs`, `test`, `refactor` |
| **Area** | `backend`, `frontend`, `infra`, `tests`, `docs`, `ci` |
| **Complexity** | `simple` (1 commit), `moderate` (few files), `complex` (cross-cutting) |
| **Risk** | `low` (additive), `medium` (modifies existing logic), `high` (deletes/restructures) |

### 2. Name the objective

One objective per invocation. Give it:

- an `id` — lowercase slug, e.g. `auth-system`;
- a `title` — one sentence of what the user actually wants;
- `base_branch` — the repo's default branch;
- `integration_branch` — `objective/<id>`;
- a `delivery.strategy` — **`single-pr` by default**.

Only choose a strategy other than `single-pr` when one of the enumerated exceptions in `core/policies/delivery.md` applies (truly independent deliverables, security isolation, deployment sequencing, explicit user request, or a size/risk threshold). When you do, record `delivery.exception_reason` naming which one — an unexplained multi-PR plan is the defect this skill exists to prevent.

### 3. Decompose into tasks

Each task is a **work unit, not a delivery unit**: it ends at commit + handoff, never at a PR.

Every task declares:

| Field | Meaning | Rule |
|---|---|---|
| `id` | `task-001`, `task-002`, … | Sequential, zero-padded |
| `title` | Imperative, one line | |
| `role` | Which role does it | One of `core/roles/*.md`: planner, orchestrator, implementer, test-engineer, reviewer, security-reviewer, performance-reviewer, debugger, integrator, research-agent |
| `depends_on` | Task ids that must complete first | Empty array = ready now |
| `scope` | Glob paths this task may **write** | Everything else is read-only for it. **Always `<dir>/**`, never a lone `*`** — see below |
| `validation_tier` | `edit` \| `worker` \| `integration` \| `delivery` | Implementation tasks are `worker`; the integration task is `integration` |
| `status` | `ready` when `depends_on` is empty, else `pending` | |
| `provider` | Optional, advisory | Metadata only — never encoded in a branch or path |

**Writing a scope: use `**`, never a lone `*`.** The check that keeps a worker inside its area is bash pattern matching, where `*` also matches `/`. So `src/*` — the obvious way to write "files directly under src" — actually authorises `src/deep/nested/secret.txt` as well, and `src/*.ts` authorises `src/a/b.ts`. There is no single-level matcher available, so a lone `*` never means what it looks like it means:

| Write | Not |
|---|---|
| `src/auth/**` — the auth subtree | `src/auth/*` (reads as one level, grants the subtree) |
| `docs/reference.md` — one literal file | `docs/*.md` (grants everything under `docs/`) |

The `**` form is sound in the other direction: `src/auth/**` does **not** match `src/authorization/` or `src/auth-backup/`, because the literal `/` after `auth` stops it. `scripts/validate_plan.py` rejects any single-`*` segment, so an accidental one fails at plan time rather than silently widening a worker's write boundary at run time.

**Parallelizable** is derived, not declared: a task is parallelizable when it has no dependency path to another ready task **and** its `scope` does not overlap that task's. Two concurrent tasks sharing write scope is a merge conflict waiting to happen — either narrow the scopes or add a dependency. `scripts/validate_plan.py` enforces exactly this.

Sizing:
- 2–6 tasks for a typical objective; more than ~8 usually means the objective is really two objectives.
- A task touching >10 files should be split.
- Do not mix a risky refactor and an unrelated feature in one task.

### 4. Present the plan for review — then STOP

Print the objective, the task table, and the DAG:

```
## Objective: auth-system — Implement authentication system
Base: main → integration branch: objective/auth-system
Delivery: single-pr

| Task | Role | Depends on | Scope | Tier | Parallel |
|---|---|---|---|---|---|
| task-001 | implementer | — | src/auth/** | worker | yes (with 002) |
| task-002 | implementer | — | migrations/** | worker | yes (with 001) |
| task-003 | implementer | 001, 002 | src/api/routes/** | worker | no |
| task-004 | test-engineer | 003 | tests/** | worker | no |
| task-005 | integrator | 004 | — | integration | no |

Wave 1: task-001, task-002   (parallel)
Wave 2: task-003
Wave 3: task-004
Wave 4: task-005 — integrate, review combined diff, hand to deliver-dev

### task-001 — Add JWT validation middleware
- Files: src/auth/middleware.ts (new), src/auth/index.ts
- Verification: `npm test -- src/auth`; a request with a bad bearer token returns 401
```

Then say exactly:

> "Review the plan above. Reply **approved** to write it out, or tell me what to change (e.g. 'merge task-001 and task-002', 'add a security review task', 'split task-003')."

**Write nothing until the user explicitly approves.** Apply feedback and re-display as many times as needed.

### 5. Multi-platform verification note (agent-kit repos)

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
bash "$REPO_ROOT/skills/dev-workflow/_shared/scripts/detect-multi-platform-repo.sh" "$REPO_ROOT"
```

When this exits 0, the integration task's verification must include `make repo-standards-gate`, and any task touching `skills/`, `hooks/`, plugin manifests, or `docs/engineering/build-and-release/platform-targets.json` must note: update `platform-targets.json` + README Row 3 when platform behaviour changes.

### 6. Write the objective state (primary output)

```bash
OBJ_DIR=".dev-files/objectives/<id>"
SHARED_DIR="$REPO_ROOT/skills/dev-workflow/_shared/scripts"

# Preferred: the shared helper owns the layout and the schema versions
bash "$SHARED_DIR/objective-state.sh" init "<id>" --title "<title>" --base-branch "<base>"
bash "$SHARED_DIR/objective-state.sh" add-task "<id>" <task-json-file>
```

If `objective-state.sh` is unavailable, write the files directly — the layout is the contract, not the helper:

```
.dev-files/objectives/<id>/
├── objective.json      # core/workflow/objective-schema.json
├── plan.md             # the human-readable plan you just showed
└── tasks/task-00N.json # core/workflow/task-schema.json
```

Then validate before reporting success:

```bash
python3 "$REPO_ROOT/skills/dev-workflow/plan-dev/scripts/validate_plan.py" ".dev-files/objectives/<id>"
```

Fix every error it reports. A plan that fails this check is not a plan — the graph checks (missing dependency, cycle, parallel tasks sharing write scope) are the ones a human reviewer reliably misses.

`.dev-files/` is normally gitignored. Only check it in when the project explicitly wants durable workflow state.

### 7. Export to GitHub issues — optional

Local state is the source of truth. Issues are for **visibility to people who are not in this session** and for cross-machine resume.

Export automatically when the user's own request asked for it ("create issues for…", "turn this into tickets") — that is what they asked for and it must keep working. Otherwise ask once:

> "Written to `.dev-files/objectives/<id>/`. Also export to GitHub issues for tracking? (yes / no)"

When exporting, one issue per task:

```bash
gh issue create \
  --title "<task title>" \
  --label "<type>" --label "agent:any" \
  --body "$(cat <<'EOF'
## Summary
<what this task does and why it is a coherent unit>

## Objective
`auth-system` — task `task-001` of 5. Delivery: one PR for the whole objective.

## Scope (writable paths)
- `src/auth/**`

## Depends on
<"None (ready)" or "task-002 (issue #N)">

## Verification — tier: worker
- [ ] <targeted check>

## Resume
- **Done:** (none yet)
- **Next:** <first step>
- **Decisions:** (none yet)
- **Blocked:** none
- **Branch:** (unset — assigned at worker start)
- **Worktree:** (unset)
- **Last agent:** (unset)

## Agent routing
- **Role:** implementer
- **Owner:** agent:any

🤖 Generated with Claude Code
EOF
)"
```

Record each issue URL back into the task's `notes` (or `objective.notes`) so a resume on another machine can find it.

### 8. Report

```
Objective auth-system written to .dev-files/objectives/auth-system/
  5 tasks, 4 waves, 2 parallelizable
  validate_plan.py: PASS
  GitHub issues: #42 #43 #44 #45 #46   (or "not exported")

Next: /orchestrate-dev auth-system     — run the graph, integrate, one PR
      /start-dev task-001              — run a single task by hand (no PR: the objective owns delivery)
```

## Hard rules

- **Never write state before user approval.** The review gate is mandatory.
- **Never assume a task becomes a PR.** One objective = one PR unless a named exception in `core/policies/delivery.md` applies.
- **Never emit a task without `depends_on`, `scope`, `validation_tier`, and `role`.** A task missing any of them cannot be scheduled or isolated.
- **Never mark tasks parallel when their scopes overlap.** Add a dependency or narrow the globs.
- **Never write a scope with a lone `*`.** It grants the whole subtree under the enforcing matcher; use `<dir>/**` or a literal path.
- **Never put unrelated work in one task.** Single coherent theme each.
- **Never write code, commit, or push.** This skill plans only.
- **Always run `validate_plan.py` on the written objective** before reporting success.
- **Always keep GitHub export optional** — but always honour an explicit "create issues" request.

## What NOT to do

**Wrong — one issue per task, one PR per issue:**
```
Phase 1 → issue #42 → PR #101
Phase 2 → issue #43 → PR #102
Phase 3 → issue #44 → PR #103
```
Three CI runs, three reviews, and nobody ever reviews the combined change. Right: one objective, five tasks, one PR.

**Wrong — mega-task:**
```
task-001: implement the entire authentication system (15 subtasks)
```
Split into 3–5 tasks with real dependencies.

**Wrong — a scope that grants more than it appears to:**
```
task-001  scope: src/*
```
Reads as "files directly under src"; actually authorises every file under `src/`, at any depth. Write `src/**` if that is what you mean, or name the files.

**Wrong — parallel tasks over the same files:**
```
task-001  scope: src/auth/**   depends_on: []
task-002  scope: src/auth/**   depends_on: []
```
Two workers, same files, guaranteed conflict. `validate_plan.py` rejects this.

**Wrong — vague task:**
```
- [ ] Fix the login bug
```
Name the files and the exact change.

## Quick reference: decomposition cheat sheet

| Scenario | Shape |
|---|---|
| Bug fix with a test | One task: fix + test together |
| Feature with DB migration | migration (implementer) → backend (implementer) → frontend (implementer) → tests (test-engineer) |
| Refactor + new feature | Separate tasks, sequenced — never one task |
| Multiple unrelated fixes | One task each; they parallelize if scopes are disjoint |
| Spec with 20+ items | Group by area into 4–8 tasks; consider two objectives |
| Cross-cutting infra change | task-001 with everything else depending on it |
| Security-sensitive change | Add a `security-reviewer` task depending on the implementation |

## Supporting files

| File | Purpose |
|---|---|
| `scripts/validate_plan.py` | Validates a written objective directory (schema + DAG + parallel-scope safety); also still validates a legacy markdown phase plan |
| `references/phase-grouping-guide.md` | Extended guide: dependency graphs, monorepos, risk isolation, anti-patterns |
| `evals/evals.json` | Test cases covering free-text, review-doc, and GitHub-issue input |
| `evals/trigger-evals.json` | Description trigger set (should / should-not fire) |

Load `references/phase-grouping-guide.md` when the input has 20+ items, spans a monorepo, or the dependency shape is non-obvious (diamonds, near-cycles).

## Handoff

```
/orchestrate-dev <objective-id>   # run the graph → integrate → one PR
/start-dev <task or description>  # single task; no PR while the objective is active
/switch-dev handoff #N            # if issues were exported and you are switching tools
```
