# Cursor IDE + Cursor CLI: permission research for plugin permission behavior

Research input to ADR 004 (permission levels). Date 2026-11-03. Evidence tags: doc-cited / source-cited / measured / unverified.

Researched 2026-11-03. Tags: **doc-cited** (URL), **measured** (command and output), **unverified**, **forum** (staff post, secondary).

## Versions

| Surface | Repo pin | Latest found | Evidence |
|---|---|---|---|
| Cursor desktop | 3.27.22 | **3.28.7** (stable) | measured: `curl 'https://cursor.com/api/download?platform=darwin-arm64&releaseTrack=stable'` returns `"version":"3.28.7"` (the `latest` track returns the same) |
| Cursor desktop, local | n/a | 3.27.22 | measured: `cursor --version` gives `3.27.22` |
| Cursor CLI (`cursor-agent` / `agent`) | 2026.09.18 (install doc) | **v2026.10.22** | doc-cited: https://cursor.com/docs/cli/changelog.md (top entry). measured: `cursor-agent --version` gives `2026.10.22-27dcf5f` |

**Delta vs 3.27.22.** The IDE release notes (https://cursor.com/docs/release-notes/ide.md) end at **3.27**, and no 3.28 notes were published as of this date. So the 3.28 delta is **unknown**. The feature changelog (https://cursor.com/changelog) is dated only. Its newest post is Agent SDK (2026-10-20), and it has no permission, hook or plugin items after 3.27. Every doc read here is the live docs as of 2026-11-03, so they describe 3.28.x or later.

---

## A. Host permission model

**Run modes (IDE, Settings > Agents > Approvals & Execution).** doc-cited: https://cursor.com/docs/agent/security/run-modes.md
- **Auto-review** (the recommended default since 3.6). Allowlisted shell, MCP and Fetch calls run immediately. Other shell commands run in the sandbox when they can. Everything else goes to an LLM classifier (Gemini 3.5 Flash Lite, with Haiku as fallback). The page says it is *"not a security boundary"*.
- **Allowlist.** Allowlisted actions run without approval. Shell commands can optionally be sandboxed.
- **Run Everything.** Every tool call runs automatically.
- "Ask Every Time" was deprecated in **3.5**: *"Use Allowlist with an empty allowlist for the same behavior."* "Run in Sandbox" was folded into Allowlist.
- Cloud agents do not use Run Modes.

**CLI equivalents.** doc-cited: https://cursor.com/docs/cli/reference/configuration.md, https://cursor.com/docs/cli/reference/parameters.md
- `approvalMode` in `cli-config.json` takes `allowlist`, `auto-review` or `unrestricted`.
- Flags: `-f/--force` (*"Force allow commands unless explicitly denied"*), `--yolo` (an alias of `--force`), `--sandbox enabled|disabled`, `--approve-mcps`, `--trust` (headless trust). The `/run-everything` (alias `/auto-run`) slash command toggles Run Everything.
- measured: `cursor-agent --help` lists `-f, --force`, `--yolo  Alias for --force (Run Everything)`, `--sandbox <mode>`, `--approve-mcps`, `--trust` and `--plugin-dir <path>`.
- measured: the local `~/.cursor/cli-config.json` (keys only) has `"approvalMode": "allowlist"`, `sandbox.mode: "disabled"`, one `permissions.allow` entry and an `autoAcceptWebSearch` key.

**CLI permission tokens.** doc-cited: https://cursor.com/docs/cli/reference/permissions.md
- Tokens: `Shell(cmdBase)` (first token, with globs and `cmd:args`), `Read(glob)`, `Write(glob)`, `WebFetch(domain)` and `Mcp(server:tool)`.
- Global file: `~/.cursor/cli-config.json`. Project file: `<project>/.cursor/cli.json`. *"Only permissions can be configured at the project level."*
- *"Deny rules take precedence over allow rules."* There is **no `ask` list**: anything not allowed prompts, unless `--force` is set.
- The docs do not say how global and project lists merge (unverified, presumably a union).

**IDE allowlists: `permissions.json`.** doc-cited: https://cursor.com/docs/reference/permissions.md
- Locations: `~/.cursor/permissions.json` and `<workspace>/.cursor/permissions.json`. The arrays in the two files are **concatenated**.
- Fields: `terminalAllowlist` (prefix match, `cmd:argsGlob`), `mcpAllowlist` (`server:tool`, wildcards) and `autoRun.{allow,block}_instructions`. The last one is natural-language steering for Auto-review only: *"Treat both as steering, not enforcement."*
- When `permissions.json` defines a key, it **replaces** the in-app allowlist for that key, and the in-app editor becomes read-only.
- **There is no user-level denylist in the IDE**, only allowlists. Hard denies exist only in the CLI (`permissions.deny`) and in admin policy.
- Precedence: *"team admin (dashboard) > permissions.json (per-user ∪ per-repo) > IDE settings UI"*. When Run Mode is admin-controlled, *"Neither permissions.json nor the IDE allowlist can add extra entries."*
- 3.26/3.27 change (doc-cited: ide.md): "Always Run" on an approval writes to `~/.cursor/permissions.json` `terminalAllowlist` when that file manages the list. It is not offered when the list is admin-managed.

**MCP approval.** doc-cited: https://cursor.com/docs/mcp.md
- *"Cursor asks for approval before using MCP tools by default."*
- MCP *"follows the same Run Modes as terminal commands"*.
- Enterprise **MCP Allowlist** settings: command and URL patterns for servers, plus a per-server tool allowlist.
- In the CLI, `--approve-mcps` or `agent mcp enable <id>` adds a server to the approved list. Global `~/.cursor/mcp.json` servers are auto-approved, while project servers still prompt. doc-cited: CLI changelog, a pre-June 2026 entry.
- Plugin MCP servers appear with a `plugin-` prefix in approval prompts. doc-cited: https://cursor.com/docs/reference/plugins.md

**Other protections, which can force approval even in auto modes.** doc-cited: run-modes.md
- Browser Protection.
- **File-Deletion Protection** (*"including `rm` commands"*).
- External-File Protection (writes outside the workspace).
- Sandbox-protected paths: `.git/config`, `.git/hooks`, `.vscode`, `.cursorignore` and *"sensitive Cursor config files"*. The docs list no separate dotfile protection.
- Auto-review now asks before recursive, force, wildcard or mirror deletes whose target is ambiguous. doc-cited: CLI changelog v2026.10.08 and IDE 3.25.

**Sandbox.** doc-cited: run-modes.md
- macOS uses Seatbelt. Linux uses Landlock v3 + seccomp (kernel 6.2+).
- Network is blocked by default. Network modes: `sandbox.json Only`, `+ Defaults` (the default), and `Allow All`.
- `sandbox.json` lives at `~/.cursor/sandbox.json` and `<project>/.cursor/sandbox.json`. The project file wins.
- *"Team-admin policies and Cursor's hardcoded security rules layer on top, so local files cannot weaken those protections."*
- Read Access (3.23+): `System` (the default) or `Workspace`, plus a Read Allowlist.

**Admin layer.** doc-cited: run-modes.md, mcp.md, CLI changelog v2026.08.11
- Admins can override which modes are available.
- Admins control sandbox network rules, the team read policy, MCP allowlist and denylist, and gating of Auto-review.
- The team admin **command denylist** is now *"enforced in local shell execution"* in the CLI.
- The MDM policy `AgentRemoteWorkspaceAuthorities` exists (IDE 3.24).

**Precedence summary.** Enterprise/team dashboard > (project ∪ user) local files > in-app settings. Deny beats allow in the CLI. For sandbox settings, project beats user.

## B. What a plugin can affect

**Plugin components.** doc-cited: https://cursor.com/docs/plugins.md and https://cursor.com/docs/reference/plugins.md
- Manifest: `.cursor-plugin/plugin.json`. `name` is required. Optional fields: `description, version, author, homepage, repository, license, keywords, logo, rules, agents, skills, commands, hooks, mcpServers, variables`.
- **The manifest has no permissions or capability section** (doc-cited: the reference field table lists none).
- Agent Plugins (root `plugin.json`) carry only skills and MCP. Rules, agents, commands and hooks are Cursor-Plugin-only.
- An explicit path field *"replaces folder discovery"* for that component.

**Hooks.** doc-cited: https://cursor.com/docs/hooks.md
- 21 events. The permission-returning events are:
  - `preToolUse`: `allow|deny`. *"`ask` is accepted by the schema but not enforced for `preToolUse` today"*. Supports `updated_input`.
  - `beforeShellExecution` and `beforeMCPExecution`: `allow|deny|ask`.
  - `beforeReadFile`: `allow|deny`.
  - `subagentStart`: `ask` is treated as `deny`.
  - `beforeSubmitPrompt`: `continue`.
- Merge rule: *"All matching hooks from every source run … any `deny` wins over `ask`, and `ask` wins over `allow`, regardless of source."*
- Source priority: Enterprise > Team > Project > User. *"Hooks from installed plugins come after all of these. Plugin hooks run command hooks only."*
- Failure behavior: `failClosed` defaults to false. Permission hooks block on invalid JSON *"even when this is `false`"*. Exit code 2 means deny.
- `loop_limit`: *"Per-script loop limit for stop/subagentStop hooks"*. The default is 5 for Cursor hooks and `null` for Claude-format hooks.
- **A hook `allow` does NOT grant approval.** Staff wrote: *"Returning `allow` from a hook does not override the MCP approval system … hooks can only deny actions"* (Dean Rie, 2026-03-21, https://forum.cursor.com/t/hooks-return-allow-but-mcp-tool-still-requires-manual-approval-gets-skipped/155434). An older thread reports the same for shell: https://forum.cursor.com/t/beforeshellexecution-hook-permissions-allow-ask-ignored-allow-list-takes-precedence/144244. [forum]
- **`ask` from `beforeShellExecution` is ignored in Auto-review.** It is honored in Allowlist and Run Everything. Staff (Colin, 2026-10-05) wrote: *"the hook's 'ask' answer currently isn't applied"*, with no fix version announced. Measured by the reporter on 3.21.16: https://forum.cursor.com/t/beforeshellexecution-hook-returning-ask-is-ignored-in-auto-review-mode-honoured-in-allowlist-and-run-everything-3-21-16/173694. [forum] Whether 3.28 changed this: **unverified**.
- **Net effect: a plugin can only *narrow* host permissions, and only `deny` is reliable on every mode.** A plugin cannot widen permissions: it cannot ship a `permissions.json`, a `cli.json` or `sandbox.json`, and a hook `allow` does not bypass approval.
  - Exception (unverified, design risk): the docs encourage *the agent* to edit `permissions.json` ("ask the Cursor agent … it edits your `permissions.json`"). So a skill *could* instruct the agent to write `~/.cursor/permissions.json`. That is a user-visible file write, not a plugin capability, and should be treated as out of bounds.

**Third-party (Claude Code) hooks.** doc-cited: https://cursor.com/docs/reference/third-party-hooks.md
- Loaded from `.claude/settings.local.json`, `.claude/settings.json` and `~/.claude/settings.json`, when *"Include Third-Party Plugins, Skills, and Other Configs"* is on. It is on by default.
- They rank below all Cursor sources.
- Mapped events: PreToolUse, PostToolUse, UserPromptSubmit, Stop, SubagentStop, SessionStart, SessionEnd, PreCompact. `Notification` and `PermissionRequest` are **not supported**.
- `permissionDecision` maps to `permission`. Tool `Bash` maps to `Shell`, and `Edit` to `Write`. `Glob` is not mapped.
- The doc does not say that a plugin's own Claude `hooks/hooks.json` is read. The CLI changelog (pre-June) says *"Plugins imported from Claude Code appear alongside native ones."* What that import loads (hooks or not) is **unverified**.

## C. Plugin configuration

- **`variables`** (doc-cited: reference/plugins.md#variables) is a JSON Schema with a restricted keyword set: `type, title, description, default, enum, const, properties, required, items`, plus length and number limits.
  - Values are set *"in the dashboard under Plugins (at install time, or later via Configure)"*. The doc says "Team admins set the actual values".
  - Values are substituted into `${VAR}` placeholders. The documented use is in `mcp.json`. The CLI masks secret-typed fields in plugin config forms (doc-cited: CLI changelog v2026.08.11).
  - **The docs do not say whether variables reach hooks or skills as environment variables (unverified, likely not).**
  - Whether a non-team individual user gets a local Configure form: not documented (unverified). The CLI mention of "plugin configuration forms" suggests yes.
  - So an `enum` variable such as `PERMISSION_PRESET: strict|auto|bypass` is *declarable*. What is unknown is whether anything other than `mcp.json` can read it.
- **No persistent plugin data directory.** Cursor *"does not expand the standard's `${PLUGIN_ROOT}` and `${PLUGIN_DATA}`"* (doc-cited: plugins.md). Only `${CURSOR_PLUGIN_ROOT}` (and `${CLAUDE_PLUGIN_ROOT}` in `mcp.json`) is expanded.
- **The install path is keyed by commit**, so plugin-root state does not survive updates. measured: `ls ~/.cursor/plugins/cache/tamirs-superpowers/tamirs-superpowers/` shows `c9399aa8e3976db2f7f372825076abb4b46c6fd1`. The other directories are `~/.cursor/plugins/{cache,local,marketplaces}`.
  - A config file must therefore live outside the plugin: the project's `.cursor/` or `.dev-files/`, or a user path such as `~/.cursor/<plugin>/` or `~/.config/<plugin>/`.
  - Hooks get `CURSOR_PROJECT_DIR`, `CURSOR_PLUGIN_ROOT`, `CURSOR_VERSION` and `CLAUDE_PROJECT_DIR`. Env vars that `sessionStart` returns propagate to later hooks in the same session (doc-cited: hooks.md).
- **Local plugins and symlinks.** *"Symlinks in `~/.cursor/plugins/local` load only when the target resolves to a directory inside that folder."* (doc-cited: plugins.md). This confirms the repo's "real copy" note.
  - Other routes: `~/.cursor/settings.json` `enabled_plugins` (CLI changelog), `--plugin-dir`, and `workspaceOpen` `pluginPaths`.
  - The Enterprise setting "Allow Local Plugin Imports" is off by default.
  - Scope: install at project or user scope. A marketplace install takes precedence over a local copy with the same name.
- **Admins** can set plugin install modes "Default Off", "Default On" or "Required" (doc-cited: plugins.md).

## D. Skills, commands and subagents

- **SKILL.md frontmatter.** doc-cited: https://cursor.com/docs/skills.md
  - Documented fields: `name`, `description`, `paths`, `disable-model-invocation`, `icon`, `color`, `metadata`.
  - `disable-model-invocation: true` means *"only included when explicitly invoked via `/skill-name`"*.
  - `user-invocable: false` is supported in the CLI to hide a skill from `/` (doc-cited: CLI changelog v2026.07.06), but it is absent from the skills doc.
  - **`allowed-tools` is not documented, so assume it is not enforced (unverified).**
- **Arguments.** No `$ARGUMENTS` or argument-hint mechanism is documented for skills or commands. The only `$ARGUMENTS` in the docs is for prompt-type *hooks*.
  - A `/skill-name` invocation *"attaches to one message"*, so trailing text such as `42 --perms=bypass` most likely reaches the model as plain prose (unverified). It is not parsed by the host.
  - Command frontmatter is only `name` and `description` (reference/plugins.md).
- **Discovery.** `.cursor/skills`, `.agents/skills`, `.claude/skills` and `.codex/skills`, at both project and user level. Custom Mode (Option+Enter) pins a skill for the whole session.
- **Subagents.** doc-cited: https://cursor.com/docs/subagents.md
  - Fields: `name, description, model, readonly, is_background`.
  - `readonly: true` means *"restricted write permissions (no file edits, no state-changing shell commands)"*.
  - There is no `tools:` field. *"Subagents inherit all tools from the parent."* In the CLI they inherit *"your credentials, rules, and approval policy"* (CLI changelog).
  - Agents are also read from `.claude/agents`.
- **Approvals inside subagents** surface in the main chat as "Waiting for approval" (IDE 3.26 or later).

## E. Recent changelog items (Aug to Oct 2026)

| Date / version | Item | Source |
|---|---|---|
| CLI 2026.10.22 | Auto-review of MCP sees the tool input schema. A custom subagent with a blocked model falls back to the parent model. | cli/changelog |
| CLI 2026.10.17 | `postToolUse` and `postToolUseFailure` fire for the `Task` (subagent) tool. Subagent hooks get the correct `transcript_path`. Unanswered approvals are no longer reported as cancelled. | cli/changelog |
| CLI 2026.10.15 | Windows hooks that fail are reported as failed instead of silently succeeding. Read deny rules apply outside the workspace. | cli/changelog |
| CLI 2026.10.08 / IDE 3.25 | Auto-review asks before ambiguous recursive and force deletes. Commands matching `block_instructions` *always* show the approval card. | cli/changelog, ide.md |
| IDE 3.26–3.27 | Always Run writes to `permissions.json` `terminalAllowlist`, and is hidden when the list is admin-managed. `parent_agent_id` arrives on `subagentStart`/`subagentStop`. | ide.md |
| IDE 3.24 | `tool_use_id` on shell and MCP hooks matches `preToolUse`. `transcript_path` is always present. `AgentRemoteWorkspaceAuthorities` policy added. | ide.md |
| IDE 3.23 | Read Access Workspace mode, Read Allowlist and team read policy. | run-modes.md |
| CLI 2026.08.11 | Plugin hooks now run, including from `--plugin-dir`. Plugin config forms mask secrets. Admin command denylist enforced in the CLI. Timed mode-switch approvals. | cli/changelog |
| CLI 2026.07.06 | `user-invocable: false` honored. Auto-Accept Web Search permission (`autoAcceptWebSearch`). | cli/changelog |
| Changelog 2026-08-19 | Any skill can be used as a Custom Mode. | changelog/08-19-26 |

---

## Implications for the design

1. **A plugin preset can only tighten, never loosen.** Cursor's own approval (the run mode, the allowlist and the classifier) always applies on top. A hook `allow` does not skip a prompt.
   - "bypass" on Cursor therefore means *the plugin's own gates are off*. Whether a merge command runs silently still depends on the user's Cursor run mode and allowlist (for example `terminalAllowlist: ["gh pr merge"]` or Run Everything).
   - The `/plugin-config` UX must say this explicitly.
2. **Enforce `deny` through hooks, and implement `ask` as a skill-level confirmation.** Hook `ask` is unenforced on `preToolUse` and ignored by `beforeShellExecution` under Auto-review, which is the default mode.
   - The "ask" level must therefore be a prose gate inside the skill: the skill stops and requests explicit approval in chat.
   - Optionally, back it with a `deny` from a `beforeShellExecution` hook for `gh pr merge` that carries an `agent_message` saying "user approval required, re-run after the user says yes". Only `deny` is honored in every mode.
3. **Put the config file outside the plugin root.** The install directory is keyed by commit SHA and Cursor has no `${PLUGIN_DATA}`.
   - Use a user file (such as `~/.config/tamirs-superpowers/permissions.json`) plus a project override (`.dev-files/` or `.tamirs-superpowers.json`).
   - The repo's `hooks/lib/plugin-state.sh` fallback is already the right pattern here.
   - Hooks can read the file through `CURSOR_PROJECT_DIR` and `$HOME`.
4. **There is no reliable install-time prompt.** `variables` is the closest mechanism, but it is documented as a dashboard (team-admin) setting with only `${VAR}` substitution in `mcp.json`.
   - Do not depend on it for the preset. Default to `strict` when no config file exists, and let `/plugin-config` create the file.
   - Whether `variables` values ever reach hook environments: test before using them.
5. **Per-invocation `--perms=bypass` is model-parsed text on Cursor.** It is not host-parsed. The skill must parse it from the prompt itself.
   - Treat any override that *widens* permissions with suspicion: prompt-injected text can contain it. Allow it to widen only up to the user's configured ceiling.
6. **Subagents inherit the parent's approval policy and every tool.** `readonly: true` is the only host-enforced restriction. Per-skill levels must be checked by the plugin's hook or skill, not delegated to Cursor.
7. **The skill `allowed-tools` field is not a Cursor control.** Do not express plugin permission levels through it on this platform.
8. **The CLI has a real deny list (`permissions.deny`, which beats allow).** A `strict` preset could *offer* to add CLI denies such as `Shell(gh:pr merge*)`, but only with explicit user consent, because that writes a user-owned config file.
   - The IDE has no user denylist.
   - The repo's setup module already avoids touching `permissions.deny` on purpose (docs/user/install/cursor.md).

## Repo drift (claims the latest docs contradict, or internal inconsistency)

1. **`subagentStop` wired vs "not wired".** `platforms/cursor/hooks.json` wires `subagentStop` (`subagent-handoff-check.sh`). But all three of these list it as deliberately unwired:
   - `platforms/cursor/README.md` ("What is deliberately not wired").
   - `adapter.yaml` notes ("subagentStart/subagentStop are unwired").
   - The `core/capabilities/platforms.json` cursor hooks note ("Unwired … subagentStop").

   The README's wired table lists only 9 events, while the bundle has 10 and the comment says "Ten". This is internal drift, so one side is stale.
2. **`loop_limit: null` on `preToolUse`/`beforeShellExecution`.** The README and the hooks.json `_comment` justify it as removing a *"default cap of 5 firings per loop"* so a guard keeps guarding. The docs scope `loop_limit` to *"stop/subagentStop hooks"* only (doc-cited: hooks.md). On permission events it is most likely a no-op, so the rationale is wrong.
3. **`platforms.json` `extension_install: unsupported` ("Cursor installs plugins, not git-URL extensions").** The CLI changelog has *"Install plugins from a git URL"* and `agent plugin marketplace add <git-url>`. The claim is arguably stale, depending on what "extension_install" means in the registry.
4. **The hooks note says "only 3 of Cursor's 21 events are wired"** in an earlier sentence of the same `platforms.json` note that later says ten. The text contradicts itself and needs a cleanup.
5. **The install doc's validated CLI version is 2026.09.18.** The latest is v2026.10.22 (installed locally). The desktop latest is 3.28.7 against the 3.27.22 pin. Not a contradiction, but the pin is behind.
6. **The install doc says plugin variables are set "by you"** under Dashboard → Plugins → Configure. The reference says *"Team admins set the actual values in the dashboard"*. Whether a solo or non-team user can set them is unverified, and the claim should be re-checked live.
7. **Confirmed, not drift:**
   - The symlink restriction (plugins.md).
   - Cursor does not read a plugin's Claude-format `hooks/hooks.json`. Only `.claude/settings*.json` is documented, though the CLI note "Plugins imported from Claude Code appear alongside native ones" deserves a live check.
   - Agent `tools:` is not enforced: the subagent schema has no `tools` field. The repo's read-only agents could additionally declare `readonly: true`. `agents/architecture-reviewer.md` has `tools:` but no `readonly:`, and none of the `agents/*.md` files use `readonly`.
   - The fail-closed semantics match the docs.

## Open questions (need a live run)

- Does 3.28.x change hook `allow`/`ask` authority? (There is a feature request: "Support authoritative allow, deny, and ask verdicts from hooks".)
- Do plugin `variables` values reach hook or skill environments, and can a non-team user set them locally?
- How does text after `/pr-dev` reach the model: verbatim in the user message, or wrapped?
- How do the CLI's `cli-config.json` and project `cli.json` permission lists merge?

---

<p align="center"><a href="https://github.com/Tamircohen28">Have a Question?</a>&nbsp;·&nbsp;<a href="https://github.com/Tamircohen28/tamirs-superpowers/issues/new/choose">Open an Issue</a></p>
