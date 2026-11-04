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
