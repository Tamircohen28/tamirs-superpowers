# OpenAI Codex CLI extensibility surface (as of 2026-10-17, latest stable 0.163.0)

Scope note: `developers.openai.com/codex/*` now 308-redirects to `learn.chatgpt.com/docs/*`; both URL forms are given where known. The plugin *developer* guides stayed at `developers.openai.com/plugins/*`. The GitHub release pages print day-month only; the year 2026 is inferred from asset timestamps and the 0.163.0 X announcement. Release-note bullets below are paraphrased summaries (the fetch tool capped verbatim quotes); PR numbers are exact. Source-code findings are from `openai/codex` `main` (GitHub code-search index at commit `5009a99d`) and are marked **[source, undocumented]** — they were not verified against a live `codex` run.

Repo baseline for comparison: `.codex-version` pins `0.160.1`; `core/capabilities/platforms.json` records the hooks field validated against 0.146.0 and plugin-bundled hooks landing in openai/codex PR #19705 (2026-04-28). Neither 0.160.1 nor the 0.14x releases were re-fetched this pass (see Gaps).

## Key Question 1: What changed from 0.156.0 to 0.163.0, and what matters to a plugin author?

### Takeaway
Eight stable releases shipped in 23 days (0.156.0 on 22 Sep 2026 through 0.163.0 on 15 Oct 2026). None of them changed the plugin manifest, the hook event list, or the SKILL.md contract; the plugin-relevant changes are runtime behaviour (parallel read-only skill lookups, hook matcher precompilation, hook UI polish, plugin default-activation policy, worktree tools, `/mcp login`, subagent V2 fixes) and the retirement of `approval_policy = "untrusted"`.

### Cited Findings

