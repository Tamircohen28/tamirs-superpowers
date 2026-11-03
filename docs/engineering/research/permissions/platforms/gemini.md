# Gemini CLI (+ Antigravity): permission research for the plugin-permissions feature

Research input to ADR 004 (permission levels). Date 2026-11-03. Evidence tags: doc-cited / source-cited / measured / unverified.

Researched 2026-11-03.

## Version baseline

- **Latest stable is `0.66.0`, released 2026-10-27, the same as the repo pin.** `measured`: `npm view @google/gemini-cli dist-tags` returned
  `latest: 0.66.0`, `preview: 0.67.0-preview.0`, `nightly: 0.67.0-nightly.20261103.g0ac57c029`.
  So there is no stable delta against 0.66.0. The preview items are listed in section F.
- **Source read:** a shallow clone of tag `v0.66.0` (commit `970413207732`). Citations below
  use `S:` for `https://github.com/google-gemini/gemini-cli/blob/v0.66.0/` and `D:` for the
  same tree's `docs/`.
- **The locally installed binary is `0.60.0`.** `measured`: `gemini --version` printed `0.60.0`. Its `--help` was used only
  for flag names.

---

## A. Host permission model (0.66.0)

**Approval modes.** There are four modes: `default`, `autoEdit` (`auto_edit` on the CLI), `plan` and `yolo`.
`source-cited`: S:packages/core/src/policy/types.ts L48-53, S:packages/cli/src/config/config.ts L698-734.
- `--yolo` and `--approval-mode` cannot be combined (config.ts L258).
- **YOLO cannot be set as a persistent default.** `general.defaultApprovalMode` accepts only
  `default | auto_edit | plan`, and a `yolo` value there is ignored. `source-cited`: config.ts L700-704;
  settingsSchema.ts L228-245.
- `security.disableYoloMode` or `admin.secureModeEnabled` turns a YOLO request into a fatal
  error. `source-cited`: config.ts L737-751.
- **An untrusted folder forces the mode to `default`.** `source-cited`: config.ts L759-764.

**Policy engine.** Rules live in TOML `[[rule]]` blocks.
`doc-cited`: D:reference/policy-engine.md L284-354.
- **Fields:** `toolName` (string or array; wildcards `*`, `mcp_server_*`, `mcp_*`), `mcpName`,
  `subagent`, `toolAnnotations`, `argsPattern` (a regex over the stable-stringified args JSON),
  `commandPrefix` (string or array) and `commandRegex` (mutually exclusive, shell only),
  `decision` (`allow | deny | ask_user`), `priority` (0-999), `denyMessage`, `modes[]`,
  `interactive` and `allowRedirection`.
- **`ask_user` in non-interactive mode is treated as `deny`.** `doc-cited`: L116-117.
- A global `deny` with no argsPattern removes the tool from the model's view. `doc-cited`: L112-115.
- **Subagents** can be matched as a virtual `toolName`. `doc-cited`: L459-478.

**Tiers and priority.** Source is authoritative here because the doc contradicts itself.
`source-cited`: S:packages/core/src/policy/config.ts L67-81 and L375-400.

| Tier | Base | Location |
|---|---|---|
| Default | 1 | built-in `packages/core/src/policy/policies/*.toml` |
| Extension | 2 | `<ext>/policies/*.toml` |
| Workspace | 3 | `.gemini/policies/`. **Disabled** by `disableWorkspacePolicies = true` (S:packages/cli/src/config/policy.ts L42); doc warns issue #18186 |
| User | 4 | `~/.gemini/policies/*.toml`, `--policy`, `policyPaths` |
| Admin | 5 | `/Library/Application Support/GeminiCli/policies` (root-owned, not group/other-writable) plus `--admin-policy` / `adminPolicyPaths` |

- **Formula:** `final = tier + priority/1000`, and the highest-priority match wins.
- **Settings-derived rules sit in the user band.** `source-cited`: config.ts L75-81, yolo.toml header.

  | Rule source | Priority |
  |---|---|
  | "Always allow" persisted approval | 4.95 user-scope, 3.95 workspace-scope (`policy-updater` in config.ts L719-775) |
  | MCP excluded | 4.9 |
  | `tools.exclude` / `--exclude-tools` | 4.4 |
  | `tools.confirmationRequired` | 4.35 |
  | `tools.allowed` / `--allowed-tools` | 4.3 |
  | `tools.core` | 4.25 |
  | trusted MCP | 4.2 |
  | allowed MCP | 4.1 |

