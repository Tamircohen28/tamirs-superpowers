# Spike: live checks of Cursor, Gemini CLI and OpenCode permission behavior

Date: 2026-11-03. Task: `permissions-design` / task-003. Feeds ADR 004.
Versions exercised: Gemini CLI **0.66.0** (fetched with `npm exec`, the local 0.60.0 was not used), OpenCode **2.2.5**,
`cursor-agent` **2026.10.22-27dcf5f** (Cursor desktop 3.28.x could not be installed or run).

Tags: **measured** = I ran it and quote the output. **source-cited** = read in source at the named tag or in the shipped
bundle. **doc-cited** = vendor docs fetched 2026-11-03. **unverified** = not established. **blocked** = needs the user.
Nothing from the earlier research reports is carried over as verified.

## Method and isolation

- Every tool ran against throwaway dirs under the task scratch dir (`HOME=<scratch>/home`, plus `XDG_*` and
  `OPENCODE_CONFIG_DIR` for OpenCode). The redirect was verified first: `opencode debug paths` printed only scratch paths.
  The real `~/.cursor`, `~/.gemini`, `~/.config/opencode` and `~/.codex` mtimes were identical before and after.
- OpenCode runs used `--standalone`. Without it the CLI tries to start or join the user's real background service
  (a first call without it failed with "port 49374 already in use by PID ... serve --service"; nothing was changed).
- **No login, no OAuth, no provider API call.** To get past "no model" I wrote two tiny HTTP mocks bound to `127.0.0.1`
  (a Gemini REST mock and an OpenAI-compatible mock) that answer the first turn with one scripted tool call.
  Gemini: `GEMINI_API_KEY=fake GOOGLE_GEMINI_BASE_URL=http://127.0.0.1:<port>`. OpenCode: a custom provider with
  `@ai-sdk/openai-compatible` and `baseURL` set to the mock. The CLIs ran their real permission code; only the model
  was fake. Cursor's agent speaks a proprietary protocol to its server, so it could not be mocked: its checks are
  source-cited from the shipped bundle or blocked.
- Fake-model caveat: in Gemini `-p` mode the shell and write tools are not even registered unless `--yolo` (measured:
  `Tool "write_file" not found`), so the Gemini hook tests use `read_file` (default mode) and `run_shell_command` (`--yolo`).

## Verdicts

| id | question | verdict | one-line answer |
|----|----------|---------|-----------------|
| U1 | Cursor hook `allow`/`ask` honored? | source-cited (CLI 2026.10.22); desktop 3.28 blocked | `beforeShellExecution` **ask forces a prompt in every approval mode, including unrestricted**; `allow` has no effect; `preToolUse` consumes only `deny`. |
| U2 | How does text after `/pr-dev` reach the model? | source-cited + doc-cited; exact wrapper blocked | No `$ARGUMENTS` substitution anywhere in the client; `argument-hint` is display metadata. Text is prompt prose. |
| U3 | Do plugin `variables` reach hook env? | source-cited; live blocked | No. They feed `${VAR}` substitution in MCP config only; the hooks loader never receives them. |
| G1 | BeforeTool hook `ask` headless: hang or deny? | **measured** | **Hangs** (no timeout, killed at 45 s, 180 s and under `--yolo`). Never emit `ask` unattended. |
| G2 | Does BeforeAgent see slash-command args? | **measured** (headless and interactive) | Interactive: yes, args only (`42 --perms=bypass`), skill name stripped. Headless: verbatim `/pr-dev 42 ...`, skill not activated. |
| G3 | Does an extension `ask_user` rule hold under `--yolo`? | **measured** | Yes. Headless it turns into a deny (`Tool execution denied by policy.`). |
| O1 | Plugin permission hook vs `--auto`; custom-action prompt under `--auto`? | **measured** | Hook runs **before** `--auto`; hook `deny` holds, hook/`assert` **`ask` is auto-approved**. |
| O2 | Session allow override a config deny? | **measured** | **Yes.** A session rule appended after config wins (`findLast`). |
| O3 | Where does `ctx.storage` live? | **measured** | Global SQLite `kv` table in `~/.local/share/opencode/opencode.db`, key `plugin:<hex id>:<key>`. |

## U1. Cursor hook `allow` / `ask`

