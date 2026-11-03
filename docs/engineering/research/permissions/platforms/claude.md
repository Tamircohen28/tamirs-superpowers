# Permissions research: Claude Code (CLI) and Claude Desktop (Code tab)

Research input to ADR 004 (permission levels). Date 2026-11-03. Evidence tags: doc-cited / source-cited / measured / unverified.

Researched 2026-11-03. Tags: `doc-cited` (URL), `measured` (command + output), `unverified`.

## Version baseline

- **Latest release is 2.1.317, the same as the repo pin. No delta.** `measured`:
  `npm view @anthropic-ai/claude-code version` → `2.1.317` (published 2026-11-02T23:57Z);
  `claude --version` → `2.1.317 (Claude Code)`; `.claude-code-version` → `validated_against: 2.1.317`.
- CHANGELOG read through 2.1.282 (about 33 releases) with `gh api repos/anthropics/claude-code/contents/CHANGELOG.md`. `measured`

---

## A. Host permission model

### Settings hierarchy, highest first
`doc-cited` https://code.claude.com/docs/en/settings#settings-precedence
1. **Managed**: server-managed (claude.ai console or apps gateway), MDM/OS policy, `managed-settings.json`, or an embedding host's SDK `managedSettings` (for example Claude Desktop). Nothing below overrides it, including `--settings`.
2. **Command line** `--settings <file|json>` (one session only). Other flags such as `--model`, `--permission-mode`, `--allowedTools` and `--disallowedTools` set single things and sit outside the stack.
3. **Project local** `.claude/settings.local.json`
4. **Shared project** `.claude/settings.json`
5. **User** `~/.claude/settings.json`
- Plugin defaults are a layer *below* user. The mods `settings.read` layers run, lowest first: `plugin, user, project, local, flag, policy`. `doc-cited` https://code.claude.com/docs/en/plugins/mods/events
- **List keys merge.** `permissions.allow/ask/deny` combine across scopes rather than override. `doc-cited` settings page ("Lists merge instead of overriding").
- **Scope limits on modes.** `permissions.defaultMode` values `auto` and `bypassPermissions` do not take effect from project or local files. Only user, `--settings` or managed can set them (since 2.1.257). `doc-cited` settings and permission-modes pages.
- **Workspace trust.** Project `allow` rules, `additionalDirectories` and most `env` wait for workspace trust. `deny` and `ask` apply immediately. A skill's `allowed-tools` is never gated by trust. `doc-cited` https://code.claude.com/docs/en/permissions#project-allow-rules-and-workspace-trust
- **Stricter value wins for some keys.** For a few security keys, a stricter value from any scope beats managed: `blockReadsOutsideWorkingDirectories`, `blockWritesOutsideWorkingDirectories` (2.1.314+), `maxEffortLevel`, and others. `doc-cited` settings page ("Exceptions to managed settings precedence").

### Rule evaluation and syntax
`doc-cited` https://code.claude.com/docs/en/permissions
- **Order is deny, then ask, then allow; first match wins; specificity is ignored.** Quote: "An allow rule can't carve an exception out of a deny rule." A deny from any scope beats an allow from any other scope.
- A bare tool name in `deny` (for example `Bash`) removes the tool from context. A scoped rule leaves the tool available and blocks only matching calls.
- **Bash:** `Bash(npm run build)` matches exactly. `*` matches any text, spaces included. Put the `*` after the subcommand (`Bash(git log *)`). The parser understands shell operators, so every subcommand of a compound command must be allowed. Deny and ask rules match nested subshells. Quote: Bash rules are "not a security boundary around the program" (for example `git -C . push` escapes `Bash(git push *)`).
- **Read/Edit:** gitignore syntax. `//abs`, `~/home`, `/` relative to the settings source, `./` or bare relative to cwd. `!` negation works in deny/ask. `Write(path)` and `Glob(path)` rules never match; `Edit(...)` covers writes.
- **WebFetch:** `WebFetch(domain:example.com)`; `*.example.com` covers subdomains; `domain:*` is not the same as bare `WebFetch`.
- **MCP:** `mcp__server`, `mcp__server__*`, `mcp__server__tool`. Plugin servers are named `mcp__plugin_<plugin>_<server>__*`. Allow globs need a literal server prefix. Deny/ask accept `"*"` and `"mcp__*"`. Rules with parameter parentheses are skipped when loaded from settings.
- **Skill:** `Skill(name)` is exact, `Skill(name *)` is a prefix with arguments, `Skill(skill:<name>)` deny matches aliases, bare `Skill` deny disables all skills. `doc-cited` https://code.claude.com/docs/en/skills
- **Agent:** `Agent(Explore)` in deny blocks that subagent type. `doc-cited` https://code.claude.com/docs/en/sub-agents