- **Default rules.** `source-cited`: S:packages/core/src/policy/policies/write.toml, yolo.toml.
  - Read-only tools allow at 1.050.
  - Write tools and **`activate_skill`** are `ask_user` at 1.010, interactive only. So in `default` mode
    a skill activation itself prompts.
  - `autoEdit` allows `write_file` and `replace` at 1.015, with an `allowed-path` safety checker.
  - **YOLO's allow-all is only `1.998`**, a default-tier rule. `ask_user` is still asked at 1.999 in YOLO.
- **The doc's tier table disagrees with its own examples.** The examples ("Workspace 2.010, User
  3.100, Admin 4.020") and "Admin tier (Base 4)" still use the old numbering. The extension reference says tier 2 is
  "alongside workspace-defined policies". `doc-cited`: D:reference/policy-engine.md L140-166 and L256;
  D:extensions/reference.md L271-273. The source values above are correct.

**`tools.*` settings.**
- `tools.core` is a built-in allowlist, `tools.allowed` bypasses confirmation, `tools.exclude` removes tools,
  and `tools.confirmationRequired` always asks.
- `tools.exclude` is deprecated in favour of `deny` rules, and `--allowed-tools` is marked
  deprecated.
- `doc-cited`: D:reference/configuration.md L1846-1874, policy-engine.md L119-123.
  `measured`: the `gemini --help` line `--allowed-tools [DEPRECATED: Use Policy Engine instead ...]`.

**Other security switches.** `doc-cited`: configuration.md L1944-1967 and L2460.
- `security.disableAlwaysAllow`
- `security.enablePermanentToolApproval` (default false)
- `security.autoAddToPolicyByDefault`
- `security.blockGitExtensions`
- `admin.secureModeEnabled`, which disallows YOLO and "Always allow"

**Trusted folders.** An untrusted folder runs in "safe mode":
- workspace settings are ignored;
- `.env` files are ignored;
- extensions cannot be installed, updated or uninstalled;
- the approval mode is forced to default.

`doc-cited`: D:cli/trusted-folders.md L72-85. `source-cited`: config.ts L759.

**Sandbox.**
- `-s/--sandbox` and `tools.sandbox` support docker, podman, lxc, windows-native or a profile path. It is described as a
  "Legacy full-process sandbox". `doc-cited`: configuration.md L1785-1791.
- A newer `sandbox-default.toml` policy exists. `source-cited`: S:packages/core/src/policy/policies/.
- Not needed for this design.

**Settings hierarchy**, lowest to highest:
1. defaults
2. system-defaults file
3. user `~/.gemini/settings.json`
4. project `.gemini/settings.json`
5. system settings file
6. environment variables
7. CLI flags

`doc-cited`: D:reference/configuration.md L7-20.

## B. What an extension can affect

**`gemini-extension.json` fields:** `name`, `version`, `description`, `mcpServers` (every option except `trust`),
`contextFileName`, `excludeTools`, `migratedTo`, **`plan.directory`** (singular `plan`, not
`plans`), `settings[]` and `themes`. `doc-cited`: D:extensions/reference.md L113-176.
- `plan.directory` must be relative with no `..`. `source-cited`: S:packages/cli/src/config/extension-manager.ts L967-980.
- Hooks go in `hooks/hooks.json`, not the manifest. Skills go in `skills/`, agents in `agents/`, commands in
  `commands/*.toml`, and policies in `policies/*.toml`. `doc-cited`: reference.md L229-299.

**Extension policies can only narrow.** The loader strips every `allow` rule and every rule or safety checker whose
`modes` includes `yolo`, with a warning. `deny` and `ask_user` survive. `source-cited`:
S:packages/core/src/policy/config.ts L227-281. `doc-cited`: reference.md L275-280.

Consequences, all `source-cited` from the priority values above:
- **An extension rule with no `modes` stays active in YOLO.** An extension `deny` or `ask_user` sits at 2.x and beats YOLO's
  allow-all at 1.998, so extension denies and asks hold under `--yolo`.
- **The user beats the extension on every path:**
  - a user TOML at 4.x;
  - `tools.allowed` at 4.3;
  - **any "Always allow" the user clicks** at 3.95 or 4.95.

  So a persisted user approval for the prefix `git push` would override the repo's
  extension rule against `git push --force`. That last point is an inference from the
  priority values; the prefix matching was not executed.
