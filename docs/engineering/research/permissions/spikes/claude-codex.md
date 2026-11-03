# Live checks of Claude Code and Codex permission behavior

Task 002 of objective `permissions-design`. Run 2026-11-03 against Claude Code **2.1.317** (installed) and Codex CLI **0.166.0** (fetched with `npm exec`; the local 0.156.0 was not used). No login, no model call, no global install. Every tool was pointed at a throwaway directory (`CLAUDE_CONFIG_DIR`, `CODEX_HOME`, `HOME`); `~/.claude/settings.json`, `~/.codex`, `~/.codex/config.toml` kept their pre-run mtimes.

Tags: **measured** = a command was run and its output is quoted; **source-cited** = read from source or from strings extracted out of the shipped binary; **doc-cited** = a vendor doc, not re-read here; **unverified** = nobody has observed it. The earlier research reports were used only to pick questions, never as evidence.

## Verdict table

| id | question | verdict | one-line answer |
|----|----------|---------|-----------------|
| C1 | Is a `userConfig` option with a `default` still prompted / counted as set? | measured + source-cited; interactive dialog **blocked** | The CLI counts it as **not yet set** and the configure view pre-fills the default; at runtime an unset option resolves to the default. |
| C2 | Does `string` + `options` validate on 2.1.317; what happens on an older host? | measured (2.1.317); older host **source-cited**, not run | Validates, but `options` must be an array of **plain strings**, and `default` must be one of them. A pre-2.1.271 host has a strict schema and would reject the unknown key. |
| C3 | Do `UserPromptSubmit` / `UserPromptExpansion` inputs carry skill arguments? | source-cited (binary schema); live run **blocked** | `UserPromptExpansion` carries `command_args` (required string) and `prompt`; `UserPromptSubmit` carries only `prompt`, plus a provenance field `source`. |
| C4 | Does a PreToolUse `ask` on `gh pr merge` prompt under `auto` / `bypassPermissions`? | **blocked** (partly source-cited) | The code keeps a hook `ask` alive and re-surfaces it over a classifier allow (`auto`); the bypass outcome could not be settled statically. |
| C5 | Desktop Code tab: userConfig dialog and hooks | **blocked** | Needs the Desktop app. |
| X1 | Codex PreToolUse `ask` (and bare `allow`) rejected, and the call proceeds? | source-cited (two upstream unit tests name it); not run | Yes: both are `Failed` hook runs with `should_block: false`; the tool runs. So is a crash, a timeout or any exit code other than 0/2. |
| X2 | `PLUGIN_DATA` exported to hooks only? | source-cited | Exported to hooks and to agent-plugin MCP stdio servers; no code path puts it in skill text or the shell tool environment. |
| X3 | Does `PermissionRequest` fire for prompts `granular` auto-rejects? | source-cited | No, for exec prompts. They become `Forbidden` before `request_approval`, the only caller of the hook. |
| X4 | Unknown keys under `[plugins."x@y"]`: error or ignored? | **measured** | Silently ignored. Wrong type on a known key is a hard error, so the table is parsed. |

## C1. Defaulted option: prompted, or already set?

**Method.** Local marketplace in scratch holding `pt` (four options: `preset` string with `options` and `default`, `plain` with no default, `needed` required with no default, `defreq` required with a default) and `pt2` (only a defaulted `preset`). Installed both with the CLI into the scratch config dir.

```text
$ claude plugin install pt2@t002-mkt --json </dev/null
..."message":"Successfully installed plugin: pt2@t002-mkt (scope: user)\n1 userConfig option not yet set — run /plugin configure pt2@t002-mkt in Claude Code, or pass --config KEY=VALUE."
$ claude plugin configure pt2@t002-mkt --json
"inputs": {"preset": "supervised"}, "configured": [], "unconfigured": ["preset"]
$ claude plugin install pt@t002-mkt --json </dev/null
...4 userConfig options not yet set (2 required)...     # includes `preset` (default) and `defreq` (required + default)
```
**measured.** A defaulted option is reported as unset, in the install message and in `configure`'s `unconfigured` list, and the "(N required)" count includes `defreq`. `configure --json` pre-fills `inputs.preset` with the default, so a dialog built from it shows the default as the starting value (**inferred**; the dialog itself was not seen).

