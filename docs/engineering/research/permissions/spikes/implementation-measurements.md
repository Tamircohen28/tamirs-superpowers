# Implementation measurements: the interactive hook-`ask` dialog and other Claude hook inputs

ADR 004 item 13 makes "U3 steps 3–4" a **gate** before any task builds on D5's Claude R4 route (only headless was
measured, see [`claude-codex.md`](claude-codex.md) "Orchestrator measurement — C4/U3"). This file records that gate
and the other items 13 lists that a headless or terminal-driven session could reach.

Host: Claude Code **2.1.318** (the installed binary had auto-updated from the repo pin 2.1.317; the hook schemas
read in C3 are unchanged in it), macOS, the user's existing login. Date 2026-11-04. Every hook was passed with
`--settings <scratch file>` or `--plugin-dir <scratch plugin>` (session-only); `~/.claude/settings.json` mtime was
identical before and after the run. Each `claude` ran under `env -i` (only `HOME`, `USER`, `LOGNAME`, `TERM`,
`LANG`, `PATH`) so the parent session's `CLAUDECODE` / `CLAUDE_CODE_*` variables did not leak in, with
`--model haiku`. No permission dialog was ever approved.

## Verdict table

| id | question | verdict | answer |
|---|---|---|---|
| M1 | U3 steps 3–4: does a PreToolUse hook `ask` raise an interactive dialog in `default`, `auto`, `bypassPermissions`; is the reason shown verbatim; what options; does declining stop the call? | **measured** (reproduced in `default`) | Yes in all three modes. The reason is shown verbatim, prefixed by `Hook PreToolUse:Bash requires confirmation for this command:` and suffixed by the hook's origin (`[settings]`). Options: `1. Yes` (pre-selected), `2. No`, `Esc to cancel · Tab to amend`; no "don't ask again". Esc ⇒ `tool_result` is the rejection, PostToolUse never fired, the command did not run. |
| M1b | Same, for a hook shipped by a **plugin**, with a multi-line reason | **measured** (`bypassPermissions`) | Same dialog; all three reason lines shown verbatim, origin suffix `[plugin:<plugin-name>]`, footer `plugin hooks.json to update hooks`. |
| M2 | U2: what does `UserPromptExpansion` / `UserPromptSubmit` receive for a typed `/tamirs-superpowers:pr-dev 42 --perms=standard` and a plain sentence? | **measured** | Expansion: `expansion_type: "slash_command"`, `command_name: "tamirs-superpowers:pr-dev"`, `command_args: "42 --perms=standard"`, `command_source: "plugin"`. Submit fires **first** with the raw line in `prompt`, same `prompt_id`. **`source` is absent** on both user-typed prompts. |
| M3 | `UserPromptSubmit.source` under `claude -p` (and the SDK's stream-json input) | **measured** | **Absent** in both. With M2: on 2.1.318 the field is in the schema but emitted on none of interactive, `-p`, stream-json. |
| M4 | Does PreToolUse matcher `mcp__plugin_tamirs-superpowers_github__.*` fire for that server's tools? | **measured** | Yes: it fired for `mcp__plugin_tamirs-superpowers_github__get_me`; a control matcher `…__nomatch_.*` did not. The exit-2 hook blocked the call before execution (`permission_denials` lists it); GitHub was never called. |
| M5 | Is an agent id present in subagent hook input? (item 13, SR S-11) | **measured** | Yes: a subagent's Bash PreToolUse carries `agent_id` (16 hex) and `agent_type: "general-purpose"` with the parent's `session_id`; main-thread calls carry neither key. |
| M6 | Does a PreToolUse matcher `Skill` fire for a model's Skill call, and what is `tool_input`? (task-010) | **measured** (`-p`) | Yes. `tool_input` is `{"skill": "<plugin>:<skill>"}`, plus `"args": "<string>"` when the call passes arguments; the exit-2 hook blocked the call (`permission_denials` lists it). See M6 below. |
| U1, U4 | `/plugin install` dialog; Desktop Code tab | blocked | Need a human at the install dialog / the Desktop app. Unchanged user steps U1, U4 in `claude-codex.md`. |
| U6 | Can a same-session background job answer the agent's own R4 dialog by keystrokes? | blocked (by rule) | Measuring it means letting a dialog be approved; not run. User step U6 below. The harness of M1 is itself that shape (see Impact 4). |

## Evidence

Scratch layout (`$S` = a session scratch directory, `$W` = `$S/work`, an empty trusted directory):

- `$S/ask.sh` saves its stdin and prints
  `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask","permissionDecisionReason":"u3-spike: pr.merge (R3) on `echo PROBE`"}}`.
- `$S/post.sh` saves its stdin (a PostToolUse capture: a file appears only if the command ran).
- `$S/s-m1.json` = `{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"$S/ask.sh"}]}],"PostToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"$S/post.sh"}]}]}}`.
- `$S/cap-hook.sh <dir> [rc]` saves stdin to `<dir>/in.<time>.<pid>.json`, exits `rc` (default 2 = block).

Terminal driver: a private tmux server (`tmux -L t015 -f /dev/null`; the `tmux` on PATH is a cmux shim, so the
Homebrew binary was called directly). `new-session -d -x 160 -y 50`, `send-keys -l <text>`, `send-keys Enter|Escape`,
`capture-pane -p -J`.

### M1 — the hook-`ask` dialog, three modes

Per mode: `tmux new-session -d -s m1-<mode> -c $W env -i … claude --settings $S/s-m1.json --permission-mode <mode> --model haiku`;
wait for the composer; send `Use the Bash tool to run exactly: echo PROBE-<mode>` + Enter; poll the pane for
`Do you want to proceed`; capture; send Escape; capture; `kill-session`. (`--max-turns` is a print-mode flag and was
not passed interactively.) Mode banner seen at start: `⏸ manual mode on` (default), `⏵⏵ auto mode on`,
`⏵⏵ bypass permissions on`; the hook input's `permission_mode` was `default`, `auto`, `bypassPermissions`.

Pane at the dialog (`bypassPermissions`; `default` and `auto` are identical apart from the probe word):

```text
 Bash command
 Echo the probe string
 echo PROBE-bypass
 │ Hook PreToolUse:Bash requires confirmation for this command:
 │ u3-spike: pr.merge (R3) on `echo PROBE` [settings]
 settings.json to update hooks

 Do you want to proceed?
 ❯ 1. Yes
   2. No

 Esc to cancel · Tab to amend
```

After Escape (all three modes):

```text
❯ Use the Bash tool to run exactly: echo PROBE-bypass
  ⎿  Interrupted · What should Claude do instead?
```

No `post.*.json` was written in any mode, no `PROBE-<mode>` output line appeared, and each session transcript's
`tool_result` is `is_error: true`, "The user doesn't want to proceed with this tool use. The tool use was rejected…".

| mode | (a) dialog | (b) reason verbatim | (c) options | after Esc |
|---|---|---|---|---|
| `default` (run twice) | yes | yes, + ` [settings]` | 1. Yes (selected) / 2. No; Esc; Tab to amend | rejected, not run |
| `auto` | yes | yes, + ` [settings]` | same | rejected, not run |
| `bypassPermissions` | yes | yes, + ` [settings]` | same | rejected, not run |

The `auto` session additionally showed `Teach auto mode about your environment?` after the decline; it is
unrelated to the hook.

### M1b — a plugin hook and a multi-line reason

A scratch plugin `t015pg` (`.claude-plugin/plugin.json` + `hooks/hooks.json` with a PreToolUse `Bash` hook
`${CLAUDE_PLUGIN_ROOT}/hooks/ask.sh`), loaded with `--plugin-dir`, `--permission-mode bypassPermissions`, no
`--settings`. Its reason has three lines (`\n`-separated), shaped like a PG R4 prompt:

```text
 │ Hook PreToolUse:Bash requires confirmation for this command:
 │ tamirs-superpowers R4 pr.merge.admin on owner/repo#42 (id 7f3a)
 │ head 0123abcd; required checks: ci FAILING, lint pending
 │ Effect: merges past branch protection. Choose No unless you typed this request. [plugin:t015pg]
 plugin hooks.json to update hooks
 Do you want to proceed?
 ❯ 1. Yes
   2. No
```

Esc: `Interrupted`, not run. `claude plugin validate` on the scratch plugin passed.

### M2 — U2, prompt-hook inputs for a typed plugin skill

Run 1, `$S/s-m2.json` (both events → `cap-hook.sh $S/m2 2`), plain `claude --settings $S/s-m2.json --model haiku` in
`$W` (the user's default mode applied: `bypassPermissions`). Typed `/tamirs-superpowers:pr-dev 42 --perms=standard`.
Only **UserPromptSubmit** fired; its exit 2 blocked the prompt before expansion:

```text
⏺ UserPromptSubmit operation blocked by hook:
  [… cap-hook.sh …]: t015 captured in.….json
  Original prompt: /tamirs-superpowers:pr-dev 42 --perms=standard
```

Run 2, `$S/s-m2b.json` (Submit → capture, exit 0; Expansion → capture, exit 2), fresh session, same line:

| event | keys received (values) |
|---|---|
| UserPromptSubmit | `prompt: "/tamirs-superpowers:pr-dev 42 --perms=standard"`, `prompt_id`, `session_id`, `session_title`, `permission_mode`, `cwd`, `transcript_path`, `scratchpad_dir`; **no `source`** |
| UserPromptExpansion | `expansion_type: "slash_command"`, `command_name: "tamirs-superpowers:pr-dev"`, `command_args: "42 --perms=standard"`, `command_source: "plugin"`, `prompt` = the typed line; same `prompt_id` and `session_id` as the submit |

The submit hook ran before the expansion hook (pids 60117 < 60265, same second). Exit 2 on the expansion showed
`UserPromptExpansion operation blocked by hook:`; no model call was made.

Plain sentence, fresh session with `s-m2.json`: `Please summarize the README in this folder.` → UserPromptSubmit with
that `prompt`, **no `source`**, blocked. (A blocked prompt is restored into the composer, so a second prompt typed in
the same session is appended to it; run 1's second capture shows exactly that and was discarded.)

### M3 — `source` under `claude -p` and stream-json

```text
cd $W && env -i … claude -p --settings $S/s-m3.json --model haiku --max-turns 1 --output-format json "Reply with the single word PONG."
printf '%s\n' '{"type":"user","message":{"role":"user","content":"Reply with the single word PONG."}}' \
  | env -i … claude -p --settings $S/s-m3sdk.json --model haiku --max-turns 1 --input-format stream-json --output-format stream-json --verbose
```

Both: `num_turns: 0`, `total_cost_usd: 0` (blocked before the model); the capture has `prompt`, `prompt_id`,
`session_id`, `session_title`, `permission_mode`, `cwd`, `transcript_path` and **no `source`**. The 2.1.318 binary
still declares `source: enum("user","sdk","system","loop_wakeup","schedule_wakeup","poll_event").optional()` with
"`user` = submitted from the interactive composer, `sdk` = non-interactive entrypoint (`-p` / Agent SDK)", so the
field exists in the schema and is simply not emitted in any of the three entrypoints here.

Side observation: `scratchpad_dir` was present in both interactive captures and absent in both headless ones. It is
not an attestation of anything (M1/M2's own sessions were driven through a pty by an agent) and must not be used as one.

### M4 — the MCP matcher

`$S/s-m4.json` registers three PreToolUse entries: `mcp__plugin_tamirs-superpowers_github__.*` → `cap-hook.sh
$S/m4/regex 2`; `mcp__plugin_tamirs-superpowers_github__nomatch_.*` → `cap-hook.sh $S/m4/neg 0`; `*` → a capture that
also exits 2 for any `mcp__*github*` tool (a safety net so nothing could reach GitHub whatever the regex did).

```text
cd $W && env -i … claude -p --settings $S/s-m4.json --model haiku --max-turns 2 --output-format json \
  "Call the tool mcp__plugin_tamirs-superpowers_github__get_me exactly once with no arguments. Do not call any other tool. Then reply DONE."
```

Result `error_max_turns`, `permission_denials: [{tool_name: "mcp__plugin_tamirs-superpowers_github__get_me", tool_input: {}}]`.
Captures: `regex/` one file (`tool_name: mcp__plugin_tamirs-superpowers_github__get_me`); `neg/` none; `*` saw the
`ToolSearch` that loaded the tool and the `get_me` call. The plugin's own `hooks/hooks.json` registers PG with exactly
this matcher string, so that wiring fires.

### M5 — agent id in subagent hook input

`$S/s-m5.json`: PreToolUse `Bash` → `cap-hook.sh $S/m5/bash 2`; `Agent|Task` → `cap-hook.sh $S/m5/agent 0`.
`claude -p … --max-turns 3 "Use the Agent tool to launch one general-purpose subagent (model haiku) whose only job is to run the Bash command: echo SUB-PROBE . …"`.

| capture | `tool_name` | `agent_id` | `agent_type` | `session_id` |
|---|---|---|---|---|
| main thread | `Agent` | absent | absent | `a7367967-…` |
| subagent | `Bash` (`echo SUB-PROBE`, blocked) | `af490d90651b7315a` | `general-purpose` | `a7367967-…` (same) |

## Impact on the implementation

1. **D5's Claude R4 route holds; the gate passes.** A PG `ask` reaches the user as a real dialog in `default`,
   `auto` and `bypassPermissions`, shows PG's reason verbatim (multi-line included) with the hook's origin, offers
   only Yes/No (no persistent allow a careless click could leave behind), and a decline stops the call. Together
   with C4's headless measurement (no human ⇒ deny), the "permission dialog of a PG hook `ask`" row of D5 is now
   measured end to end on 2.1.318. No change is needed in `hooks/permission-guard.sh`'s delivery (`ask_carried()`
   returning true for Claude is right). Two rendering facts PG's reasons should design for, no code change forced:
   `1. Yes` is pre-selected, so an Enter reflex approves; and the origin label is appended to the reason's last
   line, so the first line should carry the action id, target and effect on its own.
2. **`UserPromptSubmit.source` is never emitted on 2.1.318 (M2, M3)**, so the Claude raise path is closed in
   practice. In `hooks/permission-intent.sh`, `pair()` computes `user = s.get("source") == "user"`, which is always
   false: every Claude `--perms=` raise gets the "not typed by the user (source missing)" note, no pending record is
   written, and the context's `user_typed` is never true, so `hooks/permission-guard.sh`'s
   `raise_ok = bool(sk) and doc.get("user_typed") is True and same_agent` never holds and no per-skill RAISE from the
   user file applies on Claude. This is the ADR's own fail-closed rule ("missing `source` ⇒ not user"), so **nothing
   must change for safety**; do not relax it to treat a missing `source` as user (a pty-driven or nested host sends
   the same input, SR S-02, and this spike's sessions were exactly that). What must change is wording elsewhere:
   ADR D5's evidence cell and `docs/user/configuration.md` should say the Claude raise is unavailable until the host
   emits `source`. Optional tightening: since submit precedes expansion and both carry the same `prompt_id`, `pair()`
   could match on `prompt_id` instead of the 60 s window plus command name.
3. **`agent_id` is observed (M5).** PG's binding `str(PAY.get("agent_id") or "main")` and permission-intent's
   `agent` field are correct as written: subagent calls get their own id, main-thread calls get `main`. The ADR
   caveat "until an agent id is observed in hook input (item 13) it also reaches subagents" can be retired: the
   ticket consumer can require exact `agent` equality, so a main-thread ticket never reaches a subagent.
4. **The R4 route rests on `tty.drive` coverage, which has two source-visible gaps (not measured).** The dialog is
   answered by keystrokes; this spike answered it from a separate process with `tmux -L t015 -f /dev/null send-keys
   -t <session> Escape`. A background job the agent starts before its R4 call could send `1` instead. That is why
   `tty.drive` is R4 (D1, SR S-01), but in this tree:
   - `core/permissions/actions.json` `global_options` lists only `git` and `gh`, so for
     `tmux -L <sock> send-keys …` (or `-S`, `-f`) PG's `sub` starts with `-L` and the `{"cmd": ["tmux", "send-keys"]}`
     equivalent does not match. Add a `tmux` entry (`value`: `-L`, `-S`, `-f`, `-c`, `-T`; `flag`: `-2`, `-C`, `-D`,
     `-l`, `-N`, `-u`, `-v`).
   - `cmux send`, `cmux send-key`, `cmux send-panel`, `cmux send-key-panel` (the terminal this machine runs agents
     in) appear neither in the `tty.drive` equivalents nor in `_pg_candidate`'s token regex in
     `hooks/permission-guard.sh`, so PG exits before classifying them. Other terminals with the same verb
     (`wezterm cli send-text`, `kitty @ send-text`, `zellij action write-chars`) are absent too.
   A wrapper script (`bash ./t.sh send-keys …`, as this harness used) stays invisible to the parser; that is the
   accepted open risk on Bash-parser bypass, not a new one. Add both gaps to `tests/test-permission-guard.sh`'s
   `tty.drive` cases.
5. **The MCP matcher form is right (M4).** `hooks/hooks.json`'s `mcp__plugin_tamirs-superpowers_github__.*` entry
   fires for the bundled server's tools; D8's "E if a `mcp__plugin_tamirs-superpowers_github__.*` matcher fires
   (unverified)" can read measured. Nothing in `scripts/plugin-config.sh` depends on M1–M5.

## User steps still open

U1 and U4 as written in [`claude-codex.md`](claude-codex.md). New:

**U6 (self-approval by keystrokes; needs a human to accept that a probe may be approved).** In a scratch directory,
with a `--settings` hook that asks only for commands containing `PROBE` (and allows the rest), run `claude` inside
tmux and ask it to start, in the background, `sleep 15; tmux send-keys -t "$TMUX_PANE" 1 Enter`, then to run
`echo PROBE`. Record whether the dialog was approved without you. Then repeat with the plugin's PG loaded instead of
the scratch hook: expect PG to stop the background `tmux send-keys` as `tty.drive` (R4) before it can run; with the
gaps in Impact 4 unfixed, try `tmux -L x send-keys` and `cmux send-key` too.

Item 13's remaining Claude rows were not reached here: project `env` reaching hooks or overriding
`CLAUDE_PLUGIN_OPTION_*`, `disableAllHooks` against plugin hooks, and `pluginConfigs` in project settings.

## M6 — the `Skill` matcher (task-010)

Same host (Claude Code 2.1.318), same `env -i` and `--settings` discipline as M1–M5, run from an empty scratch
directory on 2026-11-04; `~/.claude/settings.json` mtime identical before and after. `$S/s-m6.json` registers
PreToolUse `Skill` → `cap-hook.sh $S/m6/skill` (saves stdin, exits 2) and `*` → the same capture into `$S/m6/any`,
also exiting 2, so no tool could run whatever the matcher did.

```text
cd $W && env -i … claude -p --settings $S/s-m6.json --model haiku --max-turns 2 --output-format json \
  "Use the Skill tool to invoke the skill tamirs-superpowers:decision"
# and again with "… with the args string: issue 42"
```

Both runs: `subtype: success`, `num_turns: 2`, one `permission_denials` entry with `tool_name: "Skill"`; the skill
never ran. The `Skill` capture holds one payload per run (the `*` capture saw the same single call):

```json
{"session_id": "…", "transcript_path": "…", "cwd": "$W", "prompt_id": "7fa1bfc6-…", "permission_mode": "bypassPermissions",
 "effort": {"level": "medium"}, "hook_event_name": "PreToolUse", "tool_name": "Skill",
 "tool_input": {"skill": "tamirs-superpowers:decision", "args": "issue 42"}, "tool_use_id": "toolu_…"}
```

`args` is absent when the call passes none. A main-thread call carries no `agent_id` (as in M5). The payload also
carries the turn's `prompt_id`.

**Impact.** `hooks/hooks.json` wires `permission-intent.sh` on exactly this matcher string, and the hook's
PreToolUse branch reads `tool_input.skill` (stripping the `tamirs-superpowers:` prefix in `skill_of`) and never
reads `args` for `--perms=`, which is the shape measured here, so no parser change is needed. The fixtures in
`tests/test-permission-guard.sh` and `tests/test-plugin-config.sh` (`tool_input: {skill, args}`) match it. The D8
"PreToolUse on the `Skill` tool" route for a host-recorded skill is therefore measured, not only wired.

## Live checks (issue #351) — 2026-11-04

Runs the four host measurements the sections above leave `blocked` or `source-cited`: U1 (install dialog) and U6
(self-approval by keystrokes) on Claude Code, U5 (`ask` on Codex) and S1 (`ask` on the Cursor CLI). **They supersede the
`blocked` rows U1 and U6 in the verdict table above**, and S1 overturns one source-cited claim (below).

Hosts: Claude Code **2.1.318** (`~/.local/bin/claude` called directly, never the shell function, no
`--dangerously-skip-permissions`; `env -i` with only `HOME USER LOGNAME TERM LANG SHELL PATH`; `--model haiku`); Codex
CLI **0.166.0** (the repo floor, fetched with `npm exec --prefix <scratch>/npm @openai/codex@0.166.0`; it used the
default `CODEX_HOME` and the existing ChatGPT login; the installed **0.156.0** gave the same result in one comparison
run); Cursor CLI **2026.10.22-27dcf5f**; tmux 3.8, a private server `/opt/homebrew/bin/tmux -L live -f /dev/null`
(the `tmux` on `PATH` is a cmux shim), killed afterwards. No login or OAuth flow was started. Every probe command was
`echo <PROBE-ID>` and every approval given was to such an echo. `$LIVE` below is
`/private/tmp/claude-501/-Users-tamircohen-Projects-tamirs-superpowers/4d09d4e0-b2ec-46c3-8c1c-8cf1d67342b8/scratchpad/live`
(captures, hooks and payloads kept there).

### Verdict table

| id | question | verdict | answer | host version |
|---|---|---|---|---|
| U1 | Does `/plugin install` show a configuration dialog for a `userConfig` `options` field; is the default pre-selected; can it be skipped or accepted without typing? | **measured** | **Yes to all.** After a scope picker (user / project / local) a `Configure <plugin>` screen opens with `Preset ◀ supervised ▶` (left/right cycles `options`), a `Save configuration` row and the field's `description` underneath. The **declared `default` is pre-selected**: a second plugin whose default is the *middle* option (`standard`) opened on `standard`, so it is the default, not the first option. Enter, Enter accepts without typing. Esc skips: `✓ Installed … Plugin is now active.`, nothing stored; `/plugin configure <plugin>@<mkt>` then opens the same screen (so (d) yes). A save writes `pluginConfigs."<plugin>@<mkt>".options.preset` into the **user** `~/.claude/settings.json` even for a local-scope install. | Claude Code 2.1.318 |
| U6 | Can a process other than the agent answer the host's own hook-`ask` dialog by keystrokes? | **measured** | **Yes.** A detached process (own session via `setsid`, minimal env, `TMUX` unset, its parent not the claude process) polled the pane, then ran `tmux -L live send-keys -t <pane> Enter` (run A) or `… 1` with no Enter (run B). Both answered the real dialog and `echo U6-PROBE-x` then ran (PostToolUse marker, `stdout` = the probe). The TUI cannot tell the keystroke from a human's. Not run, by the one-command rule: the variant where the agent itself starts the background `tmux send-keys`; the host side is identical (the same keystroke into the same pty). | Claude Code 2.1.318 |
| U5 | Codex `PreToolUse` hook returning `permissionDecision: "ask"` for the shell tool: reported as unsupported, and does the command still run? | **measured** | **Fail-open, as the source said.** TUI line `Hook failed — PreToolUse hook returned unsupported permissionDecision:ask`, then `Ran echo U5-PROBE-TUI`; no approval prompt even with `Permissions: Workspace (Ask for approval)`. `codex exec`: `hook: PreToolUse Failed`, command `succeeded`. Control: the same hook returning `deny` gives `PreToolUse Blocked` and the command never runs. 0.156.0 behaves identically. | Codex 0.166.0 (and 0.156.0) |
| S1 | Cursor `beforeShellExecution` returning `{"permission":"ask"}`: prompt, silent run, or reject? | **measured** | **Interactive, no force:** a card `Run this command? / Hook requested approval: probe • Not in allowlist: echo` with `Run (once) (y)`, `Run Everything (shift+tab)`, `Skip & tell the agent what to do instead (esc or n)`; `y` ran it. **Print mode `-p --trust`, no force:** rejected three times (`Rejected:`, no reason), never ran, **but the control without any hook is rejected identically** (the allowlist is `Shell(ls)`), so print mode does not show that `ask` did it. **`--yolo` (Run Everything), print and interactive:** the hook ran and **no card appeared; the command ran**. `ask` does not hold under Run Everything, contradicting the source-cited reading in `cursor-gemini-opencode.md` U1 ("forces a prompt in every approval mode, including unrestricted"). | Cursor CLI 2026.10.22 |

### U1 evidence — the install dialog

Scratch marketplace `t002-mkt` (plugin `pt2`: one `preset` field, `type: string`, `options: [supervised, standard,
unattended]`, `default: "supervised"`) plus `live-mkt3` (plugin `pt3`, the same field with `default: "standard"`). The
real TUI ran in tmux from an empty trusted directory, no `--settings`, default permission mode. Typed:
`/plugin marketplace add $LIVE/../t002/mkt`, then `/plugin install pt2@t002-mkt`.

```text
❯ /plugin marketplace add …/t002/mkt
  ⎿  Successfully added marketplace: t002-mkt
❯ /plugin install pt2@t002-mkt
   Plugin Details / pt2 / defaulted only
   ❯ Install for you (user scope)
     Install for all collaborators on this repository (project scope)
     Install for you, in this repo only (local scope)          <- chosen (Down, Down, Enter) to keep user settings out of it
     Back to plugin list
    Configure pt2
    Plugin options
    ❯ Preset  ◀ supervised ▶
      Save configuration
    p                                                           <- the field's `description`
    ↑/↓ to move · ←/→ to change · Enter to continue · Esc to cancel
```

- **Skip (Esc)** → `⎿ ✓ Installed pt2. Plugin is now active.`; `~/.claude/settings.json` had no `pluginConfigs` key; the
  project's `.claude/settings.local.json` held `enabledPlugins: {"pt2@t002-mkt": true}`.
- **`/plugin configure pt2@t002-mkt`** → the same screen, `Preset ◀ supervised ▶`. **Enter** on the field moves to
  `Save configuration` (the arrows line disappears from the footer); **Enter** again → `⎿ Configuration saved.`. No typing.
- **Where the save went** (`diff` of the user `settings.json` before/after the save, install scope `local`):

  ```diff
  +  "pluginConfigs": {
  +    "pt2@t002-mkt": {
  +      "options": {
  +        "preset": "supervised"
  ```
- **Default vs first option.** `pt2`'s default is also its first option, so a second plugin `pt3` with `default:
  "standard"` was installed the same way: `❯ Preset  ◀ standard ▶`. Skipped with Esc, then uninstalled.
- **Cleanup.** `/plugin uninstall pt2@t002-mkt` → `✔ Uninstalled pt2. Applies when you close this menu.` (it opens the
  plugin manager, focused on an MCP row marked `Enter to auth`; Esc closes it, Enter would start OAuth, so do not press it).
  `/plugin marketplace remove t002-mkt` → `✔ Removed 1 marketplace`.

**Corrections to the written user step U1.** (1) Its "nothing below touches your settings except the install" is not
right: `/plugin marketplace add` writes `extraKnownMarketplaces.<name>` into the **user** `settings.json` whatever scope
the plugin later gets, and a saved `configure` writes `pluginConfigs` there too. (2) After a saved configuration,
uninstall plus `marketplace remove` left a stub `"pluginConfigs": {},` in `settings.json` (after a skipped dialog, as with
`pt3`, the file came back byte-identical). (3) The scope picker comes before the options screen.

### U6 evidence — a second process answers the dialog

```text
$LIVE/u6/s-u6.json = PreToolUse(Bash) → ask.sh   (saves stdin; prints permissionDecision "ask",
                                                    reason "u6-spike: hook ask on echo U6-PROBE")
                     PostToolUse(Bash) → post.sh (saves stdin; a file exists only if the command ran)
tmux -L live new-session -d -s u6A -c <trusted empty dir> env -i … ~/.local/bin/claude \
     --settings $LIVE/u6/s-u6.json --model haiku --permission-mode default
# a separate, detached process, started before the prompt:
nohup env -i HOME PATH perl -MPOSIX -e 'POSIX::setsid(); exec @ARGV' $LIVE/u6/approver.sh u6A "echo U6-PROBE-A" Enter
# typed into the pane: Use the Bash tool to run exactly this one command and nothing else: echo U6-PROBE-A
```

The approver polls `capture-pane` and acts only when the dialog is up: it sends the keys if the command line is exactly
` echo U6-PROBE-A` and `Escape` otherwise. A first dry run (Esc, declined, no PostToolUse file) fixed the dialog layout:

```text
 Bash command / Echo the probe string
╌╌╌╌╌╌╌╌╌╌╌╌╌
 echo U6-PROBE-A
╌╌╌╌╌╌╌╌╌╌╌╌╌
 │ Hook PreToolUse:Bash requires confirmation for this command:
 │ u6-spike: hook ask on echo U6-PROBE [settings]
 Do you want to proceed?   ❯ 1. Yes   2. No   Esc to cancel · Tab to amend
```

```text
approver.log: 14:03:07 approver pid=96749 ppid=96324 TMUX=unset: dialog for 'echo U6-PROBE-A' seen; sending: Enter
              14:03:33 approver pid=99190 ppid=98753 TMUX=unset: dialog for 'echo U6-PROBE-B' seen; sending: 1
final pane A: ⏺ The command ran and printed U6-PROBE-A.        final pane B: ⏺ The command printed U6-PROBE-B.
PostToolUse A: {"command":"echo U6-PROBE-A", …} tool_response {"stdout":"U6-PROBE-A","stderr":"","interrupted":false, …}
PostToolUse B: command "echo U6-PROBE-B", stdout "U6-PROBE-B"          PreToolUse payload: permission_mode "default"
```

Both keystroke forms work: `Enter` takes the pre-selected `1. Yes`; the digit alone selects and confirms. The approver's
parent was not the claude process and its environment carried no `TMUX`, so this needs only the socket (`-L`/`-S`) or any
other way to write to the pty, not a position inside the pane.

### U5 evidence — Codex hook `ask`

`$LIVE/u5/repo` is a scratch `git init` repo. Its `.codex/hooks.json` registers `PreToolUse` on `Bash` →
`ask.sh` (saves stdin, prints `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"ask",
"permissionDecisionReason":"u5-spike: ask on echo U5-PROBE"}}`) and `PostToolUse` → `post.sh` (saves stdin).

```text
R=$LIVE/u5/repo
env -i HOME USER LOGNAME TERM=dumb LANG PATH=<node>:/usr/bin:/bin  <codex 0.166.0> exec --json --ephemeral \
  --dangerously-bypass-hook-trust -C $R -c 'projects={"<R>"={trust_level="trusted"}}' -c 'notify=[]' \
  "Run this one shell command and nothing else: echo U5-PROBE"
```

Two traps found on the way (both change how U5 must be run):

1. **`-c 'projects."<path>".trust_level="trusted"'` does nothing.** The override key is split on `.`
   (`codex-rs/config/src/overrides.rs:22`, `path.split('.')`), so a quoted path segment never survives. The first two
   runs silently had the project layer disabled: the hook never fired, and a deliberately malformed `.codex/hooks.json`
   produced no warning. Passing the whole table as the *value* (`-c 'projects={"<R>"={trust_level="trusted"}}'`) works.
2. **Hook trust.** `--dangerously-bypass-hook-trust` (present in 0.156.0 and 0.166.0) is per invocation. It was used instead
   of granting trust in `/hooks`, which writes `[hooks.state…]` into `~/.codex/config.toml`. It does not touch the approval
   policy or the sandbox. The user's own global `~/.codex/hooks.json` (cmux) registers a `PreToolUse` hook too, which is why two
   `PreToolUse` lines appear.

```text
$ codex exec … (plain mode, 0.166.0)                                  # stderr, trimmed
approval: never    sandbox: workspace-write [workdir, /tmp, $TMPDIR]
hook: PreToolUse
hook: PreToolUse
hook: PreToolUse Completed                                            # presumably the user's global cmux hook
hook: PreToolUse Failed                                               # our ask hook (the deny control prints `Blocked` here)
exec  /bin/zsh -lc 'echo U5-PROBE-PLAIN' …  succeeded in 0ms:  U5-PROBE-PLAIN
hook: PostToolUse … Completed
```

`ask.sh` captured `{"hook_event_name":"PreToolUse","permission_mode":"bypassPermissions","tool_name":"Bash","tool_input":
{"command":"echo U5-PROBE"},…}` and `post.sh` a PostToolUse with `"tool_response":"U5-PROBE\n"`, so the command executed.
(`permission_mode` is `bypassPermissions` here only because `exec` runs with `approval: never`, as `hook_runtime.rs:1073-1081`
predicts.) `--json` mode prints no hook items, so the reason text needs the TUI. TUI run, same repo, same flags without
`exec`/`--json`, plus `--no-alt-screen`; `/status` printed `Permissions: Workspace (Ask for approval)`:

```text
› Run this one shell command and nothing else: echo U5-PROBE-TUI
• I'll run that command.
• Hook failed
  └ PreToolUse hook returned unsupported permissionDecision:ask
• Ran echo U5-PROBE-TUI
  └ U5-PROBE-TUI                      (hook payload permission_mode: "default")
```

Control, same repo with the hook returning `permissionDecision: "deny"`: `ERROR codex_core::tools::router: error=Command
blocked by PreToolUse hook: u5-spike: deny control on echo U5-PROBE-CTL`, `hook: PreToolUse Blocked`, the model reported
the block, and no `PostToolUse` file exists. So the hook path was live and `ask` alone failed open. Installed 0.156.0:
the same `PreToolUse Failed` and `succeeded in 0ms`.

### S1 evidence — Cursor CLI hook `ask`

`$LIVE/s1/repo` (`git init`) has `.cursor/hooks.json` = `{"version":1,"hooks":{"beforeShellExecution":[{"command":
".cursor/ask.sh"}],"afterShellExecution":[{"command":".cursor/after.sh"}]}}`; `ask.sh` saves stdin and prints
`{"permission":"ask","user_message":"probe"}`; `after.sh` saves stdin. The user's global `~/.cursor/hooks.json` (cmux, a
no-op without `CMUX_*`) loads too. All runs: `env -i … cursor-agent … --trust --model auto`.

| run | flags | what happened |
|---|---|---|
| plain `-p` | `-p` | `⚠ Workspace Trust Required … Pass --trust, --yolo, or -f`, exit 1. A trust flag is mandatory in print mode. |
| R1 | `-p --trust` | The model tried `echo S1-PROBE`, again, then `/bin/echo S1-PROBE`; each `Rejected:` with no reason; reported "rejected three times". Hook ran 3 times. |
| C0 (control) | `-p --trust`, **no hook** | Identical: rejected three times. `echo` is not allowlisted (`~/.cursor/cli-config.json` has `Shell(ls)` only). |
| R2 | `-p --trust --yolo` | Hook ran once; `afterShellExecution` payload `output: "S1-PROBE-R2\n"`; the model printed it. **Ran.** |
| I1 | interactive, `--trust` | Card (below); `y` → `$ echo S1-PROBE-I1 8.7s`, `afterShellExecution` `output: "S1-PROBE-I1\n"`. |
| I2 | interactive, `--trust --yolo` | Hook ran (`before.*.json` exists); **no card**; `$ echo S1-PROBE-I2 2.1s`, `output: "S1-PROBE-I2\n"`. |

```text
  $ echo S1-PROBE-I1 Waiting for approval...
 $  echo S1-PROBE-I1 in .
 Run this command?
 Hook requested approval: probe • Not in allowlist: echo
  → Run (once) (y)
    Run Everything (shift+tab)
    Skip & tell the agent what to do instead (esc or n)
```

Notes: (1) `afterShellExecution` fires for a **rejected** command too (R1: `output: ""`, `duration` ~700 ms), so it is
not evidence that a command ran; the pane text and `output` are. (2) The card carries no "always allow" choice, matching
the source-cited `canAllowlist=false`. (3) The `user_message` is shown as `Hook requested approval: <user_message>`, and
the allowlist reason is appended after a bullet. (4) The payload carries `command`, `cwd` (empty here), `sandbox`,
`workspace_roots`, `conversation_id`, `cursor_version`. (5) `--trust` persisted a `.workspace-trusted` file under
`~/.cursor/projects/<scratch path>/`; that directory was archived to `$LIVE/s1/cursor-project-state` and removed.

### Before/after proof of the user's config

Recorded with `stat -f '%Sm %z'` and `shasum -a 256` (first 16 hex) before the first command and after the last.

| file | before | after | what happened |
|---|---|---|---|
| `~/.claude/settings.json` | 2026-11-03T22:55:58, 8529 B, `47f9808a32cf78e0` | 2026-11-04T14:26:37, 8529 B, `47f9808a32cf78e0` | **Byte-identical; mtime moved.** U1's own writes (`extraKnownMarketplaces.t002-mkt`, `pluginConfigs`, and the `"pluginConfigs": {}` stub left after uninstall). The original bytes were reconstructed from a snapshot minus the added keys and the result hashed to the recorded value *before* anything was written back; `diff` then confirmed it. |
| `~/.claude/settings.local.json` | 2026-08-12T09:54:13, 276 B, `92075d73b5f238f9` | same | untouched |
| `~/.claude/plugins/installed_plugins.json` | 15122 B, `c24351ffe9f25311` | `c24351ffe9f25311` | equal (parsed JSON compare also equal) |
| `~/.claude/plugins/known_marketplaces.json` | four entries | the same four | `t002-mkt` and `live-mkt3` added, then removed; the only differences from the snapshot are two `lastUpdated` stamps (`claude-plugins-official`, `tamirs-marketplace`) the host refreshes at startup |
| `claude plugin list`, `claude plugin marketplace list` | saved | `diff` empty (twice: after `pt2`, after `pt3`) | restored; also removed `~/.claude/plugins/cache/{t002-mkt,live-mkt3}` (orphaned scratch copies) |
| `~/.codex/config.toml` | 2026-11-03T21:35:31, 10275 B, `122994006f141a14` | 2026-11-04T14:25:05, 10275 B, `122994006f141a14` | **Byte-identical; mtime moved.** `codex exec` never touched it; launching the Codex **TUI** at 14:09:48 appended `[tui] screen_reader_detection_done = true` and `[tui.model_availability_nux] "gpt-6.1-sol" = 1` (+91 B, host housekeeping). Removing exactly those lines reproduced the recorded hash, then the file was written back. No `[projects…]` or `[hooks.state…]` entry was added. |
| `~/.codex/hooks.json` | 2026-08-31T22:04:18, 2845 B, `1593ca26c17f7c58` | same | untouched |
| `~/.cursor/hooks.json` | 2026-08-31T22:04:22, 3813 B, `531c80218c796c31` | same | untouched |
| `~/.cursor/cli-config.json` | 2026-11-01T22:10:34, 1483 B, `5ca38dfb68c14784` | 1483 → 2088 B | **Not byte-restorable, and not a config edit of ours.** `cursor-agent` rewrites it on every invocation: it refreshes `privacyCache.updatedAt` (first call, `status`, 14:11:04, before any probe) and adds `autoReviewAvailabilityCache` and `serverConfigCache`. The one preference it flipped, `hasChangedDefaultModel` false → true (from passing `--model auto`), was set back to `false`. `permissions`, `approvalMode`, `model` and the rest are unchanged against a 14:11 snapshot. |
| `~/.cursor/projects/` | 58 entries | 58 | the scratch workspace's entry (with `.workspace-trusted`) was archived under `$LIVE` and removed |

Left in place as ordinary tool state (session history, not config): the Codex TUI rollout under
`~/.codex/sessions/2026/11/04/`, Claude transcripts for the scratch directories under `~/.claude/projects/`, and the
`~/.claude.json` project entries those sessions touch. Nothing was pushed or committed.

## Impact on ADR 004 D8 (live checks)

Question for each: does it let a softer `ask` replace a `deny` anywhere?

1. **U1: no, and not an enforcement item.** It turns two doc-cited D3/D7 statements into measured ones: the install picker
   exists, opens on the declared default (not merely the first option), accepts with two Enters or is skipped, and a saved
   value lands in `<home>/.claude/settings.json` `pluginConfigs` even for a local-scope install, so D3's "a Claude
   project-scope install carries no preset" holds and the install scope does not move the store. A skipped dialog stores
   nothing, which is D7's "reported not yet set until stored" case (runtime default `supervised`, C1).
2. **U6: no, it removes ground.** The D5 dialog is a human channel only while nothing the agent can start can write to the
   terminal's pty. A second process answered it with `Enter` or a bare `1`. For Claude R4 (hook `ask` is "the only R4
   route") that makes `tty.drive` classification load-bearing rather than hardening: keep it R4, and close the two gaps
   recorded under Impact 4 above (`tmux -L/-S/-f` global options in `actions.json`; `cmux send*`, `wezterm cli
   send-text`, `kitty @ send-text`, `zellij action write-chars` absent). A wrapper script stays invisible to the parser,
   the accepted open risk. The D8 Claude cell "E: hook `ask` ... Esc rejects" stays true for a human and should say it
   is not proof against same-user automation.
3. **U5: no.** Measured fail-open on both versions, `deny` blocks. The Codex row stays "E, deny only"; R4 always `deny`
   naming the out-of-session route; the canary and "guard traps every error to a deny" cells stand. `ask` on Codex is
   a visible `Hook failed` line, never a prompt.
4. **S1: no, and it narrows the Cursor CLI cell.** D8 currently says "after S1, R4 and `confirm` via `beforeShellExecution`
   ask". Measured: `ask` produces a real card only in interactive mode **without** Run Everything; under `--yolo` it is
   silently ignored (print and interactive), and in print mode without force it is a reject indistinguishable from "not
   allowlisted". So on the Cursor CLI R3/R4 stay `deny` (`failClosed: true`), and `ask` may be added only as a courtesy
   layer for the interactive, non-yolo path, never as the thing that holds. The Cursor desktop cell stays unverified (S2).
   The source-cited claim in `cursor-gemini-opencode.md` U1 and the "L3 host ask" cell should be changed from
   "forces a prompt in every approval mode" to the measured condition.

## GUI checks (issue #351) — 2026-11-04

The four ADR 004 item 13 checks that need a desktop app: U4 (Claude Desktop's Code tab), S2 (Cursor desktop run modes),
S3 (what Cursor's `beforeSubmitPrompt` receives for `/pr-dev 42 --perms=standard`) and S4 (Cursor plugin variables).
**U4, S2 and S3 are measured** (U4 on a rerun with the screen unlocked); **S4 stays blocked.** `$G` below is the run's scratch directory, outside the repository,
where every capture, hook and payload was kept. The repo was not edited during the run. No login or OAuth flow was
started and no credentials were typed. Every probe command was `echo <PROBE-ID>`; exactly one approval was given, to
`echo S2-PROBE-autoreview`. Every other prompt was skipped, and the controls and the `preToolUse` echo ran with no prompt.

**Session condition.** The Mac's screen was **locked** for the first run (`ioreg` reported `IOConsoleLocked = true` at
15:13 and again at 15:37). Pixel input was refused (`loginwindow window … is in front`), and the AX trees of both
Electron apps exposed no web content. Cursor was not running beforehand, so it was launched with
`--remote-debugging-port` and its real workbench was driven through CDP (DOM mouse and key events,
`Page.captureScreenshot`), which needs no unlock. Claude Desktop was already running with live sessions, so it was not
restarted; U4 was run again at 17:11–17:34 with the screen unlocked.

### Verdict table

| id | verdict | answer | app version |
|---|---|---|---|
| U4 | **measured** (rerun 17:11–17:34, screen unlocked; the 15:13 attempt was blocked by the locked screen) | **No userConfig dialog:** "Add to this computer" installs a plugin at once ("Pt2 is installed and ready to use."), with no picker and no default shown, and its menu offers only Remove; the plugin's `SessionStart` hook env carried **no `CLAUDE_PLUGIN_OPTION_PRESET`**. **A `PreToolUse` hook `ask` raises Desktop's dialog:** "Allow Claude to run this command?", the reason `U4 probe: hook ask` verbatim, Deny / Allow once, under **Bypass permissions**; Deny stopped the command. | Claude Desktop 4.16336.0 (embedded Claude Code 2.1.317) |
| S2 | **measured** | `beforeShellExecution` returning `{"permission":"ask"}` **forces an approval card in all three run modes, Run Everything (Unsandboxed) included.** Auto-Review: card with `Hook requested approval: S2 probe: hook ask`; Run ran it. Allowlist: a card (generic text, no hook reason) even for an **allowlisted** `echo`, whose no-decision control ran unprompted; Skip rejected it. Run Everything: card with the hook's reason; Skip rejected it; the no-decision control ran unprompted. `preToolUse` (matcher `Shell`) returning `ask`: **not enforced**, the command ran unprompted under Run Everything. | Cursor desktop **3.27.22 → 3.28.7** (Cursor's own updater) |
| S3 | **measured** | `beforeSubmitPrompt` receives the **literal typed text** `"prompt":"/pr-dev 42 --perms=standard"` with `"attachments":[]`: no skill or command field, no expansion. Picking `/pr-dev` from the skill picker (a `cursor_skill` mention chip) gives the same payload. The hook blocked the prompt (`continue:false`), so the model never ran. | Cursor desktop 3.28.7 |
| S4 | **blocked: no Cursor Teams admin on this account** | cursor.com/dashboard (already signed in, Pro+ individual) has a *Personal*-only Plugins & MCPs page. The plugin row offers `View details` and `Remove`; the details dialog lists MCPs, Skills, Subagents, Hooks, Rules and Commands, with `Remove from Personal` as its only action: no Configure, no variables, although the plugin declares `variables.GITHUB_TOKEN`. Members shows "Upgrade to Teams". | cursor.com dashboard, 2026-11-04 |

### U4 evidence — Claude Desktop (measured on a rerun with the screen unlocked)

**First attempt (15:13, blocked).** The screen was locked: Claude Desktop's web UI could not be seen or targeted, a
background pixel click on `Customize` was refused (`loginwindow window … is in front`), the AX tree held 5,919
elements that were all menus, and an AX `View > Hide Sidebar` press took effect (the label flipped) while the capture
stayed frozen. Blind driving of the live app was ruled out; the sidebar press was undone and nothing was installed.

**Rerun (17:11–17:34, `IOConsoleLocked = false`).** Claude Desktop 4.16336.0, embedded Claude Code 2.1.317; the app
was not restarted (one main process throughout). Baseline hashes of the user's config files were taken before the
first click.

1. **Add the scratch marketplace by path.** Customize → Plugins → `Add ▾` → Add marketplace, the scratch
   marketplace's directory typed into the URL field, Sync. `main.log`: `Adding marketplace: …/t002/mkt`, then
   `Marketplace added: t002-mkt`. `~/.claude/settings.json` gained `extraKnownMarketplaces."t002-mkt"`
   (`source: directory`) and `known_marketplaces.json` gained `t002-mkt`.
2. **Install `pt2` (one `preset` userConfig field, `default: "supervised"`): no dialog.** `Pt2 / defaulted only` →
   **Add to this computer**; the row turned to `✓ Added` and a toast read "Pt2 is installed and ready to use."
   **No dialog of any kind appeared**: no scope picker, no `Configure pt2`, no field, no default shown. `main.log`:
   `installPlugin: skipping remote API path … (reason=local-sourced)`, `attempting CLI install … (scope=default)`,
   `Plugin installed: pt2@t002-mkt`. `settings.json` gained only `enabledPlugins."pt2@t002-mkt": true`, no
   `pluginConfigs`. The plugin row's `⋯` menu offers only **Remove**: there is no Configure entry in the Desktop UI.
3. **What reaches the plugin's hooks.** `pt2`'s own `SessionStart` hook (it writes `env | grep -i CLAUDE_PLUGIN` to
   its data directory) ran when the scratch session started. The captured env held only `CLAUDE_PLUGIN_ROOT` and
   `CLAUDE_PLUGIN_DATA`: **no `CLAUDE_PLUGIN_OPTION_PRESET`**. With nothing stored, the declared default is not
   exported to a hook. The CLI was not compared in this run.
4. **A Code-tab session in the scratch project.** New → This computer → the scratch project `$G/u4proj` (opened
   through a temporary symlink under `~`, removed afterwards). The app resolved the real path and asked "Trust this
   workspace? … Execution allowed by: `.claude/settings.json`"; Trust workspace. Permission mode: **Bypass
   permissions**, this account's Desktop default for local sessions (not chosen by the run).
5. **`echo U4-PROBE`: the dialog appears; declined.** The project `PreToolUse` `Bash` hook fired (`fired.log`:
   `2026-11-04T17:26:17 ask emitted`; stdin `tool_name: Bash`, **`permission_mode: "bypassPermissions"`**,
   `tool_input.command: "echo U4-PROBE ."`, the trailing ` .` from the prompt's punctuation). The screen showed a card
   **"Allow Claude to run this command?"** with the tool's description, **`U4 probe: hook ask`** (the hook's
   `permissionDecisionReason`, verbatim), `$ echo U4-PROBE .` and the buttons **Deny** and **Allow once ⌘↩**.
   **Deny** turned the tool row to `Stopped`; the command never ran.
6. **Cleanup.** The marketplace was removed through Manage marketplaces ("This will also uninstall 1 plugin from this
   marketplace: • Pt2"; `main.log`: `Removed 1 plugin(s) …`, `Removed "t002-mkt" from known_marketplaces.json`).
   The scratch session was archived, not deleted. The worktree Desktop had created under `~/.claude/worktrees/u4proj/`
   (clean) was removed with `git worktree remove` and `git branch -d`. The plugin's data directory and its orphaned
   cache copy were removed. The landing bar's Worktree box and environment were set back to their starting values.
   Desktop's add/remove had rewritten `~/.claude/settings.json` (trailing newline dropped) and
   `known_marketplaces.json` (two other marketplaces' `lastUpdated` stamps) without changing their meaning; the exact
   original bytes were put back.

Restore proof (rerun baseline 17:11 → final 17:34): `~/.claude/settings.json`, `~/.claude/settings.local.json`,
`~/.claude/plugins/known_marketplaces.json` and `~/.claude/plugins/installed_plugins.json` are byte-identical.
Deliberately not reverted: `claude_desktop_config.json`'s last-viewed session pointer (now the archived scratch session;
setting it back would mean opening the user's own session) and a capability cache key the app added; app-cache
timestamps in `config.json`; `~/.claude.json`'s trust entry for the scratch project; the scratch session's transcript;
a stale `u4proj` record in `git-worktrees.json`.

App stability, observed and not caused by the run: Desktop's main webview renderer crashed (`render process gone …
exitCode: 5`) once before the run and eight times during it; twice it showed "Claude keeps crashing", and each time
the in-page Reload was used, never Restart Claude. The main process never changed and the existing sessions stayed
listed.

### S2 evidence — Cursor desktop run modes

**Update.** `Info.plist` read `3.27.22` before; the workbench showed `New update available · Later · Install Now` and
Install Now was clicked; ShipIt logged `Installation completed successfully` and relaunched the app. After: `3.28.7`,
commit `25b52e7d03ebf2d5608914158e119f7992432a30`, user agent `Cursor/3.28.7`. The command palette has no "Check for
Updates" entry; the notification is Cursor's own ToDesktop/Squirrel updater.

**Setup.** Scratch repo `$G/cur-s2` with `.cursor/hooks.json` → `beforeShellExecution: .cursor/ask.sh`, which logs stdin
and returns `{"permission":"ask","user_message":"S2 probe: hook ask"}` for `echo S2-PROBE*`, `{}` (no decision) for the
control `echo S2-PROBE-noask*`, and `deny` for anything else (a safety net that never fired). The user-level
`~/.cursor/hooks.json` (cmux hooks, no-ops outside cmux) and the installed tamirs-superpowers 5.1.2 Cursor hooks were also
active; neither changed an outcome. Run modes on offer in 3.28.7: `Allowlist`, `Allowlist (with Sandbox)`,
`Auto-Review (with Sandbox)`, `Run Everything (Unsandboxed)`; the user's mode was Run Everything. Each run was a new
Agent chat asked to run exactly one `echo S2-PROBE-<mode>` and to report a block or rejection and stop.

| run | mode | hook decision | screen | action | result |
|---|---|---|---|---|---|
| 1 | Auto-Review (with Sandbox) | ask | `Pending approval` card, `Skip / Run`, footer **`Hook requested approval: S2 probe: hook ask`** | Run | ran, printed `S2-PROBE-autoreview` |
| 2 | Allowlist (`echo` not allowlisted) | ask | `Pending approval` card, **no hook reason** (`Agent needs your approval to run: echo S2-PROBE-allowlist`) | Skip | `Skipped echo`; agent: "The command was rejected" |
| 3 | Allowlist, `echo` **temporarily allowlisted** | ask | `Pending approval` card, generic text | Skip | rejected |
| 4 | Allowlist, `echo` allowlisted (control) | `{}` | no card | — | ran unprompted, exit code 0 |
| 5 | Run Everything (Unsandboxed) | ask | `Pending approval` card, **`Hook requested approval: S2 probe: hook ask`** | Skip | rejected |
| 6 | Run Everything (control) | `{}` | no card | — | ran unprompted |
| 7 | Run Everything, the hook moved to `preToolUse` matcher `Shell` returning `{"permission":"ask"}` | ask (fired) | **no card** | — | ran unprompted, printed `S2-PROBE-pretooluse-runeverything` |

Runs 3 and 4 differ only in the hook's answer: in Allowlist mode a hook `ask` **overrides an allowlist entry**. Runs 5
and 6: in Run Everything a hook `ask` **is not bypassed**, the opposite of the CLI under `--yolo` (S1). In Allowlist mode
the card omits the hook's `user_message`.

Payload facts: the `beforeShellExecution` stdin carries `cursor_version: "3.28.7"`, where the S1 CLI captures carry
`"2026.10.22-27dcf5f"`, so a hook can tell desktop from CLI. `sandbox: true` appears only under Auto-Review; no field
names the run mode.

Restore: `echo` was removed from the Command Allowlist (back to `cd, git push, cat, git add, git commit`); the run mode
was left on Run Everything, the original; Cursor was quit (it was not running before). In `state.vscdb` five leaves of
the reactive-storage blob changed: four app caches (`SPECIAL_KEY_id`, two `modelLastUsedAt` stamps,
`cliDetectionStatus.checkedAt`) were left alone, and `composerState.doNotShowYoloModeWarningAgain`, flipped false → true
by the mode switch, was set back to `false` with a single-row UPDATE while Cursor was closed (`pragma quick_check`:
`ok`). The seven Agent chats exist only in the scratch workspace.

### S3 evidence — `/pr-dev` text on Cursor desktop

Same scratch repo, `beforeSubmitPrompt: .cursor/prompt.sh`, which appends stdin to a log and returns
`{"continue":false,"user_message":"S3 probe: prompt captured and blocked by beforeSubmitPrompt"}` when the text contains
`perms=`, else `{"continue":true}`.

1. **Plain text**, `/pr-dev 42 --perms=standard` then Enter:

   ```json
   {"composer_mode":"agent","prompt":"/pr-dev 42 --perms=standard","attachments":[],"hook_event_name":"beforeSubmitPrompt","cursor_version":"3.28.7", …}
   ```

   The chat showed the hook's message and stopped.
2. **Picker**: typing `/pr-dev` opened the skill picker, whose top entry was `/pr-dev` "Skill · PR Dev" from the installed
   plugin; Enter made it a mention chip (`data-mention-name="pr-dev" data-typeahead-type="cursor_skill"`), then
   `42 --perms=standard` and Enter. The hook stdin was **identical**, and the prompt was blocked.

No `command_name`/`command_args` split, no `$ARGUMENTS` substitution and no skill body reaches the hook: the skill
reference survives only as the leading `/pr-dev` token. What the *model* receives after the hook was not observed (the
prompt was blocked by design: the installed `pr-dev` would otherwise have started work on PR 42). Cursor titled both
chats from the text even though the prompt was blocked.

### S4 evidence — Cursor plugin variables (blocked)

Checked in Chrome on the already signed-in account; no login was started. `cursor.com/dashboard`: Pro+ plan,
individual. `Plugins & MCPs` has a single **Personal** scope tab listing the plugin as Plugin / Optional; the row menu
offers `View details` and `Remove`; the details dialog has only `Remove from Personal`, plus section links MCPs
(`github`), Skills, Subagents, Hooks (`preToolUse`, `beforeShellExecution`, `postToolUse`), Rules and Commands: no
Configure entry, no variables field. `Members` → "Upgrade to Teams … Admin Controls". Nothing was set, so nothing needed
reverting.

### Restore proof

SHA-256 of the user's config files was taken before any change and after the run; exactly one line differs.

| file | result |
|---|---|
| `~/.claude/settings.json`, `~/.claude/settings.local.json` | identical |
| `~/.cursor/cli-config.json`, `~/.cursor/hooks.json` | identical |
| `~/Library/Application Support/Claude/claude_desktop_config.json`, `…/Claude/config.json` | identical |
| `~/Library/Application Support/Cursor/User/settings.json` | identical |
| `~/.claude/plugins/known_marketplaces.json`, `~/.claude/plugins/installed_plugins.json` | identical (no marketplace added, plugin list unchanged) |
| `~/.claude.json` | changed: Claude Code's own cache/state file, rewritten by the running sessions; this run never wrote it |

Cursor's `state.vscdb` holds app caches, so only this run's own change in it was reverted (S2 restore). The Cursor app
is now 3.28.7: the update was part of the run.

## Impact on ADR 004 D8 (GUI checks)

1. **U4 (Claude Desktop row): L3 unverified → E (measured).** A `PreToolUse` hook `ask` raises Desktop's own approval
   card with the reason verbatim and Deny / Allow once, under Bypass permissions too (as M1 on the CLI), and Deny
   blocks: "ask is delivered as" becomes "as CLI: hook `ask`", and the call stamp stays as defence in depth. This was a
   project-settings hook; a plugin's own hooks were shown to run (`pt2`'s `SessionStart`), but a plugin-shipped
   `PreToolUse` `ask` was not run separately, and `deny` was not exercised. **Level storage on Desktop:** Desktop
   offers no way to set a `userConfig` value (no install dialog, no Configure entry), and with nothing stored the hook
   env carries no `CLAUDE_PLUGIN_OPTION_*`, so the level comes only from its absence: `supervised`, which is what the
   resolver already answers (D7 "no config"). Raising it means the CLI's `/plugin configure` (the shared
   `~/.claude/settings.json` `pluginConfigs`; whether the embedded 2.1.317 reads it was not tested) or the neutral user
   policy file.
2. **S2 (Cursor desktop row): unverified → measured on 3.28.7.** L2: `beforeShellExecution` decisions are honoured in
   every mode (`deny` itself was not re-run on desktop; the deny-guard branch never fired). L3: `beforeShellExecution`
   `ask` is a real forced prompt in Auto-Review, Allowlist (over an allowlist entry) and Run Everything, which
   contradicts the forum note "ignored under Auto-review" on 3.28.7. `preToolUse` `ask` is unenforced, so `preToolUse`
   stays deny-only. A hook tells desktop (`cursor_version` `3.28.7`) from the CLI (`2026.10.22-…`, where `--yolo` drops
   the ask, S1), so the ask is delivered as `ask` on desktop from 3.28.7 and the CLI stays deny. Caveat: in Allowlist
   mode the card does not show the hook's `user_message`, so the D5 reason text is not guaranteed on screen. This run is
   the live run that moves `targets.cursor.validated_against` and `.cursor-version` to 3.28.7.
3. **S3 (per-skill levels on Cursor): no change.** The arguments arrive only as raw prompt text with no structured skill
   or argument field, and the picker's chip is flattened to the same text. A `beforeSubmitPrompt` hook can parse
   `--perms=` from `prompt` but cannot prove which skill ran, so the D8 "per-skill levels at L2" column for Cursor stays
   **A**, and a `--perms=` raise stays prompt text needing confirmation.
4. **S4 (plugin variables → hook env): no change.** This account offers no channel to set a plugin variable, so the
   neutral user-level policy file stays the only shared store (spike decision 5). Rerun on a Teams admin account.

---

<p align="center"><a href="https://github.com/Tamircohen28">Have a Question?</a>&nbsp;·&nbsp;<a href="https://github.com/Tamircohen28/tamirs-superpowers/issues/new/choose">Open an Issue</a></p>