- **An extension cannot raise its own rules above tier 2.** Priority is clamped to 0-999 inside the tier.

**`excludeTools` is a different mechanism.** The manifest's `excludeTools` is merged into the tool-registry exclusion set while the extension is
active, so it works by hiding the tool, not through policy priority. `source-cited`:
S:packages/core/src/config/config.ts L2447-2470. The documented command-scoped form is
`"run_shell_command(rm -rf)"`. `doc-cited`: reference.md L162-167. How that form behaves at registry level
is `unverified`.

**Hooks.** Events are `BeforeTool`, `AfterTool`, `BeforeAgent`, `AfterAgent`, `BeforeModel`, `AfterModel`,
`BeforeToolSelection`, `SessionStart`, `SessionEnd`, `Notification` and `PreCompress`. `doc-cited`: D:hooks/reference.md.

`BeforeTool` can do the following:
- **`deny` or `block`** blocks the call.
- **`hookSpecificOutput.tool_input`** rewrites the arguments.
- **`continue:false`** kills the loop.
- **`decision:"ask"` forces a confirmation prompt.** It is undocumented but implemented: `hookDecision === 'ask'` sets
  `decision = ASK_USER` after the policy check. The override runs unconditionally, so it overrides a
  policy ALLOW, YOLO, and even a policy DENY. `source-cited`:
  S:packages/core/src/scheduler/scheduler.ts L667-735, S:packages/core/src/scheduler/hook-utils.ts L73-78,
  S:packages/core/src/hooks/types.ts L130-220.
- **`allow` or `approve` from a hook does not widen anything.** The policy decision still governs. `source-cited`: scheduler.ts L677-685.

Exit codes follow source, not the doc. `source-cited`: S:packages/core/src/hooks/hookRunner.ts L535-560.
- 0 means allow.
- 1 means a non-blocking warning.
- **Every other non-zero exit is a deny.**

The doc says "2 = block, Other = warning" (D:hooks/reference.md L10-15), which is wrong against the code.
- Hooks require `hooksConfig.enabled`, default true.

**Skills and subagents.**
- Extension `skills/<name>/SKILL.md` and `agents/*.md` load, and both are
  `${VAR}`-hydrated. `source-cited`: extension-manager.ts L926-962.
- The skill tier is lowest after built-in, so user and workspace skills of the same name win. `doc-cited`: D:cli/skills.md L37-53.

**Widen or narrow?** An extension can only narrow, through `deny`/`ask_user` policies, `excludeTools`, and BeforeTool
`deny` or `ask`. **It has no way to auto-approve anything.** Widening is reserved to the user and admin, through
`~/.gemini/policies`, `tools.allowed`, approval modes and "Always allow".

## C. Extension configuration

**Schema.** `settings[]` entries are `{name, description, envVar, sensitive?}` and nothing else: **no type, enum,
choice, default or required flag.** Every value is a string. `source-cited`:
S:packages/cli/src/config/extensions/extensionSettings.ts L24-30, S:packages/core/src/config/config.ts L252-257.

**Storage.**
- Non-sensitive values go in `.env`, either inside the extension directory (user scope) or
  `<workspace>/.env` (workspace scope).
- Sensitive values go to the OS keychain under the service name
  `Gemini CLI Extensions <name> <id>`.
- `source-cited`: extensionSettings.ts L32-60, variables.ts L24.

**When the user is prompted.**
- At install, unless `--skip-settings` is passed, and always at user scope.
- Missing settings print a warning that names
  `gemini extensions config <name> [setting]`.
- Change a value later with `gemini extensions config <name> [setting] [--scope user|workspace]`.
- `source-cited`: extension-manager.ts L393-424, extensionSettings.ts L62-80. `measured`: `gemini extensions config --help` on 0.60.0.
- The feature is gated by `experimental.extensionConfig`, default `true`. `source-cited`: settingsSchema.ts L2253-2260.

**Where values go:**
- **MCP servers** receive them through `getExtensionEnvironment`. `source-cited`: S:packages/core/src/tools/mcp-client.ts L1004, L2388, L2468.
- **Hooks receive them too.** Every command hook gets `hook.env = {...hook.env, ...settings}` when a value
  is set (extension-manager.ts L896-922), and `hookRunner` spreads `hookConfig.env` into the child
  environment (hookRunner.ts L348-356). The same code exists in v0.60.0, v0.64.0 and v0.65.0.
  `measured`: `gh api .../contents/...extension-manager.ts?ref=v0.64.0` showed the hydration block at L887-906.
