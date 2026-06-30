---
name: switch-dev
description: 'Use when switching between Claude Code, Cursor, and Codex mid-task without losing context — hand off work via GitHub issue Resume blocks, resume on another platform, or list active agent-owned issues and worktrees. Triggers: switch agent, hand off issue, resume issue, rate limited switch platform, continue on Cursor, pick up where I left off, cross-platform handoff, switch-dev, agent handoff.'
when_to_use: 'User is rate-limited or wants to pause and continue on another AI platform (Claude Code, Cursor, Codex). Phrases: hand off issue #N, resume #N on Cursor, switch to Codex, pick up where I left off, cross-platform handoff, update resume block, agent switch status.'
argument-hint: '[handoff|resume|status] [#issue or target platform]'
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
  capability: developer-workflow
  platforms:
  - claude
  - cursor
  - codex
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
!`gh issue list --state open --label agent:any --limit 3 --json number,title --jq '.[] | "  #\(.number): \(.title)"' 2>/dev/null || true`

# switch-dev

Hand off and resume development work across **Claude Code**, **Cursor**, and **Codex** using GitHub Issues as the shared task memory.

## Why this skill exists

Rate limits and platform preferences force mid-task switches. Session context does not transfer between tools. This skill writes structured **Resume** blocks to GitHub issues (plus `agent:*` labels and handoff comments) so any platform can continue from git state + issue state without re-explaining the task.

## Supporting files

| Path | When to read |
|------|----------------|
| `references/mode-contracts.md` | Parse mode; shared script paths |
| `references/resume-schema.md` | Resume field definitions |
| `references/platform-capabilities.md` | Stay on one platform longer (first-party features) |
| `scripts/parse-mode-args.sh` | Deterministic mode/issue parsing |
| `../_shared/scripts/*` | Platform detection, worktrees, issue Resume I/O |
| `templates/resume-block.md.tmpl` | Canonical Resume markdown |
| `templates/handoff-comment.md.tmpl` | Issue comment shape |

## Resolve paths

```bash
SKILL_DIR="${CLAUDE_SKILL_DIR:-$(git rev-parse --show-toplevel)/skills/dev-workflow/switch-dev}"
SHARED_DIR="$(cd "$SKILL_DIR/../_shared/scripts" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel)"
PLATFORM="$(bash "$SHARED_DIR/detect-platform.sh")"
```

## Parse input

```bash
PARSED="$(bash "$SKILL_DIR/scripts/parse-mode-args.sh" $ARGUMENTS)"
MODE="$(echo "$PARSED" | jq -r .mode)"
ISSUE="$(echo "$PARSED" | jq -r '.issue // empty')"
TARGET="$(echo "$PARSED" | jq -r '.target_platform // "any"')"
```

| Invocation | Mode |
|--------------|------|
| `/switch-dev handoff #42` | handoff |
| `/switch-dev handoff #42 cursor` | handoff → `agent:cursor` |
| `/switch-dev resume #42` | resume |
| `/switch-dev status` | status |
| `/switch-dev #42` | handoff (default) |

---

## Mode: handoff

Triggered when rate-limited, pausing, or intentionally switching platforms.

### Step 1 — Preconditions

1. Identify issue number (from args or ask user)
2. Confirm branch and worktree path (from `git branch --show-current` and cwd)
3. **Push commits** if any unpushed work exists; warn if push fails

```bash
git status -sb
git push -u origin HEAD 2>/dev/null || echo "WARN: unpushed commits remain"
```

### Step 2 — Build Resume fields

From session context, fill:

| Field | Source |
|-------|--------|
| Done | Completed tasks since last Resume |
| Next | Single concrete next step |
| Decisions | Choices made this session |
| Blocked | `none` or blocker description |
| Branch | Current feature branch |
| Worktree | Absolute or repo-relative worktree path |
| Last agent | `$PLATFORM` |

Merge with existing Resume via `parse-issue-resume.sh` — do not erase prior **Done** items; append new completions.

### Step 3 — Update issue