**Why (source-cited, binary 2.1.317).** The "unset" test, minified `x$e`, only checks the stored value: unset if `undefined`, `""`, or (non-sensitive) failing validation against the field. It never looks at `default`. The runtime resolver, minified `Bst(stored, schema)`, starts from `default` for every field that has one (`n[a]=m.default??""`, skipping required fields without a default), then overlays stored values. A stored value outside `options` logs `plugin option X holds a value that is not one of ...; it reads as unset` and falls back to the default. The same resolver is called for LSP servers and for the plugin options load that logs `every option is its default` when nothing is stored.

**Answer.** The user is still asked (or at least told) once; if they skip it, the plugin runs on the default. A `strict` default is therefore safe without any install step.

**Not seen.** Whether the interactive `/plugin` install dialog shows a defaulted field, and whether skipping leaves a banner. See user step U1. Also unverified: that `${user_config.preset}` in a skill body reads the default when unset (resolver is shared, skill substitution was not exercised).

## C2. `string` + `options` on 2.1.317, and on an older host

```text
$ claude plugin validate mkt/pt           # options as objects [{value,label}]
  userConfig.preset.options.0: Invalid input: expected string, received object   (x3)  -> fail
$ claude plugin validate mkt/pt           # options as ["supervised","standard","unattended"], default "supervised"
  ✔ (one author warning)                                                         -> exit 0
$ ... default: "bogus"      -> userConfig.preset.default: default must be one of the options: supervised, standard, unattended
$ ... options: []           -> options needs at least one value
$ ... options on a field with sensitive:true or type != string -> options is only for a field of type "string" that is neither multiple nor sensitive
$ claude plugin configure pt@t002-mkt --values-stdin  <<< '{"preset":"bogus"}'
  Failed to save configuration: Preset must be one of: supervised, standard, unattended   (exit 1)
$ ... '{"preset":"standard","needed":"n"}'  -> Configuration saved. Restart Claude Code to apply it.
```
**measured.** `options` validates on 2.1.317 only as an array of strings (the object form in some write-ups is wrong), the default must be a member, an empty list fails, and `options` cannot be combined with `sensitive`. `configure --values-stdin` enforces the list. Values land under `pluginConfigs."<plugin>@<marketplace>".options` in the user `settings.json`.

Binary description text (source-cited): "`/config` shows the field as a picker over them, and a stored value outside them counts as unset"; and a schema rule "a field with options needs a default among them, or required: true".

**Older host.** All installed binaries are 2.1.311 or newer (`~/.local/share/claude/versions`), so a pre-2.1.271 host could not be run. The nearest measured analog: the field schema is `.strict()`, and adding an unknown key to a field fails validation on 2.1.317 with `userConfig.plain: Unrecognized key: "futureKey"`. A host without `options` in its schema would reject the field the same way. That agrees with the doc claim that users on versions before 2.1.271 cannot load the plugin (**doc-cited**). **Source-cited inference, not run.**

**Answer for ADR.** Using `options` makes 2.1.271 a hard floor for loading the whole plugin, not just for the picker. The repo pin (2.1.317) is above it, but the manifest has no field that stops an older host from trying to install, so the floor must be stated in docs and checked by `make validate`.

Extra finding (source-cited): a shell-form hook command that contains `${user_config.*}` is **refused** by the host ("The substituted value would be re-parsed by the shell. Use exec form ... or read `$CLAUDE_PLUGIN_OPTION_<KEY>` from the hook's environment"). Hooks must read the option from the environment.

## C3. Do prompt hooks see skill arguments?

**Method.** No CLI prints a hook schema, so the zod schemas were extracted from the 2.1.317 binary (`strings`) and read. **source-cited.**

```text
UserPromptExpansion : {hook_event_name, expansion_type: "slash_command"|"mcp_prompt",
                       command_name: string, command_args: string, command_source?: string, prompt: string}
UserPromptSubmit    : {hook_event_name, prompt: string,
                       source?: "user"|"sdk"|"system"|"loop_wakeup"|"schedule_wakeup"|"poll_event", session_title?}
```
Event description in the binary: "When a user-typed slash command expands into a prompt. Input to command is JSON with expansion_type, command_name, command_args, command_source, and original prompt. Exit code 2 - block expansion and show stderr to user only." The `UserPromptExpansion` matcher is `command_name`. Output schema: `additionalContext`, `suppressOriginalPrompt`; no field rewrites the arguments.

**Answer.** Yes for `UserPromptExpansion` (`command_args`, a required string) and the full typed line is in `prompt`; `UserPromptSubmit` has only `prompt`. New and design-relevant: `UserPromptSubmit.source` says who authored the prompt, which is the provenance signal a "raise the level only from a user-typed prompt" rule needs. The binary says the field "may be omitted while it rolls out", so treat a missing `source` as not-user.

