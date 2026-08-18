---
name: switch-dev
description: 'Use when switching between AI coding platforms mid-task without losing context — Claude Code, Cursor, Codex, Gemini CLI, or OpenCode. Hand off work via local objective/task/handoff state (optionally mirrored to a GitHub issue Resume block), resume on another platform, or list active objectives, agent-owned issues and worktrees. Triggers: switch agent, hand off issue, resume issue, rate limited switch platform, continue on Cursor, continue on Gemini, continue in OpenCode, pick up where I left off, cross-platform handoff, switch-dev, agent handoff.'
when_to_use: 'User is rate-limited or wants to pause and continue on another AI platform (Claude Code, Cursor, Codex, Gemini CLI, OpenCode). Phrases: hand off issue #N, resume #N on Cursor, switch to Codex, continue this on Gemini, pick up where I left off, cross-platform handoff, update resume block, agent switch status.'
argument-hint: '[handoff|resume|status] [#issue | objective=<id> | task-NNN] [target platform]'
arguments:
- mode
- issue
disable-model-invocation: true
user-invocable: true
allowed-tools:
- Bash
- Read
- Write
- Edit
- Glob
- Grep
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
    role: none
    updated-date: '2026-08-19'
    validation-tier: 0
    capabilities:
      required:
        - shell
        - git
      optional:
        - github_cli
        - worktree_isolation
    tags:
      - handoff
      - resume
      - cross-platform
      - multi-agent
      - objective-state
  capability: developer-workflow
  platforms:
  - claude
  - cursor
  - codex
  - gemini
  - opencode
  tags:
  - handoff
  - resume
  - cross-platform
  - multi-agent
  - github-issues
  - worktree
  updated-date: '2026-06-30'
---

## Live context
!`git rev-parse --show-toplevel 2>/dev/null && bash skills/dev-workflow/_shared/scripts/detect-platform.sh 2>/dev/null | sed 's/^/platform: /' || echo "not a git repo"`
!`ls -1 .dev-files/objectives 2>/dev/null | sed 's/^/objective: /' || true`
!`gh issue list --state open --label agent:any --limit 3 --json number,title --jq '.[] | "  #\(.number): \(.title)"' 2>/dev/null || true`

# switch-dev

Hand off and resume development work across **Claude Code**, **Cursor**, **Codex**, **Gemini CLI** and **OpenCode**.

## Why this skill exists

Rate limits and tool preferences force mid-task switches, and session context does not transfer between tools. The earlier version solved this with GitHub issues as the shared memory — which works, but makes a network service and a `gh` login mandatory for a purely local operation, and quietly assumed only three platforms exist.

State now lives **locally first**: `.dev-files/objectives/<id>/` holds the objective, its tasks, and a structured handoff record per task, conforming to `core/workflow/{objective,task,handoff}-schema.json`. Git holds the code. The GitHub issue Resume block is still fully supported as **optional remote persistence** — for work that other people need to see, or a switch to a different machine.

## Validation tier

Tier 0. This skill moves state; it runs no tests and makes no code commits (it will push existing commits so the next agent can see them).

## Supporting files

| Path | When to read |
|------|----------------|
| `references/mode-contracts.md` | Mode semantics, argument shapes, shared script table |
| `references/resume-schema.md` | Handoff record fields and the Resume block mirror |
| `references/platform-capabilities.md` | All five platforms; how to degrade a handoff for the target |
| `scripts/parse-mode-args.sh` | Deterministic mode/issue/objective/task/platform parsing |
| `templates/resume-block.md.tmpl` | Canonical Resume markdown |
| `templates/handoff-comment.md.tmpl` | Issue comment shape |
| `../_shared/scripts/*` | Platform detection, worktrees, objective state, handoff I/O, issue Resume I/O |

## Resolve paths and platform

```bash
SKILL_DIR="${CLAUDE_SKILL_DIR:-$(git rev-parse --show-toplevel)/skills/dev-workflow/switch-dev}"
SHARED_DIR="$(cd "$SKILL_DIR/../_shared/scripts" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel)"
PLATFORM="$(bash "$SHARED_DIR/detect-platform.sh")"
```

`detect-platform.sh` returns one of `claude`, `cursor`, `codex`, `gemini`, `opencode`. If it returns a value you do not recognise, treat the platform as `unknown`, ask the user which tool they are on rather than guessing, and continue — an unrecognised platform must never abort a handoff.

## Parse input

