---
name: plan-dev
description: "Plan development work — structure tasks into phases, review with user, then create GitHub issues. Use when the user asks to plan, decompose, structure, organize, or break down a task, spec, issue URL, or list of fixes into phases before coding."
when_to_use: "User wants to plan or structure development work into phases and create GitHub issues — invoked as /plan-dev or when the user asks to 'plan this', 'break this into phases', 'create issues for', or 'decompose this spec/task'."
argument-hint: "[task description, file paths, review doc, or GitHub issue URL]"
model: claude-sonnet-4-6
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
metadata:
  capability: developer-workflow
  tags:
    - planning
    - phases
    - github-issues
    - workflow
  updated-date: "2026-06-07"
---

# plan-dev

Structure raw tasks into reviewed phases, then upload each as a GitHub issue.

## Input

Parse `$ARGUMENTS` as the task input. This can be:
- A free-text task description
- A file path to a review, spec, or requirements doc
- A GitHub issue URL to decompose
- A list of tasks/fixes

If empty, ask for a task description and stop.

## Required execution flow

### 1. Analyze input and classify work

Read the input thoroughly. Classify each piece of work by:
- **Type**: `fix`, `feat`, `chore`, `docs`, `test`, `refactor`
- **Area**: the part of the codebase affected (e.g. `backend`, `frontend`, `infra`, `tests`, `docs`)
- **Complexity**: simple (single commit), moderate (few files), complex (cross-cutting)

If the input is a GitHub issue URL, fetch it:
```bash
gh issue view <number>
```

### 2. Structure into phases and tasks

Organize work into logical phases. Each phase becomes one GitHub issue. Group by:
1. **Dependencies** — what must land first for other work to build on
2. **Theme** — related changes that should be reviewed together
3. **Risk** — isolate risky changes from safe ones

For each task within a phase, specify:
- **Title**: concise imperative description
- **Files to modify**: specific paths
- **What to change**: concrete description
- **Verification**: how to confirm it works

### 3. Present plan for review

Print the structured plan in this format:

```
## Phase N: <phase title>
**Issue title**: <title for GitHub issue>
**Labels**: <type> (feat / fix / chore / docs / test / refactor)

### Tasks
- [ ] <task 1> — <files> — <what to change>
- [ ] <task 2> — <files> — <what to change>

### Verification
- [ ] <how to verify>
```

### 4. STOP and wait for approval

Tell the user: "Review the plan above. Reply **approved** to create GitHub issues, or tell me what to change."

**Do NOT create issues until the user explicitly approves.**

### 5. Create GitHub issues

After approval, create each phase as a GitHub issue:

```bash
gh issue create \
  --title "<issue title>" \
  --label "<type>" \
  --body "$(cat <<'EOF'
## Summary
<phase description>

## Tasks
- [ ] <task 1>
- [ ] <task 2>

## Verification
- [ ] <verification steps>

🤖 Generated with Claude Code
EOF
)"
```

Report all created issue numbers and URLs.

## What this skill does NOT do

- Create branches or worktrees
- Write any code
- Push to remote
- Open PRs

For implementation, hand off to `/start-dev`.
