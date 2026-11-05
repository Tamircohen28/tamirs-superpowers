# OpenCode — permission model research for plugin-configurable permission behavior

Research input to ADR 004 (permission levels). Date 2026-11-03. Evidence tags: doc-cited / source-cited / measured / unverified.

Researched 2026-11-03. Tags: `doc-cited` (URL), `measured` (command + output), `source-cited`
(file+line), `unverified`.

## Version baseline

- **Latest OpenCode 2 release is 2.2.5 (2026-10-30). No delta vs the repo pin.**
  - `measured`: `npm view @opencode/cli dist-tags` → `"latest": "2.2.5"`; publish times show
    2.2.0 (10-27) … 2.2.5 (10-30), nothing newer.
  - `measured`: `gh release list --repo anomalyco/opencode` → newest `v2.2.5 2026-10-30`.
    The repo moved: `sst/opencode` now resolves to `anomalyco/opencode`, default branch `dev`.
  - `measured`: local `opencode --version` → `opencode v2.2.5`.
- **Trap:** `npm view opencode-ai version` → `1.19.5`, and GitHub flags `v1.19.5` as "Latest".
  That is the **V1 line**, which is still maintained in parallel. V2 ships as `@opencode/cli`. A sync
  script that reads `opencode-ai` or GitHub's "Latest" badge will report a downgrade. `measured`
- Docs: V2 is under `https://opencode.ai/v2/docs/…`. `https://opencode.ai/docs/…` serves **V1**
  (its permissions page documents the `permission` map). `measured` (curl of both)

---

## A. Host permission model (2.2.5)

### Ruleset
- Top-level `permissions` is an **ordered array** of `{action, resource, effect}`. All three fields
  are required strings, and `effect` ∈ `allow|deny|ask`.
  `doc-cited` https://opencode.ai/v2/docs/permissions/ ; `measured`: schema `$defs.Permission.Rule`
  has `required: [action, resource, effect]`, `additionalProperties: false`, and an **unenumerated**
  `action: {type: string}`.
- **Last matching rule wins.** Rules from lower-priority config load first, global rules are
  appended next, and agent rules are appended last. An operation that checks several resources is
  denied by any deny, otherwise asks on any ask, otherwise is allowed. `doc-cited` (permissions)
- If no rule matches, the effect is **ask**. In practice the base policy below means everything is
  allowed. `doc-cited`
- Wildcards match the whole value. `*` matches any characters, including `/`. `?` matches one
  character. A shell pattern ending in ` *` also matches the bare command. `~`/`$HOME` expand for
  `read`, `edit` and `external_directory` resources, but not for `shell`. `doc-cited`
- **Default base policy for every agent:** `* * allow`, then `read *.env` ask, `read *.env.*` ask,
  `read *.env.example` allow. The shipped agents append more (plan denies edits, explore is
  read-mostly, and so on). **`external_directory` is allowed by default.** `doc-cited`
- **Built-in actions** (2.2.5 docs): `read edit glob grep shell subagent skill question webfetch
  websearch experimental_image_generate external_directory <server>_<tool>
  opencode_list_mcp_resources opencode_read_mcp_resource execute`. "V2 action names are strings,
  so plugins may define more actions." `doom_loop` and `lsp` are not Core actions. `doc-cited`
- 2.2.5: a tool call named `bash` now runs as `shell` with the same permissions.
  `doc-cited` https://github.com/anomalyco/opencode/releases/tag/v2.2.5