**Source-cited, CLI 2026.10.22** (bundle `~/.local/share/cursor-agent/versions/2026.10.22-27dcf5f/{index.js,1841.index.js}`, minified;
quoted verbatim, offsets are byte offsets in those files).

1. Schema: the output validator for `beforeShellExecution`, `beforeMCPExecution`, `subagentStart` and `preToolUse` accepts
   `["allow","deny","ask"]`; `beforeReadFile` and `beforeTabFileRead` accept only `["allow","deny"]` (index.js @4036817 shared validator for beforeShell/beforeMCP, @4040516 subagentStart, @4041117 preToolUse).
2. Shell step (1841.index.js @91940):
   `if("deny"===a?.permission){... throw new S(e)} if("ask"===a?.permission) return (0,s.$bB)(a.user_message)`.
   `$bB` builds `ShellHookApprovalRequirement{kind: FORCE_PROMPT, reason}` (index.js @3700976). An `allow` returns nothing.
3. Approval gate (`shouldBlockShellCommand`, index.js @4751752 and @4758487): `const $ = hookForcesPrompt(...)` then
   `let G = $||F ? void 0 : this.getShellAutoApprovalPolicy({approvalMode: c, isUnrestricted: u, ...})`.
   `G` is the only path to the silent `{kind:"allow"}` return, so a hook ask skips every auto-approval policy (allowlist,
   sandbox policy, unrestricted/Run Everything) and falls through to `pendingDecisionStore.requestApproval` with the
   reason `Hook requested approval: <user_message>` and `canAllowlist=false`. There is no early return for unrestricted mode before that line.
4. `preToolUse` (1841.index.js @86512 for built-in tools, @100246 for MCP): only `permission === "deny"` is acted on, plus
   `updated_input` and `additional_context`. `ask` and `allow` are dropped.
   doc-cited: `https://cursor.com/docs/hooks.md` L892 says `"ask"` is "accepted by the schema but not enforced for `preToolUse` today".
5. Failure mode: `hasFailClosedHooksForStep` rejects the call when a fail-closed preToolUse hook errors (same file).
6. `beforeMCPExecution`: schema accepts `ask` and the docs show it (hooks.md L1085); I did not locate the consumer: unverified.

**Not established:** desktop 3.28.x (Auto-review is the default run mode there and is a separate server classifier path,
`smartModeApprovalReason`), and whether print mode (`-p`) surfaces or auto-rejects the approval. **blocked**: see user steps S1, S2.
The earlier report's "ask is ignored by `beforeShellExecution` under Auto-review" is therefore **not** reproduced for the
CLI shell path; it may still hold on desktop.

## U2. Text after `/pr-dev`

- **source-cited:** the string `$ARGUMENTS` occurs **0 times** in the 8 MB CLI bundle. Skills and commands carry an
  `argumentHint` field (index.js @4006110 `ju=...argumentHint:YjP().optional(), content`, proto `AgentSkill.argument_hint`),
  parsed from the `argument-hint` frontmatter and used for display only. No code substitutes arguments into `content`.
- **doc-cited:** `https://cursor.com/docs/skills.md` L29: a skill invoked with `/` "attaches to one message"; the frontmatter table has no
  arguments field. The only documented `$ARGUMENTS` is for prompt-type hooks.
- **Conclusion:** `42 --perms=bypass` reaches the model as ordinary user text next to the attached skill body. How the server
  orders and wraps the two is **blocked** (proprietary protocol): user step S3 captures it with a `beforeSubmitPrompt` hook.

## U3. Plugin `variables` into hook env

- **doc-cited:** `https://cursor.com/docs/reference/plugins.md` L94, L112-118: `variables` declares names only; values are set in
  the dashboard (Plugins -> Configure) and "substituted into `${VAR}` placeholders" in MCP config. Hooks are not mentioned.
- **source-cited:** `configuredVariables` arrives with the plugin record from the server (index.js @3946212) and is consumed by the
  placeholder resolver (index.js @3823358): it substitutes `command`, `args`, `env` and `cwd` of MCP servers, looking in
  `process.env[name]` **first**, then `configuredVariables`. The plugin hooks loader `su(root, name, hooksSpec, path)`
  (index.js @3978959 region) takes no variables argument. So hook commands do not see them.
