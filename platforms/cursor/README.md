# platforms/cursor — the Cursor adapter

What a Cursor install of this plugin gets, and why. The capability claims live in
[`core/capabilities/platforms.json`](../../core/capabilities/platforms.json); the user-facing
install guide is [`docs/user/install/cursor.md`](../../docs/user/install/cursor.md). This file
is the engineering note behind `hooks.json`.

| File | What it is |
|---|---|
| `adapter.yaml` | Thin pointer: manifest, generated files, validation command |
| `hooks.json` | **Hand-written**, Cursor's own 21-event format — the hook bundle described below |
| `mcp.json` | Generated from the shared MCP source with `${GITHUB_TOKEN}` as a declared plugin variable |
| `rules.map.json` | Which `rules/dev/*.md` become which `.cursor/rules/*.mdc` |
| `templates/` · `setup.conf` · `capture.conf` | Machine-level setup (`scripts/setup.sh --targets cursor`) |

## Why there is a separate hooks bundle at all

Cursor never reads a plugin's `hooks/hooks.json` as a Claude file: it imports Claude-format
hooks only from `.claude/settings*.json`, and its plugin component discovery expects
`hooks/hooks.json` to be in **Cursor's** camelCase format. This repo's file at that path is
Claude's PascalCase format, so an undeclared `hooks` component would bind to it and load
nothing. `.cursor-plugin/plugin.json` therefore declares `"hooks": "./platforms/cursor/hooks.json"`
— a Cursor-format bundle at a deliberately non-default path.

The bundle runs **the same scripts** as Claude and Codex. There are no forked copies under
`platforms/cursor/`; three libraries carry the dialect:

- `hooks/lib/hook-output.sh` — detects Cursor from the payload (`conversation_id` /
  `cursor_version` / `workspace_roots`) and speaks `{permission, user_message, agent_message}`
  on the tool events.
- `hooks/lib/cursor-output.sh` — the event shapes `hook-output.sh` does not cover:
  `{continue, user_message}` for `beforeSubmitPrompt`, `{additional_context}` for `sessionStart`,
  `{pluginPaths}` for `workspaceOpen`, `{user_message}` for the Stop family, nothing for `sessionEnd`.
  Its Stop-family helpers never emit `followup_message` (see below).
- `hooks/lib/write-targets.py` — already treats Cursor's `Shell` like `Bash`.

Measured 2026-09-23 on `cursor-agent` 2026.07.17-3e2a980: `preToolUse` carries `tool_name`
`Read`/`Write`/`Shell` with `tool_input.file_path` / `tool_input.command`, the names and fields
Claude uses, so the path guards needed no translation. Desktop ≥ 3.22/3.24 adds `tool_use_id`
and `parent_tool_call_id`, which `cursor-agent-tools-guard.sh` keys its frames on.

## What the bundle wires, and why each event

Ten of Cursor's 21 events. **Wired because a script needs it, not to fill the table.**