### Approvals
- An `ask` gets one of three replies: `once`, `always` (saves a durable **project-scoped** allow
  pattern), or `reject` (rejects every pending request in the session). Saved approvals never
  override a configured deny. Since 2.1.0, `client.permission.saved.update(...)` lets you edit a
  saved approval. `doc-cited` (permissions; changelog https://opencode.ai/changelog v2.1.0)
- "Non-interactive clients must decide how to handle approval requests; configured deny rules always
  remain enforced." `doc-cited`

### Auto-approve ("yolo")
- `--auto` exists on `opencode` and `opencode run`: "Auto-approve permissions that are not
  explicitly denied". `measured` (`opencode --help`, `opencode run --help` on 2.2.5)
- Desktop has a per-project "Auto-accept permissions" setting under Settings → Projects, toggled with
  `mod+shift+a` (2.0.28). `doc-cited` https://opencode.ai/changelog v2.0.28
- The V1 docs also describe a TUI command-palette toggle for auto-approve
  (https://opencode.ai/docs/permissions/). The V2 permissions page does not mention `--auto` at all.
  TUI toggle on V2: `unverified`.
- Under auto mode **only deny survives**: every `ask` becomes `allow`. `measured` (help text) +
  `doc-cited` (V1 page: "Auto mode only changes requests that would otherwise ask")

### Legacy map
- Top-level `permission` (singular map) is still in the schema, marked `"deprecated": true`
  (`measured`). V1 → V2 action renames: `bash`→`shell`, `task`→`subagent`, `write`/`patch`→`edit`;
  `apply_patch` → `edit` since 2.1.3. A file that uses any V2 field (`permissions`, …) is read as V2,
  and its V1 fields are ignored with a log warning.
  `doc-cited` https://opencode.ai/v2/docs/migrate-v1/ ; changelog v2.1.3

### Per-agent rules
- `agents.<id>.permissions` in JSON, or a `permissions:` list in `.opencode/agents/*.md` frontmatter.
  These are **appended** after the global rules, never replacing them. A custom subagent uses its
  own rules, not a subset of its parent's. `doc-cited` (permissions, agents)

### Policies — a separate, tighten-only layer
- `policies: [{action, resource, effect: allow|deny}]`. They never prompt, and **only ever tighten**.
  `tool.use` takes an `<action>:<value>` resource and hard-denies *after* agent rules and saved
  approvals. An `allow` only lifts an earlier, broader policy deny and never grants. `skill.use`,
  `mcp.use` and `plugin.use` remove a skill, MCP server or plugin entirely (2.2.3+).
  `doc-cited` https://opencode.ai/v2/docs/policies/
- Policy precedence is the **reverse** of settings precedence: broader authority wins. The order is
  macOS managed plist > system `/Library/Application Support/opencode` or `/etc/opencode` > Console
  workspace > global `~/.config/opencode` > direct `opencode.json` (outer beats inner) >
  `.opencode/opencode.json`. A repository cannot re-enable something denied globally. `doc-cited`

### Config hierarchy (settings)
- Load order, lowest to highest: managed policies → Console/integration docs → well-known remote
  docs → global dir (`~/.config/opencode`, or `OPENCODE_CONFIG_DIR`) → explicit file → direct
  `opencode.json(c)` files from the farthest directory to the closest → `.opencode/` dirs →
  `OPENCODE_CONFIG_CONTENT` → managed settings (system dir + MDM plist, highest).
  `source-cited` anomalyco/opencode@v2.2.5 `packages/core/src/config.ts:363-373`;
  `OPENCODE_CONFIG_DIR` at `packages/util/src/global.ts:79`; `OPENCODE_CONFIG_CONTENT` at
  `config.ts:291`. Matches the docs' prose at https://opencode.ai/v2/docs/config/ ("every
  discovered .opencode config overrides every direct config").
- The env var behind the "explicit" source (presumably `OPENCODE_CONFIG`) is not named on the V2
  config page. `unverified`
- `{env:VAR}` and `{file:path}` substitution work inside config strings. `doc-cited` (config)
- Everything runs on **one shared background server per user**, which owns sessions, config,
  permissions and tools. `--standalone` gives a private server. `doc-cited`
  https://opencode.ai/v2/docs/cli/

---

## B. What a plugin can affect

The V2 plugin API is `Plugin.define({ id, setup(ctx) })` from `@opencode/plugin`. A package has
server, TUI, GUI and RPC parts. `doc-cited` https://opencode.ai/v2/docs/build/plugins/

| Capability | API | Can widen? | Evidence |
|---|---|---|---|
| Re-decide any allow/ask permission | `ctx.permission.hook("evaluate", e => { e.effect = …; e.message = … })` | **Yes**: ask→allow is allowed ("A hook may change effect to allow, ask, or deny") | `doc-cited` /v2/docs/build/plugins/server/ §Permissions |
| …but a configured deny | — | **No**: "An explicit configured deny is final and does not invoke the hook" | same |
| …and policies | — | **No**: policies apply after the rules and saved approvals, and never grant | `doc-cited` /v2/docs/policies/ |
| Define a NEW permission action | `ctx.permission.assert({sessionID, action: "deploy", resources, save, metadata})` inside a plugin tool | n/a. Evaluates the session's rules plus saved approvals and shows the **native approval prompt**; a deny throws `Tool.Error` | `doc-cited` server §Permissions; added 2.0.29 (changelog) |
| Replace a session's rules | `ctx.session.update({sessionID, permissions:[…]})` | **Likely yes.** Evaluated *after* agent rules, last match wins; child sessions inherit the rules in force when they are created | `doc-cited` server §Permissions. Whether a session `allow` overrides a config `deny` is `unverified` (the saved-approval "never overrides deny" sentence covers saved approvals only) |
| Edit agents (incl. default agent) | `ctx.agent.transform(editor => editor.update(id, a => …))` | `unverified`: whether `a.permissions` is mutable there is not documented | `doc-cited` server §Agent |
| Register / edit / remove skills | `ctx.skill.transform(editor => editor.add/update/remove)`, e.g. `skill.autoinvoke = true` | n/a | `doc-cited` server §Skills |
| Register slash commands with **code** executors | `ctx.command.transform(e => e.add({name, description, execute: async ({sessionID, prompt, delivery}) => …}))` | n/a | `doc-cited` server §Commands |
| Register tools | `ctx.tool.transform(...)`; `ctx.tool.hook("execute.before"/"execute.after")` | n/a. `execute.before` can inspect or replace input | `doc-cited` server §Tools |
| Rewrite user prompts before admission | `ctx.session.hook("prompt", e => …)`. A mutable draft (text, files, skills); no typed rejection API; commands submitted through `session.prompt` run it | n/a | `doc-cited` server §Prompt admission |
| Gate shell creation | `ctx.shell.hook("create.before")`. Mutates cmd/cwd/env/timeout; throwing is the only way to stop it, and how the error surfaces is undocumented | n/a | `doc-cited` server §Shell; `source-cited` repo `platforms/opencode/plugin/guard.ts:14-23` |
| Inject persistent context | `ctx.session.instructions.entry.put({sessionID, key, value})` (2.2.0) | n/a | `doc-cited` server §Sessions |

- Hooks from multiple plugins run in plugin order, and later hooks see earlier hooks' changes.
  `doc-cited`
- `PermissionEvaluation` = `{sessionID, agent?, action, resources[], metadata?, source?, effect,
  message?}`. It has **no field telling the plugin that `--auto` is on**. `source-cited`
  `@opencode/plugin@2.2.5` `dist/promise/permission.d.ts:7-16` (npm pack). Whether the evaluate hook
  runs before or after auto-approval: `unverified`.
- V1 → V2 hook mapping: `permission.ask` → `ctx.permission.hook("evaluate")`; `tool.execute.before`
  → `ctx.tool.hook("execute.before")`. `doc-cited` /v2/docs/build/plugins/migrate-v1/
- A plugin cannot switch off the two built-ins `opencode.config.policy` and
  `opencode.provider.opencode`. `doc-cited` /v2/docs/plugins/
- "Policies … do not sandbox plugin code." In-process plugin code is fully trusted. `doc-cited`
- **No `hooks.json` equivalent.** The lifecycle surface is the plugin API above. `doc-cited`

---

## C. Plugin configuration

- **No install-time prompt or options mechanism.** `opencode plugin add <package>` takes only a
  package specifier and writes it to the **global** config; it has no options flag. `measured`
  (`opencode plugin add --help`). There is no `userConfig` analog in the docs. `doc-cited`
  /v2/docs/plugins/
- A global `--wizard` flag ("Start wizard mode for a command") exists. Whether a plugin can hook it
  is `unverified`. `measured` (help)
- **User settings → plugin** come through the object form in any config layer,
  `plugins: [{ "package": "…", "options": { … } }]`, read as `ctx.options` (type
  `Readonly<Record<string, any>>`) during `setup`. `doc-cited` server §Options; `measured` schema
  `Config.Plugin.EntryEncoded {package, options: object}`; `source-cited` `dist/options.d.ts`.
  `plugins` arrays from every config layer are applied lowest → highest, not replaced. How two
  layers listing the **same** package with different `options` resolve: `unverified`.
- **Persistent data:** `ctx.storage.get/set/remove/scan` gives durable JSON scoped to the plugin.
  `doc-cited` server §Storage. Where it is physically stored (probably the SQLite db at
  `~/.local/share/opencode/opencode.db`) is `unverified`.
- **Paths:** `opencode debug paths` → config `~/.config/opencode`, data `~/.local/share/opencode`,
  cache `~/.cache/opencode`, state `~/.local/state/opencode`. `measured`
- **Install / update locations:** npm or Git packages are installed in the background on server
  start and cached under the global cache. Unpinned packages are update-checked, exact versions stay
  pinned. Local plugins are either configured by path (relative to the config file containing them)
  or auto-discovered under `.opencode/plugins/` and `~/.config/opencode/plugins/`. A `plugins/`
  directory beside the root `opencode.json` is **not** auto-discovered. Disable a plugin with a
  `-id` entry. Config dirs are watched and reload on change; `opencode service restart` reloads too.
  `doc-cited` /v2/docs/plugins/
- A plugin can also read env vars (`process.env`) and arbitrary files: it is ordinary Bun/Node code.
  `unverified` as a documented contract, but implied by the "do not sandbox plugin code" note.

---

## D. Skills and commands

- **Commands:** `.opencode/commands/*.md` (project) and `~/.config/opencode/commands/` (global),
  or the `commands` JSON map. Placeholders: `$ARGUMENTS` is the raw string; `$1`, `$2`, … are
  positional (quotes group words, and the highest-numbered one swallows the rest). With no
  placeholder, the args are appended after a blank line. Frontmatter: `description`, `agent`,
  `model`, `subagent`. A `` !`cmd` `` block runs **outside the permission flow**. `doc-cited`
  https://opencode.ai/v2/docs/commands/. Since 2.2.0, literal `$0`/`$ARGUMENTS` text in user input is
  preserved (changelog).
- **Skills do not take arguments.** The model loads a skill with the `skill` tool `{id}`; the user
  forces one with `@skill-id` in a prompt. The ID comes from the path (`…/pr-dev/SKILL.md` →
  `pr-dev`), not from `name`. `doc-cited` https://opencode.ai/v2/docs/skills/. So the only route
  for `/pr-dev 42 --perms=bypass` is a **command** (the repo's generated
  `.opencode/commands/pr-dev.md` passes `$ARGUMENTS`), or a plugin command executor or prompt hook
  that parses the text. `source-cited` repo `.opencode/commands/pr-dev.md`
- **Explicit-only:** `metadata.opencode/autoinvoke: false`, or `disable-model-invocation: true`
  (autoinvoke wins if both are set). This only **hides** the skill from the model's list: it "remains
  registered and can still be loaded explicitly by ID". `doc-cited` (skills). A hard gate needs
  permissions.
- **`skill` permission action:** the resource is the skill ID. `allow` advertises and loads it,
  `ask` advertises it and asks before loading, `deny` hides it and rejects the load. It can be scoped
  per agent. `doc-cited` (skills). `skill.use` policy deny removes the skill entirely (2.2.3+).
  `doc-cited` (policies)

---

## E. Relevant changelog, 2.0.26 → 2.2.5

Source: https://opencode.ai/changelog and GitHub release notes. All `doc-cited`.

- **2.2.5**: a `bash` tool call runs as `shell`, same permissions; a plugin tool literally named
  `bash` still wins (#60687).
- **2.2.4**: `ctx.experimental.artifact.transform(...)` for plugins (#60351).
- **2.2.3**: managed policy split. `integration.use` now covers integrations only; new `mcp.use`,
  `skill.use` and `plugin.use` (old prefixes auto-convert, and a bare `integration.use *` no longer
  blocks skills or plugins). TUI plugins require OpenTUI 0.8. Permission reasons and feedback are
  kept in MCP failures (#60315, #60102).
- **2.2.2**: `experimental_image_generate` is on by default when a provider supports image models
  (#60258). It is a **new permission action**.
- **2.2.1**: experimental `experimental.idle` session hook; opt-in `/schedule` scheduled prompts
  (#59437, #59401).
- **2.2.0**: session instruction entries for plugins; plugins can filter event subscriptions; plugins
  finish reloading before each session step and tool call; Code Mode MCP tools are exposed directly
  when `execute` is denied; `external_directory` checks use the project filesystem (#56550, #58864,
  #51133, #59315, #59089).
- **2.1.3**: legacy `apply_patch` permissions migrate to `edit` (#57900).
- **2.1.0**: breaking SDK, event and plugin contract changes; saved permission patterns can be edited,
  including `client.permission.saved.update` (#56659).
- **2.0.30**: MCP tool input is exposed as `metadata.input` in permission requests, so hooks can
  inspect it (#51062); honours `OPENCODE_DISABLE_CLAUDE_CODE(_SKILLS)` (#55774).
- **2.0.29**: **`ctx.permission.assert`** for plugins (native prompt plus configured rules) (#54930);
  `policies` stabilised as a top-level key (#55297).
- **2.0.28**: **per-project auto-accept permissions** (Desktop setting, `mod+shift+a`) (#54839).
- **2.0.23** (from the repo's registry, not re-read): `disable-model-invocation` for skills.

---

## Implications for the design

1. **The host already has the exact primitive the feature needs, and it is a plugin-defined
   action.** `ctx.permission.assert({action: "superpowers.pr.merge", resources: ["<repo>#42"], save:
   [...]})` evaluates the user's own `permissions` rules and shows OpenCode's native allow/always/
   reject prompt. A user could write `{ "action": "superpowers.pr.merge", "resource": "*", "effect":
   "allow" }` in `opencode.json` and get "auto" behaviour **enforced by the host**. This is the
   strongest platform for "allow/ask/deny for plugin actions". The catch: the merge has to run
   **through a plugin tool** (a `superpowers_merge` tool that calls `assert` and then `gh pr merge`),
   not through the skill telling the model to run `gh pr merge` in `shell`.
2. **Presets map onto host rules, but `--auto` collapses "strict".** Under `opencode --auto`, or the
   Desktop per-project auto-accept, every `ask` becomes `allow`. "strict = ask before merge" survives
   only if it is expressed as a **deny** (and the user unblocks it per invocation), or enforced in
   skill prose. The plugin cannot detect auto mode from `PermissionEvaluation`.
3. **A plugin can widen ask→allow, but never past a configured deny or a policy.** "bypass" in the
   plugin cannot override a user's or an org's deny on OpenCode. That is a feature: the design should
   say `bypass` = "skip the plugin's own confirmations", never "override host denies".
4. **Config file:** use the native channel, `plugins: [{ "package": "<path>", "options": { "preset":
   "strict", "skills": { "pr-dev": "ask" } } }]` read via `ctx.options`, plus `ctx.storage` for
   values changed later by `/plugin-config`. This repo loads its plugin **by path**
   (`opencode.json` `plugins: ["./platforms/opencode/plugin"]`), so options mean switching that
   entry to the object form. Skills (Markdown, read by the model) cannot read `ctx.options`. The
   plugin would have to surface the effective level, for example through
   `ctx.session.instructions.entry.put({key: "superpowers-perms", value: …})` or a tool.
   A plain file (`~/.config/tamirs-superpowers/perms.json`) is the cross-platform option, and on
   OpenCode a skill reads it with the `read` action.
5. **No install-time prompt.** "Preset chosen at install" has to live in `scripts/setup.sh`
   (`setup-opencode.sh` writes the global config), not in an OpenCode mechanism.
6. **`/plugin-config` can be a real code command.** `ctx.command.transform` registers `/plugin-config`
   with an `execute` that writes `ctx.storage` or the config file deterministically, with no model in
   the loop. Alternatively it stays a generated Markdown command pointing at a skill, which matches
   the other platforms.
7. **Per-invocation override (`--perms=bypass`):** only commands carry arguments, so the generated
   `pr-dev.md` already passes `$ARGUMENTS`. For host enforcement, a `session.hook("prompt")` can parse
   `--perms=` and call `ctx.session.update({permissions:[…]})` for that session. That is session-
   scoped, and child sessions inherit it, which is good for subagents. Whether a session allow beats a
   config deny is `unverified`, so test it before relying on it.
8. **Per-skill gating is native:** `{action: "skill", resource: "pr-dev", effect: "ask"|"deny"}`, per
   agent if needed. "Explicit-only" is `autoinvoke: false` plus an optional `skill` ask rule.
9. **Defaults to note:** the base policy is allow-all, so "strict" must be expressed as rules the
   plugin or setup writes. Saved "always" approvals are project-scoped and durable, so a user's
   one-time "always" silently turns "ask" into "allow" for that project.

## Repo drift

1. **`scripts/check-opencode-permission-keys.sh:41` `V2_ACTIONS` is missing
   `experimental_image_generate`.** The live docs list it, and it has been on by default since 2.2.2.
   It is not a gate failure, because the generator does not emit it. But the generator's deny-only
   translation (`scripts/build-opencode-agents.sh:114` `OPENCODE_ACTIONS`) never denies it, so under
   the allow-all base policy every generated agent may call image generation. The `--refresh` mode
   only checks that pinned actions are *still mentioned*; it cannot detect **new** ones. `measured`:
   `--refresh` → "every pinned action is still named …" (pass), while the docs table has one more.
   The pin's comment also says "read 2026-10-17 (docs current for @opencode/cli 2.0.32)", which is
   stale against 2.2.5.
2. **Generator omits `execute`.** It is in `V2_ACTIONS` but not in `OPENCODE_ACTIONS`. A denied
   `execute` removes Code Mode; agents that should be read-only can still reach Code Mode tools.
   Worth an explicit decision. `source-cited` (both scripts)
3. **`core/capabilities/platforms.json` opencode `doc_urls`** point to `https://opencode.ai/docs/…`,
   which serves the **V1** docs (the `permission` map). They should be `/v2/docs/…`, as
   `docs/user/install/opencode.md:33` already uses. `measured`
4. **`platforms/opencode/adapter.yaml` notes** say the plugin "LOADS on 2.0.32". `platforms.json`
   already records 2.2.5 (2026-10-31). The adapter note is stale. `source-cited`
5. **Platform-version tooling:** anything that resolves "latest OpenCode" via `opencode-ai` on npm,
   or GitHub's "Latest" badge, gets 1.19.5 (V1). Use `@opencode/cli`. `measured`. Repo usage was not
   audited; check `docs/engineering/build-and-release/platform-targets.json` and `platform-sync`.
6. **`platforms.json` `hooks.notes`** describes the capability correctly (plugin API, no
   `hooks.json`). It could add that `ctx.permission.assert` plus custom actions are available
   (2.0.29+). That is a missed capability, not an error.
7. **`opencode.json` `permissions`** match the current schema and action names (`edit`, `shell`,
   `external_directory`). The doc example (`docs/user/install/opencode.md:84`) agrees. No drift.
   `measured`: `check-opencode-permission-keys.sh --refresh` → OK, schema still `{action: string,
   resource, effect}`.

## Open questions (need a live provider session to settle)

- Does the `evaluate` hook run before or after `--auto` auto-approval, and does `assert` on a custom
  action prompt at all under `--auto`?
- Does a `ctx.session.update` allow rule override a configured deny from `opencode.json`?
- Can `ctx.agent.transform` mutate an agent's `permissions`?
- How do duplicate `plugins` entries with different `options` across config layers merge?
- Where does `ctx.storage` persist, and does it survive `opencode uninstall` (which keeps "state")?

---

<p align="center"><a href="https://github.com/Tamircohen28">Have a Question?</a>&nbsp;·&nbsp;<a href="https://github.com/Tamircohen28/tamirs-superpowers/issues/new/choose">Open an Issue</a></p>