**Not seen live.** That `command_args` for `/tamirs-superpowers:pr-dev 42 --perms=x` is exactly `42 --perms=x`, and whether it fires for a plugin skill. Cheap no-model test in U2 (exit 2 blocks the expansion before the model).

## C4. Does a PreToolUse `ask` prompt under `auto` and `bypassPermissions`?

**Blocked.** Showing a prompt needs an authenticated interactive session. What the binary says (**source-cited**, decision function that consumes hook results, minified `wXr`):

- A hook `ask` is not dropped. If a deny rule matches, deny wins. If the normal pipeline also asks, the call goes through it with `hookAskFloor: true`, and the debug log reads "Hook returned 'ask' ... (hookAskFloor — a classifier allow re-surfaces as this ask)". That is the `auto` case: the classifier cannot turn a hook ask into an allow.
- Otherwise the hook's own `ask` decision is handed on as the final decision (`ROe(ke, ...)`).
- A hook `allow` under `auto` is *not* honored: "Hook approved tool use for X, but auto mode requires classifier adjudication". So a hook cannot widen under `auto` either. (`allow` skips the prompt only in other modes.)
- `bypassPermissions` has its own branch that converts some non-hook asks to allow (`permission_bypass_removal_prompt_waived`); whether a hook-originated ask is exempt could not be settled from minified code, so it stays **unverified**.

**Design stance until measured.** Treat the hook `ask` as a belt, never the only layer, and keep a hard `deny` for R3/R4 above the ceiling. User step U3 gives the exact test.

## C5. Desktop Code tab

**Blocked.** Cannot be driven headless. User step U4. Registry value `claude_desktop.hooks: unknown` stays correct.

## X1. Codex PreToolUse `ask` and bare `allow` fail open (rust-v0.166.0, commit `6ff1e1ca3b30`)

Paths below are under `codex-rs/`. **source-cited**.

- `hooks/src/engine/output_parser.rs:441-470` (`unsupported_pre_tool_use_hook_specific_output`): `permissionDecision: "ask"` -> `Some("PreToolUse hook returned unsupported permissionDecision:ask")` (line 458-459). `"allow"` is accepted **only with `updatedInput`**; without it -> `unsupported permissionDecision:allow` (line 453-457). New versus the earlier report: `allow` + `updatedInput` is a supported rewrite, and legacy `decision:"approve"` is rejected as well (`output_parser.rs:490`; test at `pre_tool_use.rs:629`). Only `deny` (with a non-empty reason) or legacy `decision:"block"` blocks.
- `hooks/src/events/pre_tool_use.rs:242-247`: an `invalid_reason` sets `status = HookRunStatus::Failed` and pushes an Error entry; `should_block` stays `false`.
- `core/src/hook_runtime.rs:239`: `if !should_block { return PreToolUseHookResult::Continue { updated_input } }`; `core/src/tools/registry.rs:856` is the only place that turns the result into a rejection (`Blocked`). So the tool call proceeds.
- Same file, lines 268-284: exit code **2 with stderr** = block (the only non-JSON deny); exit 2 with empty stderr = `Failed`; **any other exit code** (line 285) = `Failed`, no block; a handler `error` (spawn failure) = `Failed`; `hooks/src/engine/command_runner.rs:232,376` turns a timeout into such an error ("hook timed out after Ns"). Every failure mode of a guard hook is therefore **fail-open**.
- Upstream tests assert exactly this: `unsupported_permission_decision_fails_open` (`pre_tool_use.rs:577`) and `permission_decision_allow_without_updated_input_fails_open` (`:463`).

**Not run.** There is no cargo here (running `cargo test -p codex-hooks` was also outside the "no suite" rule), and `codex` has no hook dry-run subcommand that avoids a model turn. A live run is covered by U5.

## X2. Where `PLUGIN_DATA` is exported (source-cited)

- `hooks/src/engine/discovery.rs:316-319` builds the handler environment with `PLUGIN_ROOT`, `CLAUDE_PLUGIN_ROOT`, `PLUGIN_DATA`, `CLAUDE_PLUGIN_DATA`.
- `codex-mcp/src/agent_plugin_config.rs:229-230` also injects `PLUGIN_ROOT` / `PLUGIN_DATA` into an agent plugin's stdio MCP server (the earlier report missed this consumer).
- `grep -rln PLUGIN_DATA codex-rs` returns only those two production files plus tests. Nothing sets it in skill text or the shell tool environment. A skill therefore cannot read `$PLUGIN_DATA` and has to derive `${CODEX_HOME:-$HOME/.codex}/plugins/data/<plugin>-<marketplace>` itself.
- The hook's `permission_mode` is `bypassPermissions` only when `approval_policy = never`; `on-request`, `untrusted` and `granular` all read `default` (`core/src/hook_runtime.rs:1073-1081`).