- **Text hydration:** `${ENVVAR}` placeholders in `gemini-extension.json`, `hooks/hooks.json`, extension SKILL.md
  bodies and agent definitions are substituted with setting values. An unset key is left literal.
  `source-cited`: extension-manager.ts L798-800 and L876-883; variables.ts `hydrateString`.
- **Not to the shell tool.** Settings are never written to `process.env`. The shell receives the sanitized process
  env plus `GEMINI_CLI`. `source-cited`: S:packages/core/src/services/shellExecutionService.ts L580-584.
  That settings never reach the shell is an inference from reading the code, not measured.

**Install location and updates.**
- Extensions live in `~/.gemini/extensions/<name>/` as a copy, or a symlink after `link`.
  `doc-cited`: reference.md L21-23, L104-107.
- **An update deletes the whole extension directory and copies it fresh.** Settings are
  read beforehand and re-persisted. **Anything else written inside the extension directory is lost.** `source-cited`:
  extension-manager.ts L368-436 and L555-577 (`removeDirectoryWithRetry`).
- **There is no persistent per-extension data directory**, unlike Claude's `${CLAUDE_PLUGIN_DATA}`. No such
  variable or storage path exists in `packages/`. `source-cited`: a grep of the source found nothing; absence is weak evidence.
- **0.60.0 behaviour change:** a changed environment or settings set now asks for consent again on update.
  `doc-cited`: v0.60.0 release notes, PR #28863.

## D. Skills and commands

**Skill slash commands.** Every displayable skill becomes `/<skill-name>`.
- The command activates the skill, then submits **the raw argument text as the next user prompt**.
  `/pr-dev 42 --perms=bypass` therefore arrives as the plain prompt `42 --perms=bypass`, with no parsing.
  `source-cited`: S:packages/cli/src/services/SkillCommandLoader.ts L35-55.
- **`activate_skill` is `ask_user` in `default` mode**, so the user must approve the activation. `source-cited`: write.toml.
- **The frontmatter parser reads only `name` and `description`.** There is no explicit-only invocation flag (no
  `disable-model-invocation` equivalent). The user can turn a skill off with `skills.disabled` or `/skills disable`.
  `source-cited`: S:packages/core/src/skills/skillLoader.ts L18-32, L76. `doc-cited`: configuration.md L2289-2298.

**Custom commands.** TOML `prompt` supports:
- `{{args}}`: raw substitution, shell-escaped inside `!{...}`;
- `!{cmd}`: shell injection, confirmed via policy;
- `@{path}`: file injection.

Commands are explicit-only by nature. An extension's `commands/x.toml` becomes `/x`, or `/<ext>.x` on a name conflict.
`doc-cited`: D:cli/custom-commands.md L56-275, D:extensions/reference.md L229-238, L346-350.

**Can a skill read env or config files?** Yes, through the model's `read_file` and `run_shell_command`, both subject to policy.
- A skill that ships inside the extension can also get values baked in at load through `${ENVVAR}` hydration.
- Skills installed with `gemini skills install`, which is this repo's route, are **not** hydrated, because only the extension's own `skills/` folder is.
  `source-cited`: extension-manager.ts L926-933.

## E. Antigravity (brief)

**Plugin format.**
- A plugin is a directory with `plugin.json`, or `.antigravity-plugin/plugin.json`. The doc's
  example fields are `$schema`, `name`, `displayName`, `version`, `description`, `logo` and `suggestedPrompts`.
- Components are skills, MCP servers (tools namespaced `<plugin>_<server>`), agents, rules and hooks.
- CLI commands: `agy plugin install|import [gemini|claude]|list|enable|disable|uninstall|validate [--strict]`.
- **A plugin that declares required config variables installs disabled. Enabling it opens a setup
  dialog for each variable.**
- `doc-cited`: https://antigravity.google/docs/plugins/

**Permission model (CLI).**
- `~/.gemini/antigravity-cli/settings.json` holds a `permissions` block with
  `allow`, `ask` and `deny` lists of `action(target)` rules. Actions are `command`, `read_file`, `write_file`, `read_url`,
  `execute_url`, `mcp` and `unsandboxed`. A `regex:` form is supported, e.g. `command(git)` or `mcp(linter/*)`.
