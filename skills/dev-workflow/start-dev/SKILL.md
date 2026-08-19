---
name: start-dev
description: 'Use when the user wants to implement, build, code, or ship a task that will result in commits and a pull request — given a GitHub issue number, free-text task description, or spec file. Triggers: ''implement issue #N'', ''start coding X'', ''build the feature'', ''work on this spec'', ''create a PR for this'', ''ship issue #N'', ''code up the feature'', ''begin implementation of X''.'
when_to_use: implement, build, start coding, begin implementation, work on, create PR for, ship, code up — followed by an issue number (#N), a task description, or a spec/plan file path
argument-hint: '[issue number(s) e.g. #42, free-text task description, or path/to/spec.md]'
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
  tamirs:
    visibility: public
    category: dev-workflow
    role: implementer
    updated-date: '2026-08-19'
    validation-tier: 2
    capabilities:
      required:
        - shell
        - git
      optional:
        - github_cli
        - worktree_isolation
        - subagents
    tags:
      - implementation
      - facade
      - worker
      - delivery
      - workflow
  capability: developer-workflow
  tags:
  - implementation
  - worktree
  - pr
  - workflow
  updated-date: '2026-07-09'
---

## Live context
!`git branch --show-current 2>/dev/null | sed 's/^/current branch: /' || echo "not a git repo"`
!`gh repo view --json defaultBranchRef --jq '"default branch: \(.defaultBranchRef.name)"' 2>/dev/null || true`
!`gh issue list --state open --limit 5 --json number,title --jq '.[] | "  #\(.number): \(.title)"' 2>/dev/null | head -5 || true`

# start-dev

Compatibility entry point for "implement this". Routes the request to the right piece of the workflow and stays out of the way.

> **Direction of travel.** Implementing and delivering are now separate skills: `worker-dev` (implement → validate → commit → handoff, inside an objective) and `deliver-dev` (review the integrated diff → gates → push → one PR for the objective). `/start-dev` remains a fully supported front door: for a simple standalone task it still runs the same implement→PR flow it always has, and for work an objective already owns it hands off to `worker-dev` and opens no PR. Nothing you invoke today stops working. Over time, reach for `/orchestrate-dev` for multi-part work, and `worker-dev`/`deliver-dev` directly when you want one half of an objective's flow.

## Why this skill exists

`start-dev` used to run one monolithic implementation→PR flow, which quietly assumed **every task is its own pull request**. That assumption breaks the moment a single user objective is split across several tasks: you get five PRs for one feature, five CI runs, five review cycles, and no place where the combined diff is ever reviewed. The routing below fixes that while preserving the one-task-one-PR path for the case where it is genuinely correct.

## Input

Parse `$ARGUMENTS` as one of:
- GitHub issue number(s): `#258` or `258 259 260`
- A free-text task description: `"Add rate limiting to the /login endpoint"`
- A file path to a spec or plan: `path/to/plan.md`

If `$ARGUMENTS` is empty, ask "What do you want to implement?" and stop.

## Step 0 — Route (do this before anything else)

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
SKILL_DIR="${CLAUDE_SKILL_DIR:-$REPO_ROOT/skills/dev-workflow/start-dev}"

ROUTE="$(bash "$SKILL_DIR/scripts/detect-objective.sh" "$REPO_ROOT")"
MODE="$(echo "$ROUTE" | jq -r .mode)"
OBJECTIVE_ID="$(echo "$ROUTE" | jq -r '.objective_id // empty')"
echo "$ROUTE" | jq -r '"route: \(.mode) — \(.reason)"'
```

Then pick exactly one of three routes:

| Route | When | What runs | PR? |
|---|---|---|---|
| **A — worker only** | `MODE=worker-only`: an objective already owns this work (an `.dev-files/objectives/<id>/objective.json` is active, or an orchestrator invoked us) | `worker-dev` | **No** |
| **B — orchestrate** | The request is a non-trivial multi-part objective (see the test below) | Recommend/route to `orchestrate-dev` | One, opened by `deliver-dev` at the end of the objective |
| **C — implement + deliver** | `MODE=worker-and-deliver` and the task is genuinely simple and independent | this skill's own flow (identical to the pre-split `/start-dev`) | Yes — one |

### The multi-part test (route B)

**Skip this test entirely — route C is the answer — when `orchestrate-dev` sent the work here.** Its fall-through is one-directional: it already applied the orchestration test and decided against it, so re-applying the test here would bounce the request between the two skills forever. Recognise the hand-off by any of:

- `TAMIRS_ROUTED_FROM=orchestrate-dev` in the environment;
- the invocation says the orchestration decision is already made, or "do not route back";
- this run was reached from `orchestrate-dev` in the same session.

If the work genuinely looks bigger than `orchestrate-dev` judged, say so in one line and let the user decide — never re-route on your own.

Otherwise, route to `orchestrate-dev` when **two or more** of these hold:

- the work splits into parts that could progress independently;
- it needs more than one role (e.g. implementer **and** test-engineer **and** reviewer);
- it plausibly touches more than ~10 files or more than one subsystem;
- the user's phrasing is objective-shaped ("build the auth system", "migrate X to Y") rather than task-shaped;
- a spec/plan file was passed containing multiple distinct phases.

Say so in one line and offer the route rather than silently switching:

```
This looks like a multi-part objective (auth API + migration + tests, 3 roles).
Running /orchestrate-dev — one objective, one PR at the end.
Say "just do it directly" and I'll run it as a single task instead.
```

If the user declines, continue on route C — never refuse the work.

---

## Route A — worker only (objective already active)

The objective owns delivery. This run ends at **commit + handoff**, exactly like `worker-dev` invoked directly.

```
Skill: worker-dev
Arguments: <objective-id> <task-id>
```

`worker-dev` needs both ids and reads the task file for its `scope`, `role` and `validation_tier`. Resolve them before dispatching:

```bash
SHARED_DIR="$REPO_ROOT/skills/dev-workflow/_shared/scripts"
OBJECTIVE_ID="${OBJECTIVE_ID:-$(bash "$SHARED_DIR/objective-state.sh" active)}"
TASK_ID="$(bash "$SHARED_DIR/objective-state.sh" next "$OBJECTIVE_ID")"
```

If no task matches the user's request — they asked for something the objective does not cover — say so and ask whether to add a task to the objective or run it standalone (route C). Do not invent a task id.

**Hard stop:** do not `gh pr create`, do not `gh pr merge --auto`, do not merge the base branch, and do not run the full repo suite unless the task's `validation_tier` says to. Delivery for the whole objective happens once, in `deliver-dev`.

Report at the end:

```
Task complete — committed on <branch>, handoff written to
.dev-files/objectives/<id>/handoffs/<task-id>.json
No PR opened: objective <id> owns delivery (run /orchestrate-dev or /deliver-dev to ship it).
```

---

## Route B — multi-part objective

```
Skill: orchestrate-dev
Arguments: <the original $ARGUMENTS>
```

`orchestrate-dev` builds the task DAG, runs the workers (in parallel where the platform supports subagents, sequentially where it does not), integrates, and calls `deliver-dev` once. Nothing further is required here.

---

## Route C — simple standalone task (the classic `/start-dev` behaviour)

This is the original flow, unchanged. `worker-dev` and `deliver-dev` are objective-scoped — they need a task file and an objective branch respectively — so a genuine one-off task runs here rather than through them. This is exactly what `deliver-dev` means when it points non-objective work back at "start-dev's delivery path".

Sequence:

1. **Understand** — `gh issue view <n>`, or read the spec file; confirm your understanding in one sentence. When working from a GitHub issue, read the Resume block first and stop if it reports a blocker:
   ```bash
   SHARED_DIR="$REPO_ROOT/skills/dev-workflow/_shared/scripts"
   bash "$SHARED_DIR/parse-issue-resume.sh" <issue_number>
   ```
2. **Workspace** — derive a slug branch (`feat/add-rate-limiting`) and resolve a worktree:
   ```bash
   WT_JSON="$(bash "$SHARED_DIR/resolve-worktree.sh" "$REPO_ROOT" "$BRANCH")"
   WORKTREE="$(echo "$WT_JSON" | jq -r .worktree_path)"
   ```
   All edits happen inside `$WORKTREE`, never in the main checkout.
3. **Implement** — Read before Edit; one conventional commit per logical unit; `git add -p`, never `git add .`.
4. **Validate** — Tier 1 first, then Tier 2 before pushing:
   ```bash
   CMDS=$(bash "$SKILL_DIR/scripts/detect-stack.sh" "$WORKTREE")
   while IFS= read -r cmd; do echo "Running: $cmd"; eval "$cmd" || exit 1; done <<< "$CMDS"
   if bash "$SHARED_DIR/detect-multi-platform-repo.sh" "$WORKTREE"; then
     bash "$SHARED_DIR/run-pre-pr-gates.sh" "$WORKTREE"
   fi
   ```
   Abort on the first failure. Never `--no-verify`, never skip because "it's urgent".
5. **Push and open one PR** — read `references/pr-templates.md` for the right body template and fill every `[…]` placeholder:
   ```bash
   git -C "$WORKTREE" push -u origin HEAD
   gh pr create --title "feat(auth): add rate limiting to login endpoint" --body "<filled template, incl. Closes #N>"
   ```
6. **Hand to `pr-dev`** — merge policy (auto-merge or not) is resolved by `pr-dev` against repository policy, not forced here. Run `/pr-dev <N>`.

**Want the task tracked like an objective anyway?** Create a one-task objective first and the work flows through the same machinery as everything else:

```bash
bash "$SHARED_DIR/objective-state.sh" init "<slug>" --title "<task>"
bash "$SHARED_DIR/objective-state.sh" task-add "<slug>" --role implementer --scope '<glob>' --tier worker
```

Then route A applies on the next invocation, and `deliver-dev` ships it. This is optional — a one-off task does not need objective state.

## Validation tiers

| Route | Tier run here |
|---|---|
| A (worker only) | Tier 1 — targeted tests/lint for the changed code only |
| B (orchestrate) | none directly; the objective runs Tier 1 per task, Tier 2 at integration |
| C (implement + deliver) | Tier 1 while implementing, Tier 2 before the push; Tier 3 is CI |

Tier definitions live in `core/policies/validation.md`.

## Hard rules

- **Never route back to `orchestrate-dev` when it routed here.** The hand-off is one-directional by design; a mutual bounce would loop forever and is invisible until it happens in real use.
- **Never open a PR on route A.** An active objective means delivery is somebody else's job; a PR per task is the exact defect this split exists to remove.
- **Never push directly to the default branch.** Resolve it — `bash skills/dev-workflow/_shared/scripts/default-branch.sh` — rather than comparing against a list of conventional names; a repo whose default is `trunk` or `dev` goes unguarded by any such list. Always a feature branch.
- **Never skip validation**, even if the user says "just push it". Tier 1 always; Tier 2 before any push on route C.
- **Never commit with `git add .`** blindly — stage selectively so secrets and build artifacts stay out.
- **Never make architectural decisions silently** — a choice that changes the public API, schema, or module structure gets surfaced (use `/decision`) before coding.
- **Never force auto-merge from here.** `pr-dev` resolves merge policy from the repository and the user's configuration.
- **Commit messages follow conventional commits** (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`).