### Permission modes
`doc-cited` https://code.claude.com/docs/en/permission-modes
| Mode | Behavior |
|---|---|
| `default` (labelled "Manual", alias `manual`) | Prompts on first use of each tool |
| `acceptEdits` | Auto-accepts edits and common filesystem commands inside the working dirs |
| `plan` | Read-only exploration. A hook or mod `allow` cannot approve a write here (permissions page, "Hook approvals in plan mode") |
| `auto` | A classifier reviews actions; explicit ask rules still prompt. **Built-in default for interactive CLI and VS Code since 2.1.283.** Blocks force-push, `curl \| bash`, prod deploys, and IAM or repo permission grants by default. Pauses after 3 consecutive or 20 total blocks. Broad allow rules (`Bash(*)`, `Agent`) are dropped on entry |
| `dontAsk` | Auto-denies anything that would prompt. CLI only (not Desktop) |
| `bypassPermissions` | Skips prompts except the "actions no mode auto-approves" list: explicit ask rules, `AskUserQuestion`, `requiresUserInteraction` MCP tools, critical-path `rm`, and the block-outside-working-dir keys. Refused as root/sudo. Cannot be entered mid-session unless the session started with it enabled |

- **Locks:** `permissions.disableBypassPermissionsMode: "disable"` and `permissions.disableAutoMode: "disable"` work from any scope and cannot be overridden from managed. Managed-only keys include `allowManagedPermissionRulesOnly` (ignores user/project/local/`--settings` rules and `--allowedTools`, and since 2.1.282/2.1.284 ignores `allowed-tools` from non-vouched plugins), `allowManagedHooksOnly`, `strictPluginOnlyCustomization`, `strictKnownMarketplaces` and `disableCommandPluginSources`. `doc-cited` https://code.claude.com/docs/en/managed-settings and the permissions page.
- **Sandboxing:** OS-level filesystem and network isolation for Bash, PowerShell and Monitor commands and their children. With `autoAllowBashIfSandboxed` (default true), sandboxed Bash skips a bare-`Bash` ask rule. Content-scoped ask rules such as `Bash(git push *)` still prompt. `doc-cited` permissions page ("How permissions interact with sandboxing").

---

## B. What a plugin can affect

| Lever | Can it widen host permissions? | Evidence |
|---|---|---|
| plugin `settings` / root `settings.json` | **No.** "Only `agent` and `subagentStatusLine` take effect; other keys are dropped at load." Cannot ship `permissions` | `doc-cited` https://code.claude.com/docs/en/plugins-reference#settings and https://code.claude.com/docs/en/plugins/components#default-settings |
| Skill `allowed-tools` | **Yes, narrowly.** Pre-approves the listed tools "during the turn that invokes this skill. The grant clears when you send your next message." Does not restrict anything. "Deny and ask rules still override `allowed-tools`." Ignored under managed `allowManagedPermissionRulesOnly` unless the plugin is official or vouched for (2.1.284) | `doc-cited` skills page; changelog 2.1.284/2.1.305 `measured` (gh api) |
| Skill `disallowed-tools` | Narrows: removes tools while the skill is active | `doc-cited` skills page |
| Plugin agent `tools` / `disallowedTools` | Narrows. `disallowedTools` is applied first; a specifier still removes the whole tool | `doc-cited` sub-agents page |
| Plugin agent `permissionMode` | **Ignored for plugin agents**, along with `hooks`, `mcpServers` and `initialPrompt`, "for security reasons" | `doc-cited` sub-agents and components pages |
| PreToolUse hook | `allow` skips the *prompt*, but "Deny and ask rules are still evaluated regardless of what the hook returns." Exit code 2 or `deny` blocks even when an allow rule matches. Several hooks combine as `deny > defer > ask > allow`. `updatedInput` is re-validated (2.1.300) | `doc-cited` https://code.claude.com/docs/en/hooks and the permissions page ("Precedence among rules, hooks, and mods") |
| PermissionRequest hook | `allow`/`deny`, `updatedInput` (re-checked against deny/ask), and **`updatedPermissions`** with `addRules`/`replaceRules`/`removeRules`/`setMode`/`addDirectories` to destinations `session`/`localSettings`/`projectSettings`/`userSettings`. "a hook returning allow doesn't override a matching deny rule" | `doc-cited` hooks page. **Whether a *plugin* hook may write `userSettings` rules or `setMode`: `unverified`**; the docs are silent |
| Mod `tool.check` (this repo ships a mod) | **Yes, conditionally.** "With neither managed settings nor a Team or Enterprise `/login` as the session's credential, the mod can approve a call that a deny rule refuses or a PreToolUse hook blocked." With managed settings or a Team/Enterprise login, deny and ask still hold. `decider: "person"` (2.1.304) forces the dialog | `doc-cited` permissions page and https://code.claude.com/docs/en/plugins/mods/events |
| Mod `settings.read` | Can rewrite the merged settings Claude Code reads. A built-in guard (`cc-plugin-sec-default`) may skip it under managed settings or a Team/Enterprise login | `doc-cited` mods events page |
| `bin/` executables | On the Bash `PATH`, after the user's own entries, so a plugin cannot shadow `git` | `doc-cited` components page |

