# Codex CLI — permission model and what a plugin can affect

Research input to ADR 004 (permission levels). Date 2026-11-03. Evidence tags: doc-cited / source-cited / measured / unverified.

Researched 2026-11-03.

## Version baseline

- **The latest stable release is 0.166.0**, which is the version the repo pins. There is no delta to research. `measured`: `npm view @openai/codex version` printed `0.166.0` (published 2026-10-29). `gh release list --repo openai/codex` marks `rust-v0.166.0` as "Latest". Three pre-releases sit above it (`0.167.0-alpha.2`, `-alpha.3` and `-alpha.4`, 2026-11-01 to 11-03). None of them was researched.
- **The locally installed CLI is older, at 0.156.0.** `measured`: `codex --version` printed `codex-cli 0.156.0`. It was used only for `--help` probes. Nothing was logged in, installed or configured.
- **Source citations are against the 0.166.0 tag.** I made a shallow clone of `openai/codex` at tag `rust-v0.166.0` into a scratch directory. Every path below is relative to `codex-rs/`.
- **The docs have moved.** Every `developers.openai.com/codex/*` URL now returns a 308 redirect to `learn.chatgpt.com/docs/*`, so the citations below use the new URLs. The plugin developer guide is still served at `developers.openai.com/plugins/build/plugins`.

---

## A. Host permission model (0.166.0)

### A1. Approval policy (`approval_policy`, CLI `-a/--ask-for-approval`)

| Value | Status in 0.166.0 | Evidence |
|---|---|---|
| `on-request` | Default. "The model decides when to ask." | `source-cited` protocol/src/protocol.rs:1145-1155 (`#[default] OnRequest`) |
| `on-failure` | **No longer a separate mode.** It is a serde alias of `on-request`. | `source-cited` protocol.rs:1153 `#[serde(alias = "on-failure")]` |
| `never` | Never asks. Failures go straight back to the model. | `source-cited` protocol.rs:1164-1167 |
| `granular = { sandbox_approval, rules, skill_approval, request_permissions, mcp_elicitations }` | Each flag is a bool. `true` allows that kind of prompt; `false` auto-rejects it and the user never sees it. | `source-cited` protocol.rs:1157-1186. `doc-cited` https://learn.chatgpt.com/docs/agent-approvals-security |
| `untrusted` | **Retired for users.** Setting it in config is an error, and the docs warn it "can prevent either client from starting". It survives only as an internal policy for projects marked untrusted. | `source-cited` core/src/config/mod.rs:232-234 (`approval_policy = "untrusted" is no longer supported`). Release 0.149.0 #39630 "Retire the untrusted approval policy". `doc-cited` agent-approvals-security |

- **The CLI flag accepts only two values.** `-a` takes `on-request` or `never`. `source-cited` utils/cli/src/approval_mode_cli_arg.rs:9-16. `granular` can only be set through config or `-c`.
- **Automatic review ("guardian").** `approvals_reviewer = "user"` (the default) or `"auto_review"`. It only reviews actions that would already have prompted. Low and medium risk can proceed, critical risk is denied, and any failure blocks the action. `doc-cited` agent-approvals-security.

### A2. Sandbox (`sandbox_mode`, CLI `-s/--sandbox`)

- **Three modes:** `read-only`, `workspace-write` and `danger-full-access`. `read-only` is the serde default. The `SandboxPolicy` enum also has an internal `external-sandbox` variant. `source-cited` protocol/src/config_types.rs:104-115 and protocol.rs (`SandboxPolicy`).
- **Defaults depend on the folder.** Version-controlled folders default to `workspace-write`; other folders default to `read-only`. Network access is off by default and is enabled with `[sandbox_workspace_write] network_access = true`. `.git`, `.agents`, `.codex` and `.aws` stay read-only even under writable roots. `doc-cited` agent-approvals-security.
- **Permission profiles are the newer mechanism.** They are set with `default_permissions = "<name>"` and defined as `[permissions.<name>]` (for example `extends = ":workspace"`). The built-in profiles are `:read-only`, `:workspace` and `:danger-full-access`. `source-cited` protocol/src/models.rs:414-420. `doc-cited` agent-approvals-security.