| Event | Scripts | Tier | Why | Output shape |
|---|---|---|---|---|
| `workspaceOpen` | `cursor-workspace-open.sh` | convenience | The one route to auto-load a **checkout** of this plugin: returns `{"pluginPaths":[…]}` from `SUPERPOWERS_CURSOR_PLUGIN_PATH` (colon-separated; only absolute directories carrying a plugin manifest are returned, the rest are named on stderr). Empty list otherwise. | `pluginPaths` |
| `sessionStart` | `session-init.sh` | worktree-lifecycle | Session output dir, session-files dir, prior session-files on resume, stale-worktree prune. Session key falls back to `conversation_id`, directory to `workspace_roots[0]` — the same fallbacks `enforce-worktree-edits.sh` uses, so every hook in a session keys its state identically. | `additional_context` (Cursor's `env` is **not** emitted yet: its value shape is undocumented and a mismatch could cost the context next to it) |
| `sessionEnd` | `session-end.sh`, `release-agent-claims.sh`, `handoff-reminder.sh` | worktree-lifecycle / safety / convenience | Archive session files, prune worktrees, release work claims, remind to hand off from an active worktree (`~/.cursor/worktrees/<repo>/<name>` counts). Cursor documents **no output** for this event, so all three print nothing; the handoff reminder goes to stderr. | *(empty)* |
| `beforeSubmitPrompt` | `goal-condition-lint.sh`, `scope-decompose-reminder.sh`, `skill-suggest.sh` | safety / convenience / convenience | The `UserPromptSubmit` ports. `goal-condition-lint` refuses an unsatisfiable `/goal` with `{"continue":false,"user_message":<menu>}` — Cursor's documented block route for this event, on exit 0. The two reminders answer `{"continue":true,"user_message":…}`. **Cursor has no `additional_context` on this event**: a message here reaches the *user*, not the model, so `skill-suggest` words its Cursor note for the user ("name the skill in your prompt") where the Claude note tells the model to invoke it. Every pass is an explicit `{"continue":true}`, never empty stdout. | `continue`, `user_message` |
| `preToolUse` | `cursor-agent-tools-guard.sh`, `enforce-worktree-edits.sh`, `guard-sensitive-files.sh`, `protect-other-branches.sh`, `skill-creator-guard.sh` | safety ×4, contributor | The path guards, the branch-concurrency guard and the agent `tools:` allowlist guard (Cursor does not enforce the frontmatter list itself). `skill-creator-guard` is a contributor-tier hook: off unless the tier is on, and fail-open. | `permission`, `user_message`, `agent_message` |
| `beforeShellExecution` | `guard-sensitive-files.sh` | safety | A shell command is a write path too (`tee`, redirects, `sed -i`). | `permission`, `user_message`, `agent_message` |
| `postToolUse` | `cursor-agent-tools-guard.sh` | safety (pop) | Pops the subagent frame when its `Task` completes. A missed pop leaves the frame active — over-restrictive, never unguarded — so this entry is fail-open on purpose. | `{"permission":"allow"}` from `hook_allow`; ignored by an observational event |
| `stop` | `check-done.sh` | convenience | The definition-of-done reminder. **Stays advisory**: Cursor's `followup_message` is auto-submitted as the user's next message, so the reminder stays on stderr and stdout is the cross-host no-op `{}` (`hook_stop_ok`). | `{}` |
| `preCompact` | `precompact-snapshot.sh` | convenience | Writes `.dev-files/compaction/latest.md` (branch, dirty files, objective, recent commits) before context is lost — a file survives compaction unconditionally. Observational event; the script's Claude-dialect `systemMessage` is ignored there (a Cursor `user_message` branch is a pending patch). | `user_message` documented; file is the value |

### Fail-closed on the safety tier

`failClosed: true` is Cursor's `onFailure: "block"`: a guard that crashes, times out or exits
non-zero/non-2 **denies** instead of allowing. It is set on exactly the safety-tier entries —
`enforce-worktree-edits.sh`, `guard-sensitive-files.sh` (both events),
`protect-other-branches.sh`, `cursor-agent-tools-guard.sh` on `preToolUse` — and on nothing
else, so a broken reminder costs a reminder, not a tool call. Those entries also carry
`loop_limit: null`: Cursor caps a hook at 5 firings per loop by default, and a guard that stops
guarding after five denials is not a guard.

Two Cursor rules the bundle relies on, both from the hooks reference: the permission hooks
(`preToolUse`, `beforeShellExecution`, `beforeMCPExecution`, `beforeReadFile`,
`beforeTabFileRead`, `subagentStart`) block on invalid JSON or a schema mismatch *regardless*
of `failClosed` — which is why `hook-output.sh` always prints valid JSON and why nothing here
emits a non-Cursor key on those events; and exit 2 means `permission: "deny"`, matching Claude.

### Never `followup_message`

Cursor's `stop` and `subagentStop` can return `followup_message`, which Cursor **auto-submits
as the next user message** (`subagentStop`: consumed only when `status` is `completed`). That is
a stronger primitive than Claude's advisory `Stop`, and the wrong one for a reminder: an
advisory hook that used it would put words in the user's mouth. No helper in
`cursor-output.sh` emits it, no wired script emits it, and `tests/test-cursor-lifecycle.sh`
fails if any output on any event carries that key.

## What is deliberately not wired

| Event | Why not |
|---|---|
| `subagentStop` | Its Claude peer, `subagent-handoff-check.sh`, is quiet with the cross-host `{}` but, on the path where it has something to say (an objective with no handoff), still answers `hookSpecificOutput.additionalContext` — a Claude field Cursor drops, so wiring it would run a hook whose warning never reaches anyone. It is wired the day that path is Cursor-shaped (`tests/test-cursor-lifecycle.sh` probes exactly that path every run and flips to a warning when it happens). The patch is a `cursor_subagent_note` branch; the event's only documented output is `followup_message`, so on Cursor the handoff warning belongs on stderr or as `user_message`, never as a follow-up. |
| `subagentStart` | `cursor-agent-tools-guard.sh` would not benefit as written: it keys frames on the `Task` `tool_use_id` it already sees on `preToolUse`, and on a `subagentStart` payload (`tool_name` absent) its fallback path would **deny the spawn** under any active frame. A spawn-time deny needs a dedicated branch keyed on `subagent_type` + `tool_call_id` (which equals the Task `tool_use_id`), de-duplicated against the `preToolUse` push. |
| `postToolUseFailure` | Observation point (`error_message`, `failure_type`, `is_interrupt`; out `additional_context`). No guard here needs it. Documented as available for a future retry/diagnostics hook. |
| `beforeMCPExecution` / `afterMCPExecution` | `preToolUse` already fires for MCP tool calls (`MCP:<tool>`); judging the same call twice buys nothing. Neither runs in cloud agents. |
| `beforeReadFile` / `beforeTabFileRead` | This plugin makes no guarantee about reads; every read-only agent is supposed to read. |
| `afterShellExecution` · `afterFileEdit` · `afterTabFileEdit` · `afterAgentResponse` · `afterAgentThought` | Observational, no output; nothing here needs them, and each is a process spawn per event. |

Not ported: `capture-task-slug.sh` (Claude's first-prompt worktree creator). On Cursor
`enforce-worktree-edits.sh` already creates the worktree at the first write, and Cursor's own
`--worktree` / cloud-VM isolation covers the rest; a per-prompt `git worktree add` on a host
with its own worktree layout would add churn, not safety. `docker-guard.py` stays Claude-only
(it writes Claude's envelope directly rather than through `hook-output.sh`).

## What runs where: cloud agents

Cloud agents run 14 of the 21 events and **do not load user-level hooks**. Of the ten wired here:

| Runs in cloud agents | Desktop / CLI only |
|---|---|
| `preToolUse`, `postToolUse`, `beforeShellExecution`, `beforeSubmitPrompt`, `stop`, `preCompact` | `sessionStart`, `sessionEnd`, `workspaceOpen` |

So a cloud agent keeps every guard and every prompt hook, but gets no session lifecycle: no
session-files dir from `session-init.sh` (the first write still creates the worktree), no
archive/prune/claim-release at `sessionEnd`, and no `pluginPaths` injection. `subagentStart`,
`subagentStop` and `postToolUseFailure` would run in cloud agents if wired; `beforeMCPExecution`
and `afterMCPExecution` would not.

## Tests

| Suite | What it pins |
|---|---|
| `tests/test-cursor-hooks-bundle.sh` | Bundle structure: `version: 1`, camelCase events, the manifest points at it, no forked scripts, every command resolves, `failClosed` on the safety tier only, the libraries speak Cursor |
| `tests/test-cursor-lifecycle.sh` | Every entry × every fixture for its event: exit 0/2, stdout empty or one Cursor-shaped object, never `followup_message`; the specific behaviours above; the Claude envelope of each ported hook unchanged |
| `tests/test-cursor-agent-tools-guard.sh` | The agent `tools:` guard |
| `tests/test-hook-stdin.sh` | Every hook returns promptly with no stdin / a terminal — on Cursor a stalled guard is a denial |
| `tests/fixtures/cursor/` | One payload per event, from the documented fields |

Validate the shipped subset with
`bash scripts/build-dist.sh /tmp/cx --target cursor --quiet && bash scripts/check-dist.sh /tmp/cx --target cursor`.