**Net:**
- Through declarative channels (settings, agent `permissionMode`), a plugin **cannot** escalate.
- Through bash hooks it can only skip prompts that no rule demands.
- Through `allowed-tools` it can pre-approve for one turn.
- Through a **mod** on a personal (Pro/Max) login with no managed settings, it **can override user deny rules**. That is the strongest lever, and it is Claude Code and Desktop-Code-tab only.

---

## C. Plugin configuration (`userConfig`)

`doc-cited` https://code.claude.com/docs/en/plugins-reference#user-configuration and https://code.claude.com/docs/en/plugins/components#ask-the-user-for-configuration-values

**Field types and keys**
- `type` is one of `string | number | boolean | directory | file`.
- Keys: `title` (required), `description` (required), `required`, `default` (string, number, boolean or string[]), `sensitive`, `min`/`max` (number), `multiple` (string).
- Options are strict objects: an unknown key fails the plugin load.

**Enum / choice field**
- `options: [...]` on a non-`multiple`, non-`sensitive` `string` field gives a fixed list, "shown as a picker in `/config`". Requires **v2.1.271+**, and "users on Claude Code versions before v2.1.271 can't load the plugin" once any field declares `options`.
- Each label is 1–64 characters; `default` must be one of them.

**Storage**
- Non-sensitive values go to `pluginConfigs` in **user** `settings.json`. The scope is "User or managed", so a project cannot set it (settings-reference index).
- Sensitive values go to the OS credential store.
- **Values are per-user, not per-project.** `doc-cited`
- `measured`: on this machine `~/.claude/settings.json` has `pluginConfigs: {}`, yet `claude plugin configure ... --json` lists `github_token` as configured. Sensitive values live elsewhere, and defaults are not written.

**When the user is prompted**
- The dialog appears for *unset* options on `/plugin` install, on `/plugin install` inside a session, and when the plugin is enabled from the Installed tab.
- The shell command `claude plugin install` **never prompts**. Use `--config KEY=VALUE` instead.
- **Whether a field with a `default` counts as "unset" and is still shown: `unverified`.**

**Changing values later**
- `/plugin configure <plugin>@<mkt>` or `/plugin` → Installed → Configure.
- `/config` rows for non-sensitive, non-multiple options (v2.1.269+).
- `claude plugin configure <id> --values-stdin` (v2.1.285+).
- The VS Code gear icon.
- `measured`: `claude plugin configure --help` lists `--json` and `--values-stdin`. `claude plugin configure tamirs-superpowers@tamirs-marketplace --json` prints `schema`, `choices` (booleans show as `["true","false"]`), `configured` and `unconfigured`.

**How values reach components**
- `${user_config.KEY}` is substituted in MCP config, LSP config, exec-form hook `args`, **and skill and agent Markdown content** (non-sensitive values only; a sensitive value becomes a placeholder).
- It is **rejected** in shell-form hook commands, monitor commands and `headersHelper`.
- `CLAUDE_PLUGIN_OPTION_<KEY>` (uppercased) is exported to hook processes only.
- Path variables (and so option env vars too, `unverified`) are "not present in the environment of commands Claude runs through the Bash tool". `doc-cited`