## X3. Does `PermissionRequest` fire for prompts `granular` rejects? (source-cited)

- The only caller of `run_permission_request_hooks` in `core/src` is `Session::request_approval` (`core/src/tools/approvals.rs:529`, comment at 526: "Approval precedence is: 1. Hooks 2. Guardian/user").
- For an exec prompt, `granular` is applied **earlier**: `core/src/exec_policy.rs:413` (`prompt_is_rejected_by_policy`, defined at `:218`) and `core/src/tools/sandboxing.rs:217-221` produce `ExecApprovalRequirement::Forbidden`, and `core/src/tools/orchestrator.rs:200-202` returns `ToolError::Rejected` for it without ever calling `request_approval`. `prompt_is_rejected_by_policy` returns a rejection for `sandbox_approval = false` and (for rule prompts) `rules = false`.
- `unified_exec/preparation.rs:277` rejects an escalation request outright under the same condition.
- `mcp_tool_call.rs:824` and `session/mod.rs:3254` do the same for MCP elicitations and `request_permissions`.

**Answer.** No: a `PermissionRequest` hook is not consulted for prompts that `granular` turns off, so a hook cannot rescue them. Not traced: `skill_approval = false`.

## X4. Unknown keys under `[plugins."x@y"]` (measured)

```text
CODEX_HOME=<scratch>  codex-cli 0.166.0
config.toml                                     `codex features list` / `codex plugin list`
(empty)                                         ok
approval_policy = 5                             Error: failed to load bootstrap configuration ... invalid type  (exit 1)   control
totally_unknown_key = "x"                       ok (ignored)                                                               control
[plugins."x@y"] enabled = true; preset = "standard"      ok, "No marketplace plugins found." (exit 0)
[plugins."x@y".settings] preset = "standard"             ok (exit 0)
[plugins."x@y"] enabled = "notabool"            Error: invalid type: string "notabool", expected a boolean  in `plugins`  (exit 1)
```
**measured.** The `plugins` table is parsed (a wrong type on `enabled` fails), but an unknown key or sub-table is silently ignored. Source agrees: `config/src/types.rs:1127-1129` has `#[schemars(deny_unknown_fields)]`, which only shapes the generated JSON schema; there is no serde `deny_unknown_fields`. Caveat: editors that validate against `config.schema.json` will flag such a key, and a future release may tighten it. Our settings still must not live there.

## User steps for blocked checks

Run from any normal shell where you are logged in. None of these edit global config. Scratch plugin sources are in
`/private/tmp/claude-501/-Users-tamircohen-Projects-tamirs-superpowers/4d09d4e0-b2ec-46c3-8c1c-8cf1d67342b8/scratchpad/t002/mkt` (marketplace `t002-mkt`, plugins `pt`, `pt2`); if that is gone, the manifest is the `userConfig` block quoted in C1/C2.

**U1 (C1, interactive dialog).**
1. `claude` in any scratch directory (your normal login; nothing below touches your settings except the install, undone in step 4).
2. `/plugin marketplace add <scratch path above>/mkt`, then `/plugin install pt2@t002-mkt`.
3. Observe: (a) is a "Preset" field shown at all; (b) is it a picker with `supervised` pre-selected; (c) can you accept without typing; (d) after skipping, does `/plugin configure pt2@t002-mkt` still list it. Expected from C1: shown, default pre-filled, skippable.
4. Cleanup: `/plugin uninstall pt2@t002-mkt`, then `/plugin marketplace remove t002-mkt`.

**U2 (C3, live argument capture without a model call).**
1. `D=$(mktemp -d); printf '#!/bin/sh\ncat > %s/in.$$.json\necho captured >&2\nexit 2\n' "$D" > $D/h.sh; chmod +x $D/h.sh`
2. `printf '{"hooks":{"UserPromptExpansion":[{"hooks":[{"type":"command","command":"%s/h.sh"}]}],"UserPromptSubmit":[{"hooks":[{"type":"command","command":"%s/h.sh"}]}]}}' $D $D > $D/s.json`
3. In this repo: `claude --settings $D/s.json`, type `/tamirs-superpowers:pr-dev 42 --perms=bypass`; then, in a fresh session, a plain sentence. Exit 2 blocks each prompt before the model sees it.
4. `cat $D/in.*.json`. Expected: the expansion capture has `expansion_type: "slash_command"`, `command_name` = the skill, `command_args` = `42 --perms=bypass`; the plain-sentence capture has `source: "user"`.