## What NOT to do

| Wrong | Right |
|---|---|
| Open a PR for each task of a multi-task objective | Route A/B: one PR per objective, opened by `deliver-dev` |
| `git add . && git commit -m "wip"` | Stage specific files; descriptive conventional commit |
| Push to `main` directly | Feature branch; PR |
| Skip validation because tests are "probably fine" | Run the tier the route calls for; fix failures |
| Hardcode `gh pr merge --auto` here | Let `pr-dev` resolve merge policy |
| Silently switch the user to `orchestrate-dev` | Say which route you picked and why, in one line |
| Create a worktree in an arbitrary path | `resolve-worktree.sh` |

## Quick reference

| Situation | Action |
|---|---|
| `.dev-files/objectives/<id>/` exists and is active | Route A — worker only, no PR |
| Orchestrator set `TAMIRS_ORCHESTRATED=1` | Route A |
| `orchestrate-dev` fell through to us | Route C — skip the multi-part test, never route back |
| Spec file with 4 phases | Route B — `orchestrate-dev` |
| "fix the typo in the README" | Route C |
| Already on a feature branch | Skip worktree setup; implement in place |
| Issue is blocked by another | Surface the blocker; do not start |
| One-off task, no objective | Route C — the flow above |
| Rate limited / switching tools | `/switch-dev handoff #N` |

## Supporting files

| File | Purpose |
|---|---|
| `scripts/detect-objective.sh` | Deterministic route decision (A vs C); prints JSON, always exits 0 |
| `scripts/detect-stack.sh` | Emits every validation command for this repo's stack |
| `references/pr-templates.md` | PR body templates (feature/bug-fix/spec-task/multi-issue/chore) |
| `evals/evals.json` | Route coverage, including "objective active ⇒ no PR" |

## Scope boundary

This skill routes. It does NOT merge PRs, monitor CI, or resolve post-review conflicts — that is `/pr-dev`.