- **Precedence is Deny > Ask > Allow.**
- `toolPermission` takes `strict | always-proceed | proceed-in-sandbox | request-review`.
- Modes are `auto` and `accept-edits`, set with `--mode`. `--dangerously-skip-permissions` equals `always-proceed`.
- The App has presets: Request Review, Default, Auto, Turbo.
- `doc-cited`: https://antigravity.google/docs/permissions?tab=cli
- **The docs say nothing on whether a plugin can contribute permissions.** `unverified`.

**Hooks.**
- Events: `SessionStart`, `PreToolUse`, `PostToolUse`, `PreInvocation`, `PostInvocation`, `Stop`.
- Configured in `.agents/hooks.json`, `~/.gemini/config/hooks.json`, and **plugin `hooks.json` (CLI)**.
- **PreToolUse `decision` accepts `allow | auto_approve | deny | ask | force_ask | deny_unless_prior_grant`,** plus
  `permissionOverrides`. So unlike Gemini, an Antigravity hook appears able to *widen* permissions.
  Whether a plugin hook may do so is `unverified`.
- `doc-cited`: https://antigravity.google/docs/hooks

## F. Recent changelog (0.57.0 → 0.66.0, plus 0.67.0-preview.0)

`doc-cited`: GitHub release bodies via `gh api repos/google-gemini/gemini-cli/releases/tags/<tag>`.