```bash
PARSED="$(bash "$SKILL_DIR/scripts/parse-mode-args.sh" $ARGUMENTS)"
MODE="$(echo "$PARSED" | jq -r .mode)"
ISSUE="$(echo "$PARSED" | jq -r '.issue // empty')"
OBJECTIVE="$(echo "$PARSED" | jq -r '.objective // empty')"
TASK="$(echo "$PARSED" | jq -r '.task // empty')"
TARGET="$(echo "$PARSED" | jq -r '.target_platform // "any"')"
```

| Invocation | Result |
|--------------|------|
| `/switch-dev handoff #42` | handoff, issue 42 |
| `/switch-dev handoff #42 cursor` | handoff → `agent:cursor` |
| `/switch-dev handoff objective=auth-system task-002 gemini` | handoff of one task → `agent:gemini` |
| `/switch-dev resume #42` | resume |
| `/switch-dev resume objective=auth-system` | resume the whole objective |
| `/switch-dev status` | status |
| `/switch-dev #42` | handoff (default mode) |

When neither an issue nor an objective is given, fall back to the single active objective under `.dev-files/objectives/`; if there is more than one, ask which.

---

## Mode: handoff

### Step 1 — Preconditions

1. Identify the unit being handed off: objective + task, or issue number, or just the current branch.
2. Confirm branch and worktree (`git branch --show-current`, cwd).
3. **Push commits** — the next agent can only see pushed work.

```bash
git status -sb
git push -u origin HEAD 2>/dev/null || echo "WARN: unpushed commits remain — the next agent will not see them"
```

### Step 2 — Write the local handoff record (primary)

```bash
bash "$SHARED_DIR/handoff.sh" emit "$OBJECTIVE" "$TASK" \
  --status partial \
  --summary "..." \
  --branch "$BRANCH" \
  --commit "$SHA" \
  --file 'src/auth/middleware.ts:modified' \
  --validation 'npm test -- src/auth|worker|pass' \
  --decision 'used jose over jsonwebtoken|maintained, ESM-native' \
  --followup 'refresh-token rotation still unimplemented|blocking'
```

`handoff.sh emit` writes and validates the record against `core/workflow/handoff-schema.json`; `handoff.sh show <objective> <task>` reads one back and `handoff.sh list <objective>` lists them. The fields that carry the context a session loses:

| Field | Fill with |
|---|---|
| `status` | `completed`, `partial`, `failed`, or `blocked` |
| `summary` | One paragraph: what was done, what the next agent must know first |
| `branch`, `commits` | Real branch and real SHAs — never fabricated |
| `files_changed` | Every path touched |
| `validation` | Only commands actually run, with their result; `skipped` needs a `skip_reason` |
| `decisions` | Choices made and why — this is the part that is otherwise lost |
| `risks`, `followups` | What the next agent must not rediscover the hard way |

If `handoff.sh` is unavailable, write the JSON to `.dev-files/objectives/<id>/handoffs/<task-id>.json` directly — the path and the schema are the contract, the helper is a convenience.

**No objective?** A plain branch handoff is still valid: write the same record under `.dev-files/objectives/adhoc-<branch-slug>/handoffs/task-001.json`, or, when the user wants nothing on disk, put the same fields in the issue Resume block and say that local state was skipped.

### Step 3 — Mirror to GitHub (optional)

Only when an issue number is in play and `gh` is available:

```bash
FIELDS_FILE="$(mktemp)"
jq -nc \
  --arg done "..." --arg next "..." --arg decisions "..." --arg blocked "none" \
  --arg branch "$BRANCH" --arg worktree "$WORKTREE" \
  --arg objective "$OBJECTIVE" --arg task "$TASK" \
  --arg last_agent "$PLATFORM" \
  '{done: $done, next: $next, decisions: $decisions, blocked: $blocked, branch: $branch, worktree: $worktree, objective: $objective, task: $task, last_agent: $last_agent}' \
  > "$FIELDS_FILE"

TARGET_LABEL="agent:${TARGET:-any}"
bash "$SHARED_DIR/update-issue-resume.sh" "$ISSUE" "$FIELDS_FILE" "$TARGET_LABEL"
rm -f "$FIELDS_FILE"
```

Merge with the existing Resume via `parse-issue-resume.sh` — never erase prior **Done** items; append.

If `gh` is missing, the repo has no remote, or the push failed: say so in one line and continue. A missing mirror is not a failed handoff.

### Step 4 — Check the target's capabilities

Read the target platform's row in `core/capabilities/platforms.json` (summary in `references/platform-capabilities.md`) for anything the remaining work assumes. Name any degradation explicitly in the handoff note — e.g. "target has no `parallel_subagents`: run waves 2 and 3 sequentially".

### Step 5 — Print the resume prompt