**Paths**
- `${CLAUDE_PLUGIN_ROOT}` is the per-version cache directory. It "changes when the plugin updates, so don't write state there."
- `${CLAUDE_PLUGIN_DATA}` is `~/.claude/plugins/data/<id>/`, which survives updates and is deleted on the last uninstall unless `--keep-data` is passed. `doc-cited` plugins-reference, plus https://code.claude.com/docs/en/plugins/cli-reference.

---

## D. Skills and commands

`doc-cited` https://code.claude.com/docs/en/skills

**Arguments**
- `$ARGUMENTS` is everything typed after the command. `$ARGUMENTS[N]` and `$N` are 0-based. `$name` comes from the `arguments:` frontmatter list, in order.
- If no placeholder exists, Claude Code appends `ARGUMENTS: <value>`.
- `argument-hint` only shows during autocomplete.
- Quoting groups words: `"hello world"` arrives as one argument.
- **Argument parsing is text substitution. Nothing in the host interprets `--perms=bypass`.** Inference.

**Invocation control**
- `disable-model-invocation: true`: the description is not in context, Claude cannot invoke the skill on its own (the Skill tool call is blocked), and it "also prevents the skill from being preloaded into subagents" and from running in scheduled tasks.
- `user-invocable: false`: hidden from `/` and not run when typed; Claude can still invoke it.