- **Local run:** `cursor-agent --plugin-dir <throwaway> --trust -p "..."` with a plugin carrying `variables` and `sessionStart`
  hooks stopped at `Error: Authentication required.` before any hook ran: **blocked** (S4). Inference for the design:
  an exported shell env var of the same name is the only user-controlled value a plugin could read, and only for MCP.

## G1. Gemini BeforeTool hook `{"decision":"ask"}` headless

**Measured**, Gemini CLI 0.66.0, mock Gemini on `127.0.0.1:18431`, hook at `BeforeTool` in a throwaway `~/.gemini/settings.json`:

```text
$ gemini --skip-trust -m gemini-2.5-flash -p "read the file"           # hook prints {}
exit=0 secs=2   MOCK_DONE
# hook prints {"decision":"deny","reason":"probe-deny"}
exit=0 secs=1   Error executing tool read_file: Tool execution blocked: probe-deny
# hook prints {"decision":"ask","reason":"probe-ask","systemMessage":"probe-ask-msg"}
Hook system message: probe-ask-msg            <- then nothing; process alive
exit=142 secs=45 (SIGALRM)                    <- repeated with a 180 s limit: exit=142 secs=180
# same ask hook + --yolo + run_shell_command ("echo MOCK_SHELL_RAN > shell-ran.txt")
Hook system message: probe-ask-msg  ... exit=142 secs=40,  shell-ran.txt absent
# control: hook prints {} + --yolo
shell-ran.txt present
# --yolo + hook deny:  Error executing tool run_shell_command: Tool execution blocked: probe-deny   (file absent)
```

- Hook stdin (BeforeTool) fields: `session_id, transcript_path, cwd, hook_event_name, timestamp, tool_name, tool_input`. No
  interactivity flag, no prompt id.
- **source-cited why:** `core/src/scheduler/scheduler.ts` L683-686 sets `decision = ASK_USER` *after* `checkPolicy`, so (a) it overrides a
  policy `DENY` and (b) it escapes the headless conversion that lives inside `PolicyEngine.check` (`policy-engine.ts` L1010,
  `if (nonInteractive && decision === ASK_USER) decision = DENY`). `resolveConfirmation` then parks the call in
  `AwaitingApproval` and `waitForConfirmation` waits for a UI reply that `nonInteractiveCli.ts` never sends (the file has no
  `AwaitingApproval` or `TOOL_CONFIRMATION_RESPONSE` handling).
- Interactive behavior (a prompt appears, and `--yolo` does not suppress it because `shell.ts` L319-323 skips the YOLO shortcut only
  for `forcedDecision === 'ask_user'`) is **source-cited**; I did not drive an approval in the pty.
- Design consequence: a headless `ask` is a **hang**, not a deny. The plugin cannot detect headless from hook input, so any
  guard that may run unattended must emit `deny` (with the setting that would allow it), never `ask`.

## G2. BeforeAgent and a skill slash command's arguments

**Measured** with an extension `probe-skill-ext` (linked via `gemini extensions link`) shipping `skills/pr-dev/SKILL.md`, and
`BeforeAgent` + `BeforeTool` hooks that append their stdin to a log.

- **Interactive** (pty driver, `--yolo`, typed `/probe-skill-ext:pr-dev 42 --perms=bypass`):
  ```text
  BeforeTool  {'tool_name': 'activate_skill', 'tool_input': {'name': 'pr-dev'}}
  BeforeAgent {'prompt': '42 --perms=bypass'}
  ```
  Model request contents: `model: functionCall activate_skill` -> `user: functionResponse <activated_skill name="pr-dev">` -> `user: '42 --perms=bypass'`.
  So `BeforeAgent.prompt` is the **argument text only**; the skill name appears only in the preceding `BeforeTool(activate_skill)`.
  With no arguments the prompt is the literal `Use the skill pr-dev` (source-cited: `SkillCommandLoader.ts` L47-51, `postSubmitPrompt`).
- **Name resolution:** extension skills are always namespaced, `SlashCommandResolver.ts` L51 (`shouldAlwaysPrefix` for
  `SKILL` with `extensionName`). Typing bare `/pr-dev` did **not** resolve: it was sent as plain text
  (`BeforeAgent.prompt = '/pr-dev 42 --perms=bypass'`, no `activate_skill`). The completion list shows `probe-skill-ext:pr-dev`.