```
Read .dev-files/objectives/auth-system/handoffs/task-002.json (and issue #42 Resume, if you have gh).
Branch: `worker/auth-system/002`. Worktree: `.agent-worktrees/auth-system/task-002`.
Continue the **Next** item. Do not redo anything under **Done**.
Degraded here: no parallel subagents — run remaining tasks sequentially.
Start with: /switch-dev resume objective=auth-system task-002
```

Suggest `references/platform-capabilities.md` when the user might be better off staying on the current tool.

---

## Mode: resume

### Step 1 — Load state, local first

```bash
bash "$SHARED_DIR/objective-state.sh" show "$OBJECTIVE"
bash "$SHARED_DIR/objective-state.sh" tasks "$OBJECTIVE"
bash "$SHARED_DIR/handoff.sh" show "$OBJECTIVE" "$TASK"
# Optional mirror, when an issue is known and gh is available:
bash "$SHARED_DIR/parse-issue-resume.sh" "$ISSUE"
```

If the two disagree, **local state and git win** — the mirror is a copy and may be stale. Say which one you used.

If `blocked` / `status: blocked` is set, stop and report the blocker before doing anything else.

### Step 2 — Resolve the worktree

```bash
bash "$SHARED_DIR/resolve-worktree.sh" "$REPO_ROOT" "$BRANCH"
```

Use the returned `worktree_path` for all edits. If the recorded worktree is a legacy `.<platform>/.worktrees/…` path from another tool, note it and use the current resolution for the **same branch** — the branch is the identity, the path is not.

### Step 3 — Claim it

```bash
gh issue edit "$ISSUE" --remove-label "agent:any" 2>/dev/null || true
gh issue edit "$ISSUE" --add-label "agent:${PLATFORM}"
```

Skip silently when there is no issue or no `gh`. Locally, record the claim by setting the task's `provider` to the current platform — metadata only, never part of a branch or path.

### Step 4 — Continuation checklist

```
Objective: auth-system — Implement authentication system
Task: task-002 (implementer) — status partial
Done: ...
Next: ...
Branch / worktree: ...
Decisions: ...
Risks / followups: ...
Source: local handoff record (issue #42 mirror was 2 commits stale)

Continue with **Next**. Run /start-dev to pick the task up (no PR — the objective owns delivery).
```

---

## Mode: status

Read-only dashboard. Local first, GitHub if available.

```bash
# Local objectives and task states
for d in .dev-files/objectives/*/; do
  [ -f "$d/objective.json" ] || continue
  jq -r '"\(.id)  [\(.status)]  \(.title)"' "$d/objective.json"
  jq -r '"    \(.id)  \(.role)  \(.status)"' "$d"/tasks/*.json 2>/dev/null
done

# Optional: agent-labelled issues
gh issue list --state open --json number,title,labels --jq '
  .[] | select([.labels[].name] | any(startswith("agent:"))) |
  "#\(.number) \(.title) [\([.labels[].name | select(startswith("agent:"))] | join(", "))]"
' 2>/dev/null || echo "(gh unavailable — local state only)"

bash "$SHARED_DIR/list-agent-worktrees.sh" "$REPO_ROOT"
```

Print:

| Objective / Issue | Task | Branch | Owner | Worktree | Next |
|---|---|---|---|---|---|

---

## Hard rules

- **Never hand off without writing the handoff record.** A verbal summary in a chat window is not state.
- **Never fabricate commits or validation results** in a handoff. Only what actually ran.
- **Never skip the push warning** when commits are unpushed — invisible work is the most common handoff failure.
- **Never treat GitHub as required.** `gh` missing degrades the mirror, never the handoff.
- **Never let the mirror override local state and git** when they disagree.
- **Never encode the provider in a branch name or worktree path.** Provider is metadata.
- **Never merge PRs** — that is `/pr-dev`.
- **Never use third-party handoff MCP servers** — local files, git, and (optionally) GitHub only.
- **Never assume the target platform's capabilities.** Check the registry and state the degradation.

## Pipeline integration

| From | To |
|------|-----|
| `plan-dev` | Writes the objective + tasks (issues optional) → `/switch-dev status` shows them |
| `orchestrate-dev` | Emits per-task handoffs → `/switch-dev resume objective=<id> task-NNN` |
| `worker-dev` / `start-dev` | On pause or rate limit → `/switch-dev handoff` |
| `switch-dev resume` | → continue in the worktree, or `/start-dev` |
| `pr-dev` | When blocked on a human → `/switch-dev handoff #N` |

## Scope boundary

This skill moves **task/session state** between tools. It does NOT configure MCP servers, install external orchestrators, run validation, or modify hook worktree paths under `~/.claude/worktrees/`.
