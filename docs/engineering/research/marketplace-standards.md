# Plugin marketplace standards — per-platform research

Research input to `repo-scaffold --type marketplace` (issue #370). Read on **2026-11-05**.
Every row below is **doc-cited** from the page named in its section unless tagged
`source-cited` (read from a platform's source tree) or `measured` (observed on a live
install). Nothing in the scaffold's templates goes beyond what these pages say: a platform
with no marketplace concept gets no manifest, and the scaffold says so instead.

## Summary

| Platform | Marketplace concept | Manifest path | Add command (user side) | Validation command |
|---|---|---|---|---|
| Claude Code / Claude Desktop | **Yes** | `.claude-plugin/marketplace.json` | `claude plugin marketplace add <owner/repo \| url \| path>` (also `/plugin marketplace add` in a session) | `claude plugin validate <marketplace-root-or-file>` |
| Cursor | **Yes** | `.cursor-plugin/marketplace.json` | Not stated on the reference page. The Cursor CLI changelog documents `agent plugin marketplace add <git-url>` (see [permissions research, Cursor](permissions/platforms/cursor.md)). | None documented |
| Codex (OpenAI) | **Yes** | `.agents/plugins/marketplace.json` (repo scope); `.claude-plugin/marketplace.json` is read as a "legacy-compatible marketplace" | `codex plugin marketplace add <owner/repo \| git-url \| path>` | None documented (the public-directory portal runs automated checks on a ZIP upload) |
| OpenCode | **No** | none — plugins are JS/TS modules or npm packages named in `opencode.json`'s `plugin` array | none | None documented |

## Claude Code

Sources, read 2026-11-05:

- <https://code.claude.com/docs/en/plugins/create-marketplace>
- <https://code.claude.com/docs/en/plugins/marketplace-reference>

**Manifest.** "A plugin marketplace is a directory or repository with a
`.claude-plugin/marketplace.json` file." The marketplace root is the directory holding
`.claude-plugin/`; relative plugin sources resolve from it.

**Top-level fields.**

| Field | Required | Notes |
|---|---|---|
| `name` | yes | Letters, digits, `.`, `_`, `-`; starts with a letter or digit; no `..`. Validation says "Use kebab-case" when it finds a space. Reserved names (`claude-plugins-official`, `anthropic-marketplace`, `builtin`, `npm`, `github`, …) are refused unless the source is `github.com/anthropics/`. |
| `owner` | yes | Object: `name` required; `email`, `url` optional. |
| `plugins` | yes | Array of entries, each validated on its own. |
| `$schema` | no | JSON Schema URL, ignored at load. |
| `description`, `version` | no | Validation warns when `description` is missing. Also accepted under `metadata.description` / `metadata.version`. |
| `metadata.pluginRoot` | no | Prefix for bare-name relative sources (Claude Code 2.1.239+). |
| `forceRemoveDeletedPlugins` | no | `true` uninstalls plugins removed from the list on users' machines. |
| `allowCrossMarketplaceDependenciesOn`, `renames` | no | Cross-marketplace dependency allow-list; former-name → current-name map (`null` = removed). |

Unknown top-level keys are ignored at load and reported as warnings by `claude plugin validate`.

**Plugin entry fields.** Required: `name`, `source`. Optional: `description`, `version`,
`category`, `tags`, `strict` (default `true`), `relevance`, `dependencies`, `defaultEnabled`
(default `true`), `displayName`, `metadata`, `headers`, `headersHelper` (needs
`"strict": false`), plus any `plugin.json` field (`author`, `homepage`, `repository`,
`license`, `keywords`, `commands`, `agents`, `skills`, `hooks`, `mcpServers`, …).
Keep the entry `name` equal to the plugin's own `plugin.json` `name`: otherwise
`claude plugin install <manifest-name>@<marketplace>` fails with
`Plugin "<manifest-name>" not found in marketplace`.

**Source types** (exact field names):

| `source` | Fields | Notes |
|---|---|---|
| relative path (string) | `"./plugins/<name>"` | Must start with `./` (or be a bare name under `metadata.pluginRoot`); no `..`; forward slashes. Only resolves when Claude Code holds the marketplace files (not with a `url` marketplace source). |
| `github` | `repo` (`owner/repo`), `ref`, `sha` | `sha` is a full 40-char lowercase SHA; when both are set `sha` wins. |
| `url` | `url` (`https://`, `http://`, `file://`, `git@`), `ref`, `sha` | No `owner/repo` shorthand. |
| `git-subdir` | `url` (full URL or `owner/repo`), `path`, `ref`, `sha` | Sparse checkout of one directory. |
| `npm` | `package`, `version`, `registry` | Install scripts do not run; git-host tarball links are refused. |
| `archive` | `url` (`https://` only), `sha256` (64 hex) | 2.1.224+. |
| `command` | `command`, `timeout` (1–600, default 60), `mode` (`copy` \| `link`) | 2.1.229+. The command prints one absolute plugin path and exits 0. |

**`strict`.** With a `plugin.json` present and `strict: true`, the entry's component
fields are appended to the manifest (entry `hooks` matchers replace the manifest's per
event). With `strict: false` and any component field on the entry, the two conflict and
install fails. With no `plugin.json`, the entry *is* the manifest regardless of `strict`.

**Versioning.** When both the entry and `plugin.json` set `version`, `plugin.json`
wins and `claude plugin validate` warns (`At install time, plugin.json wins`). Edits to a
relative-path plugin take effect at next session start or `/reload-plugins` with no
version change; users of a hosted marketplace get a cached copy. The update cache key is
documented on the plugin-loading reference, not on these two pages.

**Validation.** `claude plugin validate <path>` where `<path>` is the marketplace root,
the marketplace file, or a plugin directory. Success prints `✔ Validation passed`. It
checks JSON syntax, required fields, naming rules, `..` in a relative source, unknown
keys (warnings) and `plugin.json` problems for relative-path plugins. It does **not**
catch a missing source directory (that fails at install with `Source path does not
exist`) or remote fetch errors.

**User-side commands** (doc-cited on `create-marketplace`):

```text
claude plugin marketplace add <owner>/<repo>        # also: a repo URL, ./local-dir, or a direct URL to marketplace.json
claude plugin install <plugin>@<marketplace>
claude plugin marketplace remove <marketplace>      # also uninstalls its plugins
```

Inside a session the same verbs exist as `/plugin marketplace add …` and `/plugin install …`.
`/plugin marketplace update <name>` is not on these two pages; this repo's own install
docs ([docs/user/install/claude-code.md](../../user/install/claude-code.md)) use it and it
is `measured` on every release here.

**`marketplace add` input forms** (marketplace-reference): `owner/repo`, `owner/repo@ref`,
`owner/repo#ref`; a git URL (`user@host:path`, `https://…\.git`, a github.com/gitlab.com
repo URL, `#ref` to pin); any other `http(s)://` URL is a direct link to `marketplace.json`
(then relative plugin sources cannot resolve — use `github`, `url` or `git-subdir`
entries); a path to a `.json` file or a directory. There is no option for a non-standard
manifest location.

**Settings keys** (`marketplace-reference`, second half summarised by the fetcher, so
treat as approximate): `extraKnownMarketplaces` is a map from marketplace name to
`{"source": {…}}`; `strictKnownMarketplaces` / `blockedMarketplaces` are arrays of source
objects; `enabledPlugins` is keyed by `<plugin>@<marketplace>`. This repo's
`scripts/check-marketplace-schema.sh` already guards the record-vs-array shape.

## Cursor

Source, read 2026-11-05: <https://cursor.com/docs/reference/plugins> (the
`#marketplace-manifest-format` anchor is on the same page).