### A3. Shortcut flags

- **`--full-auto` no longer exists.** Release 0.147.0 says "Remove the deprecated `codex exec --full-auto` flag; use `--sandbox workspace-write`" (#36054). `measured`: `codex --help` and `codex exec --help` on 0.156.0 show no such flag. `source-cited`: grep for `full_auto` across the 0.166.0 tree finds no matches.
- **`--approve-for-me` (alias `--not-so-yolo`) replaced it.** It injects `approvals_reviewer="auto_review"`, `approval_policy="on-request"` and `sandbox_mode="workspace-write"`. It cannot be combined with `--sandbox` or `--yolo`. `source-cited` utils/cli/src/shared_options.rs:43-50, 78-91. Added in 0.147.0 (#36373).
- **`--dangerously-bypass-approvals-and-sandbox` (alias `--yolo`)** sets no approvals and no sandbox. `source-cited` shared_options.rs:52-59.
- **`--dangerously-bypass-hook-trust`** runs enabled hooks without persisted trust, for that one invocation. `source-cited` shared_options.rs:61-64.

### A4. Configuration layers and precedence

`doc-cited` https://learn.chatgpt.com/docs/config-file/config-basic. Highest first:

1. CLI flags and `-c/--config key=value` overrides.
2. Project `.codex/config.toml`, from the root down to the cwd. Closest wins, and only in trusted projects.
3. Profile file `~/.codex/<name>.config.toml`, chosen with `-p/--profile`. This is "profile v2": a separate file, not a `[profiles.x]` table. `source-cited` shared_options.rs:34-36, config_types.rs (`ProfileV2Name`).
4. User `~/.codex/config.toml`.
5. Cloud-managed defaults.
6. System `/etc/codex/config.toml`.
7. Built-in defaults.

- **Layer sources in code:** PackagedDefaults, Mdm, System, EnterpriseManaged, User, Project, SessionFlags and two legacy-managed sources. **There is no plugin layer.** `source-cited` config/src/config_layer_source.rs:8-27.
- **`requirements.toml` sets constraints, not defaults.** It holds `allowed_approval_policies`, `allowed_sandbox_modes`, `allowed_permission_profiles`, `allowed_approvals_reviewers`, `allow_managed_hooks_only`, `rules`, `plugins`, `mcp_servers` and `network`. `source-cited` config/src/config_requirements.rs:1073-1100. `doc-cited` config-basic ("Requirements constrain behavior; configuration values provide defaults").

### A5. Project trust

- **Trust is recorded per project** as `[projects."/path"] trust_level = "trusted" | "untrusted"` in the user config.
- **An untrusted project loses its whole `.codex/` layer:** config, hooks, rules and `AGENTS.md`. It also runs under the internal untrusted approval policy, where commands need approval unless an execpolicy rule allows them. `doc-cited` config-basic and agent-approvals-security. Release 0.150.0 #39837.

### A6. Command rules (execpolicy)

- **Format.** Rules are `.rules` files in a `rules/` folder next to any active config layer, for example `~/.codex/rules/default.rules` or a trusted `<repo>/.codex/rules/`.
- **Syntax.** `prefix_rule(pattern=[...], decision="allow"|"prompt"|"forbidden", justification=..., match=..., not_match=...)`. The most restrictive matching rule wins: `forbidden` > `prompt` > `allow`.
- **Testing.** `codex execpolicy check --rules F -- cmd`.
- **Status.** Rules are documented as "experimental". `doc-cited` https://learn.chatgpt.com/docs/agent-configuration/rules.
- **Plugins cannot ship rules.** The loader collects rules only from each config layer's folder. `source-cited` core/src/exec_policy.rs:664-685.
- **The TUI writes rules too.** Approving "always allow" in the TUI writes to `~/.codex/rules/default.rules`. `doc-cited` rules page.

---

## B. What a plugin can affect

### B1. Manifest

- **Codex reads two manifest formats.**
  - Legacy `.codex-plugin/plugin.json` accepts `name`, `version`, `description`, `keywords`, `skills`, `mcpServers`, `apps`, `hooks`, `interface` and a free-form `extensions` object. A separate pass reads `commands`. `source-cited` core-plugins/src/manifest.rs:50-79.
  - The portable root `plugin.json` keeps OpenAI-specific keys under `extensions.com.openai`. `doc-cited` https://developers.openai.com/plugins/build/plugins.
- **Neither format has a field for permissions, approvals, sandbox, execpolicy rules, agents or user config.** `source-cited` manifest.rs:50-74. `doc-cited` plugins/build/plugins ("doesn't document userConfig, install-time options, rules/execpolicy, agents, commands, or permission declarations").
- **Claude-style `commands/` are converted into skills at install.** Codex rewrites them as skills under the plugin. Any command whose body uses `$ARGUMENTS`, `$1`, `{{…}}`, `` !`…` `` or `@file` is **skipped**. `source-cited` core-plugins/src/command_migration.rs:350-358, 418-427 and store.rs:644 (legacy format only).

### B2. Hooks

- **Events:** `SessionStart`, `SessionEnd`, `PreToolUse`, `PermissionRequest`, `PostToolUse`, `UserPromptSubmit`, `Stop`, `PreCompact`, `PostCompact`, `SubagentStart`, `SubagentStop`, `PreModelRequest`, `PostModelRequest` and `Interrupt`. `doc-cited` https://learn.chatgpt.com/docs/hooks.
- **`PreToolUse` can only deny or rewrite. It cannot approve or ask.**
  - `deny` must carry a non-empty `permissionDecisionReason`. Exit code 2 and legacy `decision:"block"` also deny.
  - `allow` is accepted only together with `updatedInput`, which rewrites the call. `allow` without it fails as "unsupported permissionDecision:allow".
  - `ask` fails as unsupported.
  - Every failed answer is treated as fail-open: the tool call proceeds.

  `source-cited` hooks/src/engine/output_parser.rs:440-470 and hooks/src/events/pre_tool_use.rs:577-629. `doc-cited` hooks page.
- **`PermissionRequest` can answer approval prompts on the user's behalf.** It runs only when Codex is about to ask (a shell escalation or a managed-network approval). It may return `hookSpecificOutput.decision.behavior: "allow"` or `"deny"`, and any `deny` wins. Returning `updatedInput`, `updatedPermissions` or `interrupt:true` makes it fail closed. `doc-cited` hooks page. `source-cited` output_parser.rs:381-410.
  - **This is the only hook surface that can *widen* behaviour**, by auto-approving a prompt. It cannot change the policy itself.
  - Under `approval_policy = never` there are no prompts, so this hook never fires (inferred from the doc text "doesn't run for commands that don't need approval").
- **Hooks are told only whether the host is in `never` mode.** Their stdin carries `permission_mode`: `"bypassPermissions"` when `approval_policy = never`, otherwise `"default"`, which covers `on-request`, `granular` and untrusted. It does not include the sandbox mode. `source-cited` core/src/hook_runtime.rs:1073-1080 and hooks/src/schema.rs:292-338, 852-855.
- **Plugin hooks run only after the user trusts them.**
  - Trust is bound to a content hash of the whole plugin root, so updating any bundled script requires re-review in `/hooks`. `source-cited` hooks/src/engine/discovery.rs:304-310 (`plugin_content_hash(&plugin_root)`). `doc-cited` hooks page.
  - Managed config can set `allow_managed_hooks_only = true`, which drops plugin hooks entirely. `doc-cited` hooks page.
- **Hook environment.** Hooks receive `PLUGIN_ROOT`, `PLUGIN_DATA`, `CLAUDE_PLUGIN_ROOT` and `CLAUDE_PLUGIN_DATA`. `source-cited` discovery.rs:311-319.
- **Agent Plugins manifests get no hooks.** When a plugin uses the portable root `plugin.json`, Codex sets its hook sources to empty. `source-cited` core-plugins/src/loader.rs:984-994 and manager.rs:2812-2817. This confirms the repo's 0.163.0 measurement still holds on 0.166.0. It contradicts plugins/build/plugins, which describes hooks under `extensions.com.openai`.

### B3. Skills

- **SKILL.md frontmatter is minimal.** Only `name`, `description` and `metadata.short-description` are parsed. There is no `allowed-tools`, `disable-model-invocation` or argument hint. `source-cited` skills/src/parser.rs:6-20.
- **`agents/openai.yaml` adds three sections:**
  - `interface`
  - `dependencies.tools`
  - `policy.allow_implicit_invocation` (default true) and `policy.products`

  `source-cited` skills/src/metadata.rs:35-58. `doc-cited` https://learn.chatgpt.com/docs/build-skills.
- **Skill scripts go through approvals like any command.** Prompts they trigger fall under granular `skill_approval`. `source-cited` protocol.rs:1177-1179.

### B4. Custom agents

- **Agents are standalone TOML files** in `~/.codex/agents/` or `.codex/agents/`. A plugin cannot bundle one. `doc-cited` https://learn.chatgpt.com/docs/agent-configuration/subagents.
- **A role can only narrow the parent session, never widen it.** The source says: "Roles may customize the child or reduce its capabilities, but never replace the parent session's authority." `source-cited` core/src/agent/role.rs:1-4.
  - A role may set instructions, model and reasoning. It may turn off `shell_tool`, `apps`, `plugins`, `memory_tool` or `request_permissions_tool`, and it may turn off skills. `source-cited` role.rs:79-114.
  - Any `sandbox_mode` or `approval_policy` in a role file is parsed (the struct flattens `ConfigToml`) but **not applied**. `source-cited` agent-roles/src/agent_role_config.rs:20-28 and role.rs:79-88.
  - Children inherit the live turn's `approval_policy`, sandbox and approvals reviewer. `source-cited` core/src/agent/child_config.rs:175-188. `doc-cited` subagents ("A custom agent file can't replace those settings").

### B5. Widen or narrow?

- **A plugin cannot widen host permissions declaratively.** There is no manifest field and no config layer to do it with (B1 and A4).
- **It can narrow** with `PreToolUse` deny.
- **It can effectively widen only through `PermissionRequest` allow**, which answers prompts the host would otherwise show. It never changes the sandbox, and it needs the user to trust the hook first.

---

## C. Plugin configuration

- **There is no install-time prompt or `userConfig` analogue.**
  - The documented install flow only prompts to connect MCP or app services. `doc-cited` https://learn.chatgpt.com/docs/plugins.
  - MCP credentials are "supplied during connection setup", never through the manifest. `doc-cited` plugins/build/plugins.
- **`onboardingSkill` is the closest thing, and probably not on the CLI.** `extensions["com.openai"].onboardingSkill` points at a packaged setup skill. The legacy manifest honours it too. `source-cited` manifest.rs:387-390, 554-568.
  - The app-server exposes it in its plugin detail response, but only when the plugin is enabled. `source-cited` app-server/src/request_processors/plugins.rs:1119-1136.
  - The TUI references it nowhere outside tests, so the CLI probably does not run it automatically. That conclusion is from absence, so it is `unverified`.
- **The user-side `[plugins."<name>@<marketplace>"]` table is strict.** It accepts only `enabled`, `remote_plugin_id`, `release_id`, `auto_provision` and `mcp_servers.<srv>`. The last one takes `enabled`, `default_tools_approval_mode` (`auto | prompt | writes | approve`), `enabled_tools`, `disabled_tools` and `tools.<t>`. The JSON schema marks it `deny_unknown_fields`. `source-cited` config/src/types.rs:1100-1195 and config/src/mcp_types.rs:29-35. **Our own settings must not go there.**
- **Persistent data directory.** `PLUGIN_DATA` is `$CODEX_HOME/plugins/data/<plugin>-<marketplace>`. Neither install nor uninstall touches it, so it survives updates. `source-cited` core-plugins/src/store.rs:27, 90-92, 122-127, 343-345.
  - **Only hooks get it as an environment variable.** No non-test code exports it to skills or shell commands. `source-cited`: a grep for `"PLUGIN_DATA"` finds only hooks/src/engine/discovery.rs and codex-mcp/src/agent_plugin_config.rs.
- **Installed copy.** The plugin is copied to `$CODEX_HOME/plugins/cache/<marketplace>/<plugin>/<version>/` and replaced atomically on update. Old version directories are deleted. `source-cited` core-plugin-common/src/installed.rs:11 and store.rs:112-119, 554, 693-715.
- **Reading user settings.**
  - Hooks can read `$PLUGIN_DATA/...` or `$CODEX_HOME`, and can read the repo files.
  - Skills can only read files through the model's shell tool. Reads are allowed in every sandbox mode except managed deny-read rules.
  - A skill writing under `~/.codex/...` is a write outside the workspace, so it needs an approval escalation under `workspace-write`. That is inferred from the writable-roots docs and `unverified` live.

---

## D. Skills and commands

- **There is no argument substitution.**
  - Codex skills have no `$ARGUMENTS` or `$1`. `doc-cited` build-skills (no mention).
  - The converter explicitly refuses to convert command templates that use them. `source-cited` command_migration.rs:418-427.
  - A message like `$pr-dev 42 --perms=bypass` reaches the model as plain text, so the skill has to parse it from the prompt. `unverified` live.
- **Explicit invocation** is `$skill-name` in the composer or the `/skills` picker. `allow_implicit_invocation: false` in `agents/openai.yaml` blocks auto-selection, but `$skill` still works. `doc-cited` build-skills. `source-cited` metadata.rs:53-58.
- **Skills can be disabled per user.** `[[skills.config]] name=… | path=… enabled=false` in user config; the last match wins. `doc-cited` build-skills.
- **Skills can read config only through shell commands** (`cat ~/.codex/...`, `cat $REPO/.codex/...`). They get no `PLUGIN_ROOT` or `PLUGIN_DATA` (see C), so a skill has to find its own data directory from `CODEX_HOME`, defaulting to `~/.codex`.

---

## E. Changelog items relevant to this design (0.147.0 → 0.166.0)

Source: `gh release view rust-v<ver> --repo openai/codex` for each release. These are `doc-cited` from release notes.

- **0.147.0**
  - `--full-auto` removed from `codex exec` (#36054).
  - `--approve-for-me` added (#36373).
- **0.148.0**
  - Per-environment permission profiles (#38673).
  - Command and MCP-tool hook actions, and async hooks.
- **0.149.0**
  - `untrusted` approval policy retired (#39630).
  - Requirements policy moved to execpolicy (#38899).
  - Resumed and forked threads restore their permission profile (#39153).
- **0.150.0**
  - `Interrupt` hook added (#40511).
  - Untrusted projects no longer supply `AGENTS.md` (#39837).
  - Shortcuts to cycle permission modes (#39873).
- **0.151.0**
  - Per-repository plugin configuration in catalogs (#41208).
  - `/cd` can no longer weaken the sandbox (#41192).
- **0.153.0**
  - Remote-marketplace plugin CLI (#42150).
  - Full Access skips guardian review for confirmation-only actions (#42147).
- **0.154.0**
  - Running sessions refresh skills and hooks after an external plugin upgrade (#42284). The content-hash trust check therefore re-triggers mid-session.
  - No PATH helpers run before workspace trust is established (#42324).
- **0.158.0**
  - Terminal input approval is on by default for elevated commands (#47799).
  - Portable project-trust lookup APIs (#47620).
  - Extension hooks for model requests (#47679).
- **0.159.0**
  - `.aws` is protected under writable roots (#48176).
  - The bundled `plugin-creator` skill was removed (#48604).
- **0.161.0**
  - An approved filesystem escalation can grant broader writes but keeps denied reads (#49353).
  - Hook matchers are compiled during discovery (#49379).
- **0.163.0**
  - Resume restores permissions and network approvals (#53150).
  - Readable plugin mentions (#51865).
- **0.164.0**
  - **Inline `/permissions <profile>` and `/model` arguments** (#54378, #54383).
  - Guardian requires fresh approval for escalated retries (#54263).
- **0.165.0**
  - Environment-scoped managed hooks (#56304).
  - The TUI honours the server's default approval reviewer (#56090).
- **0.166.0**
  - Acknowledged approval and permission settings survive resume and fork (#57227).
  - `PreToolUse` reports the local cwd (#57198). Permission and post-tool hooks keep the command cwd (#57203).

---

## Implications for the design

1. **Our presets cannot drive Codex's host permissions.** "strict / auto / bypass" can only govern what the plugin's skills decide to do. A plugin has no declarative way to change `approval_policy` or `sandbox_mode` (B1, B5, A4). The honest model is that plugin permissions sit on top of host permissions and can only be stricter than them. If the host is `read-only` and on-request, `bypass` still prompts at the host layer.
2. **The presets map onto the host modes like this:**
   - **strict:** works on any host mode.
   - **auto:** most meaningful under `--approve-for-me` or `on-request`.
   - **bypass:** cannot be granted by the plugin. Codex only skips its own prompts under `--yolo` or `-a never`, and the user has to choose that.
   - A `PreToolUse` hook can see `permission_mode == "bypassPermissions"` (host `never`) and could warn when the plugin preset is looser than the host (B2).
3. **Plugin "ask" cannot be a hook verdict.** `PreToolUse` `ask` is unsupported and fails open. Asking has to live inside the skill, as an instruction to stop and ask the user in chat. `deny` is the only reliable hook-level enforcement, and with no `onFailure` it also fails open when the guard crashes.
4. **`PermissionRequest` allow is the one auto-approve lever.** Using it (for example so `auto` approves `gh pr merge` escalations) would be a widening the user has to trust in `/hooks`. Under the repo's own safety policy it needs explicit opt-in, and the default should be off.
5. **Install-time preset selection cannot happen in the Codex install flow.** Options:
   - A first-run check in the `SessionStart` hook, which writes `$PLUGIN_DATA/config.json` with the strict default and can tell the user to run the config skill.
   - Or `setup.sh apply --targets codex`.

   `onboardingSkill` is surfaced only through the app-server and is not proven on the CLI.
6. **Where the config file lives.**
   - User scope: `$CODEX_HOME/plugins/data/tamirs-superpowers-<marketplace>/`. It survives updates, and hooks get its path as `PLUGIN_DATA`.
   - Repo scope: a repo-local file (for example `.dev-files/` or `.tamirs-superpowers.json`), which skills can read and write without escalation.
   - **Never** inside the plugin root: it is replaced on update and hashed for hook trust.
   - **Never** under `[plugins.X]` in `config.toml`: that table is strict about its keys.
7. **The config skill's writes need approval.** A `/plugin-config` skill writing under `~/.codex` is a sandbox escalation under `workspace-write` (unverified live), so the user will see an approval prompt. Document it, or default writes to the repo-scope file. On Codex the skill is invoked as `$plugin-config` or by name. Slash-command plugin skills remain unverified.
8. **The per-invocation override has to be parsed from prose.** `pr-dev 42 --perms=bypass` gets no substitution and no structured arguments. The skill must find `--perms=<level>` in the user's message. Codex converts command templates that use `$ARGUMENTS` only by skipping them, so do not add a `commands/` file expecting arguments.
9. **Agents cannot carry permission levels.** Do not emit `sandbox_mode` or `approval_policy` into the generated `.codex/agents/*.toml`. They are ignored, and children inherit the parent's live policy. `features.shell_tool = false`, which the repo already emits, is the correct narrowing mechanism.
10. **Rules (`prefix_rule`) are a possible host-side complement, never shipped by the plugin.** The `setup.sh` Codex module could optionally write `~/.codex/rules/tamirs-superpowers.rules`, for example `prompt` on `gh pr merge` in strict, with the user's consent. They are experimental, and the user owns them.

---

## Repo drift

1. **The registry's install command does not exist.** `core/capabilities/platforms.json:452` and `:540` give `codex plugin install tamirs-superpowers`. The 0.166.0 CLI has no `install` subcommand, only `add | list | marketplace | remove`, and `add` takes `PLUGIN@MARKETPLACE`. `source-cited` cli/src/plugin_cmd.rs:61-80. `measured` on 0.156.0 with `codex plugin --help`. The correct command is `codex plugin add tamirs-superpowers@tamirs-superpowers`, which docs/user/install/codex.md already uses.
2. **`platform-specs.md` lists two wrong config values.** `skills/repo/multi-agent-repo/references/platform-specs.md:325-326` gives `approval_policy` values `"untrusted" | "on-request" | "never"`.
   - `untrusted` has been retired since 0.149.0 and is now a config error that can stop Codex starting.
   - `on-failure` is an alias of `on-request`, and `granular` is missing.
   - The `sandbox_mode` line leaves out `read-only`, which is the default.
3. **A config comment points at the wrong hooks file.** `.codex/config.toml` says "hooks/hooks.json is wired for Codex via .codex-plugin/plugin.json". Since 5.0.0 it is the generated `platforms/codex/hooks.json`.
4. **Docs and code disagree about Agent Plugins hooks.** plugins/build/plugins describes hooks under `extensions.com.openai`, but 0.166.0 source still empties hook sources for that format (loader.rs:984-994). This **confirms** the repo's decision to ship no root `plugin.json`, and the adapter note stays correct. Keep it measured on each bump.
5. **The install doc understates what Codex documents.** docs/user/install/codex.md:179 says "auto-invocation · slash commands: unknown". Codex documents implicit selection by description, `$skill` explicit mention and `allow_implicit_invocation`. The registry's `skill_auto_invocation: unknown` is defensible as unmeasured, but explicit `$name` is doc-cited and could be recorded.
6. **No `full-auto` mentions were found** in the Codex install doc, adapter or registry. Check any other skill references to `codex --full-auto` before shipping (not swept).
7. **Confirmed accurate for 0.166.0:**
   - The `PreToolUse` contract notes in codex.md (deny only, `ask` rejected, fail-open).
   - The hook environment variables.
   - Hash-bound trust.
   - The `SessionEnd` and `Interrupt` 3 s clamp (`doc-cited` hooks page).
   - The registry's "agents not plugin-shippable" note.

## Open questions (unverified)

- Does the CLI TUI ever surface `onboardingSkill` after `codex plugin add`?
- Are hook commands sandboxed? No sandbox reference appears in hooks/src/engine, which suggests they run unsandboxed.
- Does a skill shell write to `$CODEX_HOME/plugins/data/...` prompt under `workspace-write` on 0.166.0?
- Does `PermissionRequest` fire for prompts that granular `false` flags auto-reject? (Probably not.)
- Is the strict schema on `[plugins.X]` enforced at load time, or only by the JSON schema? Serde has no `deny_unknown_fields` there, so unknown keys may be silently ignored.

---

<p align="center"><a href="https://github.com/Tamircohen28">Have a Question?</a>&nbsp;·&nbsp;<a href="https://github.com/Tamircohen28/tamirs-superpowers/issues/new/choose">Open an Issue</a></p>
