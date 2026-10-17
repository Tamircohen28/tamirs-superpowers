# Claude Code releases 2.1.288 → 2.1.302: everything a plugin author must know

Scope: every Claude Code release after 2.1.287 up to the newest available on 2026-10-17. The newest is **2.1.302** (npm `latest`/`next` = 2.1.302, `stable` = 2.1.292). **Versions 2.1.297 and 2.1.298 do not exist** — neither the CHANGELOG nor the npm registry lists them; the sequence goes 2.1.296 → 2.1.299.

Primary sources used throughout:
- CHANGELOG: https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md (read in full for 2.1.288–2.1.302; cited below as [CHANGELOG])
- Publish dates: npm registry `time` map, https://registry.npmjs.org/@anthropic-ai/claude-code (cited as [npm])
- Docs: https://code.claude.com/docs/en/hooks, /plugins-reference (manifest), /plugins/cli-reference, /plugins/mods/reference, /sub-agents, /skills, /statusline

Release dates (UTC, from [npm](https://registry.npmjs.org/@anthropic-ai/claude-code)): 2.1.288 = 2026-10-02 · 2.1.289 = 2026-10-03 · 2.1.290 = 2026-10-05 · 2.1.291 = 2026-10-06 · 2.1.292 = 2026-10-06 · 2.1.293 = 2026-10-07 · 2.1.294 = 2026-10-08 · 2.1.295 = 2026-10-08 · 2.1.296 = 2026-10-09 · 2.1.299 = 2026-10-14 · 2.1.300 = 2026-10-14 · 2.1.301 = 2026-10-15 · 2.1.302 = 2026-10-16. (The GitHub Releases API was not reachable from this session's proxy, so the GitHub release timestamps could not be cross-checked; npm publish time is the primary record used.)

---

## Key Question 0: Release-by-release digest (plugin-relevant items only)

### Takeaway
Fifteen releases shipped in 15 days. The plugin-relevant substance concentrates in 2.1.288–2.1.290 (mods hardening, `agentId` on hooks, `claude plugin validate` `gatingHooks`), 2.1.292 (`claude plugin install --marketplace`, Agent tool `effort`, `prompt.autocomplete`), 2.1.293 (`agentType` in `subagentStatusLine`, Haiku 5.5), 2.1.295 (`onFailure: "block"` on command/HTTP hooks, `$.ui.notify`, 32-skill preload cap), 2.1.296 (`autoCompactWindow` agent frontmatter, `allow_large` Read, MCP description limit 4,096), 2.1.299 (biggest: `UserPromptSubmit` ordering change, MCP rule scoping change, agent `tools:` MCP scoping change, `claude plugin eval --disallow-tools`, skill-name character refusals, `$.session.identity()`, hooks-fail-closed change), 2.1.300 (`updatedInput` validation, plugin `WorktreeCreate`/`WorktreeRemove` under `--worktree`, `prompt.change` mod hook, `$.ui.view`), 2.1.301 (hook `ask` attribution to plugin, `rows` Input, `$.env.set` result shape), 2.1.302 (fork subagents on by default everywhere, 12-concurrent cap for prompt/agent hooks, plugin `bin/` on PowerShell).

### Cited Findings

#### 2.1.288 (2026-10-02)
- Added `$.ui.selection()` for mods: returns the text last selected in fullscreen mode and, when within one transcript row, that row — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added a built-in `gh api` to cloud sessions whose image has no GitHub CLI — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added a re-authenticate prompt when an MCP server asks for more OAuth scope during a tool call — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added `--max-findings <n>|all` to `/code-review`; `--max-findings default` resets — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added Ctrl+F (find session by name) and Alt+↑/↓ in the agents view; both, and rename, can be rebound in `keybindings.json` — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added `CLAUDE_CODE_DISABLE_STRUCTURED_OUTPUTS` (fixes session titles, memory recall and prompt hooks behind gateways that reject structured outputs) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed plugin LSP servers receiving literal `${user_config.*}` and `${CLAUDE_PLUGIN_ROOT}` placeholders in `initializationOptions` and `settings` — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed a plugin's `tool.call` hook making Bash fail and file searches read the wrong folder in subagents that run in a worktree — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed `git-subdir` plugin installs failing/caching incomplete on git < 2.39 (e.g. Ubuntu 22.04) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed plugins loaded with `--plugin-dir` not showing "Configure options" in `/plugin` — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed background sessions ending when a plugin was reloaded/disabled while a timer or read was running — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed agent teams: a plugin-defined agent spawned by name now runs with its own prompt, tools, `disallowedTools` and effort instead of defaults — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed `claude plugin install` for GitHub-source plugins on macOS/Linux with no GitHub SSH key: clone falls back to HTTPS — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed `owner/repo` marketplaces showing only the second attempt's error when SSH and HTTPS both fail — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed path-scoped `.claude/rules` and nested CLAUDE.md not loading when Write or Edit creates/changes a file in their scope (previously only Read) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed LSP tool calls hanging; requests now time out after 60s (per-server `requestTimeout`, documented as "Requires v2.1.288 or later") — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md); [Manifest reference](https://code.claude.com/docs/en/plugins-reference)
- Fixed `idle_prompt` notification hooks firing while background agents are still running — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed PreToolUse and PermissionRequest hooks being skipped when matching failed or tool input could not be serialized to JSON; the call is now blocked — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed `InstructionsLoaded` hook omitting `agent_id` and `agent_type` when a subagent's file access loads a rule or nested CLAUDE.md; those loads now also report `effort` — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed the Agent tool in `claude mcp serve` always reporting no available agents and rejecting every `subagent_type` — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed subagents in Claude Desktop's Code tab getting none of the tools of a user-configured MCP server named `memory` — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed a stall when launching an agent whose `tools:` lists very many `Agent(...)` entries — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed `claude plugin test` reporting mods as turned off remotely from an out-of-date saved setting — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed background command time limit to apply only in unattended sessions (`-p`, SDK, CI, cloud) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- **Renamed** `claude project purge` → `claude purge`; old name still works with a notice — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed `/autocompact` to save the auto-compact window per model — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed MCP URL prompts from servers that can't report completion to wait for "I'm done, continue" — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)

#### 2.1.289 (2026-10-03)
- Added `agent.spawn` for teammates, one agent id across plugin hook events, and `idle` and `waiting` states in `$.agent.list()` (docs: "`idle` and `waiting` require Claude Code v2.1.289 or later") — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md); [Mods reference](https://code.claude.com/docs/en/plugins/mods/reference)
- Added mod event `ui.fault` (a `Client` element failed to load/draw/run; `e.phase` is `load`/`render`/`run`): "Requires Claude Code v2.1.289 or later" — [Mods reference](https://code.claude.com/docs/en/plugins/mods/reference)
- Fixed `plugin list`, `plugin eval` and `plugin update` showing a stale copy of a plugin installed from a local folder marketplace, and hot reload for a symlinked `--plugin-dir` — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- `claude plugin list --json` gained `readFromFolder` and `folderVersion` fields ("Requires Claude Code v2.1.289 or later") — [Plugin CLI reference](https://code.claude.com/docs/en/plugins/cli-reference)
- Fixed installed mods not loading in the first session after an upgrade — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed `claude plugin validate` skipping the plugin when the folder also holds a marketplace manifest; fixed it failing an Anthropic marketplace's own plugin and listing a clean `plugin.json` in `--json` — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed a user-installed plugin being able to rewrite descriptions of an organization-managed MCP server's sign-in tools — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Multiple mod-rendering robustness fixes (unknown `Box` border style freeze; plugin panes drawing nothing for localhost/`@`/uppercase/`file:` links; `ui.render` row throwing now draws the engine's own row; `Client` failing alone and raising `ui.fault`) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed Bash deny/ask rules missing commands behind env-var prefixes or bare variable assignments under sandbox auto-allow — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)

#### 2.1.290 (2026-10-05)
- Added `serverToolUses` to the result of a mod's `turn.step` hook (tool calls the API ran itself, e.g. the advisor) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added `agentId` to the `tool.check` event of plugin hooks (tell a subagent's permission check from the main session's); added `ceiling` to the question/verdict a `tool.check` hook reads (approval an organization requires). Docs: "On `tool.check`, `e.agentId` and `e.ceiling` require Claude Code v2.1.290 or later" — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md); [Mods reference](https://code.claude.com/docs/en/plugins/mods/reference)
- Added `ThemeKey` and `Color` types to the plugin hooks typings — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added to `claude plugin validate`: each hook a mod registers at a gating site is listed with whether it has a `.catch` (`gatingHooks` under `--json`; items give `module`, `pattern`, `hook`, `hasCatch`) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md); [Plugin CLI reference](https://code.claude.com/docs/en/plugins/cli-reference)
- Added mod event `prompt.mention` (Claude Code is about to read an @-mentioned file; `next({ ...e, path })` or `{ deny }`): "Requires Claude Code v2.1.290 or later" — [Mods reference](https://code.claude.com/docs/en/plugins/mods/reference)
- Added `claude attach <name>` and `claude logs <name>`: part of a session name works in place of the id — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- `agent_id` added to `TaskCreated`, `TaskCompleted` and `TeammateIdle` hook input ("Requires Claude Code v2.1.290 or later"); WebFetch gained `offset` — [Hooks reference](https://code.claude.com/docs/en/hooks)
- Fixed `plansDirectory` project-root check for backslash paths — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed a project `CLAUDE.md`, rule or `AGENTS.md` symlinked outside the working directories loading under `permissions.blockReadsOutsideWorkingDirectories` or a `Read` deny rule — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed `claude plugin validate` and plugin loading refusing a hooks module that destructures an option named like a top-level function — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed Windows multi-line `!` shell blocks in skills/commands failing with CRLF — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed plugin hooks reading an empty `answer` on `turn.complete` for a subagent that hands its report back in auto mode — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed `disableClaudeAiConnectors` and `allowedMcpServers` URL rules not applied to some MCP entries in `.mcp.json`, plugins or agents — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed a subdirectory's `AGENTS.md` not being attached when a file under it is @-mentioned — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed Claude replying in an endless loop when a plugin's async `Stop` hook passes an unquoted script path under a folder with a space — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed some permission rules/safety checks not applied after a `PreToolUse` hook rewrote a tool call's input — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed sandboxed `Monitor` tool commands skipping the permission prompt under sandbox auto-allow — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed skills not found by SKILL.md `name` when the folder has a different name; the listing now shows both names — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed a marketplace named after another GitHub marketplace's download folder blocking that marketplace — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed `claude plugin test` refusing to run after an upgrade because of an out-of-date saved setting — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed mods staying off for people who reach Claude through a gateway (`ANTHROPIC_BASE_URL` + `ANTHROPIC_AUTH_TOKEN`) with no Anthropic account — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed background subagents losing write and Bash access in their worktree after the main session enters/exits a different worktree — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed `/plugin` reply in the desktop app's Code tab to say where to install/manage plugins there — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed plugin hooks so long text is clipped and logged instead of refused/dropped silently — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed an in-process teammate's `agent_id` in Agent results to its agent ID (`name@team` stays in `teammate_id`); `TeammateIdle` hooks no longer fire from its subagents or forks — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed skills/custom commands to refuse a `!` shell command containing raw control characters other than tab and newline — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed the Bash tool to ask before `pyright` (no longer read-only); more `ps` forms ask — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed Claude in Chrome so a project's settings files can no longer turn it on — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed `CLAUDE_CODE_DISABLE_ATTACHMENTS` so `.claude/settings.json`/`.claude/settings.local.json` can no longer set it — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed `claude plugin update` on a plugin loaded from a directory to print just its reason — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed interactive WebSearch budget to refill (100 calls/hour; `CLAUDE_CODE_WEB_SEARCH_REFILLS_PER_HOUR`) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- [VSCode] Added a way to review and run a marketplace's install/update command from the Manage plugins dialog — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)

#### 2.1.291 (2026-10-06) — regression fixes only
- Fixed a 2.1.290 regression where cloud sessions could drop answers to permission prompts; fixed a 2.1.288 regression where the last messages of a session could be lost when quitting — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)

#### 2.1.292 (2026-10-06)
- Added `--marketplace <source>` to `claude plugin install`: adds the marketplace if needed under the same policy checks as `claude plugin marketplace add`, then installs (docs: "Requires Claude Code v2.1.292 or later") — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md); [Plugin CLI reference](https://code.claude.com/docs/en/plugins/cli-reference)
- Added an `effort` parameter to the Agent tool (docs: "Requires v2.1.292 or later. It overrides the `effort` field but not `CLAUDE_CODE_EFFORT_LEVEL`") — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md); [Sub-agents docs](https://code.claude.com/docs/en/sub-agents)
- Added `prompt.autocomplete` mod event (hook returns `{ suggestions }` list of `{ text, label, description }`) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md); [Mods reference](https://code.claude.com/docs/en/plugins/mods/reference)
- Added prompt caching to `$.model.complete` (`prompt` and `system` take blocks; `cache: true` on a block) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added workflow agents to the `agent.spawn` mod hook (with run and index) so a mod can refuse them — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added `CLAUDE_CODE_OVERLOADED_RETRY_BASE_DELAY_MS` — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Mod `.catch` `next.error.kind` gained `re-entry` and `next.error.cause: lent` ("require Claude Code v2.1.292 or later") — [Mods reference](https://code.claude.com/docs/en/plugins/mods/reference)
- Mod `drop`/`config.set` deny reasons longer than 4,096 characters are now cut, not failed ("The cut requires Claude Code v2.1.292 or later") — [Mods reference](https://code.claude.com/docs/en/plugins/mods/reference); [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed subagent definitions with `permissionMode: auto` entering auto mode when auto mode is unavailable — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Security: Fixed PreToolUse hook approvals and auto mode bypassing the permission prompt for file reads from network (UNC) paths — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed a skill's or slash command's `allowed-tools` rule coming back in a later turn after leaving auto/plan mode mid-turn — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed an MCP tool with a name > 128 characters making every request fail; it is now left out with an MCP error naming it — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed `claude plugin` commands (`marketplace add`, `install`) running before an organization's managed settings loaded on first run — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed a compaction summary repeating `/name` letting Claude invoke a skill reserved for the user — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed plugins whose hooks module makes many `$.state` calls through one const taking minutes to load/validate; `claude plugin validate` now refuses a module that reads `$.state` through a re-declared or reassigned top-level `var` — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Many mod-hook correctness fixes: hook that denies after `next(e)` now reported as failed by name; `tool.check` allow no longer skips a required dialog; `tool.call` hooks now see repaired arguments; guard-with-`.catch` no longer skipped beneath another mod's `$` call; prompt drop/setting deny ignored when reason > 4,096 chars — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed `/theme`, `/config` Theme menu saving before a plugin's `config.set` hook was asked — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Improved hook output handling: `<system-reminder>` tags in hook output are escaped before reaching Claude — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Improved steps shown when a marketplace declared in settings has a name resembling an official Anthropic marketplace — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed local (stdio) MCP server connections to negotiate MCP protocol version 2026-07-28 by default on every install; `MCP_PROTOCOL_NEGOTIATION=legacy` opts out — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed `claude plugin test`: a failed `expect` inside a hook the test registered, or a stub answer the engine refuses, now fails the test — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed agent names to allow at most 256 characters; a skill's or plugin file's `name` longer than that is ignored — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)

#### 2.1.293 (2026-10-07)
- Added Claude Haiku 5.5 (`claude-haiku-5-5`), default Haiku on the Anthropic API — 1M context — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added `agentType` to the `subagentStatusLine` payload (docs: same value hooks receive as `agent_type`; "Requires Claude Code v2.1.293 or later") — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md); [Status line docs](https://code.claude.com/docs/en/statusline)
- Added `isDeferred` to `$.tool.register` for mods (`false` lists the schema upfront instead of behind tool search) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed Claude being told to use `SendMessage` in sessions where a host, permission rule or `--tools` list removed it — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed a claude.ai-synced skill's edited description not reaching the model until new conversation — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed a mod's hooks on `classic.*` events being skipped while the plugin hooks worker restarts — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed `claude plugin test` failing for mods that call `$.session.append`; tests read appended rows back with the new `mock.session` — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed `claude plugin eval` refusing every Bash-granting run on Macs with Docker Desktop — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed path-scoped rules and nested CLAUDE.md not loading when Claude views a file via single-file `cat`/`head`/`tail`/`sed -n`/`grep` in Bash — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed `keybindings.json` checks: a lone `" "` is no longer an error; keys like `"ctrl+ k"` warn — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Reverted the 2.1.281 auto-mode denial message change — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed claude.ai skill syncing to check about every 40 minutes (was 10) while idle — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed order of agent lists and MCP servers announced to the model: non-ASCII names sort after ASCII — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)

#### 2.1.294 (2026-10-08) — two fixes only
- Fixed `prompt` and `agent` hooks written as instructions allowing what they should block; improved judging of `prompt` hooks on `Stop`/`SubagentStop` written as instructions — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)

#### 2.1.295 (2026-10-08)
- Added `onFailure: "block"` for command and HTTP hooks: a hook that can't start, times out, or exits with an unexpected code blocks the action instead of letting it through (docs: `onFailure` listed under command-hook and HTTP-hook fields; "v2.1.295: `onFailure` added") — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md); [Hooks reference](https://code.claude.com/docs/en/hooks)
- Added Program Status Protocol (OSC 7501) support — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added a warning to `claude plugin install`, `enable`, `disable` and `marketplace add` when the settings file they write to does not load — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added advice to `claude plugin validate` when a plugin's README has no install line: prints the line to paste, never changes the exit code even with `--strict` — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added `$.ui.notify` for mods (native notification through the user's notification setting) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added children to a mod's `Button` (strings and `Text`) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added `CLAUDE_CODE_RETRY_WATCHDOG_MAX_WAIT_MS` — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added user-settings support for `forceLoginMethod: "gateway"` and `forceLoginGatewayUrl` on machines with no managed settings — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Async hook JSON output may now span several lines ("Spanning several lines requires Claude Code v2.1.295 or later") — [Hooks reference](https://code.claude.com/docs/en/hooks); [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed `/plugin`'s Errors tab removing a failed marketplace and uninstalling its plugins on Enter without asking — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed `claude plugin marketplace add` reporting success for a marketplace name no plugin can be installed under — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed `--tools` and `--restricted` not applying to built-in tools registering after launch — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed forked skills invoked from Workflow subagents delivering results to the main conversation instead of the invoking agent — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed in-process agent teammates failing their first `SendMessage` until loading via tool search — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed plugin marketplaces with large git submodules failing to add/refresh — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed `claude plugin test` passing a `session.append` hook that removes blocks a real session keeps — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed plugin options named `constructor` or `prototype` always reading as default — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed `/model`, `/fast` and `/output-style` saving without asking a plugin's `config.set` hook — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed an async `SessionStart` hook's unchanged context being re-added on every resume; fixed `CLAUDE_ENV_FILE` variables from `SessionStart` not reaching Bash after in-app `/resume` or `/branch` — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed a skill's `allowed-tools` and `effort` being dropped when the Skill tool finished before the stream ended (denied Bash in `-p` runs) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed generated type files being written into a `--plugin-dir` plugin's folder in `-p` and SDK sessions — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed project-scope plugins not loading in VS Code on Windows (drive-letter casing); fixed install/uninstall scope records differing only by drive-letter case — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed claude.ai-synced plugin hooks failing with "Plugin directory does not exist" after another session synced an update — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed cloud sessions hanging when a mod's `session.receive` hook asked for permission — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Improved `claude plugin validate` error for a hooks module refused over a rebound top-level `var` (names line, cause, fix) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Improved the built-in `plugin-authoring` skill — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed MCP tool descriptions loaded through tool search to be cut at 16,384 characters (was 2,048) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed subagents to preload at most 32 skills from the `skills` field, each once — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed claude.ai connectors to negotiate MCP protocol 2026-07-28 by default on installs that fetch no flags — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed what Claude and the user read when a mod denies a tool call after the tool ran ("the tool ran and a plugin withheld its result") — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed toasts from an organization's mods to show ahead of other mods' toasts — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed WebSocket (`ws`) MCP servers: messages over 16 MiB close the connection — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)

#### 2.1.296 (2026-10-09)
- Added a `code` key to the Claude apps gateway's `managed.policies[]` (same settings as `cli`, applied in Claude Desktop's Code tab) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added `autoCompactWindow` to subagent frontmatter and `--agents` definitions (docs: "Integer from `100000` to `1000000`. Requires v2.1.296 or later") — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md); [Sub-agents docs](https://code.claude.com/docs/en/sub-agents)
- Added `CLAUDE_CODE_WORKFLOW_SUBAGENT_MODEL` (one model for every workflow agent) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added `CLAUDE_CODE_OVERLOADED_RETRY_MAX_DELAY_MS` — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added a note in `/plugin` on a plugin whose hooks are left out because another enabled plugin has the same name — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added `allow_large` option to the Read tool — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed managed-settings `PreToolUse` hooks denying with `"continue": false` not ending the turn; fixed managed `PostToolUse` hooks not applying `updatedMCPToolOutput` — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed hook output being altered when it contained text resembling a plugin hint tag — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed Esc/interrupt during a `UserPromptSubmit` hook or a mod's `prompt.submit` hook ending headless sessions or letting the unchecked prompt through — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed `SessionStart` hooks of a plugin loaded after a headless session starts being skipped when a same-named plugin had already run; fixed a late-loading plugin's `SessionStart` output reaching the new conversation after `/clear` in headless — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed a plugin's served `$` methods running in the main session's cwd instead of the calling agent's — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed `$.agent.register` succeeding from a hook still running after the mod was reloaded/removed — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed `$.http.fetch` refusing a `HEAD` request with `Content-Length` over 4 MiB ("The `HEAD` exemption requires Claude Code v2.1.296 or later") — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md); [Mods reference](https://code.claude.com/docs/en/plugins/mods/reference)
- Fixed `claude plugin marketplace add`/`update`/`plugin install` internal error for a marketplace named like `constructor`; fixed a plugin secret named `constructor`/`prototype` being deleted on next save — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed PowerShell commands not seeing variables hooks write to `CLAUDE_ENV_FILE` (plain assignments only; docs: support starts in v2.1.296) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md); [Hooks reference](https://code.claude.com/docs/en/hooks)
- Fixed skills synced from claude.ai never finishing install when several sessions share a config directory; fixed a claude.ai-synced plugin being disabled when its declared marketplace dependency was also synced — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed a macOS startup hang when plugin paths copied from Linux pointed under /home — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed the Workflow tool refusing CRLF script files — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Windows: Fixed `claude plugin install` failing for GitHub `owner/repo` sources with no SSH key (HTTPS retry) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Improved `--debug` output to name unrecognized frontmatter fields in custom agent files with typo hints — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Improved `--debug` output for hooks: command hooks on tool calls, prompts, `SessionStart` and `Stop` log command, plugin, outcome and duration (`Hooks: PostToolUse:Write [...] finished with status 0 (31ms)`) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md); [Hooks reference](https://code.claude.com/docs/en/hooks)
- Changed the default limit on MCP tool descriptions sent up front and on MCP server instructions from 2,048 to 4,096 characters — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Updated cost figures: Sonnet 5.5 cache reads at $0.10/M (was $0.20) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)

#### 2.1.299 (2026-10-14) — largest plugin-impacting release in the range
- Added `CLAUDE_CODE_DISABLE_FILE_MENTIONS` (Claude gets paths of `@` mentions, reads via file tools; docs note this makes file-mention reads go through `PreToolUse` hooks) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md); [Hooks reference](https://code.claude.com/docs/en/hooks)
- Added idle compaction in the terminal (200K+ token conversation idle ~54 minutes is compacted before the 1-hour cache expires); `CLAUDE_CODE_IDLE_COMPACT_MIN_TOKENS` and `"idleCompaction": false` in settings.json; "Both need v2.1.290 or later" — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added `$.prompt.media` (a `prompt.submit` hook of a mod installed by managed settings can read attached image/document bytes) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added `$.session.identity()` for mods installed by managed settings — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added `size`, `weight`, `mono`, `tabular` to a mod's `Text`, and named spacing steps (`xs` to `xl`) to `Box`; `bold` is deprecated in favor of `weight` ("These four props require Claude Code v2.1.299 or later"; "Step names require Claude Code v2.1.299 or later") — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md); [Mods reference](https://code.claude.com/docs/en/plugins/mods/reference)
- Added the skill's frontmatter, source, plugin name and file path to what a mod's `skill.prompt` hook receives (`e.source`, `e.pluginName`, `e.path`, `e.frontmatter`, `e.frontmatterProblem`; "require Claude Code v2.1.299 or later") — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md); [Mods reference](https://code.claude.com/docs/en/plugins/mods/reference)
- Added `--disallow-tools` and a `disallowed_tools` case field to `claude plugin eval` to keep specific built-in tools (such as Agent) out of eval runs — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added a `queue` door to the `session.append` mod hook — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added a note in `/plugin` and `claude plugin validate` naming a mod's hooks that are skipped where an organization manages Claude Code — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added `/usage` warnings for max effort, workflows, always-on context and large tool results — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added `CLAUDE_CODE_ATTRIBUTION_HEADER=0` (removes the attribution block behind a Claude apps gateway / in Desktop Code tab) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added `CLAUDE_CODE_STRICT_INLINE_SHELL_RM_PROMPT=1` — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Mods now render in the VS Code extension ("requires extension version 2.1.299 or later") — [Mods reference](https://code.claude.com/docs/en/plugins/mods/reference)
- Fixed a mod that submits a prompt every turn keeping a headless run going past `--max-turns`/`--max-budget-usd` — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed installed mods kept running after being turned off remotely; they now unload between turns — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed a sandboxed shell command being able to write into a `--plugin-dir` folder — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed `claude mcp list`, `claude doctor` and `/status` reporting an empty `.mcp.json` as invalid — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed MCP servers named `constructor`/`prototype` never connecting; fixed tools of a server named `constructor`/`toString` asking for permission in auto/bypass — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed a spurious "synced[0] commands path not found" plugin error at startup when another process had just updated a claude.ai-synced plugin — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed Cowork cloud sessions staying on an old account plugin after reload/restart; fixed them running an old version of an account plugin changed/removed/disabled from another device — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed a mod's `tool.describe` or `prompt.section` answer changed after `$.ui.invalidate` never reaching Claude — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed a settings file being ignored when `enabledMcpjsonServers`/`disabledMcpjsonServers` held a single server name as a plain string — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed `claude plugin test` pausing a hook's time budget while a served `$` method kept making calls — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed plugin hooks being skipped when they pass a very deeply nested tool input/message with `next()`; fixed a `RangeError` in a getter refusing the whole value (now only that key) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed deny/ask rules for an MCP server (`mcp__<server>`) not applying when the normalized name contains a double underscore — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed the `plugin_loaded` telemetry event reporting `has_hooks` as false for plugins whose hooks are a hooks module — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed mod hot reload ignoring a fix saved right after a failed reload; saving unchanged no longer reloads — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed mods loaded from source being refused when a hook hands `$` to a function declaration imported from another file of the mod — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed mods' hooks being handed values with `__proto__` keys silently removed (could skip a `tool.check` guard) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed `claude -p` saying nothing when a settings file fails validation; now lists file and entry on stderr — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed MCP connections over HTTP hanging 30s when a server never ends the body of a notification reply — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed `/reload-plugins` not loading a plugin installed from another terminal a moment earlier — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed `$.http.fetch` refusing `304`/`204`/`205` with large `Content-Length` — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed `claude plugin eval` passing runs the API refused; such a run scores 0 and the suite exits 1 — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed MCP OAuth sign-in/refresh/sign-out not sending configured `headers`/`headersHelper` values — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed `$.ui.open` reporting a pane as placed in sessions with no surface (VS Code, `claude -p`) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed the `agent.spawn` mod hook not running when a finished subagent or killed teammate is resumed: the event now carries `resume`, and a mod can refuse it — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed `claude plugin validate` rejecting a mod's `$.state` references when `plugin.json` has no `types` key and the contract is at `./types/index.d.ts` — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed plan mode running a write that a `PreToolUse` hook or a mod's `tool.check` hook allowed — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed `SendMessage` not finding a subagent by name after the CLI restarted and resumed (names given before the last compaction still need the agent ID) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed a user-installed mod's `$.env.set` changing the environment of command hooks from managed settings — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Windows: Fixed `PreToolUse`/`PermissionRequest` hooks with no shell failing open when Git for Windows isn't installed; a guard that fails now blocks — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed worktree-isolated sessions accepting some awk programs the guard should refuse — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed `--worktree` sessions leaving a folder in `.git/worktrees` under reftable — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Improved enforcement of managed permission rules, managed hooks and organization MCP tool names against user-installed mods — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Improved the Skill tool's "Unknown skill" error to suggest the listed name when Claude wrongly adds `anthropic-skills:` — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Improved `/reload-skills` to say it re-sends the full skill list (how to get skills back after compaction) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Improved worktree creation errors (unresolvable base commit; bare-repository root) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Improved artifact watching: a local session can watch up to 25 artifacts (was 10) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed plugin hooks and workflow scripts to refuse values nesting deeper than 28,000 levels — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- **Changed actions a plugin hook can block to be refused, not let through, when the hook cannot be handed them or cannot hand back its answer; a tool that already ran has its result withheld** — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed requests to claude.ai's connector proxy and Anthropic-hosted MCP servers to no longer follow HTTP redirects; same for cloud/self-hosted runner MCP proxy — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- **Changed skill and command loading: one whose file or folder name has hidden, direction-changing or blank-like characters, `<` or `>` is no longer offered until renamed; such a `name:` is ignored** — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md); [Skills docs](https://code.claude.com/docs/en/skills)
- Changed `ui.render` trees in `claude plugin test`: each mod's Box/Text root now carries `part: { plugin }`, so exact-tree assertions must include it — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed `claude plugin test` to fail a served `$` method call not answered within ten seconds — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- **Changed MCP allow rules to reach only the server they name: `mcp__a` no longer allows `a__b` or `a_`; write `mcp__<server>__*` with the whole normalized name** — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- **Changed agent `tools:` lists to take only the named MCP server's tools; list a server whose name contains `__` as `mcp__<whole name>__*`** — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed cloud session and Remote Control MCP connectors to negotiate MCP protocol 2026-07-28 by default — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed Anthropic first-party MCP server descriptions/instructions at `api.anthropic.com` to reach Claude in full (not cut at 4,096) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed auto mode in Cowork cloud sessions: a `PermissionRequest` hook can no longer approve shell commands or subagents — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- **Changed `UserPromptSubmit` hooks to run before a skill or custom slash command expands, so a hook that blocks the prompt also stops its embedded shell commands** — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- **Changed a skill's own front-matter `UserPromptSubmit` hook to first run on the prompt after the one that invokes the skill** — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed the `turn.start` mod hook to also hear subagents' and teammates' turns; tell apart by `e.agentId` (absent on main loop) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed the resume command printed at exit to name the session by ID, never name — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)

#### 2.1.300 (2026-10-14)
- Added `virtualText` to a mod's prompt decorations — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added `cache_creation_5m_tokens` and `cache_creation_1h_tokens` to the OpenTelemetry `api_request` event — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added `$.ui.view({ agentId })` for mods (show an agent's transcript in the main view; `$.ui.view({})` goes back) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added a `dir` prop on a mod's `Text` for right-to-left text — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added `/advisor` on Claude Platform on AWS; `CLAUDE_CODE_DISABLE_ADVISOR_TOOL=1` turns it off — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added OpenTelemetry GenAI semantic-convention attributes (`gen_ai.provider.name`, `gen_ai.conversation.id`, `gen_ai.tool.name`, `error.type`) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added support for rewriting a workflow agent's `prompt` and `model` in the `agent.spawn` mod hook — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added the `prompt.change` mod hook (prompt box text changes without a typed edit: history recall, clear, undo, or a plugin's fill) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- `next.error.cause: rewritten` in mod `.catch` handlers ("`rewritten` v2.1.300 or later") — [Mods reference](https://code.claude.com/docs/en/plugins/mods/reference)
- Fixed `SessionEnd` hooks sometimes not running when exiting while a background command is still running — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- **Fixed plugin `WorktreeCreate` and `WorktreeRemove` hooks not running when Claude Code starts with `--worktree` (not yet with `--tmux`)** — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed agent hooks ignoring their `model` (aliases like `haiku` now resolve; a subagent's model no longer overrides; unavailable model falls back to caller's instead of allowing) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed `--worktree` starting from wrong commit when a tag/branch was named like a commit ID; fixed `.invalid` branch and reopen failures under reftable; fixed `--worktree` in a bare-repo worktree when origin default branch can't be fetched — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed a mod's `prompt.edit` hook not raised for a newline via `chat:newline` keybinding — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed a conversation failing every turn with 400 when the API rejected an MCP tool's input schema; that tool is now sent without parameters — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed Claude not told about an MCP server's tools and instructions until its next tool call when the server connected after compaction — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed a note about mod hot-reloading appearing in the transcript as if typed — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Improved mod sharing in the built-in `plugin-authoring` skill (scans a mod's files for keys first) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed `PermissionRequest` hooks in Cowork cloud sessions: a `setMode` update in a hook's allow is now ignored — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- **Changed hooks: `updatedInput` from `PreToolUse` and `PermissionRequest` hooks is now validated like Claude's own input: unknown keys are dropped, and input the tool rejects denies the call** — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- **Removed** the `--sandbox` and `--no-sandbox` flags from `claude remote-control` (had no effect); passing either now exits with an error; set `sandbox.enabled` in settings — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed Claude Desktop's Code tab to apply managed settings when `forceLoginGatewayUrl` names an Anthropic-operated gateway — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed local transcripts to also record each API request's system prompt, tools and parameters — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed large requests to api.anthropic.com to gzip; `CLAUDE_CODE_GZIP_REQUEST_BODIES=0` turns off — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- [Remote Control] diff view fix "requires Claude Code v2.1.296 or later on your machine" — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)

#### 2.1.301 (2026-10-15)
- Added `CLAUDE_CODE_RETRY_WATCHDOG_MAX_USAGE_LIMIT_WAIT_MS` — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added `rows` to a mod's `Input` (multi-line text field; Enter submits, Shift+Enter or backslash-Enter new line) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added `classifier_verdict`, `permission_mode` and `classifier_category` to OpenTelemetry `tool_decision` events — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed quitting removing a worktree made by a `WorktreeCreate` hook without asking when it may hold unpushed commits — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed artifact updates being refused where a `PreToolUse` hook covers Edit or Write — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed skills/commands with very many or long argument names stalling; only the first 64 names, each up to 64 characters, are filled in; fixed heavy memory use when arguments fill many placeholders — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed skills no longer listed to the model after `/rewind` — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- **Fixed the permission prompt for a plugin or skill hook's `ask` decision not showing which plugin or skill the hook comes from** — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed a mod's `$.model.fork` returning `nothing-to-fork` before the first response of a new process (`claude -p`, cloud) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed workflow scripts asking for permission after a Bash `cd` — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Improved mods: in VS Code and desktop/mobile apps, a tree above the question dialog can hold Markdown and up to 48 rows; terminal keeps 12 plain rows — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed a mod hook's `.catch` handler to run only when the hook throws or times out; events raised beneath the hook's own calls skip that hook without asking its `.catch` — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed a mod's `$.env.set` to resolve with `{}` on success or `{ deny }` with a reason when the write is not made — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Self-hosted runner: use `deniedMcpServers` to keep attach-repo tools off when managed settings restrict MCP servers — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)

#### 2.1.302 (2026-10-16) — newest as of 2026-10-17
- Added `CLAUDE_CODE_AUTO_MODE_MODEL` (model for the client-side auto mode classifier) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added an `Idle compaction` row to `/config` — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Added a notice that standalone Claude Design (claude.ai/design) closes by December 14, 2026 — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed `claude plugin` and other subcommands sometimes exiting before a queued settings/config write finished (could lose the change or leave a `.tmp` file) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed plugin marketplaces re-cloning on every refresh, and newly installed git plugins showing version "unknown", when git defaults to reftable — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- **Fixed the PowerShell tool not finding commands in a plugin's `bin/` folder** — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed Claude in the desktop app pointing to claude.ai settings or `/mcp` to authorize/reconnect an MCP server where not available — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed MCP servers showing no tools when negotiating protocol 2026-07-28 but omitting `resultType`, `ttlMs` or `cacheScope` — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed `claude plugin details <name>@builtin` suggesting `claude plugin list`; now points to `/plugin` — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Fixed worktree isolation refusing to create/resume worktrees under git 2.56+ with a stray `.git` file — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Windows: Fixed every file write refused/asked on exFAT/FAT32, including sessions started with `--plugin-dir` — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Improved startup with many plugins: plugin command and agent files take far fewer file-system calls — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed `claude -p` and Agent SDK sessions with no permission mode to start in `default` mode on third-party providers, with telemetry off or on a fresh install; `--permission-mode auto` keeps auto — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- **Changed fork subagents (`subagent_type: "fork"`) to be on by default in `claude -p`, the Agent SDK, the desktop app and VS Code; `CLAUDE_CODE_FORK_SUBAGENT=0` turns them off; `claude mcp serve` never offers them** — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed the desktop app and VS Code to always run the main conversation's subagents in the background; a subagent's own Agent calls in `-p`/SDK/desktop/VS Code run in the foreground by default — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- **Changed prompt and agent hooks so that at most 12 of one event run at a time; the rest wait their turn** — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- [Claude Tag] admin settings now organize access into four tabs: Bundles, Connectors, Skills and plugins, and Channels — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)

### Inferences
- The `stable` npm dist-tag sits at 2.1.292 while `latest` is 2.1.302, so a plugin that relies on anything from 2.1.293+ (e.g. `agentType` in `subagentStatusLine`, `onFailure`, `autoCompactWindow`, `--disallow-tools`) will meet users on the stable channel who do not have it yet.
- The 2.1.299 "refused, not let through" change for plugin hooks plus 2.1.295's `onFailure: "block"` together move hooks toward fail-closed; a plugin whose guard hooks were written assuming fail-open (e.g. "if the hook can't run, the write still happens") now sees the opposite in the plugin-hook (mod) path and can opt into it for command/HTTP hooks.

### Gaps
- GitHub release dates could not be fetched (proxy returned 403 for the Releases API). npm publish timestamps are used instead; they may differ from the GitHub release time by minutes to hours.
- No reliable source was found explaining why 2.1.297 and 2.1.298 were skipped.

---

## Key Question 1: Which new hook events and payload fields exist now that did not in 2.1.287?

### Takeaway
No new *settings-hook event names* were added in 2.1.288–2.1.302; the docs' 33-event list (`SessionStart`, `Setup`, `UserPromptSubmit`, `UserPromptExpansion`, `PreToolUse`, `PermissionRequest`, `PermissionDenied`, `PostToolUse`, `PostToolUseFailure`, `PostToolBatch`, `Notification`, `MessageDisplay`, `SubagentStart`, `SubagentStop`, `TaskCreated`, `TaskCompleted`, `Stop`, `StopFailure`, `TeammateIdle`, `InstructionsLoaded`, `ConfigChange`, `CwdChanged`, `DirectoryAdded`, `FileChanged`, `WorktreeCreate`, `WorktreeRemove`, `PreCompact`, `PostCompact`, `PreModelSwitch`, `PostModelSwitch`, `Elicitation`, `ElicitationResult`, `SessionEnd`) predates this range. What changed are payload fields, hook-config fields (`onFailure`), semantics (ordering, validation, fail-closed), and a large set of new **mod** (hooks-module) events and `$` methods.

### Cited Findings
Settings hooks (hooks.json):
- `onFailure` is a new configuration field on command hooks and HTTP hooks; "`onFailure: "block"`: a hook that can't start, times out, or exits with an unexpected code blocks the action instead of letting it through" (2.1.295). Docs list `onFailure` under both "Command hook fields" and "HTTP hook fields" and note "v2.1.295: `onFailure` added" — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md); [Hooks reference](https://code.claude.com/docs/en/hooks)
- Documented hook-config fields now: common `type` (`"command"`, `"http"`, `"mcp_tool"`, `"prompt"`, `"agent"`), `if`, `timeout`, `statusMessage`, `once`; matcher group `matcher`; command: `command`, `args`, `async`, `asyncRewake`, `shell`, `onFailure`; HTTP: `url`, `headers`, `allowedEnvVars`, `onFailure`; MCP tool: `server`, `tool`, `input`; prompt/agent: `prompt`, `model` — [Hooks reference](https://code.claude.com/docs/en/hooks)
- Documented output fields: universal `continue`, `stopReason`, `suppressOutput`, `systemMessage`, `terminalSequence`; top-level `decision` (`"block"`), `reason`; `hookSpecificOutput` (with `hookEventName`): `additionalContext`, `permissionDecision` (`allow`/`deny`/`ask`/`defer` on PreToolUse; `allow`/`deny`/`ask` on PreModelSwitch), `permissionDecisionReason`, `updatedInput`, `decision.behavior`/`decision.updatedInput` (PermissionRequest), `retry` (PermissionDenied), `updatedToolOutput` (PostToolUse), `worktreePath` (WorktreeCreate, HTTP hooks), `action`/`content` (Elicitation), `displayContent` (MessageDisplay), `initialUserMessage`, `sessionTitle`, `watchPaths`, `reloadSkills` (SessionStart) — [Hooks reference](https://code.claude.com/docs/en/hooks)
- Common input fields: `session_id`, `prompt_id`, `transcript_path`, `cwd`, `scratchpad_dir`, `permission_mode`, `effort`, `hook_event_name`, `agent_id`, `agent_type` — [Hooks reference](https://code.claude.com/docs/en/hooks)
- `agent_id` added to `TaskCreated`, `TaskCompleted` and `TeammateIdle` input: "Requires Claude Code v2.1.290 or later" — [Hooks reference](https://code.claude.com/docs/en/hooks)
- `InstructionsLoaded` now reports `agent_id`, `agent_type` and `effort` for rules/nested CLAUDE.md loaded by a subagent's file access (2.1.288 fix) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- `InstructionsLoaded` input: `file_path`, `memory_type` (`"User"`, `"Project"`, `"Local"`, `"Managed"`), `load_reason` (`"session_start"`, `"nested_traversal"`, `"path_glob_match"`, `"include"`, `"compact"`), `globs`, `trigger_file_path`, `parent_file_path`; no decision control — [Hooks reference](https://code.claude.com/docs/en/hooks)
- `StopFailure` input `error` values: `rate_limit`, `overloaded`, `authentication_failed`, `oauth_org_not_allowed`, `account_on_hold`, `billing_error`, `invalid_request`, `model_not_found`, `server_error`, `max_output_tokens`, `cloud_credential_error`, `unknown`; plus `error_details`, `last_assistant_message`; no decision control — [Hooks reference](https://code.claude.com/docs/en/hooks)
- `Notification` matchers now include `permission_prompt`, `idle_prompt`, `auth_success`, `elicitation_dialog`, `elicitation_url_dialog`, `elicitation_complete`, `elicitation_response`, `agent_needs_input`, `agent_completed`, `quota_auto_resume_fired`, `quota_auto_resume_stale`, `quota_auto_resume_disabled` — [Hooks reference](https://code.claude.com/docs/en/hooks)
- `SubagentStop` input: `stop_hook_active`, `agent_id`, `agent_type`, `agent_transcript_path`, `last_assistant_message`, `background_tasks`, `session_crons` — [Hooks reference](https://code.claude.com/docs/en/hooks)
- `PostToolBatch` input: `tool_calls[]` of `tool_name`, `tool_input`, `tool_use_id`, `tool_response` — [Hooks reference](https://code.claude.com/docs/en/hooks)
- `UserPromptExpansion` input: `expansion_type` (`slash_command` or `mcp_prompt`), `command_name`, `command_args`, `command_source`, `prompt` — [Hooks reference](https://code.claude.com/docs/en/hooks)
- `PermissionDenied` input: `tool_name`, `tool_input`, `tool_use_id`, `reason`, `mcp_server`; output `hookSpecificOutput.retry: true` — [Hooks reference](https://code.claude.com/docs/en/hooks)
- `SessionStart` input: `source` (`"startup"`, `"resume"`, `"clear"`, `"compact"`, `"fork"`), `model`, `agent_type`, `session_title`, and on resume/fork `seconds_since_last_response`, `context_tokens`, `prompt_cache_likely_expired`, `estimated_cache_write_usd` (v2.1.251) — [Hooks reference](https://code.claude.com/docs/en/hooks)
- Semantics change (2.1.300): "`updatedInput` from PreToolUse and PermissionRequest hooks is now validated like Claude's own input: unknown keys are dropped, and input the tool rejects denies the call" — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Semantics change (2.1.299): `UserPromptSubmit` hooks run before a skill/slash command expands; a skill's own frontmatter `UserPromptSubmit` hook first runs on the *next* prompt after the one that invokes the skill — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Semantics change (2.1.302): "at most 12 of one event run at a time" for prompt and agent hooks — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Semantics change (2.1.288): PreToolUse/PermissionRequest hooks skipped on match/serialization failure now block the call; (2.1.299 Windows): a guard that fails now blocks — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Async hook JSON may span multiple lines when alone on stdout (v2.1.295); `asyncRewake` hooks still get `timeout` enforced and exit code 2 wakes Claude even when idle — [Hooks reference](https://code.claude.com/docs/en/hooks)
- `CLAUDE_ENV_FILE` is available for `SessionStart`, `Setup`, `CwdChanged`, `FileChanged`; PowerShell support for plain-assignment lines starts in v2.1.296 — [Hooks reference](https://code.claude.com/docs/en/hooks)
- Debug log lines `Hooks: <Event>:<matched> [<command>] finished with status N (Nms)` for command hooks on tool events, `UserPromptSubmit`, `SessionStart`, `Stop` (v2.1.296) — [Hooks reference](https://code.claude.com/docs/en/hooks)
- Hook output containing `<system-reminder>` tags is escaped (2.1.292); text resembling a plugin hint tag no longer altered (2.1.296) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- `WorktreeCreate`/`WorktreeRemove` plugin hooks now run under `--worktree` (2.1.300, "not yet with `--tmux`"); quitting no longer removes a `WorktreeCreate`-made worktree that may hold unpushed commits without asking (2.1.301) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- `SessionEnd` hooks now run when exiting while a background command is still running (2.1.300); exit force-kills background commands 1.5s after being asked to stop — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)

Mod (hooks-module) events and `$` API added or changed in range:
- New events: `prompt.autocomplete` (2.1.292), `prompt.mention` (v2.1.290), `prompt.change` (2.1.300), `ui.fault` (v2.1.289); `agent.spawn` now fires for teammates (2.1.289), workflow agents (2.1.292) and resumes with `resume` field (2.1.299); `turn.start` fires for subagent/teammate turns with `e.agentId` (2.1.299); `session.append` gained a `queue` door (2.1.299); `skill.prompt` gained `e.source`, `e.pluginName`, `e.path`, `e.frontmatter`, `e.frontmatterProblem` (v2.1.299); `tool.check` gained `e.agentId`, `e.ceiling` (v2.1.290); `turn.step` result gained `serverToolUses` (2.1.290) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md); [Mods reference](https://code.claude.com/docs/en/plugins/mods/reference)
- Full current mod event list: `tool.call`, `tool.check`, `tool.describe`; `prompt.submit`, `prompt.fill`, `prompt.suggest`, `prompt.edit`, `prompt.autocomplete`, `prompt.compose`, `prompt.section`, `prompt.context`, `prompt.attachment`, `prompt.mention`, `skill.prompt`, `attribution.text`; `command.run`, `command.describe`, `config.set`, `config.describe`; `turn.start`, `turn.step`, `turn.complete`; `session.start`, `session.end`, `session.compact`, `session.receive`, `session.send`, `session.append`, `session.attach`, `session.detach`, `session.measure`; `agent.offer`, `agent.spawn`; `ui.render`, `ui.resolve`, `ui.press`, `ui.input`, `ui.select`, `ui.focus`, `ui.scroll`, `ui.close`, `ui.message`, `ui.fault`; `plugin.register`, `engine.create`; `telemetry.log`, `telemetry.mark`; `classic.<Event>` for every settings hook; and every `$` method as an event — [Mods reference](https://code.claude.com/docs/en/plugins/mods/reference)
- New `$` methods: `$.ui.selection()` (2.1.288), `$.ui.notify` (2.1.295), `$.ui.view({ agentId })` (2.1.300), `$.prompt.media` and `$.session.identity()` (2.1.299, managed-settings mods only), `isDeferred` on `$.tool.register` (2.1.293), prompt caching in `$.model.complete` (2.1.292), `$.agent.list()` statuses `idle`/`waiting` (v2.1.289), `$.env.set` resolves `{}` or `{ deny }` (2.1.301) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md); [Mods reference](https://code.claude.com/docs/en/plugins/mods/reference)
- Current `$` namespaces: `$.plugin`, `$.ui` (`resolve`, `invalidate`, `open`, `close`, `panes`, `focus`, `scroll`, `toast`, `status`, `log`, `notice`, `ask`, `copy`, `selection`, `blit`), `$.command`, `$.tool`, `$.agent`, `$.model` (`complete`, `fork`, `classify`), `$.prompt` (`submit`, `read`, `fill`, `suggest`, `compose`), `$.turn`, `$.session` (`messages`, `cwd`, `root`, `model`, `turns`, `id`, `repo`, `surfaces`, `usage`, `version`, `compact`, `send`, `append`, `authorize`), `$.config`, `$.settings`, `$.env`, `$.fs`, `$.store`, `$.state`, `$.clock`, `$.http`, `$.process`, `$.mcp`, `$.audio`, `$.telemetry` — [Mods reference](https://code.claude.com/docs/en/plugins/mods/reference)
- UI element additions: `Text` `size`/`weight`/`mono`/`tabular` and `Box` spacing steps `xs`..`xl` (v2.1.299; `bold` deprecated → `weight`), `Text` `dir` (2.1.300), `Button` children (2.1.295), `Input` `rows` (2.1.301), `virtualText` prompt decoration (2.1.300). On an earlier release a tree using `weight`/steps does not draw; Claude Code draws its own version of the site — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md); [Mods reference](https://code.claude.com/docs/en/plugins/mods/reference)
- `.catch` semantics: `next.error.kind` `re-entry` (v2.1.292), `next.error.cause` `lent` (v2.1.292) / `rewritten` (v2.1.300); as of 2.1.301 `.catch` runs only on throw/timeout — [Mods reference](https://code.claude.com/docs/en/plugins/mods/reference); [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)

### Inferences
- A plugin that ships both `hooks/hooks.json` command hooks and a hooks module can now attribute a permission `ask` to itself (2.1.301), guard against its own hook failing open with `onFailure: "block"` (2.1.295), and read `agent_id`/`agent_type` on virtually every event to distinguish worker turns from the main loop.
- A `PreToolUse` hook that returns `updatedInput` with extra/invented keys (e.g. to pass hints) will silently lose those keys from 2.1.300.

### Gaps
- The hooks docs page is ~270K characters; the portion covering `PreCompact`/`PostCompact`, `Elicitation`, `PreModelSwitch`/`PostModelSwitch`, `WorktreeCreate`/`WorktreeRemove`, `SessionEnd` input and the "Hooks in skills and agents" section was not read in full. No CHANGELOG entry in range changes those events' payloads, so they are presumed unchanged since 2.1.287, but this was not verified against the page.

---

## Key Question 2: What new plugin manifest fields, skill/agent frontmatter fields, or userConfig option types exist?

### Takeaway
No new `plugin.json` top-level fields or `userConfig` `type` values were introduced in 2.1.288–2.1.302 per the CHANGELOG; the manifest reference now documents `termsOfServiceUrl`, `experimental.{themes,monitors,evals}`, `workflows`, `channels`, `types`, `defaultEnabled`, `dependencies`, `displayName`, `metadata`, `$schema` but none carries a ≥2.1.288 version note. The one new frontmatter field is `autoCompactWindow` on subagents (2.1.296); the Agent tool gained an `effort` parameter (2.1.292). Skill/agent/plugin `name` limits and refused characters were tightened (2.1.292, 2.1.299).

### Cited Findings
- Manifest top-level fields (current): `$schema`, `name`, `displayName`, `version`, `description`, `author`, `homepage`, `repository`, `license`, `keywords`, `metadata`, `icon`, `documentationUrl`, `supportUrl`, `privacyPolicyUrl`, `termsOfServiceUrl`, `defaultEnabled`, `dependencies`, `settings` (only `agent` and `subagentStatusLine` take effect), `userConfig`, `types`, `channels`, `skills`, `commands`, `agents`, `hooks`, `mcpServers`, `lspServers`, `outputStyles`, `workflows`, `experimental` (`themes`, `monitors`, `evals`) — [Manifest reference](https://code.claude.com/docs/en/plugins-reference)
- `userConfig` option fields: `type` (`string`, `number`, `boolean`, `directory`, `file`), `title`, `description`, `required`, `default`, `options` (v2.1.271+), `multiple`, `sensitive`, `min`/`max`; `/config` rows require v2.1.269+ — [Manifest reference](https://code.claude.com/docs/en/plugins-reference)
- Value reach: `${user_config.KEY}` substitutes in MCP server config, LSP server config, exec-form hook `args`, skill and agent content (non-sensitive only); `CLAUDE_PLUGIN_OPTION_<KEY>` exported to hook processes; shell-form hook commands, monitor commands and MCP `headersHelper` reject `${user_config.*}` — [Manifest reference](https://code.claude.com/docs/en/plugins-reference)
- Directory listing fields (`icon`, `documentationUrl`, `supportUrl`, `privacyPolicyUrl`, `termsOfServiceUrl`): accepted by `claude plugin validate` without warning on v2.1.281+; reported as unknown in a marketplace entry — [Manifest reference](https://code.claude.com/docs/en/plugins-reference)
- `claude plugin validate` reserved-name check: names starting with `claude-`, `anthropic-`, `anthropics-`, `cc-plugin-`, or equal to `claude`, `anthropic`, `anthropics`, `claude-code`, `claude-mods`, or combining `official` with `claude`/`anthropic` → error; `claude`/`anthropic` as a whole word elsewhere → warning — [Manifest reference](https://code.claude.com/docs/en/plugins-reference)
- LSP server config `requestTimeout` (default `60000`): "Requires v2.1.288 or later" — [Manifest reference](https://code.claude.com/docs/en/plugins-reference)
- `bin/` standard layout: "Files here are on the Bash tool's `PATH` while the plugin is enabled... claude.ai and Cowork don't install a plugin that has this directory" — [Manifest reference](https://code.claude.com/docs/en/plugins-reference); PowerShell now also finds plugin `bin/` commands (2.1.302) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- A `CLAUDE.md` at the plugin root isn't loaded and `claude plugin validate` warns about it — [Manifest reference](https://code.claude.com/docs/en/plugins-reference)
- Mod manifest: `hooks/hooks.json` `modules` array; `types` key optional when the contract is at `./types/index.d.ts` (2.1.299 validate fix) — [Mods reference](https://code.claude.com/docs/en/plugins/mods/reference); [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Subagent frontmatter (current): `name` (≤256 chars, no `:`), `description`, `tools`, `disallowedTools`, `model` (`sonnet`, `opus`, `haiku`, `fable`, full ID, `inherit`), `permissionMode` (`default`, `acceptEdits`, `auto`, `dontAsk`, `bypassPermissions`, `plan`, `manual`), `maxTurns`, `autoCompactWindow` (integer 100000–1000000, v2.1.296+), `skills`, `mcpServers`, `hooks`, `memory` (`user`/`project`/`local`), `background`, `omitClaudeMd` (v2.1.271+), `effort` (`low`..`max`), `isolation` (`worktree`), `color`, `initialPrompt`, `experimental.cacheTtl` (`5m`/`1h`, v2.1.248+). `permissionMode`, `mcpServers`, `hooks`, `initialPrompt` are "Ignored for plugin subagents" — [Sub-agents docs](https://code.claude.com/docs/en/sub-agents)
- Agent `tools:` MCP scoping changed in 2.1.299: "take only the named MCP server's tools; list a server whose name contains `__` as `mcp__<whole name>__*`" — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Subagents preload at most 32 skills from `skills` (2.1.295) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- `--debug` names unrecognized agent frontmatter fields with typo hints (2.1.296) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Agent tool parameters: `subagent_type` (incl. `"fork"`), `model`, `effort` (v2.1.292+; overrides frontmatter `effort`, not `CLAUDE_CODE_EFFORT_LEVEL`), `name`, `isolation`, `run_in_background` — [Sub-agents docs](https://code.claude.com/docs/en/sub-agents)
- SKILL.md frontmatter (current): `name`, `description`, `when_to_use`, `argument-hint`, `arguments`, `disable-model-invocation`, `user-invocable`, `allowed-tools`, `disallowed-tools`, `model`, `effort` (`low`..`max`), `context` (`fork`), `agent`, `background` (v2.1.218+), `hooks` (incl. `once`), `paths`, `shell` (`bash`/`powershell`), `metadata`, `license`, `compatibility` — [Skills docs](https://code.claude.com/docs/en/skills)
- Skill substitutions: `$ARGUMENTS`, `$ARGUMENTS[N]`/`$N`, `$name`, `${CLAUDE_SESSION_ID}`, `${CLAUDE_EFFORT}`, `${CLAUDE_SKILL_DIR}`, `${CLAUDE_PROJECT_DIR}`, `${CLAUDE_PLUGIN_ROOT}`, `${CLAUDE_PLUGIN_DATA}` — [Skills docs](https://code.claude.com/docs/en/skills)
- Skill/command name refusals (2.1.299): hidden/direction-changing/blank-like characters, `<`, `>` in file or folder name → not offered until renamed; such a `name:` ignored. Reserved: `synced` folder; `anthropic-skills` / `anthropic-skills:` prefix outside a plugin — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md); [Skills docs](https://code.claude.com/docs/en/skills)
- Name length: agent names ≤256 chars; a skill's or plugin file's `name` longer than that is ignored (2.1.292); skill/command argument names: only first 64, each ≤64 chars, filled in (2.1.301) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Skills listing now shows both folder name and frontmatter `name` when they differ (2.1.290) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- `!` shell blocks in skills/commands refuse raw control characters other than tab/newline (2.1.290); CRLF multi-line `!` blocks fixed on Windows (2.1.290) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Output styles: no changes in range; `/output-style` now asks a plugin's `config.set` hook before saving (2.1.295) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Status line payload: `agentType` added to `subagentStatusLine` task fields (v2.1.293+); main payload unchanged in range (`rate_limits.spend_limit.*` v2.1.251/2.1.284, `prompt_cache` v2.1.251, `exceeds_200k_tokens`, `fast_mode`, `effort.level`, `thinking.enabled`, `session_name`, `prompt_id`) — [Status line docs](https://code.claude.com/docs/en/statusline)

### Inferences
- Because `permissionMode`, `mcpServers` and `hooks` are ignored for *plugin* subagents, a plugin that wants per-agent hooks must keep wiring them in `hooks/hooks.json` with `agent_type` matching, not in `agents/*.md`.

### Gaps
- The sub-agents page was truncated at 100K chars; the full Agent tool parameter table and the `CLAUDE_CODE_FORK_SUBAGENT` doc note were not seen on the page (the env var is attested only in the 2.1.302 CHANGELOG entry).

---

## Key Question 3: What new CLI commands/flags exist for plugin authors?

### Takeaway
New in range: `claude plugin install --marketplace <source>` (2.1.292), `claude plugin eval --disallow-tools` + case field `disallowed_tools` (2.1.299), `claude plugin validate --json` `gatingHooks` (2.1.290), README install-line advice in `validate` (2.1.295), `claude plugin list --json` `readFromFolder`/`folderVersion` (2.1.289), and `claude attach/logs <name>` (2.1.290). `claude plugin configure`, `init`, `tag`, `details`, `prune`, `eval init` exist in the docs but carry no ≥2.1.288 version gate. `claude project purge` was renamed `claude purge` (2.1.288).

### Cited Findings
- `claude plugin install --marketplace <source>`: "Install `<plugin>`, given by its bare name, from the marketplace at `<source>`, adding the marketplace first... Requires Claude Code v2.1.292 or later" — [Plugin CLI reference](https://code.claude.com/docs/en/plugins/cli-reference)
- `plugin install` other flags: `--accept-command <sha256>` (v2.1.271+), `--json` (v2.1.268+); non-TTY without `-y`/`--accept-command` refuses the install (exit 1) — [Plugin CLI reference](https://code.claude.com/docs/en/plugins/cli-reference)
- `plugin uninstall --keep-data`, `--json` (`failureCode: "settings_still_on"` v2.1.282+, `savedKept`, `keptData`) — [Plugin CLI reference](https://code.claude.com/docs/en/plugins/cli-reference)
- `plugin enable`/`disable --json` (`failureCode: "already_in_goal_state"`, `alreadyInGoalState: true`) — [Plugin CLI reference](https://code.claude.com/docs/en/plugins/cli-reference)
- `plugin update -y`, `--accept-command`, `--json` — [Plugin CLI reference](https://code.claude.com/docs/en/plugins/cli-reference)
- `plugin list --json`, `--available`, `--data-size [plugin]` (v2.1.285+); JSON fields incl. `readFromFolder` and `folderVersion` (v2.1.289+) — [Plugin CLI reference](https://code.claude.com/docs/en/plugins/cli-reference)
- `plugin details <name>` — [Plugin CLI reference](https://code.claude.com/docs/en/plugins/cli-reference)
- `plugin configure <plugin>` (qualified `name@marketplace` only; `--json`; `--values-stdin < values.json`; prints `Configuration saved. Restart Claude Code to apply it.`; never prints sensitive values) — [Plugin CLI reference](https://code.claude.com/docs/en/plugins/cli-reference)
- `plugin prune` — [Plugin CLI reference](https://code.claude.com/docs/en/plugins/cli-reference)
- `plugin eval` flags: `--judge-model <model>`, `--threshold <0..1>` (default `1.0`), `--allow-tools <tools...>`, `--eval-dir <dir>`, `--json [path]`, `--tag`; put the target before `--tag`, `--allow-tools`, `--json`; `--disallow-tools` and `disallowed_tools` case field added 2.1.299; a run ending on an API error scores 0 and exits 1 (2.1.299) — [Plugin CLI reference](https://code.claude.com/docs/en/plugins/cli-reference); [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- `plugin eval init` with `--eval-dir` — [Plugin CLI reference](https://code.claude.com/docs/en/plugins/cli-reference)
- `plugin tag [path] [options]` (`--push`, `--dry-run`, `--force`/`-f`); `/plugin tag` in-session equivalent — [Plugin CLI reference](https://code.claude.com/docs/en/plugins/cli-reference)
- `plugin init <name> [options]` e.g. `--with skills hooks` — [Plugin CLI reference](https://code.claude.com/docs/en/plugins/cli-reference)
- `plugin test [directory]`: runs `.test.ts`/`.test.tsx`; 5s per test unless `timeoutMs`; now fails on a failed `expect` in a registered hook or a refused stub (2.1.292), on `session.append` removing kept blocks (2.1.295), on a served `$` method not answering in 10s (2.1.299); `mock.session` added (2.1.293); `ui.render` roots carry `part: { plugin }` (2.1.299) — [Mods reference](https://code.claude.com/docs/en/plugins/mods/reference); [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- `plugin validate`: `--strict`, `--json` (v2.1.259+); exit `0`/`1`/`2`; `--json` top-level includes `gatingHooks` (v2.1.290+) listing `module`, `pattern`, `hook`, `hasCatch`; README install-line advice never changes exit code (2.1.295); names a mod's hooks skipped under org management (2.1.299); warns when a shell-form hook leaves `${CLAUDE_PLUGIN_ROOT}` unquoted unless `shell` is `"powershell"` — [Plugin CLI reference](https://code.claude.com/docs/en/plugins/cli-reference); [Manifest reference](https://code.claude.com/docs/en/plugins-reference); [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- `plugin marketplace add/list/remove/update` all take `--json` (v2.1.287+); `marketplace update` without a name refuses `--json` — [Plugin CLI reference](https://code.claude.com/docs/en/plugins/cli-reference)
- `/plugin install <plugin> --marketplace <source>` in-session (v2.1.275+); `/plugin configure <plugin>` — [Plugin CLI reference](https://code.claude.com/docs/en/plugins/cli-reference)
- Session-only plugins: `--plugin-dir` (directory, `.zip`, or folder of plugins v2.1.265+), `--plugin-url`; `claude --plugin-dir ./my-plugin plugin list` shows `<name>@inline` with `scope` `session`; `CLAUDE_CODE_PLUGIN_DIRS` env and `CLAUDE_CODE_PLUGIN_DIR_WATCH=1`; `disableSideloadFlags` managed setting rejects both flags — [Plugin CLI reference](https://code.claude.com/docs/en/plugins/cli-reference); [Mods reference](https://code.claude.com/docs/en/plugins/mods/reference)
- `claude purge [path]` replaces `claude project purge` (2.1.288; old name prints a notice) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md); [CLI reference](https://code.claude.com/docs/en/cli-reference)
- `claude attach <id|name>`, `claude logs <id|name>`: name fragment "requires Claude Code v2.1.290 or later" — [CLI reference](https://code.claude.com/docs/en/cli-reference)
- `claude --advisor <model>`, `--restricted` (v2.1.248+), `--safe-mode`, `--bare`, `--agents` (file form with `--print` v2.1.281+), `--permission-prompts none` (v2.1.259+), `--worktree`/`-w`, `--tmux` — [CLI reference](https://code.claude.com/docs/en/cli-reference)
- **Removed**: `--sandbox`/`--no-sandbox` on `claude remote-control` (2.1.300; now error); `--enable-auto-mode` (removed v2.1.111, listed for completeness) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md); [CLI reference](https://code.claude.com/docs/en/cli-reference)
- No `claude plugin publish` subcommand appears in the CLI reference or CHANGELOG; directory submission is documented as a web flow ("submit the plugin" link on the manifest page) — [Manifest reference](https://code.claude.com/docs/en/plugins-reference); [Plugin CLI reference](https://code.claude.com/docs/en/plugins/cli-reference)

### Inferences
- `claude plugin configure --values-stdin` plus `--json` is the scriptable path for CI to set non-sensitive `userConfig`; sensitive values can be set but never read back.

### Gaps
- Exit-code table for `plugin eval` (beyond `0`/`1`) was in the persisted docs output but not extracted here.

---

## Key Question 4: Any new distribution mechanisms (plugin directory, claude.ai sync, org-managed plugins)?

### Takeaway
No new distribution channel launched in range; the existing four (marketplaces, claude.ai sync of skills/plugins, org-managed/managed-settings plugins, Anthropic's directory) all received reliability and policy fixes. Notable: claude.ai-synced plugins/skills got several sync-race fixes (2.1.293, 2.1.295, 2.1.296, 2.1.299), marketplace `--marketplace` one-step install (2.1.292), HTTPS fallback for SSH-less GitHub installs (2.1.288 macOS/Linux, 2.1.296 Windows), reftable fixes (2.1.302), and the Claude Tag admin UI gained a "Skills and plugins" tab (2.1.302).

### Cited Findings
- claude.ai sync: skill sync checks ~every 10 minutes active, ~40 minutes idle (changed 2.1.293); `syncClaudeAiSkills: false` opts out; `CLAUDE_CODE_SYNC_SKILLS=1` for non-interactive; synced skills live in `~/.claude/skills/synced/`; not synced in API-key sessions, bare mode, `--safe-mode`, or with `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC`; terminal syncing requires v2.1.273+ — [Skills docs](https://code.claude.com/docs/en/skills); [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Synced-plugin fixes: hooks failing "Plugin directory does not exist" after another session synced an update (2.1.295); never-finishing installs when sessions share a config dir, and plugin disabled when its marketplace dependency was also synced (2.1.296); spurious "synced[0] commands path not found" (2.1.299); Cowork cloud sessions staying on an old account plugin (2.1.299) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Anthropic directory: `plugin.json` listing fields `icon`, `documentationUrl`, `supportUrl`, `privacyPolicyUrl`, `termsOfServiceUrl`; "claude.ai and Cowork don't install a plugin that has [a `bin/`] directory" — [Manifest reference](https://code.claude.com/docs/en/plugins-reference)
- Org-managed: `prependPlugins`/`appendPlugins`, `allowManagedModsOnly`, `allowModsToOverrideDenyRules`, `allowManagedHooksOnly`, `disableAllHooks`, `disableSideloadFlags`, `pluginConfigs`; built-in guard `sec-default@builtin` (`cc-plugin-sec-default`) loads ahead of user mods on managed machines or Team/Enterprise sign-ins — [Mods reference](https://code.claude.com/docs/en/plugins/mods/reference)
- Org-vs-user mod precedence fixes: a user-installed mod that could unload or bypass an organization's plugin/guard is now the one unloaded (2.1.290, 2.1.292); tampered managed-settings cache fixes (2.1.292, 2.1.295); "Improved enforcement of managed permission rules, managed hooks and organization MCP tool names against user-installed mods" (2.1.299); `/plugin` and `validate` name a mod's hooks skipped under org management (2.1.299) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Marketplaces: `--marketplace` one-step install (2.1.292); `marketplace add` refuses names no plugin can install under and `constructor`-like names (2.1.295, 2.1.296); large-submodule marketplaces fetch only plugin-holding submodules (2.1.295); `/plugin` Errors tab no longer removes a failed marketplace without asking (2.1.295); warning when install/enable/disable/marketplace add writes to a settings file that does not load (2.1.295); steps shown for a marketplace name resembling an official Anthropic one (2.1.292); reftable re-clone/"unknown" version fix (2.1.302) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Plugin `version` pinning does not apply to `command`-source plugins, claude.ai-hosted marketplaces, or in-place local-path marketplaces — [Manifest reference](https://code.claude.com/docs/en/plugins-reference)
- Claude Tag admin settings reorganized into Bundles, Connectors, Skills and plugins, Channels tabs (2.1.302); Slack plugin confirmation card shows name not ID (2.1.296) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Startup with many plugins: command and agent files take far fewer FS calls (2.1.302) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)

### Inferences
- Nothing in range changes the plugin-directory source rules this repo already follows; the `bin/` exclusion on claude.ai/Cowork is the one layout rule worth re-checking before any distribution that adds executables.

### Gaps
- No primary source in range states directory review-policy changes; the directory's own submission rules were not re-fetched.

---

## Key Question 5: Anything about plugins on Claude Desktop, Claude Code on the web, or Remote Control that changes what a plugin can do there?

### Takeaway
Desktop: the gateway `code` policy key (2.1.296) and managed-settings application in the Code tab (2.1.300) bring Desktop under org policy; `/plugin` in Desktop's Code tab now explains where to manage plugins (2.1.290); fork subagents on by default and subagents always background in Desktop/VS Code (2.1.302). Cloud (Claude Code on the web/Cowork): `PermissionRequest` hooks lose the ability to approve shell commands/subagents in auto mode and `setMode` is ignored (2.1.299, 2.1.300); account plugins now refresh correctly (2.1.299). Mods: VS Code renders mods from extension 2.1.299; mods reference says entries cover CLI and Desktop as of v2.1.290.

### Cited Findings
- Desktop: `code` key in gateway `managed.policies[]` applied in Claude Desktop's Code tab (2.1.296); Desktop Code tab applies managed settings when `forceLoginGatewayUrl` names an Anthropic-operated gateway (2.1.300); `CLAUDE_CODE_ATTRIBUTION_HEADER=0` in a gateway `code` policy's `env` turns off the attribution block (2.1.299) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Desktop: `/plugin` reply in the desktop app's Code tab now says where to install/manage plugins there (2.1.290); subagents in Desktop's Code tab now get tools of a user MCP server named `memory` (2.1.288); desktop no longer points to claude.ai settings or `/mcp` for MCP auth where unavailable (2.1.302) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Desktop/VS Code: fork subagents on by default (`CLAUDE_CODE_FORK_SUBAGENT=0` to disable); main conversation's subagents always run in background (2.1.302) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Mods surfaces: "Entries cover the Claude Code CLI and the Desktop app as of v2.1.290, and the VS Code extension as of v2.1.299"; render-site table lists Terminal/Desktop/VS Code per site; VS Code ignores `Box` `position`/`hover`, `Text` `size`/`mono`/`tabular`, `Button` `hotkey`/`plain`/`autoFocus`/`action`, `Code` styling; `Client` not rendered in VS Code; `Raster`/`Image` terminal only; `Svg` Desktop/VS Code only — [Mods reference](https://code.claude.com/docs/en/plugins/mods/reference)
- `$.ui.open` no longer reports a pane as placed where no surface draws it (VS Code, `claude -p`) (2.1.299); `$.model.fork` works before first response in `claude -p`/cloud (2.1.301); mod `$.ui.notify` routes through the user's notification setting (2.1.295) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Cloud/Cowork: auto mode `PermissionRequest` hook can no longer approve shell commands or subagents (2.1.299); `setMode` in a hook's allow ignored (2.1.300); a mod's `session.receive` asking for permission no longer hangs cloud sessions (2.1.295); old account plugin after reload/restart fixed; running an old version after change from another device fixed (2.1.299); Edit/Retry failing while `UserPromptSubmit`/`prompt.submit` hooks ran fixed (2.1.299, regression in 2.1.296); first turn no longer waits for stdio MCP server with `alwaysLoad: false` (2.1.288) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Cloud: built-in `gh api` in sessions whose image lacks the GitHub CLI (2.1.288); `GH_HOST`/`GH_REPO` other than github.com refused (2.1.290); cloud session MCP connectors negotiate protocol 2026-07-28 (2.1.299); MCP proxy redirects no longer followed (2.1.299) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Remote Control: `--sandbox`/`--no-sandbox` removed from `claude remote-control` (2.1.300); servers retry connection renewal after keychain errors (2.1.300); diff-view fix requires v2.1.296+ on the machine (2.1.300); `PushNotification` fixes in `claude remote-control` sessions (2.1.293, 2.1.295); subagent pane spins "Remote Control is disconnected" when offline (2.1.302) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Headless/SDK: `claude -p` with no permission mode starts in `default` on third-party providers/telemetry-off/fresh install (2.1.302); `claude -p` text output prints each turn's response as it ends (2.1.295); a stderr line says what `-p` is waiting for (2.1.295); `--tools`/`--restricted` apply to late-registering built-in tools (2.1.295); `claude -p` lists invalid settings entries on stderr (2.1.299) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Status line still Claude Code-only; `subagentStatusLine` can ship as a plugin `settings.json` default but "plugin values don't run under `allowManagedHooksOnly`" — [Status line docs](https://code.claude.com/docs/en/statusline)

### Inferences
- A plugin hook that relied on `PermissionRequest` → `allow` to auto-approve Bash in Cowork cloud auto mode no longer works from 2.1.299; equivalent approvals must come from permission rules or auto-mode config.
- A mod drawn for the terminal should be tested in VS Code (2.1.299+) with the ignored-prop list in mind; `Client` elements will not render there at all.

### Gaps
- No source in range states whether Claude Desktop's Code tab runs `hooks/hooks.json` command hooks identically to the CLI; the mods reference only says mods render on Desktop.

---

## Key Question 6: Which previously documented behaviours were removed or renamed?

### Takeaway
Three hard removals/renames and several behaviour reversals: `claude project purge` → `claude purge` (2.1.288); `claude remote-control --sandbox/--no-sandbox` removed (2.1.300); mod `Text` `bold` deprecated in favor of `weight` (2.1.299); MCP permission-rule prefix matching narrowed (2.1.299); agent `tools:` MCP matching narrowed (2.1.299); `UserPromptSubmit` ordering relative to skill expansion changed (2.1.299); reversions of 2.1.281 auto-mode denial wording and 2.1.290 cloud `/loop` wakeup notice (2.1.293).

### Cited Findings
- Renamed: `claude project purge` → `claude purge`; "the old name still works and prints a notice" (2.1.288) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Removed: `--sandbox` and `--no-sandbox` from `claude remote-control`; "passing either now exits with an error. Set `sandbox.enabled` in settings" (2.1.300) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Deprecated: mod `Text` `bold` → `weight` ("`bold` on a `Text` is deprecated in favor of `weight` and still works"; `weight: 'semibold'` is the equivalent on v2.1.299+) — [Mods reference](https://code.claude.com/docs/en/plugins/mods/reference)
- Narrowed: "MCP allow rules to reach only the server they name: `mcp__a` no longer allows a server named `a__b` or `a_`; write `mcp__<server>__*`" (2.1.299) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Narrowed: "agent `tools:` lists to take only the named MCP server's tools; list a server whose name contains `__` as `mcp__<whole name>__*`" (2.1.299) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Reordered: `UserPromptSubmit` hooks run before skill/slash-command expansion; a skill's own frontmatter `UserPromptSubmit` hook first runs on the following prompt (2.1.299) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed default: `claude -p`/SDK start in `default` permission mode on third-party providers, telemetry-off, fresh install (2.1.302) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed default: fork subagents on by default in `-p`, SDK, desktop, VS Code (2.1.302) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed default: stdio MCP (2.1.292), claude.ai connectors (2.1.295), cloud/Remote Control connectors (2.1.299) negotiate MCP protocol version 2026-07-28; `MCP_PROTOCOL_NEGOTIATION=legacy` opts out — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Changed limits: MCP tool descriptions sent up front and server instructions 2,048 → 4,096 chars (2.1.296); via tool search 2,048 → 16,384 (2.1.295); Anthropic first-party servers uncut (2.1.299) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Reverted: the 2.1.281 auto-mode denial message change; the 2.1.290 cloud-session `/loop` wakeup-loss notice (both 2.1.293) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Reverted: a 2.1.288 `claude auth status` change in VS Code (2.1.289) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Semantics: plugin-hook-blockable actions are refused, not let through, when the hook can't be handed them or can't answer (2.1.299); `updatedInput` validated with unknown keys dropped (2.1.300); `.catch` runs only on throw/timeout (2.1.301); at most 12 prompt/agent hooks of one event concurrently (2.1.302) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Settings scope narrowed: Claude in Chrome can't be enabled from project settings (2.1.290); `CLAUDE_CODE_DISABLE_ATTACHMENTS` can't be set from `.claude/settings*.json` (2.1.290) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Bash permission tightening: `pyright` no longer read-only; more `ps` forms ask (2.1.290) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Model routing: Haiku 5.5 default Haiku (2.1.293); `fable`/`best` alias retries on previous Fable model (2.1.301); `CLAUDE_CODE_AUTO_MODE_MODEL` (2.1.302); `CLAUDE_CODE_WORKFLOW_SUBAGENT_MODEL` (2.1.296); client-side auto-mode classifier ignores an `ANTHROPIC_DEFAULT_SONNET_MODEL` pin naming Sonnet 5.5/Opus 5.5 (2.1.288); background requests behind a gateway use Haiku 4.5 (2.1.295) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Compaction/memory: idle compaction (2.1.299, `/config` row 2.1.302); `/autocompact` per model (2.1.288); `/reload-skills` re-sends full skill list after compaction (2.1.299); skills listed again after `/rewind` (2.1.301) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- CLAUDE.md/AGENTS.md loading: nested CLAUDE.md and `.claude/rules` load on Write/Edit (2.1.288) and on single-file `cat`/`head`/`tail`/`sed -n`/`grep` (2.1.293); subdirectory `AGENTS.md` attached on @-mention (2.1.290); symlinked-outside CLAUDE.md/AGENTS.md/rules no longer load under `blockReadsOutsideWorkingDirectories`/Read deny (2.1.290) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Keybindings: agents-view Ctrl+F / Alt+↑/↓ / rename rebindable in `keybindings.json` (2.1.288); `" "` no longer an error, `"ctrl+ k"` warns (2.1.293); mod `Button` `action` can name a keybinding action — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md); [Mods reference](https://code.claude.com/docs/en/plugins/mods/reference)
- Monitor tool: sandboxed `Monitor` commands now follow permission rules under sandbox auto-allow (2.1.290) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Worktrees: plugin `WorktreeCreate`/`WorktreeRemove` under `--worktree` (2.1.300); unpushed-commit guard on quit (2.1.301); git 2.56 stray `.git` file fix (2.1.302); reftable fixes (2.1.299, 2.1.300); awk guard (2.1.299); subagent worktree access after main-session worktree switch (2.1.290) — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md)
- Rate limit / usage: `/usage` warnings for max effort, workflows, always-on context, large tool results (2.1.299); over-100% display fixed (2.1.299); headless `rate_limit_event` says whether extra usage is on (2.1.295); `CLAUDE_CODE_RETRY_WATCHDOG_MAX_WAIT_MS` (2.1.295) and `_MAX_USAGE_LIMIT_WAIT_MS` (2.1.301); `$.session.usage()` returns `{ startedAt, context, rateLimits, cost }` with `rateLimits` as `{ kind, percentUsed, resetsAt }` — [CHANGELOG](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md); [Mods reference](https://code.claude.com/docs/en/plugins/mods/reference)

### Inferences
- The two 2.1.299 MCP-name scoping changes are the most likely silent breakages for an existing plugin: any `permissions.allow` entry written as a bare `mcp__github` prefix, or an `agents/*.md` `tools:` line naming a server that is a prefix of another server's name, now matches less than before.

### Gaps
- No deprecation of `hooks/hooks.json` settings hooks, output styles, or the statusline command was found in range; absence is reported from the CHANGELOG and the current docs, not from an explicit "not deprecated" statement.