**Two plugin formats.** "Agent Plugins" carry `plugin.json` at the plugin root (skills,
MCP servers); "Cursor Plugins" carry `.cursor-plugin/plugin.json` (skills, MCP servers,
rules, agents, commands, hooks, variables).

**Marketplace.** "A single Git repository can contain multiple plugins using a
**marketplace manifest**." Path: `.cursor-plugin/marketplace.json` at the repo root. The
file must be 10 MB or smaller.

| Field | Required | Notes |
|---|---|---|
| `name` | yes | kebab-case |
| `owner` | yes | `name` required, `email` optional |
| `plugins` | yes | array of entries |
| `metadata` | no | `description`, `version`, `pluginRoot` ("prefix path for all plugin sources") |

**Plugin entry.** Required: `name` (kebab-case). Other fields: `source`, `description`,
`version`, `author`, `homepage`, `repository`, `license`, `keywords`, `logo`, `category`,
`tags`, `skills`, `rules`, `agents`, `commands`, `hooks`, `mcpServers`, `variables`.

**Source types.** The page documents one: "Path to plugin directory, or object with
`path` and options" (example `"source": "plugin-one"`). The object form's options beyond
`path` are not stated. Resolution: for `"source": "my-plugin"` the parser looks for
`my-plugin/.cursor-plugin/plugin.json`; if found it is merged with the entry and the
plugin's own manifest wins; component discovery then runs inside `my-plugin/`. No
`github`, `npm` or URL source type is documented.

