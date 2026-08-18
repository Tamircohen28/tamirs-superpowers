# Handoff state schema

Handoff state has two layers. Keep them in this order of authority:

1. **Local objective state — primary.** `.dev-files/objectives/<id>/` holds `objective.json`, `tasks/task-NNN.json`, and `handoffs/task-NNN.json`, conforming to `core/workflow/{objective,task,handoff}-schema.json`. It needs no network, no GitHub account, and no `gh`.
2. **GitHub issue Resume block — optional remote persistence.** Useful when the work must be visible to other people or picked up on another machine. It is a mirror, never the source of truth.

Git itself is the third layer and outranks both for *code*: commits are the real record of what was done.

## Handoff record (primary)

Written to `.dev-files/objectives/<id>/handoffs/<task-id>.json`. See `core/workflow/handoff-schema.json` for the full shape. The fields that matter at a switch:

| Field | Meaning |
|---|---|
| `task_id`, `status` | Which task, and `completed` / `partial` / `failed` / `blocked` |
| `summary` | One paragraph the next agent reads first |
| `branch`, `commits` | Where the work actually is. Push before handing off, or the next agent cannot see it. |
| `files_changed` | Every path touched; all must fall inside the task's `scope[]` |
| `validation` | Only commands that were really run, with their result |
| `decisions` | Choices made, with rationale — this is what session context loses |
| `risks`, `followups` | What the next agent must not re-discover the hard way |

## Resume block (optional mirror)

Every agent-task issue created by the `plan-dev` export includes a `## Resume` section.

| Field | Required | Description |
|-------|----------|-------------|
| **Done** | yes | Completed work — bullet list or prose |
| **Next** | yes | Single concrete next action |
| **Decisions** | yes | Architectural or approach choices made |
| **Blocked** | yes | `none` or a description of the blocker |
| **Branch** | yes once coding started | e.g. `worker/auth-system/001` |
| **Worktree** | yes once coding started | e.g. `.agent-worktrees/auth-system/task-001` |
| **Objective** | yes when part of an objective | Objective id, e.g. `auth-system` |
| **Task** | yes when part of an objective | Task id, e.g. `task-001` |
| **Last agent** | yes on handoff | Platform + timestamp |

`Objective` and `Task` are additions; a Resume block written before they existed is still valid and must be read without complaint.

## Agent routing section

| Field | Description |
|-------|-------------|
| **Owner** | Label value: `agent:claude`, `agent:cursor`, `agent:codex`, `agent:gemini`, `agent:opencode`, `agent:any` |
| **Suggested platform** | Hint from planning — advisory, never enforced |

## Labels

| Label | Meaning |
|-------|---------|
| `agent:claude` | Claude Code (or Claude Desktop) owns this issue |
| `agent:cursor` | Cursor owns this issue |
| `agent:codex` | Codex owns this issue |
| `agent:gemini` | Gemini CLI owns this issue |
| `agent:opencode` | OpenCode owns this issue |
| `agent:any` | Unassigned — any platform may claim it |

On `resume`, set Owner to the current platform. On `handoff`, set it to the target platform, or `agent:any` when the next tool is undecided. Provider is **metadata**: it never appears in a branch name or a worktree path.
