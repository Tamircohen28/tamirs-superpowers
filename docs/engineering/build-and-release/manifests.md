# One source, every manifest

Six per-host manifests and one per-host hooks file are **generated**. Nobody edits them;
`make validate` fails when one differs from what its sources produce.

| Generated file | Read by | Generator |
|---|---|---|
| `platforms/agent-plugins/plugin.json` | Agent Plugins 1.0 clients (Copilot CLI, Kiro, VS Code, Cursor, Codex ≥ 0.147) — placed at the ROOT of the `agent-plugins` release tarball by `build-dist.sh`, never at the repository root (see below) | `scripts/build-manifests.sh` |
| `platforms/agent-plugins/mcp.json` | the same hosts, through that manifest | `scripts/build-manifests.sh` |
| `.codex-plugin/plugin.json` | Codex — the one Codex route this repository ships | `scripts/build-manifests.sh` |
| `.cursor-plugin/plugin.json` | Cursor (preferred over the root manifest when both exist) | `scripts/build-manifests.sh` |
| `platforms/cursor/mcp.json` | Cursor, through `.cursor-plugin/plugin.json` `mcpServers` | `scripts/build-manifests.sh` |
| `gemini-extension.json` | Gemini CLI | `scripts/build-manifests.sh` |
| `platforms/codex/hooks.json` | Codex, through both Codex manifests' `hooks` | `scripts/build-codex-hooks.sh` |

The **inputs** are three files, and only those three are edited:

| Source | Holds |
|---|---|
| `.claude-plugin/plugin.json` | the identity: `name`, `description`, `author`, `homepage`, `repository`, `license`, `keywords`, `skills` |
| `plugin-version.json` | the version ([versioning](versioning.md)) |
| `platforms/manifests.source.json` | the per-target overlay: what one target adds or overrides |
| `hooks/hooks.json` | the hook wiring (input to the Codex hooks generator only) |

The Claude manifest and `.mcp.json` are inputs, never outputs: Claude Code's loader and
the Anthropic directory read them directly, and the directory's rules on them (no
`$schema`, `sensitive` user config, `${user_config.*}` placeholders) are checked by
`scripts/check-claude-dist.sh`, not here.

```bash
bash scripts/build-manifests.sh .            # regenerate the six manifests
bash scripts/build-codex-hooks.sh .          # regenerate the Codex hooks file
bash scripts/build-manifests.sh . --check    # CI: exit 1 on drift, prints the diff
bash scripts/build-codex-hooks.sh . --check
bash tests/test-manifests.sh                 # the rules below, plus planted-drift probes
```

Both generators write 2-space JSON with keys in the order the overlay lists them, after
the identity block, so a change to one field is a one-line diff.

## Why one source

Before this, the same author, homepage, repository, license, keywords and skills list
sat in four hand-kept files, and three of them disagreed on the description without
anyone being able to say which difference was deliberate. `plugin-version.json` had
already made the version single-sourced. This extends the same rule to the rest of the
identity, and makes every *difference* between targets a declared line in the overlay
rather than an accident of which file was edited last.

## The overlay

`platforms/manifests.source.json` has one section per target. Three conventions keep it
small:

- a target's `description` **replaces** the canonical one (Codex's description does not
  claim agents, because Codex has no plugin route for them; Cursor's claims the 26
  generated slash commands);
- `keywords_exclude` removes canonical keywords that name another host (`claude-code`
  is excluded from every non-Claude manifest);
- a `manifest` key whose value is `null` for `skills` is filled with the canonical
  `skills` list **at that position**, so the key order of the generated file is the
  order the overlay reads in.

Everything else under a target's `manifest` is copied verbatim.

## The root Agent Plugins manifest