```bash
FIELDS_FILE="$(mktemp)"
jq -nc \
  --arg done "..." \
  --arg next "..." \
  --arg decisions "..." \
  --arg blocked "none" \
  --arg branch "$BRANCH" \
  --arg worktree "$WORKTREE" \
  --arg last_agent "$PLATFORM" \
  '{done: $done, next: $next, decisions: $decisions, blocked: $blocked, branch: $branch, worktree: $worktree, last_agent: $last_agent}' \
  > "$FIELDS_FILE"

TARGET_LABEL="agent:${TARGET}"
[[ "$TARGET" == "any" ]] && TARGET_LABEL="agent:any"

bash "$SHARED_DIR/update-issue-resume.sh" "$ISSUE" "$FIELDS_FILE" "$TARGET_LABEL"
rm -f "$FIELDS_FILE"
```

### Step 4 — Print resume prompt

Output a copy-paste block for the **target** platform:

```
Read issue #N Resume section. Branch: `feat/...`. Worktree: `.<platform>/.worktrees/...`.
Continue the **Next** item. Do not redo items listed under **Done**.
Run `/switch-dev resume #N` or `/start-dev #N` to begin.
```

Suggest `references/platform-capabilities.md` if user might stay on the same platform instead.

---

## Mode: resume

Triggered when opening work on a new platform.

### Step 1 — Load issue

```bash
bash "$SHARED_DIR/parse-issue-resume.sh" "$ISSUE"
```

If `blocked` is not `none` or empty → stop and report blocker.

### Step 2 — Resolve worktree

```bash
BRANCH="$(jq -r .branch <<<"$RESUME")"
bash "$SHARED_DIR/resolve-worktree.sh" "$REPO_ROOT" "$BRANCH"
```

Use returned `worktree_path` for all edits. If Resume **Worktree** points to another platform's path, note it but use **current** platform's worktree (same branch).

### Step 3 — Claim issue

```bash
FIELDS_FILE="$(mktemp)"
# Copy resume fields; update last_agent to $PLATFORM
bash "$SHARED_DIR/update-issue-resume.sh" "$ISSUE" "$FIELDS_FILE" "agent:${PLATFORM}"
```

For resume-only claim without full handoff comment, use `gh issue edit` to swap `agent:*` label if `update-issue-resume` is too heavy — prefer label swap:

```bash
gh issue edit "$ISSUE" --remove-label "agent:any" 2>/dev/null || true
gh issue edit "$ISSUE" --add-label "agent:${PLATFORM}"
```

### Step 4 — Continuation checklist

Print:

```
Issue: #N — <title>
Done: ...
Next: ...
Branch: ...
Worktree: ...
Decisions: ...

Continue with **Next**. Run `/start-dev #N` if implementation not started.
```

---

## Mode: status

Read-only dashboard.

```bash
# Open issues with agent labels
gh issue list --state open --json number,title,labels --jq '
  .[] | select([.labels[].name] | any(startswith("agent:"))) |
  "#\(.number) \(.title) [\([.labels[].name | select(startswith("agent:"))] | join(", "))]"
'

bash "$SHARED_DIR/list-agent-worktrees.sh" "$REPO_ROOT"
```

Print table:

| Issue | Branch | Owner | Worktree | Next |
|-------|--------|-------|----------|------|

Fill **Next** from `parse-issue-resume.sh` per issue when ≤10 open agent issues.

---

## Hard rules

- **Never hand off without updating the Resume block** — issue is the source of truth.
- **Never skip push warning** on handoff when commits are unpushed.
- **Never merge PRs** — use `/pr-dev`.
- **Never use third-party handoff MCP servers** — GitHub + git only.
- **Always use platform worktrees** per `rules/dev/git-worktree-agent-workflow.md`.

## Pipeline integration

| From | To |
|------|-----|
| `plan-dev` | Creates issues with Resume scaffold → `/start-dev #N` |
| `start-dev` | On pause/rate limit → `/switch-dev handoff #N` |
| `switch-dev resume` | → `/start-dev #N` or continue in worktree |
| `pr-dev` | When blocked on human → `/switch-dev handoff #N` |

## Scope boundary

This skill manages **task/session handoff via GitHub**. It does NOT configure MCP servers, install external orchestrators, or modify hook worktree paths under `~/.claude/worktrees/`.