**Release timeline (stable tags only)**
- `rust-v0.156.0` published 22 Sep; `rust-v0.157.0` 25 Sep; `rust-v0.158.0` 28 Sep; `rust-v0.159.0` 29 Sep; `rust-v0.160.0` 1 Oct; `rust-v0.161.0` 7 Oct; `rust-v0.162.0` 8 Oct; `rust-v0.162.1` 9 Oct; `rust-v0.163.0` 15 Oct (marked Latest); `0.164.0-alpha.1`/`alpha.2` 16 Oct with no notes — [Releases list](https://github.com/openai/codex/releases?q=rust-v0.16&expanded=true); per-tag pages linked below.
- 0.163.0 announced as stable on 15 Oct 2026 — [@CodexReleases](https://x.com/CodexReleases/status/2110847076934328501); [Release 0.163.0](https://github.com/openai/codex/releases/tag/rust-v0.163.0).

**0.156.0 (22 Sep)** — [Release page](https://github.com/openai/codex/releases/tag/rust-v0.156.0)
- New: `/tui` fullscreen mode (#46732, #46734, #46883, #46895); voice on by default with F8 toggle (#44921, #46071); `/usage` dashboard that includes plugin and skill activity (#45764, #45769); agents overview with status filtering and worktree session creation, worktrees on by default (#46839, #45276, #44870); `/daemon` updates the local background server, `--no-daemon` bypasses it (#45854, #46088).
- Plugins: thread-level plugin exclusions (#44655, #45755); disabled-plugin settings exposed in app-server API (#44905); plugin install requests limited to the root thread (#45806); onboarding skills shown in plugin details (#46544); plugin MCP/app extension APIs renamed (#46564); cloud plugin discovery at turn start via MCP extension (#46572).
- Hooks: command-start callback for tool lifecycle extensions (#46539); delivered messages survive post-tool hook failures (#47039).
- Skills: executor skills disable-able per environment (#46015); skill discovery routed through EnvironmentAccess (#46293).
- Subagents: `LocalAgentControl` rename and backend-independent contract (#46547, #46513); `spawn_agent` delegation guidance relaxed (#46264); subagents can request MCP elicitation (#46877); local agent message board with SQLite storage and collaboration tools (#46966–#47055); `ToolPolicy` decouples tool restrictions from session identity (#46999); startup tool allowlists (#45711).
- MCP: manual callback input for OAuth login (#44629); OAuth discovery recovers from 503 (#44636); enterprise MCP auth config (#44832, #45459); read-only policy on MCP tool requests (#46042).
- Config/AGENTS.md: ignored config settings now warn (#44691); paths rejected in `project_doc_fallback_filenames` (#45865); global instructions refreshed at model-request boundaries (#44675); thread-scoped instruction providers shared with subagents (#44701, #46577).
- Sandbox: standalone network proxy binary with JSON config (#46573); Windows offline sandbox blocks non-loopback inbound (#44639); macOS Seatbelt blocks mutating fcntls (#46500).

**0.157.0 (25 Sep)** — [Release page](https://github.com/openai/codex/releases/tag/rust-v0.157.0)
- New: GPT-6 Sol and Luna with Bedrock support (#47332, #47347); fullscreen transcript on by default (#47178); automatic background-server startup for eligible sessions (#47179, #47318); `f` forks a conversation into another app (#47185); `/import` in background-server sessions (#47317).
- Plugins: plugin recommendations moved into developer context (#47349); hosted plugin extensions in app-server summaries (#47263).
- Skills: host-supplied cloud skills refresh at turn start (#47074).
- Subagents: spawn routed through `SpawnRequest` (#47235); agent snapshots from `close_agent` (#47252).
- MCP: stdio-only Unix local servers (#47094); HTTP(S)-only OAuth endpoints (#47326); trace context across transports (#47212).
- Sandbox: opt-in Windows MXC sandbox (#47375); network policy enforced across HTTP/WebSocket/app-server (#47389, #47407–#47411).
- Hooks, worktrees, AGENTS.md: no entries.

**0.158.0 (28 Sep)** — [Release page](https://github.com/openai/codex/releases/tag/rust-v0.158.0)
- New: `codex mcp add --oauth-client-secret` for pre-registered OAuth clients (#47891); bearer-token auth for exec-server WebSocket (#47601, #47648); terminal-input approval on by default for elevated commands (#47799, #48073).
- Hooks: command hooks use native POSIX spawning (#47610); extension hooks for model requests and response streams (#47679); tool dispatch/timing exposed to extensions (#47662).
- Plugins: selected plugin identities separated from MCP contributions (#47939); plugin extension metadata removed from discovery (#48035); loaded plugins validated outside the cache lock (#47858).
- Subagents: option to disable multi-agent v2 direct messaging (#47540); in-memory message board for ephemeral sessions (#47946); pending inter-agent messages persisted to rollouts (#47691); spawn latency/failure metrics (#47984).
- MCP: configurable MCP and Code Mode input schema budgets (#47936); cached catalogs satisfy startup readiness (#47935).
- Config: key alias normalization before merging (#47903, #47904); project trust lookup APIs (#47620, #47924).
- Skills, worktrees, AGENTS.md: no entries.

**0.159.0 (29 Sep)** — [Release page](https://github.com/openai/codex/releases/tag/rust-v0.159.0)
- New: opt-in `instant_interrupt` lets new input steer Codex mid-response (#48135, #48141); app-server thread-history pagination from an item (#48151).
- Chores: removed the bundled `plugin-creator` skill (#48604); removed `tui.prompt_suggestions` (#48621).
- Skills: skill catalogs stabilized across executor availability changes (#48353).
- Sandbox: `.aws` protected by default under writable roots (#48176); approved commands keep explicit filesystem denials (#48155).
- Hooks, worktrees, AGENTS.md, subagents: no entries.

**0.160.0 (1 Oct)** — [Release page](https://github.com/openai/codex/releases/tag/rust-v0.160.0)
- New: sessions can start outside a project using workspace defaults (#49160); "Show more" pagination in the agent command center (#49106).
- Plugins: parsed plugin manifests cached, remote plugin HTTP connections reused (#49099, #49100).
- Skills: cloud/executor skill listings deduplicated before budgeting (#49127).
- Subagents: pending environments preserved when subagents spawn; config/preparation failures reported (#49075).
- Hooks, MCP, worktrees, AGENTS.md: no entries.

**0.161.0 (7 Oct)** — [Release page](https://github.com/openai/codex/releases/tag/rust-v0.161.0)
- New: GPT-6.1 Sol default model (#49318, #49339); `/mcp login <name>` in the TUI (#49290); Daybreak opt-in via `--enable cli_daybreak` / `features.cli_daybreak=true` (#49856–#49861, #51207); `codex exec --cyber-access-program` (#49939).
- Hooks: hook matchers compiled during discovery (#49379); MCP-hook argument expansion caches its placeholder regex (#49956).
- Skills: skill invocation events exported via OpenTelemetry (#49689); shadow skill ranking moved off turn preparation (#49812).
- Subagents: multi-agent V2 on Bedrock (#49345, #49369); remote agent message boards (#49267, #49686); opt-in model catalog in multi-agent context (#49560); parent notified when Guardian stops a subagent (#49312); coordinated agent-tree shutdown (#49814).
- MCP: enterprise MCP auth fails closed on config refresh (#49260, #49276); authorization servers validated before ID-JAG exchange (#49478).
- Config: managed requirements can disable Windows MXC (#49642); API-key model discovery on by default (#49807).
- Sandbox: approved filesystem escalation keeps denied reads and network restrictions (#49353, #49880).
- AGENTS.md: repository-local Codex guidance/skills/env config removed from the openai/codex repo itself (#49713) — housekeeping, not a behaviour change.
- Plugins, worktrees: no entries.

**0.162.0 (8 Oct)** — [Release page](https://github.com/openai/codex/releases/tag/rust-v0.162.0)
- New: **tools to create and list managed Git worktrees from trusted local projects, when the worktrees feature is on** (#50148); pin tasks with `p` in the command center (#51500); `/copy`, `Ctrl+Insert`, `tui.mouse_scroll_speed` (#50434, #50215, #50209); live web access and remote compaction for custom Responses-compatible providers (#50459); Code Mode opt-in ranked tool search (#51209).
- Hooks: ANSI styles render in hook `systemMessage` (#50359); hook `statusMessage` appears as the title in the hooks browser (#51433); URL destinations preserved in wrapped hook details (#51473).
- Plugins/skills: plugin and skill snapshots scoped per step (#50050); required environment skills enforced before inference (#51157); skill identity uses PathUri (#51482).
- Subagents: dynamic tool inheritance for fresh V2 subagents (#50082); resolved model and effort shown in sub-agent activity (#51463); spawn failure diagnostics (#51355); partial-history subagent forks removed (#51329).
- MCP: tool pagination in legacy protocol mode (#50035); startup notifications limited to owned threads (#50781); selected environments exposed to MCP contributors (#51503).
- Config: unknown TUI keys rejected in strict validation (#50525); live TUI settings survive failed reloads (#51510).
- Sandbox: CLI command to uninstall the legacy Windows sandbox (#50437); ripgrep config no longer weakens deny-glob masks (#51527).
- Cloud: native gRPC client for cloud thread resume/attach (#50113).
- AGENTS.md: no entries.

**0.162.1 (9 Oct)** — two fixes: TUI crash on multi-line async questions; startup failure from feature-setting mismatch between background server and CLI defaults — [Releases list](https://github.com/openai/codex/releases?q=rust-v0.16&expanded=true).

**0.163.0 (15 Oct)** — [Release page](https://github.com/openai/codex/releases/tag/rust-v0.163.0)
- New: `/config` panel searches settings, applies supported ones live, flags restart-needed ones (#52990, #53429); steering follow-ups mid-response is now default and interrupts stop Code Mode cells (#51812, #51835); `/keymap` leader key default Ctrl+X, voice mute F9 (#52273); `/daemon` restart (#53173); **independent read-only tools — including skill, memory and conversation-history lookups — run in parallel** (#52245); Daybreak on by default for eligible accounts, `codex exec` can select it with an API key (#53701, #53717).
- Plugins: plugin toggles work while searching (#52200); **configurable default plugin activation policy** (#52220); plugin mentions no longer suppress same-name skills (#51865).
- Hooks: hook configuration shared across cloned hook views (#53657).
- Subagents: idle multi-agent v2 children keep agent state (#52034); spawned children provisional until spawn returns (#53654); subagent capabilities preserved independently of forked history (#52241); opt-in subagent model-context default (#52659).
- MCP: `rmcp` upgraded to 3.5.1 (#52972); application network policy enforced in standalone MCP commands (#52215); verified sandbox launcher for local MCP servers (#52182); MCP sandbox policy separated from launcher metadata (#53709).
- Config: global app-server config independent of launch directory (#51872); configurable date/timezone in environment context (#52164).
- Sandbox: Windows MXC opt-out (#51547); sandbox integrity checks for bubblewrap/Seatbelt before commands and filesystem ops (#51840–#51843); Linux docs now explain bubblewrap + seccomp (#52610); the patched bundled `zsh` is gone, configs using retired shell flags get a migration notice (#52160, #52213).
- Worktrees, AGENTS.md: no entries.
- Independent summary of 0.163.0 (secondary source, consistent with the above): [gptmap](https://www.gptmap.org/en/posts/codex-0-163-release); [chatgptaihub](https://chatgptaihub.com/codex-cli-0-163-config-live-steering-daemon-restart-parallel-read-only-lookups).

**Docs-side changes in the window (app/platform changelog, not CLI-versioned)**
- 2026-09-05: "The `codex mcp-server` command and standalone `codex-mcp-server` binary have been removed"; use the app server instead; `codex mcp` client use continues — [Changelog](https://learn.chatgpt.com/docs/changelog).
- 2026-09-29 (app 26.928): improved terminal startup in attached worktrees — [Changelog](https://learn.chatgpt.com/docs/changelog).
- 2026-10-07 (app 26.1002): fixed worktree creation for WSL repositories — [Changelog](https://learn.chatgpt.com/docs/changelog).
- 2026-10-14: GPT-5.5 retired; update custom agents and scheduled tasks that select it — [Changelog](https://learn.chatgpt.com/docs/changelog).
- `approval_policy = "untrusted"` is retired and "can stop either client from starting" — [Sandbox & approvals](https://learn.chatgpt.com/docs/agent-approvals-security).

### Inferences
- For a plugin author the only *contract* changes in the window are (a) `untrusted` approval policy now fatal if a shipped `config.toml` sets it, and (b) retired shell flags producing a migration notice (0.163.0). Everything else is additive runtime behaviour.
- The 0.163.0 "configurable default plugin activation policy" (#52220) has no documented config key; a test named `maybe_persist_mcp_tool_approval_preserves_plugin_default_activation` exists in `codex-rs/core/src/mcp_tool_call_tests.rs` **[source, undocumented]** — [code search](https://github.com/openai/codex/blob/main/codex-rs/core/src/mcp_tool_call_tests.rs). The key name is not established.
- Hook-related entries in 0.161–0.163 (matcher precompilation, `statusMessage` as browser title, ANSI in `systemMessage`) indicate hooks are a maintained, UI-surfaced feature rather than a compat shim.

### Gaps
- 0.160.1 (the version this repo pins in `.codex-version`) was not on the fetched releases page and its tag page was not fetched; its contents are unknown.
- Release pages for 0.156.0 and 0.163.0 were truncated by the fetch tool (~100k chars); entries after the cut are missing.
- No "since version" is documented for hooks, plugins, subagents or skills on any docs page fetched; every docs page returned "no version numbers".

## Key Question 2: Does Codex support plugin hooks natively? Which events? In what file/format?

### Takeaway
Yes — hooks are a first-class, on-by-default Codex feature with 12 events, read from `hooks.json` (same JSON shape as Claude Code's), an inline `[hooks]` TOML table, or a plugin's `hooks/hooks.json`. Codex deliberately sets `CLAUDE_PLUGIN_ROOT`/`CLAUDE_PLUGIN_DATA` for compatibility, but its `HooksFile` parser is `#[serde(deny_unknown_fields)]`, so a top-level `modules` key (Claude Code mods) will fail to parse **[source]**.

### Cited Findings
- Event names: `SessionStart`, `SessionEnd`, `SubagentStart`, `UserPromptSubmit`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, `PreCompact`, `PostCompact`, `SubagentStop`, `Stop`, `Interrupt` — [Hooks](https://learn.chatgpt.com/docs/hooks) (redirect of `developers.openai.com/codex/hooks`).
- File locations: `~/.codex/hooks.json`, `~/.codex/config.toml`, `<repo>/.codex/hooks.json`, `<repo>/.codex/config.toml`; TOML form is `[[hooks.EventName]]` then `[[hooks.EventName.hooks]]`; project hooks load only when the project `.codex/` layer is trusted — [Hooks](https://learn.chatgpt.com/docs/hooks).
- Handler fields: `type` (`command` or `mcp_tool`), `command`, `commandWindows`, `timeout` (seconds, default `600`; `SessionEnd`/`Interrupt` default `1`, max `3`), `statusMessage`, `async`, `additionalContextLimit`; `mcp_tool` handlers take `server`, `tool`, `input` and are not supported for `SessionEnd` — [Hooks](https://learn.chatgpt.com/docs/hooks).
- Config reference adds: handlers of type `prompt` and `agent` are "skipped"; `additionalContextLimit` default 2500 with `0` meaning pass full context; `async` default `false` and `SessionEnd` always synchronous; `commandWindows` alias `command_windows` — [Config reference](https://learn.chatgpt.com/docs/config-file/config-reference).
- **[source]** `HooksFile` is `#[serde(deny_unknown_fields)]` with exactly two fields: `description: Option<String>` and `hooks: HookEventsToml`; `HookHandlerConfig` is `#[serde(tag = "type")]` with variants `Command`, `McpTool`, `Prompt` (empty), `Agent` (empty); `MatcherGroup { matcher: Option<String>, hooks: Vec<HookHandlerConfig> }`; the only alias is `command_windows` — [hook_config.rs](https://raw.githubusercontent.com/openai/codex/main/codex-rs/config/src/hook_config.rs).
- Stdin payload common fields: `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `model`; Codex extension `turn_id`; several events carry `permission_mode` (`default`, `acceptEdits`, `plan`, `dontAsk`, `bypassPermissions`); event-specific: `SessionStart.source`, `SessionEnd.reason` (always `other`), `SubagentStart/Stop.agent_id`+`agent_type`, `SubagentStop.agent_transcript_path`/`stop_hook_active`/`last_assistant_message`, `PreToolUse`/`PermissionRequest`/`PostToolUse.tool_name`+`tool_input` (`PostToolUse` adds `tool_use_id`, `tool_response`), `PreCompact/PostCompact.trigger` (`manual`/`auto`), `UserPromptSubmit.prompt`, `Stop.stop_hook_active`+`last_assistant_message` — [Hooks](https://learn.chatgpt.com/docs/hooks).
- Exit codes: `0` continues; `2` blocks with reason read from stderr, supported for `PreToolUse`, `UserPromptSubmit`, `PostToolUse` (feedback), `Stop`, `SubagentStop` (continuation); `Stop` and `SubagentStop` must print JSON on exit 0, plain text is invalid; `Interrupt` cannot prevent the interruption — [Hooks](https://learn.chatgpt.com/docs/hooks).
- Output JSON: `continue`, `stopReason`, `systemMessage` (shown as a warning), `suppressOutput` (parsed, not implemented); `hookSpecificOutput` requires `hookEventName` and may carry `additionalContext`, `permissionDecision`, `permissionDecisionReason`, `updatedInput`, `decision`; `additionalContext` default limit ~2500 tokens, oversize spilled to disk with a preview; plain stdout is developer context for `SessionStart`, `SubagentStart`, `UserPromptSubmit` and ignored for `PreToolUse`/`PermissionRequest`/`PostToolUse`/`PreCompact`/`PostCompact` — [Hooks](https://learn.chatgpt.com/docs/hooks).
- `PreToolUse`: `permissionDecision: "deny"` blocks; legacy `decision: "block"` also works; `"allow"` + `updatedInput` rewrites the call (Bash/`apply_patch` need a string `command`); `"ask"`, `continue: false`, `stopReason` are unsupported and fail the hook — [Hooks](https://learn.chatgpt.com/docs/hooks).
- Matchers are regex; `"*"`, `""` or omitted match all; honoured for `PreToolUse`/`PostToolUse`/`PermissionRequest` (tool name; **`apply_patch` also matches `Edit` and `Write`**), `SessionStart` (`startup`, `resume`, `clear`, `compact`, `fork`), `SessionEnd` (`other`), `PreCompact`/`PostCompact`, `SubagentStart/Stop` (`agent_type`); ignored for `UserPromptSubmit`, `Stop`, `Interrupt`; hosted tools such as `WebSearch` are not covered — [Hooks](https://learn.chatgpt.com/docs/hooks).
- Feature flag: hooks enabled by default; disable with `[features] hooks = false`; `codex_hooks` is a deprecated alias; admins can force-disable via `requirements.toml` — [Hooks](https://learn.chatgpt.com/docs/hooks); `features.codex_hooks` listed as deprecated alias — [Config reference](https://learn.chatgpt.com/docs/config-file/config-reference).
- Trust: non-managed hooks (user, project, plugin) require review in `/hooks`; trust is tied to a hash; `--dangerously-bypass-hook-trust` skips per invocation; "Enabling a plugin does not trust its hooks"; `async: true` hooks run in background, up to 8 per session, cannot block or rewrite — [Hooks](https://learn.chatgpt.com/docs/hooks).
- Managed hooks: `requirements.toml` `[hooks]` with `managed_dir` (macOS/Linux) or `windows_managed_dir`; `allow_managed_hooks_only = true` "skips user, project, session, and plugin hooks" — [Hooks](https://learn.chatgpt.com/docs/hooks); [Config reference](https://learn.chatgpt.com/docs/config-file/config-reference).
- Plugin-bundled hooks: default path `hooks/hooks.json` in the plugin root; manifest `hooks` entry in `.codex-plugin/plugin.json` can be a `./`-prefixed path, array of paths, inline object, or array of inline objects; paths must stay inside the plugin root — [Hooks](https://learn.chatgpt.com/docs/hooks); setting `hooks` "replaces default discovery rather than adding to it" — [Build plugins](https://developers.openai.com/plugins/build/plugins).
- Env vars for plugin hooks: `PLUGIN_ROOT`, `PLUGIN_DATA` (Codex-specific); `CLAUDE_PLUGIN_ROOT` and `CLAUDE_PLUGIN_DATA` "for compatibility with existing plugin hooks"; `CODEX_PLUGIN_ROOT` is not mentioned — [Hooks](https://learn.chatgpt.com/docs/hooks); [Build plugins](https://developers.openai.com/plugins/build/plugins).
- Plugins with hooks are "Supported for manually installed Codex desktop plugins only. Plugins with hooks aren't eligible for the public directory." and "Hook scripts must exist in the execution environment. Installing on the web doesn't deploy them." — [Build plugins](https://developers.openai.com/plugins/build/plugins); plugins overview says the Codex IDE extension "doesn't support plugins" — [Plugins](https://learn.chatgpt.com/docs/plugins).
- A `modules` key is not mentioned on any docs page — [Hooks](https://learn.chatgpt.com/docs/hooks); [Config reference](https://learn.chatgpt.com/docs/config-file/config-reference).

### Inferences
- **Direct consequence for this repo:** `hooks/hooks.json` carrying a top-level `modules` key will be rejected by `HooksFile`'s `deny_unknown_fields` when Codex loads it via `.codex-plugin/plugin.json` `hooks`. The repo's `platforms.json` fallback ("point `.codex-plugin/plugin.json` `hooks` at a generated copy without `modules`") is the correct remedy; this pass turns "UNVERIFIED" into "source-confirmed rejection" (still not run live). Whether the failure is a hard error or a logged warning that drops all hooks is not established — either way the hooks would not load.
- Of this repo's 12 wired events, Codex fires `SessionStart`, `SessionEnd`, `PreToolUse`, `PostToolUse`, `Stop`, `SubagentStop`, `UserPromptSubmit`; it has no `StopFailure`, `Notification`, `DirectoryAdded`, `WorktreeCreate`, `WorktreeRemove`. Codex additionally offers `PermissionRequest`, `PreCompact`, `PostCompact`, `SubagentStart`, `Interrupt`.
- `apply_patch` matching `Edit`/`Write` is what lets this repo's `enforce-worktree-edits.sh` matcher keep working unmodified on Codex.

### Gaps
- No doc or release note states the Codex version in which hooks, `PermissionRequest`, `Interrupt` or `mcp_tool` handlers arrived; the docs explicitly say linked `main`-branch schemas "may include fields not in the current release".
- Whether an invalid `hooks.json` aborts plugin load entirely or only the hooks component is not documented and was not tested.

## Key Question 3: Does Codex support subagents, parallel agents, or agent teams? How are they defined?

### Takeaway
Yes: subagent workflows are on by default, custom agents are standalone TOML files in `~/.codex/agents/` or `.codex/agents/`, orchestration is model-driven (not user-scripted), and there is still no plugin-manifest path to ship an agent. There is no "agent teams" product; the closest is the multi-agent V2 message board.

### Cited Findings
- "Current Codex releases enable subagent workflows by default." Activity appears in the ChatGPT desktop app, Codex CLI and IDE extension — [Subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents).
- Custom agent files: `~/.codex/agents/` (personal) and `.codex/agents/` (project); each a standalone TOML defining one agent; required `name`, `description`, `developer_instructions`; optional `model`, `model_reasoning_effort`, `model_reasoning_summary`, `model_verbosity`; may reduce capabilities with `features.shell_tool`, `features.apps`, `features.plugins`, `features.memories`, `features.request_permissions_tool` (set `false`), `skills.config`, `skills.bundled.enabled`, `skills.include_instructions`; cannot override `sandbox_mode`, `approval_policy`, `model_provider`, `mcp_servers`; the `name` field, not the filename, is authoritative; built-ins `default`, `worker`, `explorer` can be shadowed by a custom agent of the same name — [Subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents).
- `[agents]` keys: `agents.enabled` (default `true`), `agents.max_concurrent_threads_per_session`, `agents.max_threads` (legacy alias), `agents.default_subagent_model`, `agents.default_subagent_reasoning_effort`, `agents.interrupt_message` (default `true`), plus `agents.<name>.config_file` and `agents.<name>.description` — [Subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents); [Config reference](https://learn.chatgpt.com/docs/config-file/config-reference).
- `features.multi_agent`: boolean, "Stable; on by default" — [Config reference](https://learn.chatgpt.com/docs/config-file/config-reference).
- Orchestration: spawning, routing follow-ups, waiting and closing threads "are handled by ChatGPT or Codex"; Codex waits for all results then returns one consolidated response; `/subagents` lists and switches threads; parallel agents recommended for read-heavy work; subagents inherit the parent's sandbox and approval settings — [Subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents).
- Tool names visible in release notes: `spawn_agent` (#46264, 0.156.0) and `close_agent` (#47252, 0.157.0) — [0.156.0](https://github.com/openai/codex/releases/tag/rust-v0.156.0); [0.157.0](https://github.com/openai/codex/releases/tag/rust-v0.157.0).
- Multi-agent V2 message board: local SQLite board with collaboration tools (0.156.0, #46966–#47055); option to disable V2 direct messaging (0.158.0, #47540); remote boards (0.161.0, #49267) — release pages above.
- Hook events `SubagentStart`/`SubagentStop` carry `agent_id`, `agent_type` and match on `agent_type` — [Hooks](https://learn.chatgpt.com/docs/hooks).
- The plugin manifest parser accepts `name`, `version`, `description`, `keywords`, `skills`, `mcpServers`, `apps`, `hooks`, `interface`, `extensions` (and `commands` via a separate struct); no `agents` field **[source]** — [core-plugins/manifest.rs](https://raw.githubusercontent.com/openai/codex/main/codex-rs/core-plugins/src/manifest.rs). The docs likewise never list agents as a plugin component — [Plugins](https://learn.chatgpt.com/docs/plugins).

### Inferences
- Nothing in 0.156–0.163 changes the repo's existing conclusion (platforms.json, citing openai/codex#28491 → #18988) that bundling an agent in a plugin remains an open request; the manifest parser still has no field for it.
- Codex has no equivalent to Claude Code's explicit `Agent` tool with a caller-chosen agent definition and model pin per spawn from a plugin; the nearest control is `agents.default_subagent_model` plus per-agent TOML `model`.

### Gaps
- The exact spawn/wait/send tool names beyond `spawn_agent`/`close_agent`, and `max_depth`, are not documented on the subagents page.
- Whether `.codex/agents/` is honoured in the CLI only for trusted projects is implied by the general `.codex/` trust rule but not stated on the subagents page.
- Not established whether #28491/#18988 were closed or changed in the window (not re-fetched).

## Key Question 4: Does Codex support skills with frontmatter? Which fields?

### Takeaway
Codex reads only `name`, `description` and `metadata.short-description` from SKILL.md frontmatter and silently ignores every other key **[source]**; `allowed-tools`, `user-invocable` and `disable-model-invocation` have no effect. Invocation policy and UI metadata live in a sibling `agents/openai.yaml` instead.

### Cited Findings
- "The `SKILL.md` file must include `name` and `description`"; a skill directory may contain `scripts/`, `references/`, `assets/` and optional `agents/openai.yaml`; Codex loads name/description first and the full body only on selection; skills with the same `name` are not merged — [Build skills](https://learn.chatgpt.com/docs/build-skills) (redirect of `developers.openai.com/codex/skills`).
- **[source]** `SkillFrontmatter { name: Option<String>, description: Option<String>, metadata: SkillFrontmatterMetadata }`, `SkillFrontmatterMetadata { short_description }` with `rename = "short-description"`; `deny_unknown_fields` is not set, "so unknown keys are ignored"; `name` capped at 64 chars (`MAX_NAME_LEN`) with no charset check, `description` empty → `MissingField("description")`, no length limit; lenient YAML repair quotes unquoted scalars — [skills/parser.rs](https://raw.githubusercontent.com/openai/codex/main/codex-rs/skills/src/parser.rs).
- The bundled `skill-creator`'s `quick_validate.py` accepts only `name`, `description`, `license`, `allowed-tools`, `metadata`; `name` must match `^[a-z0-9-]+$`, no leading/trailing/double hyphen, ≤64 chars; `description` ≤1024 chars, no `<`/`>` — [quick_validate.py](https://raw.githubusercontent.com/openai/codex/main/codex-rs/skills/src/assets/samples/skill-creator/scripts/quick_validate.py). (This is the Agent Skills spec's allow-list, which the validator enforces even though the runtime ignores `allowed-tools`.)
- Discovery paths: REPO `$CWD/.agents/skills`, `$CWD/../.agents/skills` up to `$REPO_ROOT/.agents/skills`; USER `$HOME/.agents/skills`; ADMIN `/etc/codex/skills`; SYSTEM bundled (e.g. `skill-creator`, `plan`); symlinked skill folders are followed — [Build skills](https://learn.chatgpt.com/docs/build-skills).
- Invocation: `/skills` or `$skill-name` in CLI/IDE, `@` in ChatGPT; implicit selection by description match — [Build skills](https://learn.chatgpt.com/docs/build-skills); [Skills & plugins](https://learn.chatgpt.com/docs/skills-and-plugins).
- `agents/openai.yaml`: `interface` (`display_name`, `short_description`, `icon_small`, `icon_large`, `brand_color`, `default_prompt`); `policy.allow_implicit_invocation` (default `true`; when `false`, explicit `$skill` still works); `dependencies.tools[]` with `type`, `value`, `description`, `transport`, `url` — [Build skills](https://learn.chatgpt.com/docs/build-skills).
- Config: `[[skills.config]]` with `path` and `enabled = false`; `skills.max_context_tokens` (default 2% of context window or 8000 chars if unknown; explicit values cap at 10000) — [Build skills](https://learn.chatgpt.com/docs/build-skills); [Config reference](https://learn.chatgpt.com/docs/config-file/config-reference).
- Plugin manifest `skills` accepts a single string or an array of strings; invalid values warn and yield an empty list **[source]** — [core-plugins/manifest.rs](https://raw.githubusercontent.com/openai/codex/main/codex-rs/core-plugins/src/manifest.rs).
- Marketplace entries may flag `requires_local_executor` for skills-only plugins needing desktop execution; for a legacy `.codex-plugin/plugin.json` it goes at top level — [Desktop-only](https://developers.openai.com/plugins/deploy/desktop-only).
- The bundled `plugin-creator` skill was removed in 0.159.0 (#48604) — [0.159.0](https://github.com/openai/codex/releases/tag/rust-v0.159.0); the Build-plugins guide still references `$plugin-creator` — [Build plugins](https://developers.openai.com/plugins/build/plugins) (conflict: docs vs release notes).
- 0.163.0: read-only skill lookups run in parallel (#52245); plugin mentions no longer suppress same-name skills (#51865) — [0.163.0](https://github.com/openai/codex/releases/tag/rust-v0.163.0).

### Inferences
- Codex's equivalent of Claude's `disable-model-invocation: true` is `agents/openai.yaml` `policy.allow_implicit_invocation: false`; there is no equivalent of `user-invocable: false` (hiding from `$`/`/skills`) or of `allowed-tools`/`effort`/`context: fork`/`model` frontmatter.
- `name` is not required to match the directory name by either the runtime or the validator.
- `.agents/skills` (the Agent Skills spec path) is the documented repo path; `.codex/skills` is not documented as a discovery path.

### Gaps
- `SkillMetadata` struct and whether `agents/openai.yaml` is parsed in the CLI (vs only the desktop app) were not found in the files fetched.
- No `features.skills`-style toggle was found; `skills.bundled.enabled` is named only in the subagents page.

## Key Question 5: How are MCP servers declared for a plugin, and does Codex support stdio/HTTP/OAuth?

### Takeaway
User-level MCP is `[mcp_servers.<name>]` in `config.toml` with full stdio and streamable-HTTP support plus OAuth (DCR and CIMD) via `codex mcp login`; plugin-level MCP is the manifest `mcpServers` field (a `./` path such as `./.mcp.json`, or an inline object), with per-user overrides under `plugins.<plugin>.mcp_servers.<server>`. `.mcp.json` is read only as a plugin's declared file, not as a project-root convention.

### Cited Findings
- Locations: `~/.codex/config.toml` or project `.codex/config.toml` (trusted only); each server is `[mcp_servers.<server-name>]` — [MCP](https://learn.chatgpt.com/docs/extend/mcp?surface=cli).
- STDIO keys: `command` (required), `args`, `env`, `env_vars` (names or `{source = "local"|"remote"}`), `cwd`, `experimental_environment = "remote"` — [MCP](https://learn.chatgpt.com/docs/extend/mcp?surface=cli).
- HTTP keys: `url` (required), `auth` (`oauth` default or `chatgpt`), `bearer_token_env_var`, `http_headers`, `env_http_headers`, `http_headers_helper` (local only) — [MCP](https://learn.chatgpt.com/docs/extend/mcp?surface=cli).
- Shared: `startup_timeout_sec` (10), `tool_timeout_sec` (60), `enabled`, `required`, `enabled_tools`, `disabled_tools` (applied after allow list), `default_tools_approval_mode` (`auto`|`prompt`|`writes`|`approve`), `tools.<tool>.approval_mode`, `tools.<tool>.output_token_limit`, `oauth` table (`client_id`, `callback_url`, `callback_port`, `client_secret` via `--oauth-client-secret`), top-level `mcp_optional_startup_grace_ms` (1000), `mcp_oauth_callback_url`, `mcp_oauth_callback_port` — [MCP](https://learn.chatgpt.com/docs/extend/mcp?surface=cli).
- OAuth: `codex mcp login <server-name>`, `--oauth-client-registration cimd|dcr|auto`; DCR and CIMD supported; configured client ID skips registration — [MCP](https://learn.chatgpt.com/docs/extend/mcp?surface=cli); `/mcp login <name>` in-TUI since 0.161.0 (#49290) — [0.161.0](https://github.com/openai/codex/releases/tag/rust-v0.161.0); `codex mcp add --oauth-client-secret` since 0.158.0 (#47891) — [0.158.0](https://github.com/openai/codex/releases/tag/rust-v0.158.0).
- CLI: `codex mcp add <name> [--env --url --oauth-client-id --oauth-client-secret] -- <command>`, `codex mcp list`, `codex mcp login` — [MCP](https://learn.chatgpt.com/docs/extend/mcp?surface=cli).
- `.mcp.json`: "The page doesn't say Codex reads `.mcp.json` in general"; plugin-provided HTTP servers may declare OAuth there with camelCase `clientId`, `callbackUrl`, `callbackPort` — [MCP](https://learn.chatgpt.com/docs/extend/mcp?surface=cli).
- Plugin servers: declared in the manifest and launched from the plugin; user overrides `plugins.<plugin>.mcp_servers.<server>.enabled|default_tools_approval_mode|enabled_tools|disabled_tools|tools.<tool>.approval_mode` — [MCP](https://learn.chatgpt.com/docs/extend/mcp?surface=cli); [Config reference](https://learn.chatgpt.com/docs/config-file/config-reference).
- Portable format: root `mcp.json` with `$schema` `https://agent-plugins.org/schemas/1.0.0/mcp.schema.json`, entries under `mcpServers` with `type` (e.g. `streamable-http`, `stdio`) and `url`/`command`/`args`/`cwd`; auth under `extensions["com.openai"].auth` with `type` `none|oauth|mixed|api_key`, `client.mode` `provided|dcr|cimd`, `clientId`, `tokenEndpointAuthMethod`, OAuth endpoint fields; `api_key` with `headerScheme` `bearer|basic|custom_header`; no `clientSecret` field in the manifest — [Build plugins](https://developers.openai.com/plugins/build/plugins); stdio example uses `"args": ["${PLUGIN_ROOT}/server/dist/index.js"]`, `${PLUGIN_ROOT}` is a built-in placeholder — [Desktop-only](https://developers.openai.com/plugins/deploy/desktop-only).
- **[source]** manifest `mcpServers` accepts a string path or an inline object (serialized to a JSON string); a test fixture uses `{"mcpServers": {"demo": {"command": "demo-mcp", "environment_id": "local"}}}` — [core-plugins/manifest.rs](https://raw.githubusercontent.com/openai/codex/main/codex-rs/core-plugins/src/manifest.rs); [provider_tests.rs](https://github.com/openai/codex/blob/main/codex-rs/ext/mcp/src/plugin/provider_tests.rs).
- Enterprise: "Plugins that declare MCP servers in `mcp.json` or `.mcp.json` are marked Desktop only and work only in the ChatGPT desktop app" — [Plugin management](https://learn.chatgpt.com/docs/enterprise/plugin-management).
- Codex-as-MCP-server (`codex mcp-server`) removed 2026-09-05 — [Changelog](https://learn.chatgpt.com/docs/changelog).
- 0.163.0: verified sandbox launcher for local MCP servers (#52182); network policy in standalone MCP commands (#52215) — [0.163.0](https://github.com/openai/codex/releases/tag/rust-v0.163.0).

### Inferences
- This repo's `.codex-plugin/plugin.json` `"mcpServers": "./.mcp.json"` is the documented compatibility form; the server's `${user_config.github_token}` interpolation is a Claude Code `userConfig` mechanism with no Codex counterpart, so on Codex the env value would be the literal string unless Codex expands it (not established — see Q6).
- `environment_id` in the inline MCP fixture is an undocumented per-server key (likely `local`/`remote` placement).

### Gaps
- `scopes`, `oauth_resource`, `codex mcp get|remove` not on the MCP page.
- Whether Codex expands `${user_config.*}` or any `${...}` other than `${PLUGIN_ROOT}` inside a plugin's `.mcp.json` is not documented.

## Key Question 6: What does Codex NOT support that Claude Code does?

### Takeaway
No mods/function hooks, no `modules` key (actively rejected), no `statusLine`/output styles/`userConfig`/`settings` in the manifest, no worktree/notification/directory hook events, no plugin-shipped agents, and no skill-frontmatter gating. Codex compensates with its own TUI `tui.status_line`, `agents/openai.yaml`, and `requirements.toml`.

### Cited Findings
- Manifest fields Codex parses: `name`, `version`, `description`, `keywords`, `skills`, `mcpServers`, `apps`, `hooks`, `interface`, `extensions`, plus `commands` via `RawPluginCommandManifest`; `author`, `homepage`, `repository`, `license`, `settings`, `userConfig`, `statusLine`, `agents` "are not accepted by the code shown" and unknown keys are ignored (no `deny_unknown_fields`) **[source]** — [core-plugins/manifest.rs](https://raw.githubusercontent.com/openai/codex/main/codex-rs/core-plugins/src/manifest.rs). Docs list `author`/`homepage`/`repository`/`license` as portable identity fields of the root `plugin.json` — [Build plugins](https://developers.openai.com/plugins/build/plugins).
- `HooksFile` rejects unknown top-level keys (`deny_unknown_fields`); no `modules` field **[source]** — [hook_config.rs](https://raw.githubusercontent.com/openai/codex/main/codex-rs/config/src/hook_config.rs).
- Hook handler types `prompt` and `agent` are parsed but "skipped" — [Config reference](https://learn.chatgpt.com/docs/config-file/config-reference).
- No `Notification`, `DirectoryAdded`, `WorktreeCreate`, `WorktreeRemove`, `StopFailure`, `PreModelSwitch` events in the 12-event list — [Hooks](https://learn.chatgpt.com/docs/hooks).
- Status line is user config, not plugin-shippable: `tui.status_line` (array of ordered footer items or `null`) — [Config reference](https://learn.chatgpt.com/docs/config-file/config-reference).
- Output styles: no equivalent key found anywhere in the config reference; personality `friendly`/`pragmatic` settings deprecated in 0.156.0 (#45809) — [0.156.0](https://github.com/openai/codex/releases/tag/rust-v0.156.0).
- Custom prompts (`~/.codex/prompts/*.md`, `/prompts:name`, `$1..$9`, `$ARGUMENTS`, named `$KEY` placeholders, frontmatter `description` and `argument-hint`) are "deprecated. Use skills"; they are local-only and "not shared through your repository" — [Custom prompts](https://learn.chatgpt.com/docs/custom-prompts).
- Worktrees: app-managed under `$CODEX_HOME/worktrees`, `.worktreeinclude` copies ignored files, keeps 15 most recent by default, no hook on creation, no documented `config.toml` key — [Worktrees](https://learn.chatgpt.com/docs/environments/git-worktrees); CLI gained worktree create/list tools in 0.162.0 (#50148) "when the worktrees feature is on" — [0.162.0](https://github.com/openai/codex/releases/tag/rust-v0.162.0).
- Credentials: "The manifest has no `clientSecret` field. Supply secrets through the connection setup flow and keep them out of the package." — [Build plugins](https://developers.openai.com/plugins/build/plugins).
- `features.hooks`, `features.multi_agent`, `features.apps`, `features.shell_tool`, `features.remote_plugin`, `features.unified_exec` stable/on; `features.memories` off; `features.code_mode.enabled`, `features.network_proxy`, `features.prevent_idle_sleep`, `features.rollout_budget.enabled` experimental/off — [Config reference](https://learn.chatgpt.com/docs/config-file/config-reference).
- Codex IDE extension "doesn't support plugins" — [Plugins](https://learn.chatgpt.com/docs/plugins).
- Codex app/desktop: can "Import setup and recent work from Claude Code, Claude Cowork, and Cursor, including instructions, settings, skills, and plugins" (2026-08-11) — [Changelog](https://learn.chatgpt.com/docs/changelog); an `external-agent-migration` crate reads plugin manifests from Claude-style version roots **[source]** — [connectors_cur.rs](https://github.com/openai/codex/blob/main/codex-rs/external-agent-migration/src/detect/sessions/connectors_cur.rs).

### Inferences
- `${CLAUDE_PLUGIN_ROOT}` in hook commands works on Codex because the env var is exported, but `${CLAUDE_PLUGIN_DATA}` resolution via `hooks/lib/plugin-state.sh`'s fallback is now unnecessary on Codex (Codex sets both); the fallback remains correct for other hosts.
- The `commands` manifest field is a new, undocumented plugin component **[source]**; it contradicts the repo's 0.156-era survey ("0 declare a commands manifest field") only in that the parser now has a slot — no doc, format or shipped example was found.

### Gaps
- `RawPluginCommandManifest`'s shape (file path, fields) was not fetched.
- Whether Codex ignores or warns on Claude-specific manifest keys (`settings`, `userConfig`) is inferred from the absence of `deny_unknown_fields`; not run live.

## Key Question 7: Is there a Codex plugin registry/marketplace, and what are its submission rules?

### Takeaway
There are two routes: (1) the public OpenAI Plugin Directory shared by ChatGPT and Codex, submitted as a ZIP through platform.openai.com/plugins with automated scans, identity verification and policy attestations — which currently refuses packages with hooks or `.app.json`; and (2) self-hosted marketplaces (`.agents/plugins/marketplace.json` in a Git repo or local root, `codex plugin marketplace add`), which is the only route for hooks and local stdio MCP.

### Cited Findings
- "ChatGPT and Codex share one universal plugin directory" — [Skills & plugins](https://learn.chatgpt.com/docs/skills-and-plugins).
- Submission: Plugins dashboard at `platform.openai.com/plugins`, "Upload new or existing plugin" ZIP; remote MCP needs a stable public HTTPS endpoint; org owners or members with "Apps Management Write"; individual/business verification required; one active review per plugin — [Submission](https://developers.openai.com/plugins/deploy/submission).
- Review: automated checks on metadata, skills and MCP tools; required skill scans; MCP domain verification token at `/.well-known/openai-apps-challenge`; five positive and three negative test cases, video walkthrough, release notes, reviewer credentials; policy attestations; feedback by email; no fixed timeline — [Submission](https://developers.openai.com/plugins/deploy/submission).
- Required fields: `name`, `displayName`, `shortDescription`, `longDescription`, `developerName`, `category`; Codex format also `version`, `description`, `author.name`, `capabilities`, `composerIcon`, `logo`; MCP review also `websiteURL`, `supportURL`, `privacyPolicyURL`, `termsOfServiceURL` (HTTPS, no credentials); icons square ≥48×48 ≤5 MiB; `displayName`/`shortDescription` ≤30 chars, `longDescription` ≤4000 — [Submission](https://developers.openai.com/plugins/deploy/submission).
- Blocked: "ZIP packages with app references (`apps` / `.app.json`) or lifecycle hooks cannot currently be submitted"; nonempty server `headers` rejected; manifest rejects `clientSecret`, `test_credentials`, `reviewer_instructions`; only one MCP server connected per plugin; adding MCP to a skills-only plugin unsupported; URL changes require support — [Submission](https://developers.openai.com/plugins/deploy/submission).
- Desktop-only path: local stdio MCP "limited to approved partners"; organization must be allowlisted by an OpenAI representative; skills-only desktop plugins set `"requires_local_executor": true`; shows a "Desktop only" badge; installable only from the ChatGPT desktop app — [Desktop-only](https://developers.openai.com/plugins/deploy/desktop-only).
- Self-hosted marketplaces: `$REPO_ROOT/.agents/plugins/marketplace.json`, legacy `$REPO_ROOT/.claude-plugin/marketplace.json`, personal `~/.agents/plugins/marketplace.json`; fields `name`, `interface.displayName`, `plugins[]` with `name`, `source` (`local`|`url`|`git-subdir`|`npm` plus `path`/`url`/`ref`/`sha`/`package`/`version`/`registry`), `policy.installation` (`AVAILABLE`|`INSTALLED_BY_DEFAULT`|`NOT_AVAILABLE`), `policy.authentication` (e.g. `ON_INSTALL`), required `category`; `source.path` relative, `./`-prefixed, inside root; unresolvable entries skipped; npm sources run no lifecycle scripts — [Build plugins](https://developers.openai.com/plugins/build/plugins).
- Install mechanics: cache `~/.codex/plugins/cache/$MARKETPLACE_NAME/$PLUGIN_NAME/$VERSION/` (`local` for local plugins); enable with `[plugins."my-plugin@local-repo"] enabled = true` in `.codex/config.toml` (trusted projects) or `~/.codex/config.toml`; `codex plugin marketplace add|list|upgrade|remove` with `owner/repo[@ref]`, Git URLs or local roots, flags `--ref`, `--sparse PATH`; "Bump `version` and refresh the marketplace after changes" — [Build plugins](https://developers.openai.com/plugins/build/plugins). Config keys `marketplaces.<name>.source|source_type (git|local)|ref|sparse_paths` — [Config reference](https://learn.chatgpt.com/docs/config-file/config-reference).
- In-CLI browser: "In Codex CLI, you use `/plugins`"; "Install a plugin from a configured marketplace, then start a new session before using its bundled skills or tools" — [Plugins](https://learn.chatgpt.com/docs/plugins).
- Enterprise: admins import a marketplace from a GitHub repo containing `.agents/plugins/marketplace.json` or `.claude-plugin/marketplace.json`; daily syncs; `pluginId` moves uploaded plugins to GitHub management; workspace publishing admin-only, disable with `features.plugin_sharing = false` in `requirements.toml` — [Plugin management](https://learn.chatgpt.com/docs/enterprise/plugin-management); [Build plugins](https://developers.openai.com/plugins/build/plugins).
- Portable format: root `plugin.json` with `$schema` `https://agent-plugins.org/schemas/1.0.0/plugin.schema.json`, OpenAI settings under `extensions.com.openai` (`apps`, `hooks`, `onboardingSkill`, `interface`); "If `extensions.com.openai` is present, it replaces the `.codex-plugin/plugin.json` overlay entirely"; `.codex-plugin/plugin.json` "remains supported as a fallback" — [Build plugins](https://developers.openai.com/plugins/build/plugins). Tests also accept `.claude-plugin/plugin.json` as an alternate manifest path **[source]** — [core-plugins/manifest.rs](https://raw.githubusercontent.com/openai/codex/main/codex-rs/core-plugins/src/manifest.rs).
- Example public plugins: [Figma](https://github.com/openai/plugins/tree/main/plugins/figma), [Notion](https://github.com/openai/plugins/tree/main/plugins/notion), [Build web apps](https://github.com/openai/plugins/tree/main/plugins/build-web-apps) — [Build plugins](https://developers.openai.com/plugins/build/plugins).

### Inferences
- This repo (hooks + stdio MCP) is ineligible for the public directory on two independent grounds and must distribute via a self-hosted marketplace (`codex plugin marketplace add Tamircohen28/tamirs-marketplace`), which matches `platforms.json`'s existing install command.
- The `.claude-plugin/marketplace.json` legacy path means the repo's existing Claude marketplace file could be consumed by Codex directly; untested.

### Gaps
- `codex plugin install <name>` (the command recorded in this repo's `platforms.json`) was not confirmed on any fetched docs page; the documented CLI surface is `codex plugin marketplace ...` plus the `/plugins` browser.
- The submission page is undated; whether hooks/app packages will become submittable is stated only as "currently".

## Additional surfaces: AGENTS.md, rules layering, sandbox/approvals, cloud/app/IDE

### Takeaway
AGENTS.md is layered root→cwd with `AGENTS.override.md` precedence and a 32 KiB cap; `CLAUDE.md` is never read unless added to `project_doc_fallback_filenames`; sandbox/approval are `config.toml` keys with a new permission-profile system; plugins work in CLI and the desktop app but not the IDE extension.

### Cited Findings
- AGENTS.md: global `$CODEX_HOME/AGENTS.override.md` else `AGENTS.md` (first non-empty); project walk from root toward cwd, per directory `AGENTS.override.md`, then `AGENTS.md`, then fallbacks, "at most one file per directory"; concatenated root-down so closer files override; stops at `project_doc_max_bytes` (default 32 KiB); `project_doc_fallback_filenames` example `["TEAM_GUIDE.md", ".agents.md"]`; "Filenames not on this list are ignored"; `CLAUDE.md` not mentioned — [AGENTS.md](https://learn.chatgpt.com/docs/agent-configuration/agents-md). Paths rejected in fallback filenames since 0.156.0 (#45865).
- `model_instructions_file` replaces built-in instructions; `developer_instructions` injects extra developer text; `projects.<path>.trust_level` `"trusted"|"untrusted"` and untrusted projects skip `.codex/` layers; `profile`/`profiles` ignored in project-local `.codex/config.toml`; profile files at `$CODEX_HOME/<name>.config.toml` via `--profile` — [Config reference](https://learn.chatgpt.com/docs/config-file/config-reference).
- Approvals: `on-request` (default pairing with `workspace-write`), `never` (`-a never`), granular `approval_policy = { granular = { ... } }`, `approvals_reviewer = "auto_review"`, admin `allowed_approvals_reviewers`; `untrusted` retired; `on-failure` deprecated — [Sandbox & approvals](https://learn.chatgpt.com/docs/agent-approvals-security); [Config reference](https://learn.chatgpt.com/docs/config-file/config-reference).
- Sandbox: `read-only`, `workspace-write`, `danger-full-access` (`--dangerously-bypass-approvals-and-sandbox`, alias `--yolo`); `[sandbox_workspace_write] network_access` (off), `writable_roots`, `exclude_slash_tmp`, `exclude_tmpdir_env_var`; protected paths `.git`, `.agents`, `.codex`, `.aws`; permission profiles `default_permissions` with built-ins `:read-only`, `:workspace`, `:danger-full-access` and `[permissions.<name>]` (`extends`, `filesystem`, `network.*`, `workspace_roots`); `[features.network_proxy]` with `domains` map, `*`/`**` wildcards, deny wins; macOS Seatbelt, Linux `bwrap`+`seccomp` (since 0.115), Windows MXC via `[features] prefer_mxc = true` or `windows.sandbox = mxc|elevated|unelevated` — [Sandbox & approvals](https://learn.chatgpt.com/docs/agent-approvals-security); [Config reference](https://learn.chatgpt.com/docs/config-file/config-reference).
- MCP tools with a destructive annotation always require approval unless also read-annotated — [Sandbox & approvals](https://learn.chatgpt.com/docs/agent-approvals-security).
- Surfaces: plugins in ChatGPT web/desktop (Plugins tab) and Codex CLI (`/plugins`); "The Codex IDE extension doesn't support plugins"; hooks need scripts present in the execution environment, web installs don't deploy them — [Plugins](https://learn.chatgpt.com/docs/plugins); [Build plugins](https://developers.openai.com/plugins/build/plugins).
- Multi-folder projects: "automatic discovery of AGENTS.md, skills, and config.toml use the primary folder" (app 26.715) — [Changelog](https://learn.chatgpt.com/docs/changelog).
- `notify` = array<string> command receiving a JSON payload (the Codex analogue of a Notification hook) — [Config reference](https://learn.chatgpt.com/docs/config-file/config-reference).

### Inferences
- A plugin cannot ship AGENTS.md content; the only instruction channels a plugin controls are skills, `SessionStart`/`UserPromptSubmit` hook `additionalContext`, and `onboardingSkill`.
- Codex's `notify` command is user config, so this repo's Pushover `Notification` hook has no plugin-shippable Codex equivalent.

### Gaps
- `features.worktrees` key name (the 0.162.0 note says "when the worktrees feature is on") was not found in the fetched config reference portions.
- Cloud Codex (codex.openai.com / "Codex cloud") plugin behaviour was not covered by any fetched page beyond "installing on the web doesn't deploy hook scripts"; no reliable source on whether cloud tasks load repo-level `.agents/plugins/marketplace.json`.
- The Codex IDE extension page was not fetched; the "no plugins" claim rests on the plugins overview page alone.