- **Headless** (`gemini -p "/pr-dev 42 --perms=bypass"`): `BeforeAgent.prompt = '/pr-dev 42 --perms=bypass'`, the model saw the same
  text, no `activate_skill`. Source: `nonInteractiveCliCommands.ts` L45-47 builds its `CommandService` from Builtin, McpPrompt and
  File loaders only, so skill slash commands do not exist headless.
- Provenance: the interactive `BeforeAgent` text is what the user typed after the command, so it can prove a user-supplied
  `--perms=` for the skill named by the immediately preceding `activate_skill` event. A *model*-initiated `activate_skill` also fires
  `BeforeTool` but is not followed by a `BeforeAgent` with args. Correlation is by order within a session (no prompt id in the hook input): unverified under concurrency.

## G3. Extension `ask_user` under `--yolo`

**Measured.** Throwaway extension (`gemini extensions link`) with `policies/p.toml`:

```toml
[[rule]]
toolName = "run_shell_command"
commandRegex = "echo MOCK_SHELL_RAN"
decision = "ask_user"
priority = 100          # no `modes`
```

```text
$ gemini --skip-trust -m gemini-2.5-flash --yolo -p "run it"      # mock asks for: echo MOCK_SHELL_RAN > shell-ran.txt
A (extension rule present): exit=0  Error executing tool run_shell_command: Tool execution denied by policy.   shell-ran=no
B (policies/ moved away):   exit=0                                                                            shell-ran=YES
```

- **source-cited:** extension tier 2 plus `100/1000` = 2.100 beats the YOLO allow-all at 1.998 (`policies/yolo.toml` L28-52, tier
  arithmetic in `toml-loader.ts` L48). Headless, `ask_user` becomes `DENY` (`policy-engine.ts` L1010), which is what A shows.
  `loadExtensionPolicies` (`config.ts` L222-258) drops `allow` rules and any rule or checker whose `modes` includes `yolo`:
  the plugin can ship *only* deny/ask, and only mode-less ones.
- Not exercised: a TTY session (where the same rule would prompt), and a user-tier rule or "Always allow" overriding it
  (priority 4.x, source-cited only).

## O1. Plugin permission hook and `--auto`

**Measured**, OpenCode 2.2.5, `opencode run --standalone --auto`, mock provider, probe plugin (`permission.hook("evaluate")`
logs `effectIn` and may set `e.effect`), the mock asks for `shell: echo MOCK_SHELL > shell-ran.txt`. "cfg" = global `opencode.json` `permissions`.

| case | cfg for `shell` | hook sets | flag | result |
|------|-----------------|-----------|------|--------|
| O1a | ask | - | `--auto` | ran (hook saw `effectIn=ask`) |
| O1-base | ask | - | none | `! permission requested: shell (...); auto-rejecting`, not run |
| O1b | ask | `deny` | `--auto` | **blocked**: `Error: probe-hook-message` |
| O1c | allow | `ask` | `--auto` | **ran** (ask auto-approved) |
| O1d | allow | `ask` | none | `permission requested ... auto-rejecting`, not run |
| O1e | ask | `allow` | none | ran (a hook can widen ask to allow) |

Custom action raised from the plugin with `ctx.permission.assert({action:"probe.merge", resources:["repo#1"], save:[...]})`:

| case | cfg for `probe.merge` | flag | result |
|------|-----------------------|------|--------|
| O1f/g | none | none / `--auto` | `effectIn=allow`, assert ok: **a custom action with no rule is allowed** (base policy is allow-all) |
| O1h | ask | none | `permission requested: probe.merge (repo#1); auto-rejecting`, assert rejected |
| O1i | ask | `--auto` | **assert ok** (auto-approved) |
| O1j | deny | `--auto` | `Permission denied: probe.merge`; **the hook was never called** (no `evaluate` event) |

- **source-cited:** `core/src/permission.ts` `evaluateInput` (L176-199): config/session deny first (`denied`, returns before the hook),
  then `hooks.trigger("permission","evaluate")` which may rewrite `effect`, then the `Unattended` reference (schedules only).
  `--auto` is **client-side**: `cli/src/run/noninteractive.ts` L165-190 `replyPermission` answers every pending request with
  `decision: input.auto ? "once" : "reject"`. Only requests whose final effect is `ask` ever reach the client. TUI: `tui/src/context/permission.tsx`
  maps `args.auto` to `"autoaccept"` (TUI itself not run).
