# Resume block schema

Every agent-task issue created by `plan-dev` or the `agent_task` template includes a `## Resume` section. Agents **must** keep it current before handoff.

## Fields

| Field | Required | Description |
|-------|----------|-------------|
| **Done** | yes | Completed work — bullet list or prose |
| **Next** | yes | Single concrete next action |
| **Decisions** | yes | Architectural or approach choices made |
| **Blocked** | yes | `none` or description of blocker |
| **Branch** | yes when coding started | e.g. `feat/add-rate-limiting` |
| **Worktree** | yes when coding started | e.g. `.cursor/.worktrees/feat-add-rate-limiting` |
| **Last agent** | yes on handoff | Platform + timestamp |

## Agent routing section

| Field | Description |
|-------|-------------|
| **Owner** | GitHub label value: `agent:claude`, `agent:cursor`, `agent:codex`, `agent:any` |
| **Suggested platform** | Hint from planning — not enforced |

## Labels

| Label | Meaning |
|-------|---------|
| `agent:claude` | Claude Code owns this issue |
| `agent:cursor` | Cursor owns this issue |
| `agent:codex` | Codex owns this issue |
| `agent:any` | Unassigned — any platform may claim |

On `resume`, set Owner label to current platform. On `handoff`, set to target platform or `agent:any`.