**Versioning.** `version` is a "Semantic version (e.g., `1.0.0`)" on both `plugin.json`
and entries; `metadata.version` exists with no description. What triggers an update is
not stated.

**Validation / install.** No CLI validation command and no user-side add/install command
is on this page. Plugins are *submitted* at <https://cursor.com/marketplace/publish> and
reviewed by the Cursor team; the checklist includes "Cursor multi-plugin repositories have
`.cursor-plugin/marketplace.json` at the repo root with unique plugin names" and "All paths
in manifest are relative and valid (no `..`, no absolute paths)". The Cursor CLI changelog
separately documents `agent plugin marketplace add <git-url>` (doc-cited in
[permissions/platforms/cursor.md](permissions/platforms/cursor.md), read 2026-11-03).

**Claude compatibility.** Not stated, beyond `${CLAUDE_PLUGIN_ROOT}` being expanded in MCP
`command`, `args`, `env` and `cwd`.

## Codex (OpenAI)

Sources, read 2026-11-05:

- <https://developers.openai.com/plugins/build/plugins> ("Package your plugin")
- <https://developers.openai.com/plugins/deploy/submission> (linked from it; second half summarised by the fetcher)

**Framing.** "Public plugins are published once to the universal plugin directory shared by
ChatGPT and Codex. Local and repo marketplaces are separate authoring, testing, and
team-distribution sources." "A marketplace is a JSON catalog of plugins."

**Manifest paths named on the page.**

| Scope | Path |
|---|---|
| repo | `$REPO_ROOT/.agents/plugins/marketplace.json` |
| personal | `~/.agents/plugins/marketplace.json` |
| legacy-compatible | `$REPO_ROOT/.claude-plugin/marketplace.json` |

**Top-level fields shown.** `name`, `interface` (with `interface.displayName`), `plugins`.

**Plugin entry.** `name`, `source`, `policy` (`policy.installation`,
`policy.authentication`), `category`. "Always include `policy.installation`,
`policy.authentication`, and `category` on each plugin entry." `policy.installation`
values named: `AVAILABLE`, `INSTALLED_BY_DEFAULT`, `NOT_AVAILABLE`. `policy.authentication`
"decide[s] whether auth happens on install or first use"; the only literal shown is
`ON_INSTALL`. This repo's own [`.agents/plugins/marketplace.json`](../../../.agents/plugins/marketplace.json)
uses exactly that shape (`measured`: it is what Codex reads for this plugin today).

**Source types.**

| `source` | Fields | Notes |
|---|---|---|
| `local` | `path` (`./…`, inside the marketplace root) | A plain string path is also accepted for local entries. |
| `url` | not shown in an example | "when the plugin lives at the repository root" |
| `git-subdir` | `url`, `path`, `ref` (or `sha`) | |
| `npm` | `package` (required), `version` (versions, dist-tags, ranges), `registry` (HTTPS, no credentials) | "Codex downloads the package without running lifecycle scripts." |

An entry whose source cannot be resolved is skipped "instead of failing the whole
marketplace". Installed local plugins are cached at
`~/.codex/plugins/cache/$MARKETPLACE_NAME/$PLUGIN_NAME/$VERSION/` with `$VERSION` = `local`.