- **0.58:** declared top-level safety checkers in the write policy (#28961); Seatbelt sandbox isolation (#28935).
- **0.59:** fail-closed workspace trust; filter mcpServers in restricted mode (#29099).
- **0.60:** **extensions prompt for consent on environment changes and sanitize runtime-altering env vars**
  (#28863); hardened extension path and boundary validation (#29169); strict ownership checks on
  system config paths (#29115); sandbox settings-directory isolation (#29216).
- **0.61:** prevent indirect injection via build-file modification and untrusted flags (#29250).
  In source, an ALLOW plus "taint risk" becomes ASK, or DENY when headless (scheduler.ts L687-697).
- **0.63:** aligned policy redirection gates and path validation (#29506); **autonomous plan execution in
  non-interactive mode** (#29539).
- **0.64:** propagate folder-trust state in headless mode (#29528); atomic state persistence (#29558).
- **0.65:** **read-only workspace settings in untrusted folders** (#29583); fewer untrusted-flag false
  positives (#29672); other extensions keep loading when one fails the allowlist (#29720).
- **0.66:** settings placeholders resolved *after* `.env` load (#29750); hardened SKILL.md frontmatter
  parsing (#29769); safe git env with no interactive credential prompts (#29760).
- **0.67.0-preview.0:** untrusted-flag checks scoped to external output, approved flags remembered (#29833);
  `hooks migrate --from-claude` now converts timeouts from seconds to milliseconds (#29899); ACP permission requests carry MCP
  metadata (#29910).

---

## Implications for the design

1. **The plugin cannot grant "bypass" on Gemini.** An extension policy `allow` is silently dropped, and a
   hook `allow` does not override policy.
   - A `bypass` or `auto` preset on Gemini can only mean "the plugin's own skill logic does not
     stop to ask".
   - The host still prompts unless the user widened it: `--approval-mode=yolo` or
     `auto_edit`, `~/.gemini/policies/*.toml`, `tools.allowed`, or "Always allow".
   - The `/plugin-config` skill can offer to write a **user-tier** TOML
     (`~/.gemini/policies/tamirs-superpowers-perms.toml`), which may contain `allow`. That is editing a user
     config file, so it needs explicit consent each time.
2. **`strict` is enforceable, even under YOLO.**
   - A shipped extension rule with no `modes` and `decision = "ask_user"`, matching for example
     `mcpName = "github"`, `toolName = "merge_pull_request"` and `commandRegex 'gh\s+pr\s+merge'`, sits at 2.x and beats
     YOLO's 1.998. Headless, `ask_user` becomes `deny`, which is the correct strict behaviour.
   - **The user can still override it** with a tier-4 rule or an "Always allow", and that should be documented as the escape hatch.
3. **Use a BeforeTool hook that returns `{"decision":"ask"}` for dynamic levels.**
   - The hook reads the plugin config file plus a per-invocation marker and forces a prompt. That covers `ask` for skills whose
     static policy is silent.
   - Hook `ask` also overrides policy DENY, which is surprising. It relies on undocumented behaviour, so it needs a regression probe.
   - **Hooks are fail-open on Gemini**, so pair every hook with a static deny or ask policy for the
     must-hold cases.
4. **Config storage must live outside the extension directory**, because updates wipe it. Use
   `~/.gemini/tamirs-superpowers/permissions.json` or the repo's `plugin-state.sh` fallback path.
   - `settings[]` has no enum, but a non-sensitive `TS_PERMISSION_PRESET` string setting works as an install-time
     prompt.
   - The value survives updates and reaches hooks and MCP as env vars, but **the plugin must validate the
     string itself**. Free text is accepted at the prompt.
5. **Per-invocation override:** `/pr-dev 42 --perms=bypass` reaches the model only as prompt text.
   - The skill must parse it in its own instructions.
   - A `BeforeAgent` hook sees the prompt and could record the override in a session file for the BeforeTool hook.
     `unverified`: whether `BeforeAgent` receives the post-submit text of a skill slash command.
6. **There is no explicit-only skill gate on Gemini.** `/plugin-config` can be auto-activated, but
   `activate_skill` itself asks in `default` mode. The skill should confirm before writing regardless.
7. **On Antigravity a hook may auto-approve.** The design's "what the plugin can widen" row therefore differs per
   platform and belongs in `core/capabilities/platforms.json`, not in prose.

## Repo drift (files read; nothing edited)

1. **The "settings reach MCP only, not hooks" claim is contradicted by source.** It appears in
   `docs/user/install/gemini.md` L176, `platforms/manifests.source.json` L133 (`settings_note`) and
   `platforms/gemini/adapter.yaml` notes.
   - Source has hydrated hook env from settings since at least v0.60.0.
   - The likely cause is that the probe ran with `--skip-settings`, so no value existed and nothing was injected.
   - Settings also hydrate `${VAR}` in bundled skills, agents and hooks.json.
2. **`policies.source.json` and the TOML header are correct but incomplete.**
   - Correct: extension `allow` and YOLO rules are dropped, and the user tier outranks.
   - Missing: these denies also **hold in YOLO** (2.x beats 1.998).
   - Missing: they **lose to `tools.allowed` and persisted "Always allow" approvals**, not only to a user TOML.
3. **The `adapter.yaml` exit-code claim contradicts the upstream doc, but source confirms it.** The claim is "every non-zero exit but 1 is a deny".
   The repo is right, and D:hooks/reference.md L10-15 is wrong.
4. **`platforms/gemini/hooks.json` ignores the hook `ask` decision.** Its description lists outputs as `{decision:deny}` / `{}` / context, so
   `gemini-wrap.sh` presumably never emits `ask`. A Claude `permissionDecision: "ask"` would degrade.
   `unverified`: the wrapper was not read.
5. **"Validated against 0.66.0"** (`docs/user/install/gemini.md` L20) is not reproducible on this machine,
   where `gemini --version` printed 0.60.0. It may have been run elsewhere.
6. **The upstream policy doc has stale examples** that contradict its own tier table. Cite the source,
   S:packages/core/src/policy/config.ts L67-71, rather than the doc's priority examples.
7. **Antigravity has a documented config-variable mechanism.** `docs/user/install/antigravity.md` L80 says "Gemini's keychain-backed `settings[]`
   has no documented Antigravity equivalent". The plugins page now documents required config variables
   with a setup dialog on enable.
8. **The Antigravity docs now cover plugin hooks.** `docs/user/install/antigravity.md` L48 says "hooks/policies not mentioned". The hooks page documents plugin `hooks.json` support in the CLI and the
   PreToolUse decision values. Firing is still unmeasured, so shipping no hooks remains defensible,
   but the "not mentioned" row is stale.
9. **The Antigravity `plugin.json` schema may no longer be closed.** `platforms/manifests.source.json` L136 says `plugin.json` is a CLOSED schema
   `{name, description}`. The plugins page example shows `displayName`, `version`, `logo`,
   `suggestedPrompts` and `$schema`. Re-check with `agy plugin validate --strict`; it is `unverified` without the binary.

## Open questions

- Does a BeforeTool hook `ask` work in non-interactive mode, or hang or deny? (`resolveConfirmation` path)
- Does `BeforeAgent.prompt` carry a skill slash command's argument text?
- Does command-scoped `excludeTools` (`run_shell_command(gh pr merge)`) actually filter by command at
  registry level?
- Can user-tier `~/.gemini/policies` files be written without an integrity or consent prompt? Only workspace
  policies showed an integrity check (policy.ts L117-150).
- Does Antigravity honour `auto_approve` or `permissionOverrides` from a *plugin* hook?
