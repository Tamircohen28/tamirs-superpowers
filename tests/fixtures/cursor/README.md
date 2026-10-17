# Cursor hook payload fixtures

One JSON payload per Cursor hook event, built from the fields the Cursor hooks
reference documents for that event (https://cursor.com/docs/agent/hooks, read for
desktop 3.24 — see `docs/engineering/roadmap/v5-research/cursor.md`), not from a
captured session. They are what `tests/test-cursor-lifecycle.sh` feeds every entry of
`platforms/cursor/hooks.json`.

Every fixture except `workspaceOpen.json` carries the common fields
(`conversation_id`, `generation_id`, `model`, `model_id`, `hook_event_name`,
`cursor_version`, `workspace_roots`, `transcript_path`), so
`hook_detect_platform` in `hooks/lib/hook-output.sh` reports `cursor` for all of them.
`workspaceOpen` omits the conversation fields by design — Cursor fires it before any
conversation exists — and is recognised by `cursor_version` + `workspace_roots`.

Every path is rooted at `/workspace/project`. The test rewrites that prefix, in every
string field, onto a temporary git repo; no fixture names a real machine path.

| Fixture | Event | What it exercises |
|---|---|---|
| `workspaceOpen.json` | `workspaceOpen` | `cursor-workspace-open.sh` → `pluginPaths` |
| `sessionStart.json` | `sessionStart` | `session-init.sh` → `additional_context`; `session_id` present, no `cwd` |
| `sessionEnd.json` | `sessionEnd` | the three SessionEnd peers print nothing; `reason: user_close` |
| `beforeSubmitPrompt.json` | `beforeSubmitPrompt` | an ordinary prompt — every prompt hook answers `{"continue":true}` |
| `beforeSubmitPrompt-goal-unsatisfiable.json` | `beforeSubmitPrompt` | the 2026-08-17 incident condition, verbatim → `goal-condition-lint.sh` blocks with `continue:false` |
| `beforeSubmitPrompt-goal-ok.json` | `beforeSubmitPrompt` | a checkable `/goal` passes |
| `beforeSubmitPrompt-cost.json` | `beforeSubmitPrompt` | `skill-suggest.sh` names `session-report` as `user_message` |
| `beforeSubmitPrompt-sweeping.json` | `beforeSubmitPrompt` | `scope-decompose-reminder.sh` nudges as `user_message` |
| `preToolUse-write.json` | `preToolUse` | a `Write` into the main checkout — the path guards judge it |
| `preToolUse-read.json` | `preToolUse` | a `Read` — every guard allows |
| `beforeShellExecution.json` | `beforeShellExecution` | `guard-sensitive-files.sh` on a read-only command |
| `postToolUse.json` | `postToolUse` | the agent-tools guard's pop path |
| `stop.json` | `stop` | `check-done.sh` must not emit `followup_message` |
| `preCompact.json` | `preCompact` | `precompact-snapshot.sh` writes its file; `context_usage_percent` et al. |
| `subagentStart.json` | `subagentStart` | **not wired** — kept so the test can prove why (`tool_call_id` = the Task `tool_use_id`) |
| `subagentStop.json` | `subagentStop` | **not wired** — the test re-checks `subagent-handoff-check.sh`'s stdout and flips to a warning once it speaks Cursor |
| `postToolUseFailure.json` | `postToolUseFailure` | **not wired** — observation point, documented as available |

Payload-field additions by desktop version, for anyone extending these: 3.22 added
`parent_tool_call_id` (`preToolUse`/`postToolUse`/`postToolUseFailure`) and
`child_conversation_id` (`subagentStop`); 3.24 added `tool_use_id` on the shell and
MCP hooks and sets `transcript_path` whenever a transcript exists.