**U3 (C4, hook `ask` under each mode).**
1. `D=$(mktemp -d); printf '#!/bin/sh\necho "{\\"hookSpecificOutput\\":{\\"hookEventName\\":\\"PreToolUse\\",\\"permissionDecision\\":\\"ask\\",\\"permissionDecisionReason\\":\\"spike\\"}}"\n' > $D/ask.sh; chmod +x $D/ask.sh; sh $D/ask.sh` (the last command must print one line of valid JSON).
2. `printf '{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"%s/ask.sh"}]}]}}' $D > $D/s.json`
3. For each of `default`, `auto`, `bypassPermissions`: `claude --settings $D/s.json --permission-mode <mode>`, then ask "run `echo hi` with Bash". The hook asks for every Bash call and `echo hi` is harmless; never use a real `gh pr merge`.
4. Record per mode whether a permission prompt appeared. Expected from the docs: yes in all three. A mode where `echo hi` simply runs means a hook `ask` is not a backstop there.
5. Optional headless: `claude -p --settings $D/s.json --permission-mode bypassPermissions "run echo hi with Bash"`; record denied, hang or ran.

**U4 (C5, Desktop).** Install the same scratch marketplace in the Desktop app (Code tab -> plugins -> add marketplace by path), install `pt2`, and note whether a configuration dialog appears with the picker; then repeat U3 (steps 1-4) by adding the `PreToolUse` block from `$D/s.json` to the app's settings and note whether the `ask` prompt appears.

**U5 (X1 live, optional).** In a scratch `CODEX_HOME` you have logged into, register the `ask.sh` hook from U3 as a `PreToolUse` hook for `Bash` (trust it in `/hooks`), run `codex exec "run echo hi"`; expect the command to run and the hook to be listed as failed with "unsupported permissionDecision:ask".

## Impact on ADR 004

1. **Enforcement layers.** Claude: `deny` is the hard layer, `ask` is a probable second layer (C4 pending), with the classifier unable to override a hook ask under `auto`. Codex: `deny` is the only hook verdict that does anything (X1); a hook `ask` or bare `allow` is a no-op. Codex wiring must therefore return `deny` plus an in-chat confirmation, never `ask`, and treat `PermissionRequest` as unable to see `granular`-rejected prompts (X3).
2. **Fail-open handling.** On Codex every guard failure (crash, timeout, bad exit code, malformed JSON, exit 2 without stderr) lets the call run. The deny path must print its reason to stderr and exit 2, or emit valid `deny` JSON with a reason, and the design cannot rely on a hook as the *only* barrier for R4 on Codex. Add a startup self-test (`SessionStart`) that reports a broken guard. Claude's `onFailure: "block"` (2.1.295+) is the counterpart and is already in the repo; keep the manifest-invariants test covering both.
3. **Minimum versions.** `userConfig.options` raises the Claude floor to **2.1.271** for loading the plugin at all (C2). Codex needs 0.166.0 only for `allow` + `updatedInput`, which we do not use; the `deny`-only contract is stable across the observed range.
4. **Preset storage.** Claude: a `string`+`options` field with a valid `default` works, is validated by `configure`, and an unset value resolves to the default at runtime (C1/C2), so `supervised` as default is safe. The manifest must use string options and a member default; hooks must read `CLAUDE_PLUGIN_OPTION_*`, never `${user_config.*}` in a shell-form command. Codex: nothing in `config.toml` can carry it (unknown keys are ignored, X4), so the preset lives in the neutral user file, and a skill must compute its data directory itself (X2).
5. **Raising the level per run.** Claude can gate an escalating `--perms=` on `UserPromptSubmit.source == "user"` and read arguments from `UserPromptExpansion.command_args` (C3, pending U2). Codex has no equivalent: the override is prompt text and needs an in-chat confirmation.
6. **Open after this spike:** U1 (dialog), U2 (live `command_args`), U3 (bypass behavior of hook `ask`), U4 (Desktop). Only U3 changes the design: if hook `ask` is ignored under `bypassPermissions`, `deny` plus a skill-body confirmation becomes the only Claude barrier there too.