- Consequences: hook order is **config deny -> plugin hook -> client**; a plugin `deny` is final, a plugin `ask` is not a
  guard under `--auto` (nor under TUI auto-accept or a saved "always"), and an `ask` rule is needed in config for a custom action to prompt at all.
- Side observation (O2c below): a config `deny` also removes the tool from the model's tool list.

## O2. Session allow versus config deny

**Measured.** Probe plugin calls `ctx.session.update({sessionID, permissions:[...]})` from `session.hook("prompt")`:

| case | cfg `shell` | session rule `shell` | result |
|------|-------------|----------------------|--------|
| O2a | deny | allow | `session.update ok`; `evaluate effectIn=allow`; **shell ran**; model tool list includes `shell` |
| O2c (control) | deny | none | not run; tool list has no `shell` |
| O2b | allow | deny | not run |

- **source-cited:** `permission.ts` L161-166 `configured = merge(agent.permissions, session.permissions)`; `evaluate` (L86-93) uses
  `findLast`, so the later session rule wins over config. `setPermissions` (`session/session.ts` L92, `projector.ts` L693) **replaces** the session's
  ruleset wholesale. Config permissions are pushed onto the agent (`config/plugin/agent.ts` L83-121), i.e. they sit earlier than any session rule.
- Consequence: any plugin that can reach `ctx.session.update` can nullify a user's `opencode.json` deny for its session (and child
  sessions inherit). A permission design must not use session rules to *widen*, and should assume other plugins might.
  Managed (admin) policy exists (`config/plugin/policy.ts`) but I only saw it applied to providers, integrations and websearch: unverified for tool actions.

## O3. Where `ctx.storage` lives

**Measured.** Plugin called `ctx.storage.set("probe-key", {v:1})`; then
`sqlite3 -readonly <data>/opencode.db "select key, value from kv;"` printed
`plugin:00700072006f00620065002e007000650072006d:probe-key|{"v":1}`.
- **source-cited:** `core/src/plugin/host.ts` L688-706: namespace `plugin:` + the plugin id as 4-hex-digit code units + `:`; backed by the global `kv`
  table (`kv/sql.ts`, `kv.ts`), not per project.
- Default path on this machine (unredirected `opencode debug paths db`): `~/.local/share/opencode/opencode.db`. With
  `XDG_DATA_HOME` it moves. Survival across `opencode uninstall`: **unverified** (help text says it keeps "session data, configuration, and state").
- Not shared with any other platform and not human-editable: use it only as a cache, not as the policy source.

## User steps for blocked checks

No step below needs me to log in on your behalf; each uses your own authenticated Cursor install.

**S1. Cursor CLI: does hook `ask` prompt (U1, CLI).** *Measured 2026-11-04 — see `implementation-measurements.md` "Live checks (issue #351)": interactive prompts; ignored under `--yolo`; print mode inconclusive. The source-cited claim above that it prompts "in every mode" is superseded.* In a scratch repo (`mkdir /tmp/cur-ask && cd /tmp/cur-ask && git init`):
1. `mkdir .cursor && printf '#!/bin/bash\ncat >/dev/null\necho "{\\"permission\\":\\"ask\\",\\"user_message\\":\\"probe\\"}"\n' > .cursor/ask.sh && chmod +x .cursor/ask.sh`
2. `printf '{"version":1,"hooks":{"beforeShellExecution":[{"command":".cursor/ask.sh"}]}}' > .cursor/hooks.json`
3. `cursor-agent --yolo "run: echo hi > out.txt"` (interactive). Expected: an approval card containing `Hook requested approval: probe` even with `--yolo`; `out.txt` absent until you approve.
4. Repeat with `-p` (print mode). Record: prompt, silent run, or auto-reject.
5. Replace `"ask"` with `"allow"` and run without `--yolo`: expected the normal allowlist prompt still appears.

**S2. Cursor desktop 3.28.x (U1, desktop).** Same `.cursor/hooks.json`. In Agent chat, once per run mode (Auto-review default, Allowlist, Run Everything),
ask it to run `echo hi`. Record per mode whether the approval card appears. Then switch the hook to `preToolUse` with `matcher` `Shell` and `ask`; expected no prompt (docs say unenforced).

