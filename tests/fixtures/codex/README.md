# Codex hook payload fixtures

Stdin payloads shaped the way Codex CLI hands them to a plugin hook, consumed by
`tests/hooks/test-codex-contract.sh`. `cwd` is the placeholder `__CWD__`; the test
substitutes the temp repo it builds. `model` is the placeholder string `placeholder`
on purpose — Codex sends the session's model id there, and this repo never writes a
model name down.

## Provenance

**Measured on codex-cli 0.163.0, 2026-10-17** (npm `@openai/codex` installed into a
throwaway prefix; a probe plugin with a recording hook, installed from a local
marketplace; one `codex exec --dangerously-bypass-hook-trust --json` session against
a dead local provider endpoint, no credential, no login — the model call never
succeeds, but `SessionStart` and `UserPromptSubmit` fire before it). The recorded
payloads, verbatim apart from paths:

```json
{"session_id":"…","transcript_path":null,"cwd":"…","hook_event_name":"SessionStart","model":"…","permission_mode":"bypassPermissions","source":"startup"}
{"session_id":"…","turn_id":"…","transcript_path":null,"cwd":"…","hook_event_name":"UserPromptSubmit","model":"…","permission_mode":"bypassPermissions","prompt":"say hi"}
```

The hook's environment carried `PLUGIN_ROOT`, `PLUGIN_DATA`, `CLAUDE_PLUGIN_ROOT`,
`CLAUDE_PLUGIN_DATA` and `CODEX_HOME` (measured under `env -i`, so nothing was
inherited); the working directory was the session `cwd`.

**Documented, not run** (a tool call or a completed turn needs a live model):
`PreToolUse`/`PostToolUse` (`tool_name`, `tool_use_id`, `tool_input`; Bash and
`apply_patch` carry `tool_input.command`; PostToolUse adds `tool_response`),
`Stop` (`stop_hook_active`, `last_assistant_message`), `SubagentStop` (plus
`agent_id`, `agent_type`, `agent_transcript_path`), `PreCompact` (`trigger`),
`SessionEnd` (`reason`, always `other`) — from https://learn.chatgpt.com/docs/hooks.
The `apply_patch` envelope is the V4A shape `tests/hooks/lib/apply-patch-fixtures.sh`
already builds.

| Fixture | Event | Shape |
|---|---|---|
| `session-start.json` | SessionStart | measured |
| `user-prompt-submit.json` | UserPromptSubmit | measured |
| `session-end.json` | SessionEnd | documented |
| `pre-tool-use-apply-patch-protected.json` | PreToolUse, `apply_patch` → `yarn.lock` | documented |
| `pre-tool-use-apply-patch-ordinary.json` | PreToolUse, `apply_patch` → `src/app.ts` | documented |
| `pre-tool-use-bash-ordinary.json` | PreToolUse, `Bash` | documented |
| `pre-tool-use-bash-docker.json` | PreToolUse, `Bash` creating a container | documented |
| `post-tool-use.json` | PostToolUse, `apply_patch` | documented |
| `pre-compact.json` | PreCompact | documented |
| `stop.json` | Stop | documented |
| `subagent-stop.json` | SubagentStop | documented |

Re-measure after a Codex release that changes the hooks page; the test asserts the
common fields (`session_id`, `transcript_path`, `cwd`, `hook_event_name`, `model`) on
every fixture so a drift in this table is caught there first.
