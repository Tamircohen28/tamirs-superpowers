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

Structure raw tasks, specs, and review docs into phased GitHub issues — reviewed by the user before a single issue is created.

## Why this skill exists

When a developer jumps straight from "here's a big task" to writing code, they lose sequencing — risky changes land alongside safe ones, reviewers get massive PRs with unrelated diffs, and nothing is trackable. The naive approach of "just start coding and figure it out" creates re-work, merge conflicts, and no audit trail.

This skill forces a planning gate: parse the raw input, organize it by dependency/theme/risk into reviewable phases, show the plan to the user for approval, and only then create atomic GitHub issues. Each phase maps to one issue, making the work parallelizable, reviewable, and cancellable independently.

## Input

Parse `$ARGUMENTS` as one of:
- Free-text task or feature description
- File path to a spec, review doc, or requirements file
- A GitHub issue URL or number to decompose into sub-tasks
- A bullet list of fixes or changes

If empty, prompt: "What should I plan? Paste a task description, file path, or GitHub issue URL."

## Required execution flow

### 1. Fetch and read the input

**If a GitHub issue number or URL is given:**
```bash
gh issue view <number> --json title,body,labels,comments
```

**If a file path is given:**
Read the file contents fully before proceeding.

**If a URL (not GitHub issue) is given:**
Use WebFetch to retrieve the content.

Classify each piece of work:
| Field | Options |
|---|---|
| **Type** | `feat`, `fix`, `chore`, `docs`, `test`, `refactor` |
| **Area** | part of codebase — `backend`, `frontend`, `infra`, `tests`, `docs`, `ci` |
| **Complexity** | `simple` (1 commit), `moderate` (few files), `complex` (cross-cutting) |
| **Risk** | `low` (additive), `medium` (modifies existing logic), `high` (deletes/restructures) |

### 2. Organize into phases

Group tasks by:
1. **Dependencies first** — what must land before other work can build on it
2. **Theme** — related changes that should be reviewed together in one PR
3. **Risk isolation** — never mix a risky refactor with an unrelated feature

Each phase becomes exactly one GitHub issue and should be implementable in one PR.

**Phase size rules:**
- Aim for 2–6 tasks per phase
- If a phase would touch >10 files: split it
- If a phase has zero dependencies on other phases: it can run in parallel

### 3. Present plan for review

Print the full plan using this format for every phase:

```
## Phase 1: <phase title>
**Issue title**: <concise imperative — starts with verb>
**Type**: feat | fix | chore | docs | test | refactor
**Area**: <affected codebase area>
**Depends on**: Phase N (or "none")
**Parallel-safe**: yes | no

### Tasks
- [ ] <task 1> — files: `path/to/file.ts` — change: <what to do>
- [ ] <task 2> — files: `path/to/other.ts` — change: <what to do>

### Verification
- [ ] <concrete check — command or manual step>
- [ ] <edge case to confirm>
- [ ] `make repo-standards-gate` passes before PR (multi-platform / agent-kit repos only)

---
```

Example of a well-formed phase:

