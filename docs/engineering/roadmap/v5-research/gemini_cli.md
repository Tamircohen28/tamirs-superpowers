# Google Gemini CLI extensibility surface (as of 2026-10-17, latest stable v0.64.0)

**Read this first — platform status caveat.** Every official geminicli.com doc page fetched for this research now carries a banner stating that "Gemini CLI was replaced by Antigravity CLI on June 18th, 2026" for unpaid-tier and Google One users, and that "Gemini CLI has not been optimized for Gemini 4 Argon" — [geminicli.com changelog](https://geminicli.com/docs/changelogs/); [hooks doc](https://geminicli.com/docs/hooks/); [IDE doc](https://geminicli.com/docs/ide-integration/). Google's own post (May 19, 2026) says that on June 18, 2026 Gemini CLI and the Gemini Code Assist IDE extensions "will stop serving requests" for Google AI Pro/Ultra subscribers and free individual Code Assist users; enterprise customers with Gemini Code Assist Standard/Enterprise licenses keep access unchanged, and Gemini CLI "remains available" via paid Gemini API keys and Gemini Enterprise Agent Platform API keys — [Google Developers Blog: Transitioning Gemini CLI to Antigravity CLI](https://developers.googleblog.com/en/an-important-update-transitioning-gemini-cli-to-antigravity-cli/). The open-source repo nonetheless kept shipping weekly stable releases through v0.64.0 (Oct 13, 2026), with v0.65.0-preview.0 and nightlies continuing — [GitHub Releases](https://github.com/google-gemini/gemini-cli/releases). An extension author targeting "Gemini CLI" today is therefore targeting (a) enterprise/API-key users of the OSS CLI and (b) Antigravity CLI (`agy`), which imports Gemini extensions as "plugins" — see the final section.

---

## Key question 1: What shipped in 0.60, 0.61, 0.62, 0.63, 0.64, and which items matter to an extension author?

### Takeaway
0.60–0.64 (Sep 15 – Oct 13, 2026) were almost entirely security-hardening and stability releases: no new extension manifest fields, hook events, skill features or agent formats landed in this window. The items an extension author must know are the 0.60.0 consent prompt for extension-driven environment changes plus sanitization of runtime-altering env vars, the 0.60.0 extension-loader path hardening, the 0.60.0/0.62.0 MCP OAuth changes (RFC 9207 `iss` enforcement; refresh-token preservation), and 0.63.0's autonomous plan execution in non-interactive mode.

### Cited Findings
- **Release cadence/dates (stable):** v0.60.0 — 2026-09-15; v0.61.0 — 2026-09-23; v0.62.0 — 2026-09-29; v0.63.0 — 2026-10-06; v0.64.0 — 2026-10-13 (marked "Latest"); v0.65.0-preview.0 — 2026-10-13; nightlies through v0.66.0-nightly.20261016 — [GitHub Releases](https://github.com/google-gemini/gemini-cli/releases); dates for 0.60/0.61/0.63/0.64 also on the [official changelog](https://geminicli.com/docs/changelogs/).
- The official changelog page has announcement entries for v0.64.0, v0.63.0, v0.61.0 and v0.60.0 but **no v0.62.0 entry**; v0.62.0 does exist on GitHub (published 29 Sep, by gemini-cli-robot) — [changelog](https://geminicli.com/docs/changelogs/); [v0.62.0 release](https://github.com/google-gemini/gemini-cli/releases/tag/v0.62.0).
- The changelog describes three release channels: nightly, preview, stable, with a "Current releases" table linking `/docs/changelogs/preview` and `/docs/changelogs/latest` — [changelog](https://geminicli.com/docs/changelogs/).

**v0.60.0 (2026-09-15)** — [release page](https://github.com/google-gemini/gemini-cli/releases/tag/v0.60.0); [changelog](https://geminicli.com/docs/changelogs/)
- Official headline: "Extension & Tool Safety Hardening: Added user consent prompts for environment changes, sanitized runtime-altering environment variables, and enforced envelope metadata provenance for untrusted tool outputs" (PRs #28863, #29215) and "Sandbox Directory Isolation: Isolated settings and temporary directories inside sandbox containers, including the macOS Seatbelt sandbox" (PRs #29171, #29216).
- Extension-relevant PRs: #28863 "consent prompts for extension environment changes and sanitized runtime-altering environment variables" (@amelidev); #29169 "Hardened path resolution and boundary validation in the extension loader" (@diegogodinezr).
- MCP-relevant: #29117 "Enforced RFC 9207 issuer identification in the MCP OAuth flow"; #29158 removed a hardcoded Google CrUX API key in chrome-devtools-mcp.
- Config-relevant: #29115 "stricter permission and ownership checks on system-wide configuration paths".
- Also: #29120 web-fetch destination validation; #29170 workspace path boundary + symlink resolution in command safety/file discovery; #29116 NTFS 8.3 short-name mitigation.

**v0.61.0 (2026-09-23)** — [release page](https://github.com/google-gemini/gemini-cli/releases/tag/v0.61.0); [changelog](https://geminicli.com/docs/changelogs/)
- Official headline: "Core Security Hardening: Prevented indirect prompt injection via build file modifications and untrusted flags, hardened filesystem boundaries, and isolated runtime state" (#29250, #29214); "Agent Loop and Model Stability: Preserved `AgentLoopContext` state across spread operations and kept explicit versioned Flash model IDs" (#29335, #29252).
- Only 8 PRs; nothing touching extensions, hooks, skills, MCP, policy or plan mode.

**v0.62.0 (2026-09-29)** — [release page](https://github.com/google-gemini/gemini-cli/releases/tag/v0.62.0)
- 19 PRs; MCP: #29341 "Formatted MCP tool call titles as structured signatures and separated explanations (core and ACP)"; OAuth: #29339 "Kept the OAuth refresh token on refresh and made credential deletion idempotent"; ACP: #29439 "Emitted the tool_call update before request_permission in ACP mode"; model update #29443 (title names Gemini 3.8 Flash and 3.5 Flash Lite); PTY/ConPTY lifecycle fixes (#29340, #29379, #29380); VS Code companion focus fix (#29378).
- No extension/hook/skill/agent/policy/plan items.

**v0.63.0 (2026-10-06)** — [release page](https://github.com/google-gemini/gemini-cli/releases/tag/v0.63.0); [changelog](https://geminicli.com/docs/changelogs/)
- Official headline: "Autonomous Plan Execution: Enabled autonomous plan execution in non-interactive mode for unattended agent workflows" (#29539); "Core Stability and Memory Lifecycle: Bounded tool output sizes, optimized memory in long-running agent loops, and prevented infinite authentication loops in headless and supervisor environments" (#29451, #29448).
- Other: #29446 "Separates a missing MCP enablement config from malformed JSON"; #29506 "Aligns policy redirection gates, path validation, and workflow parsing in core"; #29463 ACP session resolution fix; #29542 disables truncation when `maxChars` ≤ 0 in `formatTruncatedToolOutput`; #29468 retry progress indicator.

**v0.64.0 (2026-10-13)** — [release page](https://github.com/google-gemini/gemini-cli/releases); [changelog](https://geminicli.com/docs/changelogs/)
- Official headline: "Atomic Operations & State Persistence: Serialized file tool operations with atomic writes, and added atomic CLI state persistence that recovers from a backup if corruption occurs" (#29499, #29558); "Chat Recording Optimization: ... append-only delta patching and bounded history windowing in `ChatRecordingService`" (#29568); "CLI Interaction & Input Robustness: Fixed `@file:line` references, stopped CPU hangs from `@` in code blocks, and made Ctrl+C emergency aborts reach cancellation handlers" (#29581, #29586).
- Extension-relevant: #29540 "retry directory removal on Windows locking errors during extension updates". Headless: #29528 "propagate resolved folder trust state in headless mode". ACP: #29549 bridges `PromptResponse.usage` and emits `usage_update`; #29580 session-by-exact-id. A2A server: #29450 V1→V2 settings migration.
- Release notes are a flat list of PR titles; none is labelled breaking.

**Where the big features actually arrived (from the changelog's first mention):** subagents v0.12.0 (2025-10-27, "We now have a new built-in subagent"); policy engine v0.18.0 (2025-11-17); Agent Skills v0.23.0 (2026-01-07, "Experimental Agent Skills Support in Preview"); hooks v0.24.0 (2026-01-14, "visual indicators for hook execution") with hooks "enabled by default ... as of v0.26.0+"; themes in extensions v0.28.0 (2026-02-10); Plan mode `/plan` and new extensions management UI/settings v0.29.0 (2026-02-17); browser agent v0.31.0 (2026-02-27); native Git worktrees v0.36.0 (2026-04-01); Antigravity agent runner integration v0.54.0 (2026-08-06); `gemini extensions install` v0.8.0 (2025-09-29); remote agents v0.24.0 — [changelog](https://geminicli.com/docs/changelogs/); hooks default-on version from [Google Developers Blog, Jan 28 2026](https://developers.googleblog.com/en/tailor-gemini-cli-to-your-workflow-with-hooks/).

### Inferences
- Nothing in 0.60–0.64 changes the on-disk format of an extension; a package valid against the current reference docs (which are dated Apr–Jun 2026) remains valid on 0.64.0.
- The 0.60.0 consent prompt for "extension environment changes" means an extension whose `settings[].envVar` or MCP `env` alters the runtime will now trigger a user prompt; authors should expect install-time friction and avoid runtime-altering variables (inferred from PR title; the exact variable list is not in the docs fetched).
- The 0.63.0 "autonomous plan execution in non-interactive mode" matters for CI/GitHub-Action usage of `-p` with plan mode (inferred).

### Gaps
- GitHub API access was blocked in this session (403), so release bodies were read via rendered pages; PR *descriptions* (vs titles) were not read, so the precise semantics of #28863/#29169/#29539 are inferred from titles only.
- The changelog says nothing about which minor versions in 0.60–0.64 changed extension docs; the docs' "last updated" stamps (hooks Apr 13 2026; IDE Jun 18 2026) predate the window.

---

## Key question 2: Does Gemini CLI support hooks? Which events? In what file?

### Takeaway
Yes. Hooks are command-type scripts configured under a `"hooks"` key in `settings.json` (project `.gemini/settings.json`, user `~/.gemini/settings.json`, system `/etc/gemini-cli/settings.json`) or shipped by an extension in `hooks/hooks.json`; eleven events exist, with a stdin/stdout JSON contract and Claude-style exit-code semantics (0 parse JSON, 2 block).

### Cited Findings
- **Events (exact):** `SessionStart`, `SessionEnd`, `BeforeAgent`, `AfterAgent`, `BeforeModel`, `AfterModel`, `BeforeToolSelection`, `BeforeTool`, `AfterTool`, `PreCompress`, `Notification` — [Hooks overview](https://geminicli.com/docs/hooks/).
- **Config locations (highest→lowest precedence):** 1. Project `.gemini/settings.json`; 2. User `~/.gemini/settings.json`; 3. System `/etc/gemini-cli/settings.json`; 4. Extensions — [Hooks overview](https://geminicli.com/docs/hooks/).
- **Extension packaging:** hooks live in `hooks/hooks.json` inside the extension directory; "Note that hooks are not defined in the `gemini-extension.json` manifest." `${extensionPath}`, `${workspacePath}` and `${/}` substitution work inside `hooks/hooks.json` — [Extension reference](https://geminicli.com/docs/extensions/reference.md).
- **JSON shape:** `{"hooks": {"BeforeTool": [{"matcher": "write_file|replace", "hooks": [{"name": "security-check", "type": "command", "command": "$GEMINI_PROJECT_DIR/.gemini/hooks/security.sh", "timeout": 5000}]}]}}` — [Hooks overview](https://geminicli.com/docs/hooks/).
- **Hook fields:** `type` (required; only `"command"`), `command` (required for command type), `name` (optional; used by logs and `/hooks` commands), `timeout` (ms, default `60000`), `description` (optional). Per-group fields: `matcher` (optional), `sequential` (optional; `true` runs in order, `false` in parallel), `hooks` (required array) — [Hooks reference](https://geminicli.com/docs/hooks/reference.md).
- **Matchers:** tool events (`BeforeTool`, `AfterTool`) use a regex against the tool name (e.g. `"write_.*"`); MCP tools are named `mcp_<server_name>_<tool_name>`; lifecycle events use an exact string (e.g. `"startup"`); `"*"` or `""` matches all — [Hooks overview](https://geminicli.com/docs/hooks/); [Hooks reference](https://geminicli.com/docs/hooks/reference.md).
- **Common stdin fields:** `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `timestamp` — [Hooks reference](https://geminicli.com/docs/hooks/reference.md).
- **Common stdout fields:** `systemMessage`, `suppressOutput`, `continue` (false stops the agent loop), `stopReason`, `decision` (`"allow"` | `"deny"`, alias `"block"`), `reason`; plus a `hookSpecificOutput` object with inner keys `additionalContext`, `tool_input`, `tailToolCallRequest`, `llm_request`, `llm_response`, `toolConfig` (`mode`, `allowedFunctionNames`), `clearContext` — [Hooks reference](https://geminicli.com/docs/hooks/reference.md).
- **Exit codes:** `0` success (stdout parsed as JSON; "Preferred for intentional blocks, e.g., `{"decision": "deny"}`"); `2` system block (stderr = rejection reason); other = non-fatal warning. "Stdout must contain only the final JSON object" — plain text causes a parse failure and the CLI defaults to Allow; log to stderr — [Hooks overview](https://geminicli.com/docs/hooks/).
- **Per-event I/O:** `BeforeTool` input `tool_name`, `tool_input`, `mcp_context`, `original_request_name`; `hookSpecificOutput.tool_input` merges/overrides model args; deny → tool error to agent. `AfterTool` input adds `tool_response` (`llmContent`, `returnDisplay`, optional `error`); deny replaces output with `reason`; `tailToolCallRequest` `{name, args}` runs another tool. `BeforeAgent` input `prompt`; deny discards message from history. `AfterAgent` input `prompt`, `prompt_response`, `stop_hook_active`; deny forces a retry with `reason` as new prompt; `clearContext: true` clears LLM history. `BeforeModel` input `llm_request` (`model`, `messages`, `config`); can override request or return synthetic `llm_response`. `BeforeToolSelection` sets `toolConfig.mode` `"AUTO"|"ANY"|"NONE"` and `allowedFunctionNames`. `AfterModel` fires per streamed chunk. `SessionStart` input `source` `"startup"|"resume"|"clear"`, advisory. `SessionEnd` input `reason` `"exit"|"clear"|"logout"|"prompt_input_exit"|"other"`, best-effort (CLI does not wait). `Notification` input `notification_type` (`"ToolPermission"`), `message`, `details`; observability only. `PreCompress` input `trigger` `"auto"|"manual"`; advisory — [Hooks reference](https://geminicli.com/docs/hooks/reference.md).
- **Env vars for hook processes:** `GEMINI_PROJECT_DIR`, `GEMINI_PLANS_DIR`, `GEMINI_SESSION_ID`, `GEMINI_CWD`, and `CLAUDE_PROJECT_DIR` ("Alias for compatibility") — [Hooks overview](https://geminicli.com/docs/hooks/).
- **Management:** `/hooks panel`, `/hooks enable-all`, `/hooks disable-all`, `/hooks enable <name>`, `/hooks disable <name>` — [Hooks overview](https://geminicli.com/docs/hooks/).
- **Security:** project hooks are fingerprinted; if a hook's name or command changes (e.g. via `git pull`) it is treated as new/untrusted and the user is warned — [Hooks overview](https://geminicli.com/docs/hooks/).
- **Arrival:** first changelog mention v0.24.0 (2026-01-14); Google's Jan 28, 2026 post says hooks are "enabled by default in Gemini CLI as of v0.26.0+"; the Ralph extension uses an `AfterAgent` hook to loop the agent — [changelog](https://geminicli.com/docs/changelogs/); [Google Developers Blog](https://developers.googleblog.com/en/tailor-gemini-cli-to-your-workflow-with-hooks/).
- Hooks doc page last updated Apr 13, 2026 — [Hooks overview](https://geminicli.com/docs/hooks/).

### Inferences
- Event vocabulary maps closely to Claude Code's: `BeforeTool`/`AfterTool` ≈ `PreToolUse`/`PostToolUse`; `AfterAgent` ≈ `Stop`; `BeforeAgent` ≈ `UserPromptSubmit`; `PreCompress` ≈ `PreCompact`; `SessionStart`/`SessionEnd`/`Notification` are name-identical. The presence of `CLAUDE_PROJECT_DIR` as an alias signals Google deliberately targeted portability of Claude hook scripts.
- No equivalent exists for Claude Code's `SubagentStop`, `SubagentStart`, `StopFailure`, `PermissionRequest`, `DirectoryAdded`, `WorktreeCreate`/`WorktreeRemove`, `PreModelSwitch`/`PostModelSwitch`, or `mcp_tool` hooks (absent from the eleven-event list).
- Gemini has three hooks Claude lacks: `BeforeModel`, `AfterModel`, `BeforeToolSelection` (model-request interception).

### Gaps
- The docs name no settings key such as `hooks.enabled`/`hooks.disabled`; enable/disable state is only documented via `/hooks` commands. Not confirmed whether a settings key exists.
- Matcher behaviour for model events (`BeforeModel`/`AfterModel`/`BeforeToolSelection`) is not described.
- The exact `hookSpecificOutput` envelope (whether it requires a `hookEventName` field as Claude does) is not defined on the reference page.

---

## Key question 3: Skills or only commands? What frontmatter/format?

### Takeaway
Both. Custom commands are TOML files (`prompt` + optional `description`) under `commands/`; Agent Skills are `SKILL.md`-based directories following the agentskills.io open standard, with only `name` and `description` frontmatter documented, discovered from built-in → extension `skills/` → user `~/.gemini/skills/` (alias `~/.agents/skills/`) → workspace `.gemini/skills/` (alias `.agents/skills/`), and activated through an `activate_skill` tool with a user consent prompt.

### Cited Findings
**Skills**
- "Based on the Agent Skills open standard" (links agentskills.io); skills are "self-contained directories that package instructions and assets" offering "on-demand expertise" vs GEMINI.md's persistent context — [Skills](https://geminicli.com/docs/cli/skills.md).
- Discovery tiers, lowest→highest precedence: Built-in; Extension (bundled); User `~/.gemini/skills/` or `~/.agents/skills/` alias; Workspace `.gemini/skills/` or `.agents/skills/`. Higher tier wins on name collision; within a tier `.agents/skills/` beats `.gemini/skills/` — [Skills](https://geminicli.com/docs/cli/skills.md).
- Lifecycle: at session start only name+description of enabled skills go into the system prompt; Gemini calls the `activate_skill` tool when a task matches; the user sees a consent prompt (name, purpose, directory path); after approval the SKILL.md body and folder structure enter the conversation and the skill directory becomes an allowed file path — [Skills](https://geminicli.com/docs/cli/skills.md).
- Frontmatter: only `name` ("should match the directory name") and `description` ("CRITICAL ... be specific about the tasks it handles and the keywords that should trigger it") are documented; "Only `SKILL.md` is required." Layout: `SKILL.md`, optional `scripts/`, `references/`, `assets/` — [Creating skills](https://geminicli.com/docs/cli/creating-skills.md).
- Built-in `skill-creator` meta-skill scaffolds a skill; helper scripts `node scripts/init_skill.cjs <name> --path <dir>`, `node scripts/validate_skill.cjs <path>`, `node scripts/package_skill.cjs <path>` (produces a `.skill` zip) — [Creating skills](https://geminicli.com/docs/cli/creating-skills.md).
- Commands: `/skills list [all] [nodesc]`, `/skills link <path> [--scope user|workspace]`, `/skills disable <name>`, `/skills enable <name>`, `/skills reload` (alias `/skills refresh`); terminal: `gemini skills list --all`, `gemini skills install <git-url or local path> --consent`, `gemini skills uninstall <name> --scope workspace`; options `--scope`, `--path` (subdir of a git repo), `--consent` — [Skills](https://geminicli.com/docs/cli/skills.md).
- Extension bundling: `skills/<skill>/SKILL.md`; "Each skill directory exposes a skill by its name" — [Extension reference](https://geminicli.com/docs/extensions/reference.md).
- Arrival: v0.23.0 (2026-01-07) "Experimental Agent Skills Support in Preview" — [changelog](https://geminicli.com/docs/changelogs/).

**Custom commands (TOML)**
- Fields: `prompt` (required, string) and `description` (optional, string; shown in `/help`; generated from filename if omitted). No other fields documented — [Custom commands](https://geminicli.com/docs/cli/custom-commands.md).
- Locations: user `~/.gemini/commands/`; project `<project-root>/.gemini/commands/`; on conflict "the project command will always be used". Extension `commands/` dir: `commands/gcs/sync.toml` → `/gcs:sync`; extension commands have the lowest precedence and conflicting names are prefixed, e.g. `/gcp.deploy` — [Custom commands](https://geminicli.com/docs/cli/custom-commands.md); [Extension reference](https://geminicli.com/docs/extensions/reference.md).
- Namespacing: subdirectories, `git/commit.toml` → `/git:commit`. `{{args}}` placeholder; inside `!{...}` args are shell-escaped; without `{{args}}` the full typed command is appended after two newlines. `!{...}` shell injection (confirmation prompt; stderr + `[Shell command exited with code 1]` on failure; braces must balance). `@{path}` file injection (recursive, respects `.gitignore`/`.geminiignore`; images/PDF/audio/video injected as multimodal). Order: `@{...}` before `!{...}` before `{{args}}` — [Custom commands](https://geminicli.com/docs/cli/custom-commands.md).
- MCP prompts are also exposed as slash commands (`/poem-writer --title=... --mood=...`) via `prompts/get` — [MCP](https://geminicli.com/docs/tools/mcp-server.md).

### Inferences
- Gemini's SKILL.md is a strict subset of Claude Code's: no `user-invocable`, `disable-model-invocation`, `allowed-tools`, `effort`, `model`, `context: fork`, or `agent` fields. A skill written for Claude will load in Gemini only if the extra fields are ignored rather than rejected (not verified; see Gaps).
- `.agents/skills/` support means a repo can ship one skills directory read by Gemini CLI, Antigravity and other agentskills.io consumers.
- Antigravity CLI's importer "converts legacy commands to skills", so TOML commands are a dead-end format going forward (see Q8).

### Gaps
- Whether unknown frontmatter keys in SKILL.md cause a validation error or are ignored is not stated in the docs fetched.
- No doc states a settings key that toggles skills globally (only `/skills enable|disable`).
- Whether the `.skill` zip from `package_skill.cjs` is installable via `gemini skills install` is not stated.

---

## Key question 4: Subagents / agent teams? How defined?

### Takeaway
Yes — subagents are Markdown files with YAML frontmatter in `.gemini/agents/*.md` (project), `~/.gemini/agents/*.md` (user) or an extension's `agents/` directory, exposed to the main agent as tools and invocable with `@name`; four built-ins exist; there is no nesting, and no documented parallel "agent teams" primitive (the "background multi-agent" orchestration is an Antigravity CLI claim, not Gemini CLI).

### Cited Findings
- Each subagent has its own system prompt, optional restricted tools and separate context window; exposed to the main agent "as a tool with the same name"; delegated automatically or forced with `@name` at the start of a prompt — [Subagents](https://geminicli.com/docs/core/subagents.md).
- Frontmatter fields: `name` (required; lowercase letters, numbers, hyphens, underscores; used as tool name), `description` (required), `kind` (`local` default | `remote`), `tools` (array; supports `*`, `mcp_*`, `mcp_<server>_*`; omitted = inherit all), `mcpServers` (inline, isolated to the agent), `model` (default `inherit`), `temperature` (0.0–2.0, default `1`), `max_turns` (default `30`), `timeout_mins` (default `10`). File must start with `---`; Markdown body = system prompt — [Subagents](https://geminicli.com/docs/core/subagents.md).
- Discovery: project `.gemini/agents/*.md`; user `~/.gemini/agents/*.md`; extensions bundle sub-agent `.md` definitions in `agents/` — "Sub-agents are a preview feature currently under active development" — [Subagents](https://geminicli.com/docs/core/subagents.md); [Extension reference](https://geminicli.com/docs/extensions/reference.md).
- Built-ins: `codebase_investigator` (enabled), `cli_help` (enabled), `generalist` (enabled), `browser_agent` (disabled; needs Chrome 144+; `sessionMode` `persistent`|`isolated`|`existing`; `visualModel` requires API-key or Vertex auth) — [Subagents](https://geminicli.com/docs/core/subagents.md).
- Settings: disable all with `"experimental": { "enableAgents": false }`; per-agent `agents.overrides.<name>` with `enabled`, `runConfig` (`maxTurns`, `maxTimeMinutes`) or `modelConfig`; `agents.browser` (`sessionMode`, `headless`, `allowedDomains`, `maxActionsPerTask`); `modelConfigs.overrides` with `match.overrideScope` = agent name — [Subagents](https://geminicli.com/docs/core/subagents.md).
- Policy engine rules accept a `subagent` key to scope a rule to one agent; subagents also appear as virtual tool names for `toolName` matching — [Subagents](https://geminicli.com/docs/core/subagents.md); [Policy engine reference](https://geminicli.com/docs/reference/policy-engine.md).
- Limits: "No nesting: Subagents cannot call other subagents, even if granted the `*` tool wildcard"; isolated history. Remote subagents via A2A protocol (`/docs/core/remote-agents`). The page "does not mention" parallel execution or teams — [Subagents](https://geminicli.com/docs/core/subagents.md).
- Arrival: v0.12.0 (2025-10-27) first built-in subagent; remote agents v0.24.0; browser agent v0.31.0 — [changelog](https://geminicli.com/docs/changelogs/).
- Conductor is a separate Gemini CLI *extension* (`gemini extensions install https://github.com/gemini-cli-extensions/conductor --auto-update`) for "context-driven development" (context → spec/plan → implementation), launched in preview; it is not an agent-teams primitive — [Google Developers Blog: Conductor](https://developers.googleblog.com/en/conductor-introducing-context-driven-development-for-gemini-cli/); [Conductor README](https://github.com/gemini-cli-extensions/conductor).
- Antigravity CLI (not Gemini CLI) is the product Google describes as orchestrating "multiple agents for complex tasks in the background" — [Google Developers Blog](https://developers.googleblog.com/en/an-important-update-transitioning-gemini-cli-to-antigravity-cli/).

### Inferences
- The frontmatter is close to Claude Code's `agents/*.md` (`name`, `description`, `tools`, `model`) with extra run-limits (`max_turns`, `timeout_mins`, `temperature`) and per-agent `mcpServers`; Claude-only fields (`omitClaudeMd`, `effort`, `permissionMode`, `color`) have no equivalent.
- Because subagents are exposed as tools, hooks' `BeforeTool`/`AfterTool` with a matcher on the agent name and policy `toolName` rules can gate delegation (inferred from "virtual tool names").

### Gaps
- Whether multiple subagents can run concurrently in one turn (the main model calling several agent-tools at once) is not documented.
- The exact extension-side path for agents is given only as `agents/` with `.md` files; no example file name constraints beyond `name` slug rules.

---

## Key question 5: What manifest fields does `gemini-extension.json` accept today, and how do install/update/registry work?

### Takeaway
The manifest accepts `name`, `version`, `description`, `migratedTo`, `mcpServers`, `contextFileName`, `excludeTools`, `plan`, `settings`, `themes`; hooks, commands, skills, agents and policies are discovered by directory convention rather than manifest fields. Extensions install from a GitHub URL or local path into `~/.gemini/extensions`, are copied (not linked) unless `gemini extensions link` is used, and are listed on geminicli.com/extensions.

### Cited Findings
- Each extension "must have a `gemini-extension.json` file in its root directory"; extensions load from `<home>/.gemini/extensions` — [Extension reference](https://geminicli.com/docs/extensions/reference.md).
- Fields: `name` (lowercase, numbers, dashes; should match the directory name); `version`; `description` (displayed on geminicli.com/extensions); `migratedTo` (new repo source — CLI checks it for updates and migrates the installation); `mcpServers` (name→config; "all MCP server configuration options are supported except for `trust`"; a same-named server in `settings.json` takes precedence); `contextFileName` (defaults to `GEMINI.md` if present); `excludeTools` (array; supports command-specific forms like `"run_shell_command(rm -rf)"`); `plan` (object with `directory`, e.g. `{ "directory": ".gemini/plans" }`); `settings` (array of `{name, description, envVar, sensitive}` — `sensitive: true` stores the value in the system keychain and obfuscates it in the UI); `themes` (array of custom UI themes) — [Extension reference](https://geminicli.com/docs/extensions/reference.md).
- Variable substitution in `gemini-extension.json` and `hooks/hooks.json`: `${extensionPath}`, `${workspacePath}`, `${/}` — [Extension reference](https://geminicli.com/docs/extensions/reference.md).
- Directory conventions: `GEMINI.md` (or `contextFileName`); `commands/*.toml`; `hooks/hooks.json`; `skills/<skill>/SKILL.md`; `agents/*.md`; `policies/*.toml`; `.env` (setting values stored in the extension dir). "Gemini CLI ignores any `allow` decisions or `yolo` mode configurations in extension policies." Extensions do not inherit the full shell environment — needed vars must be declared in `settings` with `envVar` — [Extension reference](https://geminicli.com/docs/extensions/reference.md).
- Settings are set with `gemini extensions config <name> [setting] [--scope <scope>]`; there is no `userConfig` field (the `settings` array is the equivalent) — [Extension reference](https://geminicli.com/docs/extensions/reference.md).
- CLI: `gemini extensions install <source> [--ref <ref>] [--auto-update] [--pre-release] [--consent] [--skip-settings]` (`<source>` = GitHub URL or local path; GitHub installs require `git`); `gemini extensions uninstall <name...>`; `gemini extensions update <name>` / `--all`; `gemini extensions new <path> [template]` (templates `mcp-server`, `context`, `custom-commands`); `gemini extensions link <path>`; `gemini extensions enable|disable <name> [--scope user|workspace]`; interactive `/extensions list`. "Gemini CLI creates a copy of the extension during installation"; management operations take effect after restart; "Extensions are enabled globally by default"; workspace config beats extension config on conflict — [Extension reference](https://geminicli.com/docs/extensions/reference.md); [Extensions overview](https://geminicli.com/docs/extensions/).
- Gallery: "browse the Gemini CLI extension gallery" at geminicli.com/extensions; the overview links "Publish to the gallery" and "Developer guide: Releasing" pages — [Extensions overview](https://geminicli.com/docs/extensions/).
- Arrival: v0.8.0 (2025-09-29) `gemini extensions install <github url|folder path>`; v0.28.0 custom themes in extensions; v0.29.0 "New UI and settings to explore and manage extensions more easily"; v0.60.0 consent prompts for extension environment changes — [changelog](https://geminicli.com/docs/changelogs/).

### Inferences
- `excludeTools` at manifest level is the only tool-gating field; there is no `allowed-tools`-style allowlist for the extension as a whole (only MCP `includeTools` per server).
- `settings[].sensitive` + keychain is the functional analogue of Claude's `userConfig` sensitive options; the `.env` file in the extension directory is where non-sensitive values persist.
- Install is git-clone-based with `--ref`; there is no documented release-archive install path or signed-package registry.

### Gaps
- The "Publish to the gallery" and "Releasing" guide pages were not fetched; the exact submission mechanism (PR to a registry repo vs. form) is unverified.
- No required/optional typing for manifest fields is stated.
- `gemini extensions list` as a terminal subcommand and an `explore` subcommand are not documented on the reference page (only `/extensions list`).
- The contents of the install consent prompt are not described.

---

## Key question 6: MCP support (transports, OAuth, tool filtering)

### Takeaway
Three transports (`command` stdio, `url` SSE, `httpUrl` streamable HTTP), OAuth 2.0 with automatic discovery on 401 plus Google-credential/service-account modes, per-server `includeTools`/`excludeTools` (exclude wins) and global `mcp.allowed`/`mcp.excluded`, with tools named `mcp_{serverName}_{toolName}`.

### Cited Findings
- `mcpServers.<name>` keys: transport `command` | `url` | `httpUrl`; optional `args`, `env` (supports `$VAR`, `${VAR}`, Windows `%VAR%`), `cwd`, `headers`, `timeout` (ms, default 600000), `trust` (skip confirmations; default false), `includeTools`, `excludeTools` ("`excludeTools` takes precedence over `includeTools`"), `oauth` (`enabled`, `clientId`, `clientSecret`, `authorizationUrl`, `issuer`, `authorizationResponseIssParameterSupported`, `tokenUrl`, `scopes`, `redirectUri`, `tokenParamName`, `audiences`), `authProviderType` (`dynamic_discovery` default | `google_credentials` | `service_account_impersonation`), `targetAudience`, `targetServiceAccount` — [MCP servers](https://geminicli.com/docs/tools/mcp-server.md).
- OAuth: automatic discovery on 401; tokens in `~/.gemini/mcp-oauth-tokens.json`; callback `http://localhost:<random-port>/oauth/callback`; fails without browser access; RFC 9207 `iss` check (set `authorizationResponseIssParameterSupported: false` to relax) — [MCP servers](https://geminicli.com/docs/tools/mcp-server.md); enforced in v0.60.0 #29117 — [v0.60.0](https://github.com/google-gemini/gemini-cli/releases/tag/v0.60.0).
- `/mcp`, `/mcp auth [<server>]`, `/mcp list`, `/mcp enable|disable <name> [--session]` (state in `~/.gemini/mcp-server-enablement.json`); global `mcp.serverCommand`, `mcp.allowed`, `mcp.excluded` — [MCP servers](https://geminicli.com/docs/tools/mcp-server.md).
- Naming: FQN `mcp_{serverName}_{toolName}`; server names should avoid underscores because the policy parser splits on the first underscore after `mcp_`; `@server://resource/path` injects a resource — [MCP servers](https://geminicli.com/docs/tools/mcp-server.md).
- In extensions, `mcpServers` supports every option except `trust` — [Extension reference](https://geminicli.com/docs/extensions/reference.md).

### Inferences
- An extension cannot pre-trust its own MCP server, so every tool call from an extension MCP server is subject to approval mode / policy unless the user adds a policy rule.

### Gaps
- `/mcp schema` and `/mcp desc` subcommands and a `targetScope` key were not found on the page (may not exist).

---

## Key question 7: Context files, policy engine, approval modes, sandboxing, checkpointing, worktrees, headless, IDE, GitHub Action, telemetry

### Takeaway
All of these exist on Gemini CLI today; the extension-relevant ones are context files (`GEMINI.md`, honoured unchanged by Antigravity), extension-shipped policy TOML (deny/ask only), and headless JSON/stream-JSON output for CI.

### Cited Findings
**Context files**
- Extensions load `GEMINI.md` from their directory or the file named by `contextFileName` — [Extension reference](https://geminicli.com/docs/extensions/reference.md). Antigravity's migration guide says "`GEMINI.md` / `AGENTS.md` — Unchanged; Workspace and `~/.gemini/GEMINI.md` rules are still enforced" — [Antigravity migration guide](https://antigravity.google/docs/cli/gcli-migration).

**Policy engine** (first mention v0.18.0, 2025-11-17 — [changelog](https://geminicli.com/docs/changelogs/))
- `[[rule]]` TOML keys: `toolName` (string|array; wildcards `*`, `mcp_server_*`, `mcp_*_toolName`), `subagent`, `mcpName`, `toolAnnotations`, `argsPattern` (regex over JSON-stringified args), `commandPrefix`, `commandRegex` (not combinable with `commandPrefix`), `decision` (`allow`|`deny`|`ask_user`), `priority` (0–999), `denyMessage` (example also shows `deny_message` — inconsistent), `modes`, `interactive` (bool), `allowRedirection` (bool). In non-interactive mode `ask_user` is treated as `deny` — [Policy engine reference](https://geminicli.com/docs/reference/policy-engine.md).
- Tiers/bases: Default 1 (built-in); Extension 2 (extension `policies/`); Workspace 3 (`$WORKSPACE_ROOT/.gemini/policies/*.toml`, "currently disabled"); User 4 (`~/.gemini/policies/*.toml`); Admin 5 (Linux `/etc/gemini-cli/policies`; macOS `/Library/Application Support/GeminiCli/policies`; Windows `C:\ProgramData\gemini-cli\policies`; supplemental via `--admin-policy` or `adminPolicyPaths`). `final_priority = tier_base + (toml_priority / 1000)`. Admin dir must be root-owned and not group/other-writable or it is ignored — [Policy engine reference](https://geminicli.com/docs/reference/policy-engine.md).
- Extension policies: "Gemini CLI ignores any `allow` decisions or `yolo` mode configurations in extension policies" — [Extension reference](https://geminicli.com/docs/extensions/reference.md).

**Approval modes / Plan mode**
- Modes named `default`, `autoEdit`, `plan`, `yolo` on the policy page; `plan` is "strict read-only"; "Allow for all future sessions" grants cascade (plan → all; default → default/autoEdit/yolo; autoEdit → autoEdit/yolo; yolo → yolo) — [Policy engine reference](https://geminicli.com/docs/reference/policy-engine.md). The configuration reference spells the setting values `default`, `auto_edit`, `plan` and says YOLO "can only be enabled via command line (`--yolo` or `--approval-mode=yolo`)" — [Configuration reference](https://geminicli.com/docs/reference/configuration.md).
- Plan Mode is enabled by default; Shift+Tab cycles modes; `gemini --approval-mode=plan`; `enter_plan_mode` tool unavailable in YOLO; a custom plan directory needs a policy allowing writes — [Plan mode](https://geminicli.com/docs/cli/plan-mode). `/plan` arrived v0.29.0 (2026-02-17) — [changelog](https://geminicli.com/docs/changelogs/). Hook env var `GEMINI_PLANS_DIR` and manifest `plan.directory` tie extensions into it — [Hooks overview](https://geminicli.com/docs/hooks/); [Extension reference](https://geminicli.com/docs/extensions/reference.md).

**Sandboxing**
- Methods: macOS Seatbelt (`sandbox-exec`), Docker/Podman (default image `ghcr.io/google/gemini-cli:latest`), Windows Native, gVisor/runsc (explicit), LXC/LXD (experimental). Enable via `-s`/`--sandbox`, `GEMINI_SANDBOX=true|docker|podman|sandbox-exec|runsc|lxc`, or `{"tools": {"sandbox": "docker"}}`. `SEATBELT_PROFILE` values: `permissive-open` (default), `permissive-proxied`, `restrictive-open`, `restrictive-proxied`, `strict-open`, `strict-proxied`. Custom `.gemini/sandbox.Dockerfile` with `BUILD_SANDBOX=1 GEMINI_SANDBOX=docker` (source builds only) — [Sandbox](https://geminicli.com/docs/cli/sandbox.md). 0.60.0 isolated settings and temp dirs inside containers (#29171, #29216); 0.61.0 hardened FS boundaries (#29214) — [changelog](https://geminicli.com/docs/changelogs/).

**Checkpointing**
- Off by default; `general.checkpointing.enabled: true` in `settings.json`; "The `--checkpointing` command-line flag was removed in version 0.11.0"; shadow repo at `~/.gemini/history/<project_hash>`; checkpoint on approving `write_file`/`replace`; `/restore [<checkpoint_file>]` — [Checkpointing](https://geminicli.com/docs/cli/checkpointing.md).

**Git worktrees** (experimental, v0.36.0 2026-04-01)
- Off by default; enable via `/settings` "Enable Git Worktrees" or `"experimental": { "worktrees": true }`; on exit prints resume/remove instructions; resume with `gemini --resume <session_id>` from the worktree dir — [Git worktrees](https://geminicli.com/docs/cli/git-worktrees.md); [changelog](https://geminicli.com/docs/changelogs/).

**Headless**
- Triggered in a non-TTY environment or with `-p`/`--prompt`; `--output-format` with JSON (`response`, `stats`, optional `error`) and streaming JSONL events `init`, `message`, `tool_use`, `tool_result`, `error`, `result`; exit codes `0`, `1`, `42` (input error), `53` (turn limit exceeded) — [Headless](https://geminicli.com/docs/cli/headless.md). 0.63.0 enabled autonomous plan execution in non-interactive mode; 0.64.0 propagates folder-trust in headless mode — [changelog](https://geminicli.com/docs/changelogs/); [v0.64.0](https://github.com/google-gemini/gemini-cli/releases).

**IDE integration**
- "Gemini CLI Companion" extension for Antigravity, VS Code and compatible editors (forks via Open VSX); JetBrains and Zed via the ACP Agent Registry; `/ide install|enable|disable|status`; context = 10 most-recent files, cursor, selection ≤16KB; native diffing; env `GEMINI_CLI_IDE_PID`, `GEMINI_CLI_IDE_WORKSPACE_PATH`, `GEMINI_CLI_IDE_SERVER_PORT`; page updated Jun 18, 2026 — [IDE integration](https://geminicli.com/docs/ide-integration/).

**GitHub Action**
- `google-github-actions/run-gemini-cli`; inputs `prompt`, `settings` (JSON written to `.gemini/settings.json`), `gemini_api_key`, `google_api_key`, `gemini_model`, `gcp_location`, `gcp_project_id`, `gcp_service_account`, `gcp_workload_identity_provider`, `gcp_token_format`, `gcp_access_token_scopes`, `use_vertex_ai`, `use_gemini_code_assist`, `gemini_cli_version` (default `latest`), `gemini_debug`, `extensions` ("A list of Gemini CLI extensions to install"), `upload_artifacts`, `use_pnpm`, `workflow_name`, `github_pr_number`, `github_issue_number`; outputs `summary`, `error`; workflows Gemini Dispatch, Issue Triage (`@gemini-cli /triage`), PR Review (`@gemini-cli /review`), Assistant (`@gemini-cli ...`); `/setup-github` in the CLI is the recommended setup — [run-gemini-cli README](https://github.com/google-github-actions/run-gemini-cli).

**Telemetry / OpenTelemetry**
- `telemetry` settings: `enabled` (false), `target` (`local`|`gcp`), `otlpEndpoint` (`http://localhost:4317`), `otlpProtocol` (`grpc`|`http`), `logPrompts` (true), `outfile`, `useCollector`, `traces`, `useCliAuth`; env `GEMINI_TELEMETRY_ENABLED|TARGET|OTLP_ENDPOINT|OTLP_PROTOCOL|OTLP_HEADERS|OUTFILE|LOG_PROMPTS|USE_COLLECTOR|USE_CLI_AUTH|TRACES_ENABLED`, `GEMINI_CLI_SURFACE`, `OTLP_GOOGLE_CLOUD_PROJECT`; events `gemini_cli.config`, `gemini_cli.user_prompt`, `gemini_cli.tool_call`, `gemini_cli.api_request/response/error`, `gemini_cli.agent.start/finish`, `gemini_cli.startup_stats`; metrics `gemini_cli.session.count`, `gemini_cli.tool.call.count/latency`, `gemini_cli.token.usage`, `gen_ai.client.token.usage` — [Telemetry](https://geminicli.com/docs/cli/telemetry.md).

### Inferences
- An extension can ship *restrictive* policy (deny/ask_user) only; it cannot widen permissions — the mirror of Claude's rule that plugin `permissions-allow` cannot be shipped silently.
- Checkpointing + worktrees are host features with no extension hook points (no `WorktreeCreate` event), so a worktree-per-objective workflow must be driven by shell in a command/skill.

### Gaps
- Spelling conflict: `autoEdit` (policy page) vs `auto_edit` (configuration reference) — which is the settings.json value is unresolved from these pages.
- `privacy.usageStatisticsEnabled` opt-out key not confirmed on the telemetry page.
- Headless flags (`-i`, `--allowed-tools`, `--include-directories`, `--resume`, `--session-summary`, `--model`) are not on the headless page; the CLI reference (`/docs/cli/cli-reference`) was not fetched.
- The ACP integration's first version was not found in the changelog (the v0.19.0 "Zed integration" entry does not name ACP).

---

## Key question 8: What does Gemini CLI NOT support that Claude Code does (mods, statusline, output styles, userConfig)? And what is the Antigravity CLI situation?

### Takeaway
Gemini CLI has no in-process "mods"/TSX hook modules, no statusline script, no output styles, no `userConfig` block (its `settings` array + keychain is the analogue), no plugin eval harness, no `SubagentStop`/worktree/permission-request/model-switch hooks, no agent teams, no nested subagents, and extension policies can only restrict. Its distribution path is a git-clone gallery, not a signed directory; and the product itself is in a sunset for consumer tiers, with Antigravity CLI (`agy`) importing extensions as "plugins".

### Cited Findings
- Changelog scan v0.4.0–v0.59.0 found no entries for "statusline" (closest: v0.4.0 "Footer visibility configuration", v0.8.0 "Terminal Title Status") and none for "output styles" (v0.6.0 "JSON output mode" is unrelated) — [changelog](https://geminicli.com/docs/changelogs/).
- Manifest has no `userConfig`; closest equivalent is `settings` (`name`, `description`, `envVar`, `sensitive`) set via `gemini extensions config` — [Extension reference](https://geminicli.com/docs/extensions/reference.md).
- Hooks: only `type: "command"` is supported — no in-process/module hooks — [Hooks reference](https://geminicli.com/docs/hooks/reference.md).
- Subagents cannot nest; no teams/parallel primitive documented; preview status — [Subagents](https://geminicli.com/docs/core/subagents.md).
- Extension policies: `allow`/`yolo` ignored — [Extension reference](https://geminicli.com/docs/extensions/reference.md).
- Antigravity CLI: binary `agy`; `agy plugin import gemini` "converts legacy extensions into native plugins"; commands → skills ("legacy commands converted to skills"); global skills move from `~/.gemini/skills/` to `~/.gemini/antigravity-cli/skills/`; workspace skills to `.agents/skills/`; MCP moves from inline `settings.json` to `~/.gemini/config/mcp_config.json` / `.agents/mcp_config.json` with `serverUrl` replacing `url`/`httpUrl`; `GEMINI.md`/`AGENTS.md` unchanged; auth tokens migrate to OS keyring; "agents: skipped (none detected)" appears in import output; "Partial parity" for custom themes/visual overlays — [Antigravity migration guide](https://antigravity.google/docs/cli/gcli-migration).
- Google's transition post lists Agent Skills, Hooks, Subagents and Extensions (renamed Antigravity plugins) as carried over, says there won't be 1:1 feature parity at launch, and does not mention MCP by name — [Google Developers Blog](https://developers.googleblog.com/en/an-important-update-transitioning-gemini-cli-to-antigravity-cli/).
- Antigravity CLI is built in Go and shares its agent harness with the Antigravity 2.0 desktop app; one report says it is not published as open source — [Google Developers Blog](https://developers.googleblog.com/en/an-important-update-transitioning-gemini-cli-to-antigravity-cli/); open-source caveat per search summary of [ostechnix](https://ostechnix.com/google-is-replacing-gemini-cli-with-google-antigravity/) (secondary; flagged).
- A third-party vendor doc claims Antigravity CLI "loads hooks but does not fire them yet" — [Weilliptic docs](https://docs.weilliptic.ai/docs/codensics/integrations-gemini) — **unverified against any Google source**; the official migration page links a "Lifecycle hooks" page that was not fetched.

### Inferences
- For a multi-platform plugin, the durable Gemini-side assets are `GEMINI.md`/`AGENTS.md`, `.agents/skills/*/SKILL.md`, `agents/*.md`, and MCP server definitions; `commands/*.toml` and `hooks/hooks.json` are the formats most likely to need conversion for Antigravity.
- Claude-only concepts with no Gemini target: mods (`mod/register.tsx`), `settings.statusLine`, `output-styles/`, `userConfig` sensitive options (partially mirrored by `settings[].sensitive`), `claude plugin eval`, `SubagentStop`/`StopFailure`/worktree hooks, `effort:`/`user-invocable`/`disable-model-invocation` skill frontmatter, `omitClaudeMd`.

### Gaps
- No official statement was found on whether the google-gemini/gemini-cli OSS repo will stop releasing; releases continue through v0.65.0-preview.0 (2026-10-13) as observed.
- The Antigravity "Lifecycle hooks" doc (which events `agy` fires) was not fetched; hook parity is therefore unknown.
- Whether `agy plugin import gemini` preserves `hooks/hooks.json` and `policies/*.toml` is not stated on the migration page.