**Plugin manifest.** The portable entry point is a root `plugin.json` (`$schema`, `name`,
`version`, `description`, `author{name,email,url}`, `homepage`, `repository`, `license`,
`keywords`, `extensions.com.openai`); `.codex-plugin/plugin.json` is "optional and serves as
a compatibility fallback". Submitted packages: `name` max 64 chars, lowercase letters,
digits, single hyphens; `version` required for Codex, "an explicit semantic version".

**User-side commands** (doc-cited on the build page):

```text
codex plugin marketplace add owner/repo
codex plugin marketplace add owner/repo --ref main
codex plugin marketplace add https://github.com/example/plugins.git --sparse .agents/plugins
codex plugin marketplace add ./local-marketplace-root
codex plugin marketplace list
codex plugin marketplace upgrade [marketplace-name]
codex plugin marketplace remove marketplace-name
```

`--sparse PATH` is "valid only for Git marketplace sources". The page says these commands
"support plugin authoring and catalog setup" and points to the ChatGPT desktop app to
install and test a local plugin; it states no `codex plugin install`. The `source-cited`
install verb on the CLI is `codex plugin add <plugin>@<marketplace>` (cli/src/plugin_cmd.rs
on 0.166.0, recorded in [permissions/platforms/codex.md](permissions/platforms/codex.md)).
`config.toml` enables an installed plugin under `[plugins."<plugin>@<marketplace>"]` with
`enabled = true`.

**Validation.** None stated. The public-directory portal runs automated checks on an
uploaded ZIP; `@plugin-creator` scaffolds the compatibility manifest.

**Claude compatibility.** Codex reads `$REPO_ROOT/.claude-plugin/marketplace.json` as a
legacy-compatible marketplace and sets `CLAUDE_PLUGIN_ROOT` / `CLAUDE_PLUGIN_DATA` for
hook compatibility. "OpenAI also accepts legacy and Claude-compatible manifests, but new
packages should use this format."

## OpenCode

Source, read 2026-11-05: <https://opencode.ai/docs/plugins/> (page dated Nov 5, 2026).

**What a plugin is.** "A plugin is a **JavaScript/TypeScript module** that exports one or
more plugin functions. Each function receives a context object and returns a hooks object."
Locations: `.opencode/plugins/` (project) and `~/.config/opencode/plugins/` (global), loaded
automatically at startup. npm packages are named in `opencode.json`:

```json
{ "plugin": ["opencode-helicone-session", "@my-org/custom-plugin"] }
```

"npm plugins are installed automatically using Bun at startup" and cached under
`~/.cache/opencode/node_modules/`. Version-pinning syntax is not stated.

**Marketplace.** **None.** The page defines no marketplace, registry or catalog manifest;
it only says "Browse available plugins in the ecosystem" (a curated docs page). The
distribution channel is npm plus local files. No add/install command, no validation
command, and no statement about Claude Code plugins or marketplaces.

**Consequence for the scaffold.** `--type marketplace` writes **no OpenCode manifest**.
The generated README states that OpenCode has no marketplace and that a catalogued plugin
reaches OpenCode only if it is also published to npm as an OpenCode plugin module, which
users then name in `opencode.json`. This matches the capability registry's
`plugin_marketplace: unsupported` row for OpenCode.

## What the scaffold does with this

| Platform | Scaffolded file | Validated by `scripts/validate-marketplace.sh` |
|---|---|---|
| Claude Code / Desktop | `.claude-plugin/marketplace.json` | required fields, name charset, source shapes, `..` escapes, local path exists, entry/plugin `name` agreement, duplicates; plus `claude plugin validate .` when the CLI is on PATH |
| Cursor | `.cursor-plugin/marketplace.json` | required fields, kebab-case names, path sources resolve (honouring `metadata.pluginRoot`), ≤ 10 MB, duplicates |
| Codex | `.agents/plugins/marketplace.json` | required fields, `policy.installation` enum, `policy.authentication` and `category` present, source shapes, local path exists |
| OpenCode | none | prints that no manifest exists for OpenCode |
| cross-platform | — | a plugin named in the Cursor or Codex catalog but absent from the Claude catalog is an error; the reverse is a warning |

Capability-registry rows updated from this research: `core/capabilities/platforms.json`
`plugin_marketplace` on `claude_code`, `claude_desktop`, `codex`, `cursor`, `opencode`
(`last_verified: 2026-11-05`).