```
## Phase 1: Add authentication middleware
**Issue title**: feat: add JWT validation middleware to API routes
**Type**: feat
**Area**: backend
**Depends on**: none
**Parallel-safe**: yes

### Tasks
- [ ] Create `src/middleware/auth.ts` — implement `validateJwt(req, res, next)` using jsonwebtoken
- [ ] Register middleware in `src/app.ts` on all `/api/v1/*` routes except `/health`
- [ ] Add `JWT_SECRET` to `.env.example` with placeholder value

### Verification
- [ ] `curl -H "Authorization: Bearer badtoken" https://api.example.com/v1/users` returns 401
- [ ] `npm test` passes with no regressions
```

### 4. STOP — wait for user approval

After printing all phases, say exactly:

> "Review the plan above. Reply **approved** to create GitHub issues, or tell me what to change (e.g. 'merge phases 2 and 3', 'add a testing phase', 'split phase 1')."

**Do NOT create any issues until the user explicitly says "approved" or equivalent.**

### 5. Apply feedback (if requested)

If the user requests changes — merge phases, reorder, add tasks, adjust scope — update the plan and re-display it. Repeat steps 3–4 until approved.

### 5b. Multi-platform verification line (agent-kit repos)

Before creating issues, detect multi-platform layout:

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
bash "$REPO_ROOT/skills/dev-workflow/_shared/scripts/detect-multi-platform-repo.sh" "$REPO_ROOT"
```

When exit code is 0, **every** phase Verification section must include:

```
- [ ] `make repo-standards-gate` passes (agent runs before push/PR — wired in start-dev Step 4)
```

Phases that touch `skills/`, `hooks/`, plugin manifests, or `docs/engineering/build-and-release/platform-targets.json` must also note: update `platform-targets.json` + README Row 3 when platform behavior changes.

### 6. Create GitHub issues

After approval, create each phase as a GitHub issue in sequence:

```bash
gh issue create \
  --title "<issue title from plan>" \
  --label "<type>" \
  --label "agent:any" \
  --body "$(cat <<'EOF'
## Summary
<2-sentence description of the phase goal and why it's a standalone unit>

## Tasks
- [ ] <task 1>
- [ ] <task 2>

## Verification
- [ ] <verification step 1>
- [ ] <verification step 2>
- [ ] `make repo-standards-gate` passes before PR (include when multi-platform repo)

## Dependencies
<"None" or "Blocked by #N">

## Resume
- **Done:** (none yet)
- **Next:** <first task from Tasks list>
- **Decisions:** (none yet)
- **Blocked:** none
- **Branch:** (unset — assigned at start-dev)
- **Worktree:** (unset)
- **Last agent:** (unset)

## Agent routing
- **Owner:** agent:any
- **Suggested platform:** <claude|cursor|codex|any> — based on task type

🤖 Generated with Claude Code
EOF
)"
```

After each issue is created, capture its URL:
```bash
# gh issue create outputs the URL on the last line
```

### 7. Report

After all issues are created, print a summary table:

```
| Phase | Issue | Title |
|---|---|---|
| 1 | #42 | https://github.com/<repo>/issues/42 |
| 2 | #43 | https://github.com/<repo>/issues/43 |
```

Suggest next step: "Run `/start-dev <issue numbers>` to begin implementation, or `/switch-dev resume <issue numbers>` to pick up on another platform."

## Hard rules

- **Never create issues before user approval.** The review gate is mandatory — not optional.
- **Never put unrelated work in the same phase.** Each issue must have a single coherent theme.
- **Never skip dependency ordering.** Phase 1 must be completable without Phase 2 existing.
- **Never create phases with more than 10 file changes.** Split instead.
- **Never write code or make commits.** This skill plans only; `/start-dev` implements.
- **Never push to any branch.** Planning produces GitHub issues, not commits.
- **Always add `agent:any` label** alongside the type label on every created issue.
- **Always add `make repo-standards-gate` to Verification** on multi-platform repos (detect via `detect-multi-platform-repo.sh`) so start-dev enforces it before PR.

## What NOT to do

**Wrong — jumping straight to issue creation:**
```
User: "Plan the auth feature"
Claude: *immediately creates 5 issues without showing plan*
```
Always show the plan first and wait for "approved."

**Wrong — mega-phase with 15 tasks:**
```
## Phase 1: Implement entire authentication system
- [ ] Add JWT library
- [ ] Create user model
- [ ] Write login endpoint
- [ ] Write registration endpoint
- [ ] Add password hashing
- [ ] Create middleware
- [ ] Write tests
- [ ] Update docs
- [ ] Add env vars
- [ ] Update CI
- [ ] Add rate limiting
...
```
Split into 3–4 focused phases.

**Wrong — mixing risk levels:**
```
## Phase 1: Add feature X and refactor entire auth module
```
Risky refactors belong in their own phase so they can be reviewed and reverted independently.

**Wrong — vague task descriptions:**
```
- [ ] Fix the login bug
```
Every task must name specific files and describe the exact change.

## Quick-reference: Phase grouping cheat sheet

| Scenario | Grouping strategy |
|---|---|
| Bug fix with a test | One phase: fix + test together |
| New feature with DB migration | Phase 1: migration; Phase 2: backend; Phase 3: frontend |
| Refactor + new feature | Separate phases — never together |
| Multiple unrelated fixes | One phase per fix, or group if truly trivial |
| Spec with 20+ items | Group by domain/area into 4–8 phases |
| Cross-cutting infra change | Always Phase 1 — everything else depends on it |

## Supporting files

| File | Purpose |
|---|---|
| `scripts/validate_plan.py` | Static validator — checks phase structure, task counts, dependency refs before approval |
| `references/phase-grouping-guide.md` | Extended guide for dependency graphs, monorepo scenarios, risk isolation, and anti-patterns |
| `evals/evals.json` | 3 realistic test cases covering free-text tasks, review-doc decomposition, and GitHub issue URL input |

Load `references/phase-grouping-guide.md` when:
- The input has 20+ items or complex cross-cutting dependencies
- The user asks about monorepo considerations or parallel vs sequential ordering
- Phasing decisions are non-obvious (diamond dependencies, circular refs)

Run `scripts/validate_plan.py <plan.md>` optionally to self-check a plan draft before showing it to the user.

## Handoff

This skill produces GitHub issues only. To implement them, use:
```
/start-dev <issue numbers>
```