`plugin.json` is the [Agent Plugins 1.0](https://github.com/agentplugins/agent-plugins-spec/blob/main/spec/1.0.0.md)
manifest: required `$schema` and `name`, the portable identity fields, and
`extensions.<reverse-domain>` for anything client-specific. The generator enforces the
spec's own constraints before writing: the name pattern, `author` limited to
`name`/`email`/`url` (Codex's parser rejects any other key there), and no top-level key
outside the spec, since a conformant client *reports and ignores* one.

### Why the Agent Plugins manifest is not at the repository root

Measured on codex-cli 0.163.0 (2026-10-17; the provenance is in
`tests/hooks/test-codex-contract.sh` and `docs/user/install/codex.md`): when a plugin
carries a root Agent Plugins `plugin.json`, Codex's loader empties the plugin's hook
sources before any hooks path is read — the overlay's `hooks`,
`extensions.com.openai.hooks`, or both — and `codex doctor` reports no MCP servers
either. A repository with that file at its root therefore ships **zero hooks** to a Codex
that installs it from the marketplace. So the manifest is generated under
`platforms/agent-plugins/` and moved to the root of the `agent-plugins` distribution only;
the repository root carries none, `scripts/check-dist.sh --target codex` refuses one, and
`tests/test-dist.sh` plants one to prove it.

Skills and MCP are not named in the Agent Plugins manifest at all. The spec discovers skills as
the immediate children of `skills/` and reads MCP from the root `mcp.json`; Codex's
Agent Plugins parser hard-codes exactly those two locations and reads no `skills` or
`mcpServers` key from the root or from the extension. **Open question, recorded rather
than assumed:** this repo's skills sit two levels down (`skills/<domain>/<name>/`), the
spec says a client must not search deeper than one, and whether Codex's skill loader
does recurse was not established by reading its manifest parser. Until a live Codex run
confirms it, `platforms/manifests.source.json` carries `emit_codex_extension`: set it to
`false` and the root manifest is written without `extensions.com.openai`, which makes
Codex fall back to `.codex-plugin/plugin.json` and its explicit seven skill roots.

### The Codex extension replaces the overlay

Codex's documented behaviour: when `extensions.com.openai` is present in the root
manifest it **replaces `.codex-plugin/plugin.json` entirely** — the two are not merged
— and the overlay is read only when the extension is absent. So the Codex settings
(`hooks`, `interface`) exist twice, once in each file, and the generator refuses to
write them if they differ. `.codex-plugin/plugin.json` stays as the pre-0.147 fallback
and as the file that lists the seven skill roots explicitly.

The extension carries `hooks` and `interface`. It does not carry `skills` or
`mcpServers`: neither is documented under the extension, and Codex's parser does not
read them from there. `onboardingSkill` (a skill run on install, the documented route
to bootstrap a host where hooks cannot run) is not set because no such skill exists
yet.

### The root `mcp.json`

Spec rules the generator enforces: only `$schema` and `mcpServers` at the top (one
unknown key disables MCP for the whole plugin); `type` on every server (an unknown
field in a server entry skips that server); a stdio `command` that is a single token —
a bare name or a `./`-relative path, **with no placeholder**, because expansion applies
only to `args`, `env` values and `cwd`; and only `${PLUGIN_ROOT}` and `${PLUGIN_DATA}`
anywhere, since an unrecognised placeholder stays literal.

That last rule is why the root file passes **no credential**. Agent Plugins 1.0 says
`env` values are visible package data and defines no credential mechanism — it is
client-managed, and v1.1 (a working draft) adds none. The Claude form
`${user_config.github_token}` would reach the github server as that literal string, which
the server would present as its token and fail on its first call. With no `env`, the
launcher (`scripts/github-mcp.sh`) refuses to start and says what is missing. On the
Agent Plugins route the server therefore starts only when the host itself supplies
`GITHUB_PERSONAL_ACCESS_TOKEN` to it; how a Codex user does that for a plugin server is
not documented and was not verified. The Codex `.codex-plugin` route points at `.mcp.json`
and has the same gap (Codex is not documented to expand `${user_config.*}`).

## Cursor: the variables rule

In a Cursor plugin, a `${VAR}` in an MCP file is a **plugin variable**, not shell
syntax, and every one must be declared under the manifest's `variables` JSON Schema;
values are set by the user or admin under Plugins → Configure and never live in the
repo. `${user_config.github_token}` is not a declarable name, so Cursor gets its own
generated `platforms/cursor/mcp.json`:

- `command` is `${CURSOR_PLUGIN_ROOT}/scripts/github-mcp.sh` — Cursor expands
  `${CURSOR_PLUGIN_ROOT}` and `${CLAUDE_PLUGIN_ROOT}`, and does **not** expand
  `${PLUGIN_ROOT}`;
- `env.GITHUB_PERSONAL_ACCESS_TOKEN` is `${GITHUB_TOKEN}`, declared in
  `.cursor-plugin/plugin.json` `variables.properties.GITHUB_TOKEN` with a title and
  description and **no default** (a default would be a credential in the repo).

The generator refuses to write a Cursor MCP file that uses a variable the manifest does
not declare, or a declared variable with a default; `tests/test-manifests.sh` asserts
both on the tree and plants both to confirm the refusal.

## The Codex hooks subset

Codex loads a plugin's hooks file natively and exports `CLAUDE_PLUGIN_ROOT` for
compatibility, but its hooks-file parser is strict at the top level: exactly
`description` and `hooks`, nothing else. The top-level `modules` array that loads the
mod (added in 4.10.0) makes the Claude file unparseable on Codex. Source-read, not run
live; either way no plugin hook runs on Codex from that file.

`scripts/build-codex-hooks.sh` writes `platforms/codex/hooks.json` from
`hooks/hooks.json`:

| Change | Why |
|---|---|
| `modules` dropped | the mod loader; Codex rejects the key and runs no mod |
| `Notification`, `DirectoryAdded`, `WorktreeCreate`, `WorktreeRemove`, `StopFailure` dropped | no Codex equivalent; the file declares only what can fire, so a `/hooks` review reviews only real hooks |
| `onFailure` dropped from every entry | Claude's key; Codex's command-hook struct has no such field, so **every guard is fail-open on Codex** — a guard that crashes or times out lets the action through |
| `${CLAUDE_PLUGIN_ROOT}`, `timeout`, `statusMessage` kept | Codex exports the variable and accepts both fields under those names |
| `description` added | says the file is generated and why |

The kept events are exactly the Codex-supported events the canonical file wires; the
generator adds none (a Codex-only event with no handler here is not a hook) and fails
on a canonical event that is neither supported nor on its known-dropped list, so a new
Claude event cannot be dropped silently. Every command's script must exist.

Both Codex manifests point `hooks` at the generated file, which **replaces** Codex's
default discovery of `hooks/hooks.json` rather than adding to it.

Two Codex contract points the generator does *not* cover, tracked in the V5 plan:
`Stop`/`SubagentStop` hooks must print JSON on exit 0, and `PreToolUse` `ask`,
`continue: false` and `stopReason` fail the hook.

## Version bumps

`plugin.json` is a consumer in `plugin-version.json`, so `check-version-truth.sh` fails
when it lags and `--sync` repairs it. The canonical fix after a bump is still to run the
generator, which reads the version from `plugin-version.json`:

```bash
# edit plugin-version.json, then
bash scripts/check-version-truth.sh --sync   # README badge, platform-targets.json, ...
bash scripts/build-manifests.sh .            # every generated manifest
```

## What is not generated

`.agents/plugins/marketplace.json` (Codex marketplace entry) is untouched: a root Agent
Plugins manifest changes nothing there, entries still point at the plugin folder through
`source.path`. `.mcp.json` and `.claude-plugin/plugin.json` are the Claude inputs.
`platforms/cursor/hooks.json` is hand-written in Cursor's own event format
([cursor install doc](../../user/install/cursor.md)).
