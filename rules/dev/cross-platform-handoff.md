---
alwaysApply: false
globs: [".dev-files/objectives/**/*", ".agent-worktrees/**/*", ".claude/.worktrees/**/*", ".cursor/.worktrees/**/*", ".codex/.worktrees/**/*"]
---

# Cross-Provider Handoff

Hand long-running work between the surfaces this repo supports — **Claude Code**, **Claude Desktop**, **Codex CLI**, **Cursor IDE**, **Gemini CLI**, **OpenCode CLI** — without losing task context. Six supported surfaces across five platforms (Claude, Codex, Cursor, Gemini, OpenCode); the surface, not the vendor, is what a handoff names.

The unit that survives a handoff is the **task**, not the session and not the platform. A task carries a role, a scope, a validation tier, and a handoff record. Which provider executed it is metadata.

Canonical state lives in the repo working tree:

```text
.dev-files/objectives/<objective-id>/
├── objective.json     ← core/workflow/objective-schema.json
├── plan.md
├── tasks/task-NNN.json    ← core/workflow/task-schema.json
├── handoffs/task-NNN.json ← core/workflow/handoff-schema.json
└── integration.json
```

Git holds the code state (see [`git-worktree-agent-workflow.md`](git-worktree-agent-workflow.md)); `.dev-files/objectives/` holds the workflow state (see [`dev-files-workspace.md`](dev-files-workspace.md)). Together they are sufficient. **No external service, database, or orchestrator is required for a handoff.**

---

## When to hand off

- Rate limit or quota exhaustion on the current provider
- Ending a session mid-task
- A deliberate provider switch — a capability the current provider lacks, or one it does better
- A role change (implementer → reviewer) that a different provider is better suited to

---

## The handoff contract

**Outgoing agent — before stopping:**

1. Commit. Uncommitted work does not survive a handoff, and no one else may discard it.
2. Write `handoffs/task-NNN.json` per [`core/workflow/handoff-schema.json`](../../core/workflow/handoff-schema.json):

   ```json
   {
     "task_id": "task-001",
     "status": "completed",
     "commits": ["abc1234"],
     "files_changed": ["src/auth/session.ts"],
     "validation": [
       { "tier": 1, "command": "make lint", "result": "pass" }
     ],
     "decisions": ["session cookie is httpOnly; rejected localStorage"],
     "risks": ["refresh-token rotation untested"],
     "followups": ["add rotation test in task-004"],
     "provider": "claude_code"
   }
   ```

   `provider` uses the snake_case **surface** id from [`core/capabilities/platforms.json`](../../core/capabilities/platforms.json) — `claude_code`, `claude_desktop`, `codex`, `cursor`, `gemini_cli`, `opencode`. Those ids live under `.platforms.<platform>.surfaces`, not at the registry root: the registry is rooted at the platform and lists its surfaces underneath. `status` is `completed`, `blocked`, or `partial`. A `blocked` or `partial` handoff must say what is left in `followups` — an empty followups list on a partial handoff is a broken handoff.
3. Update `tasks/task-NNN.json` `status`, and `objective.json` if the objective's shape changed.
4. Optionally push the worker branch — required only if the next agent is on a different machine.

**Incoming agent — before touching code:**

1. Read `objective.json`, then the task and its `depends_on` chain.
2. Read every existing handoff for the objective. Decisions recorded there are binding; do not silently re-decide them.
3. Resolve the worktree for the task (`resolve-worktree.sh`) rather than creating a new one — an existing worktree with the branch already checked out is the state you are resuming.
4. Verify the recorded commits are present (`git log`) before trusting the handoff.

Never fabricate a `validation` entry you did not run. Recording a check you skipped is faking validation — a hard invariant ([`core/policies/safety.md`](../../core/policies/safety.md)).

---

## Optional remote persistence (GitHub)

Local files are primary. GitHub is an **optional mirror**, useful when:

- the handoff crosses machines or people;
- the work should be visible to humans who are not in a session;
- an issue already exists and the team tracks work there.

When mirroring, `plan-dev` and the `agent_task` issue template render a **Resume** block from the same state:

```markdown
## Resume
- **Objective:** auth-system
- **Task:** task-001 (role: implementer)
- **Done:** ...
- **Next:** ...
- **Decisions:** ...
- **Blocked:** none
- **Branch:** worker/auth-system/001
- **Last provider:** cursor @ 2026-08-19T12:00:00Z
```

Rules for the mirror:

- It is **generated from** `.dev-files/objectives/`, never the other way round. On disagreement, local files win.
- Every skill that mirrors must work with `gh` absent — skip the mirror, say so plainly, continue. See [`gh-cli-preference.md`](gh-cli-preference.md).
- Do not require a GitHub issue to exist before a task can start. An objective that never touches GitHub is a normal objective.

Routing labels (`agent:any`, and provider labels where a repo uses them) are a convenience for humans scanning the issue list. They do not control execution; provider selection is a separate resolution step described in [`core/providers/selection.md`](../../core/providers/selection.md).

---

## Provider capability differences

Never assume the next surface has subagents, hooks, background tasks, a statusline, or the same MCP behavior. Before relying on one, check [`core/capabilities/platforms.json`](../../core/capabilities/platforms.json) and degrade explicitly: use a stated fallback, or say the feature is unsupported here. Never silently pretend it worked.

Capabilities hang off a surface, so look the surface id up under its platform:

```bash
jq -r --arg p claude_code '(first(.platforms[]?.surfaces[$p]? | select(. != null)) // .platforms[$p]?)
     | .capabilities | to_entries[] | "\(.key): \(.value.status)"' core/capabilities/platforms.json
```

[`scripts/lib/registry.sh`](../../scripts/lib/registry.sh) performs that walk once and returns a flat, one-entry-per-supported-surface view. Read it rather than re-deriving the path.

| Surface | Handoff note |
|----------|--------------|
| Claude Code | Subagents available; `EnterWorktree` may have placed the worktree in a legacy path |
| Claude Desktop | Same plugin artifact as Claude Code; no terminal, so shell-driven steps do not carry over |
| Codex CLI | Manual worktrees; reads `AGENTS.md` as its entrypoint into canonical rules |
| Cursor IDE | Manual worktrees; `.mdc` rules load the canonical rules by reference |
| Gemini CLI | Installed as an extension; manual worktrees |
| OpenCode CLI | Native skills; agent definitions generated from canonical `agents/`; no hooks or statusline |

`platforms.json` is the authority for every one of these claims — the table is orientation, not evidence.

The registry also lists four **unverified** surfaces — `codex_ide`, `cursor_cli`, `gemini_code_assist`, `opencode_desktop`. They carry no capabilities block at all, because nobody measured them; the registry claims nothing about them in either direction. **Never hand a task off to an unverified surface**, and never record one in a handoff's `provider` field.

---

## Skills involved

| Skill | Role in handoff |
|-------|-----------------|
| `plan-dev` | Produces `objective.json` + tasks; optionally mirrors to issues |
| `start-dev` | Executes one task; loads prior handoffs; writes its own |
| `switch-dev` | `handoff`, `resume`, `status` modes over the local objective state |
| `pr-dev` | Delivery lifecycle for the objective, from the integration worktree |

## Out of scope

No third-party handoff MCP servers, no external orchestrators, no persistent task service. Git plus local files, with GitHub as an optional mirror.