**Dynamic context**
- `` !`cmd` `` (at line start or after whitespace) and ```` ```! ```` blocks run *before* the content reaches Claude, and the output is inlined.
- Each command is checked against permission rules: a deny aborts the invocation, and outside auto mode a non-allow also aborts unless `allowed-tools` pre-approves it.
- Default timeout is 2 minutes; a failure aborts the skill.
- `disableSkillShellExecution: true` replaces the output with `[shell command execution disabled by policy]`, plugin skills included.
- **So a skill can read a config file or an env var via `!` injection**, for example `` !`cat "${CLAUDE_PLUGIN_DATA}/perms.json"` ``. The path variable is substituted in plugin skill bodies.

**Other substitutions:** `${CLAUDE_SKILL_DIR}`, `${CLAUDE_SESSION_ID}`, `${CLAUDE_EFFORT}`, `${CLAUDE_PROJECT_DIR}`, and `${CLAUDE_PLUGIN_ROOT}`/`${CLAUDE_PLUGIN_DATA}` (plugin skills only). `${user_config.KEY}` works in skill content per the plugins-reference. The skills page itself does not mention it.

**Hooks on invocation**
- `UserPromptExpansion` sees `command_name` and `command_args`. It can `block` or add `additionalContext`, but cannot rewrite them. `doc-cited` hooks page.
- A mod's `prompt.submit` can rewrite the prompt text, and `skill.prompt` can see and alter a skill's text. `doc-cited` mods events page.

---

## E. Claude Desktop (Code tab) differences

`doc-cited` https://code.claude.com/docs/en/desktop unless noted.
- **Settings files:** the same ones the CLI reads (permissions, `defaultMode`, `pluginConfigs`).
- **Plugins:** install through **+ → Add plugins / Manage plugins**, scoped to user, project or local. There is no `/plugin` command; since 2.1.290 typing it explains where to go (changelog, `measured`). Plugins are unavailable in cloud and WSL sessions.
- **userConfig dialog on Desktop:** not documented. `unverified`. `/config` "is part of the terminal interface… the desktop app [doesn't] open it" (`doc-cited` settings page), so the `/config` option picker is CLI-only.
- **Permission modes:**
  - Manual, Accept edits, Plan, Auto and Bypass are available.
  - **`dontAsk` is CLI-only.**
  - There is no Shift+Tab cycling.
  - Bypass needs the "Allow bypass permissions mode" toggle on Pro/Max/Ultra; Team/Enterprise policy controls it.
  - A mode picked in the selector is remembered per folder, except Plan.
  - Since 2.1.309, a critical `rm` in bypass mode is denied with a rewrite hint (changelog, `measured`).
- **Hooks in Desktop sessions:** not stated in the docs. The repo registry says `unknown`, which is consistent.
- **Mods:** they run in the Code tab (except WSL), per the repo registry citing the mods docs. `doc-cited` via repo; not re-fetched.
- **Managed policy:** an embedding host such as Desktop can supply managed settings via SDK `managedSettings`. `doc-cited` settings page.

---

## F. Changelog items, 2.1.282–2.1.317

`measured` via `gh api .../CHANGELOG.md`.

**Permissions and modes**
- 2.1.283: interactive default mode becomes **`auto`** (per the permission-modes doc).
- 2.1.292: a subagent with `permissionMode: auto` no longer enters auto when auto is unavailable.
- 2.1.302: `claude -p` and SDK sessions with no mode start in `default` on third-party providers, with telemetry off, or on a fresh install.
- 2.1.309: critical `rm` in bypass mode on Desktop/VS Code is denied with a hint.
- 2.1.314: `permissions.blockWritesOutsideWorkingDirectories` added. A `--setting-sources` exclusion now really excludes auto rules and saved consents.
- 2.1.316/317: auto-mode fixes, including teammates no longer starting in auto when the lead is manual.

**Plugins and `allowed-tools`**
- 2.1.282/2.1.284: under managed `allowManagedPermissionRulesOnly`, repo/user skills and non-official plugins no longer pre-approve their own tools via `allowed-tools`.
- 2.1.304: under a "hooks from plugins only" policy, a skill whose hooks are kept out loses its `allowed-tools`.
- 2.1.305: plugins that Desktop mounts by path lose `allowed-tools` under the same managed key.

**userConfig**
- 2.1.285: `claude plugin configure` (`--values-stdin`) added; `install --config <server>.<key>`; VS Code plugin options form.
- 2.1.295/2.1.296: plugin options named `constructor` or `prototype` fixed.
- 2.1.288: LSP `${user_config.*}` substitution fixed.
- (From docs, before this window: `options` picker in 2.1.271, `/config` rows in 2.1.269.)

**Hooks**
- 2.1.295: `onFailure: "block"` for command and HTTP hooks.
- 2.1.299/2.1.310: Windows PreToolUse/PermissionRequest hooks no longer fail open.
- 2.1.299: plan mode no longer runs a write that a PreToolUse hook or mod allowed.
- 2.1.300: `updatedInput` validated like model input. Cowork-cloud PermissionRequest `setMode` is ignored.
- 2.1.301: an `ask` prompt now names the plugin or skill the hook comes from.
- 2.1.317: `onFailure: "block"` for SDK callbacks.

**Mods**
- 2.1.299: "Improved enforcement of managed permission rules, managed hooks and organization MCP tool names against user-installed mods."
- 2.1.304: `tool.check` gains `decider: "person"` and `e.isReadOnly`.

---

## Implications for the design

1. **The plugin's levels govern plugin behavior, not host tool permissions.** The plugin cannot ship allow/ask/deny rules (B, settings). "strict/auto/bypass" can only decide what the *skill* chooses to do, such as merging versus waiting. The host's deny/ask rules and mode still gate each tool call. Document it that way.
2. **Rename the presets.** `auto` and `bypass` collide with the host modes `auto` and `bypassPermissions`, and users will expect the plugin preset to change host behavior. Suggest `strict | assisted | autonomous`, or `ask | auto-merge | unattended`. Explicitly say the plugin preset never changes the host mode.
3. **Install-time preset: use a `userConfig` `string` with `options` and `default: "strict"`.** It renders as a picker in `/config` (CLI) and the configure dialog.
   - Cost: plugin load needs ≥2.1.271. Fine for a 2.1.317 pin.
   - Values are per-user only (`pluginConfigs` is user/managed scope), so per-project or per-skill levels need a separate file.
   - Interactive `/plugin` install prompts only for *unset* options. Whether a defaulted option is shown is unverified, so test it.
4. **Per-skill and group levels belong in a file, not `userConfig`.**
   - `userConfig` is flat, with no object type.
   - Put user-wide levels in `${CLAUDE_PLUGIN_DATA}/…`, which survives updates, never in `${CLAUDE_PLUGIN_ROOT}`.
   - Put per-project levels in the existing `.dev-files/policy.json`.
   - `/plugin-config` writes the file. Skills read it via `` !`…` `` injection or a bundled resolver script, like `resolve-merge-policy.sh`.
   - Within a skill body, `${user_config.KEY}` and `${CLAUDE_PLUGIN_DATA}` are substituted at load. Bash commands Claude runs do not get `CLAUDE_PLUGIN_OPTION_*`; only hooks do.
5. **The per-invocation override (`--perms=bypass`) is model-interpreted text in `$ARGUMENTS`.**
   - Fold it into the existing precedence chain: invocation arg > `TAMIRS_AUTO_MERGE` > objective > `policy.json` > preset > repo capability.
   - **Escalation must stay narrowing-safe.** A prompt-injected "--perms=bypass" in a PR body is exactly the attack. Accept an escalating override only from the user-typed invocation, not from content Claude read.
   - Option: a `UserPromptExpansion` hook can see `command_args` and record the override where the resolver reads it, or block a disallowed one. It cannot rewrite the arguments.
6. **Use a host-enforced backstop where one exists.**
   - For merge, the strongest host-level enforcement is an `ask` rule on `Bash(gh pr merge *)` and `mcp__plugin_tamirs-superpowers_github__merge_pull_request`. It prompts even in `bypassPermissions` and auto.
   - The plugin cannot install that rule. It can *recommend* it, or write it via `setup.sh` / capture-config, which are user-run.
   - A PreToolUse hook returning `ask` on merge when the level is strict is the plugin-shippable equivalent. Hook decisions can always narrow.
7. **Do not use the mod's `tool.check` to *allow* things.** On personal logins it can override user deny rules (B). Using it to implement a "bypass" preset would make the plugin an escalation vector, and it fails the directory reviewers' bar. Use `tool.check` only to deny or `ask` (`decider: "person"`).
8. **Desktop degrades:**
   - no `/config` (so no picker there);
   - `dontAsk` does not exist;
   - the userConfig dialog and hooks are unmeasured.
   The skill-level resolver plus file config is the only path that works identically on both surfaces, and on the other platforms.
9. **Respect managed locks.** If `disableBypassPermissionsMode` is set, or the host mode is `plan`/`default`, an "unattended" preset should report that it is constrained rather than pretend. The hook payload's `permission_mode` field (`default|plan|acceptEdits|auto|dontAsk|bypassPermissions`) lets a hook read the host mode. `doc-cited` hooks page.

---

## Repo drift

1. **`settings.statusLine` in `.claude-plugin/plugin.json` is dropped by the host.**
   - Docs: plugin `settings` honors "Only `agent` and `subagentStatusLine`; other keys are dropped at load." `doc-cited`
   - `docs/engineering/statusline.md` line 3 says the statusline "is wired via `settings.statusLine` in `.claude-plugin/plugin.json`", and CLAUDE.md says "`settings.statusLine` → `scripts/statusline.sh`".
   - On this machine `~/.claude/settings.json` has its own `statusLine` (`measured`, key present), which would mask the drop.
   - `unverified` whether the 2.1.317 loader still honors it. Check with `claude --debug` or on a clean `CLAUDE_CONFIG_DIR`.
2. **Auto-merge default disagrees within the repo.**
   - `core/policies/safety.md` row: "Every PR auto-merges | Off unless configured".
   - `skills/dev-workflow/pr-dev/scripts/resolve-merge-policy.sh` header, precedence step 5: "documented default: enable auto-merge when the repository allows it".
   - Decide which is canonical before building presets; `strict` as the default matches safety.md.
3. **`docs/user/configuration.md` lines 65–66 say options can be set "in `/config`".** That is true only in the CLI (v2.1.269+) and only for non-sensitive options. `/config` does not open in Desktop. `doc-cited` settings page. Minor; worth a Desktop caveat.
4. **Registry `claude_desktop.hooks: unknown`** is still correct; the docs remain silent. No drift.
5. **CLAUDE.md "Invocation tiers"** says `disable-model-invocation` blocks sub-agent invocation. The docs agree: "prevents … preloaded into subagents" and the Skill tool call is blocked. No drift.
6. **The registry and CLAUDE.md do not mention that plugin agents ignore `permissionMode`, or that a mod's `tool.check` can override deny rules on personal logins.** Not drift, but both facts are load-bearing for this feature and belong in `platforms.json` notes once the design lands.