**S3. `/pr-dev` argument text (U2).** Add a `beforeSubmitPrompt` hook that runs `cat >> /tmp/cur-prompt.jsonl`. In desktop and CLI type `/pr-dev 42 --perms=bypass` (use a scratch skill
named `pr-dev` with a one-line body). Read the `prompt` field of the last line. Then ask the model "quote the last user message verbatim, and say whether `$ARGUMENTS` appears anywhere".

**S4. Plugin variables into hooks (U3).** Create a plugin with `.cursor-plugin/plugin.json` containing
`"variables":{"type":"object","properties":{"TS_PERMISSION_PRESET":{"type":"string"}}}` and a `sessionStart` hook running
`env | grep -i TS_ >> /tmp/cur-env.txt`. Install it, set the value in Dashboard -> Plugins -> Configure (note whether a non-team account may), start a new chat, `cat /tmp/cur-env.txt`.
Expected: empty. Also run once with `TS_PERMISSION_PRESET=strict cursor-agent ...` exported, to confirm the shell env passes through hooks.

Optional (not blocking): drive a Gemini interactive approval for a BeforeTool `ask` in a TTY, and an OpenCode TUI auto-accept toggle against the O1 setup, to turn two source-cited lines into measurements.

## Impact on ADR 004

Minimum versions are the versions exercised; none was tested below them.

| Platform | Hard-deny (L2) | Host ask (L3) | Unattended / auto behavior | Min version |
|----------|----------------|---------------|----------------------------|-------------|
| Cursor | `deny` from `beforeShellExecution` or `preToolUse` (both consumed). | `beforeShellExecution` `ask` is a real forced prompt on the CLI (source-cited), desktop unknown; `preToolUse` `ask` is **not** enforced. | Unknown for `-p`; treat as unattended = deny. | CLI 2026.10.22 (shell ask); desktop: unverified |
| Gemini | BeforeTool `deny`, and extension policy `deny` (extension `allow` is dropped). | Extension `ask_user` policy: holds under `--yolo`, turns into deny headless (**measured**). Hook `ask`: holds under `--yolo` interactively, **hangs headless**. | A hook that may run headless must never return `ask`. | 0.66.0 |
| OpenCode | Plugin hook `deny` (final, also under `--auto`); config `deny` also hides the tool. | `ctx.permission.assert` / hook `ask` prompts normally but **`--auto` approves it**. | `--auto` and TUI auto-accept erase any plugin `ask`. | 2.2.5 |

Decisions the spike supports:

1. **Cursor.** Use `beforeShellExecution` for shell-level `ask`/`deny` (CLI), keep `preToolUse` for `deny` only, and keep the in-skill confirmation gate
   as the desktop fallback until S2 is done. Do not use `allow` from a hook as a way to skip prompts: it has no effect.
2. **Gemini.** Ship statically-known R3/R4 actions as mode-less extension `ask_user`/`deny` rules (survive `--yolo`, deny headless).
   Use the BeforeTool hook for dynamic levels, but make it emit `deny` whenever the preset is `unattended`, because a headless `ask` blocks the run forever. Parse `--perms=`
   in `BeforeAgent` (interactive only; the argument text is all that arrives) and bind it to the skill via the preceding `activate_skill` `BeforeTool`; headless there is no skill command, so the override is plain prompt text.
3. **OpenCode.** An `ask` level cannot be enforced against `--auto`; express "ask before merge" as `deny` for the unattended case and as `assert` + config `ask` rule for interactive use.
   The plugin must not call `ctx.session.update` to widen permissions, and the ADR should state that a session rule can override a user's config deny (O2),
   so "plugin can only tighten" holds for the host contract only if no plugin uses that API. Presets cannot live in `ctx.storage` alone: it is a machine-local SQLite row, so the neutral
   policy file stays canonical and `storage` is at most a cache.
4. **Cross-platform.** "Headless ask" is three different things: Gemini hangs, OpenCode auto-rejects (or auto-approves with `--auto`), Cursor unknown. The ADR's rule "no human present -> ask becomes deny
   plus the setting that would allow it" must be implemented by the plugin itself on Gemini and OpenCode; the host will not do it.
5. **Config location.** U3 and O3 confirm there is no per-platform channel that reaches hooks on Cursor and no portable one on OpenCode: the neutral user-level file remains the only shared store.
