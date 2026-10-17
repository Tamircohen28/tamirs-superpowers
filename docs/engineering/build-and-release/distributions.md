# Per-host distributions

One source tree, seven subsets. `scripts/build-dist.sh --target <t>` writes the subset a
host should receive, `scripts/check-dist.sh --target <t>` (or, for Claude,
`scripts/check-claude-dist.sh`) holds it to that host's rules, and
`tests/test-dist.sh` plants each rule's failure shape and asserts the check names it. CI
builds and checks every target on every pull request; the release workflow tags the
Claude tree and attaches the others to the GitHub Release.

## Why subsets and not the repository

Every host reads a different manifest and a different hooks file, and each has a parser
with hard edges that the whole tree trips on:

| Host | What the whole tree does to it | What its subset ships instead |
|---|---|---|
| Anthropic's plugin directory | holds a listing on tests, engineering docs, fixtures, other hosts' docs, and prose about what the plugin *used* to do | [`directory-distribution.md`](directory-distribution.md): the Claude manifest, the mod, `hooks/hooks.json`, user docs for Claude only |
| Codex CLI | its hooks parser (`HooksFile`, `deny_unknown_fields`) rejects the `modules` key the Claude hooks file carries, so no hook loads; the mod and output styles are dead weight | the root Agent Plugins manifest (`extensions.com.openai`), `.codex-plugin/plugin.json` as the pre-0.147 fallback, the generated `platforms/codex/hooks.json`, `.codex/agents/*.toml` |
| Cursor | binds `hooks/hooks.json` by default and cannot read it; every `${VAR}` in an MCP config must be a declared plugin variable | `.cursor-plugin/plugin.json`, `platforms/cursor/hooks.json`, `platforms/cursor/mcp.json`, the generated `.cursor/rules` and `.cursor/commands`, `agents/` |
| Gemini CLI | discovers skills one level deep only; the `.gemini/skills` mirror is symlinks; runs hooks from `hooks/hooks.json` and nowhere else, where the Claude file's `${CLAUDE_PLUGIN_ROOT}` expands to nothing | `gemini-extension.json`, the `.gemini/` adapter with the mirror **dereferenced into copies** so the tarball stands alone, the **generated** `platforms/gemini/hooks.json` placed at `hooks/hooks.json` with `hooks/gemini-wrap.sh`, and `policies/*.toml` |
| Antigravity | a closed plugin schema (`plugin.json` is `{name, description}` and nothing else), skills one level under `skills/`, no hooks file in the format | `plugin.json` and `mcp_config.json` at the root (generated under `platforms/antigravity/`), the `.agents/skills` mirror dereferenced and flattened to `skills/`, the Gemini agent translations as `agents/`; unverified against a live `agy` (the registry says so) |
| OpenCode | executes no shell hook, reads `AGENTS.md` only | `opencode.json`, `AGENTS.md`, the `.opencode/` adapter |
| Agent Plugins 1.0 clients (Copilot CLI, Kiro, VS Code, …) | know skills and MCP and nothing else | `plugin.json` and `mcp.json` at the package root (generated under `platforms/agent-plugins/`, never at the repository root: a root manifest makes Codex drop every hook), `skills/` and what the skills link to |

Every target shares the canonical content: `skills/`, `core/`, `rules/`, `templates/`,
`config/`, the scripts skills run, and `LICENSE`, `SECURITY.md`, `PRIVACY.md`,
`plugin-version.json`. The per-target table in `build-dist.sh` adds the host's manifest
set and hooks file and prunes the other hosts' install docs and setup libraries. The
markdown-link closure then pulls in every file a shipped doc links to, limited to the
target's roots and `docs/user/`, so no shipped page points at a 404 and no engineering
page or changelog comes along by accident.

## The checks

`check-dist.sh` is the per-target table of host rules, kept in the same spirit as the
Claude checker: a rule is added when a host's parser or policy is documented or
source-read to reject a shape, with the source quoted in the script, and
`tests/test-dist.sh` plants that shape to prove the rule fires. Structural rules every
target meets: no symbolic link, no binary a host cannot read, every `.json` parses, one
version across `plugin-version.json` and every manifest present, no credential-shaped
literal, no test, changelog, engineering doc or workflow. Per target:

| Target | Rules |
|---|---|
| `codex` | `.codex-plugin/plugin.json` present and **no root Agent Plugins manifest** (measured: it empties every hook source on 0.163.0); `platforms/codex/hooks.json` present with no `modules`, no `onFailure` (a Claude key), only the twelve Codex events, every named script shipped; the Claude hooks file and the mod absent; the fallback manifest's `hooks` points at the generated file |
| `cursor` | bundle declares `"version": 1`; every `${VAR}` in `platforms/cursor/mcp.json` is declared under the manifest's `variables.properties`; `.cursor/rules` and `agents/` present; the Claude hooks file and the mod absent |
| `gemini` | `gemini-extension.json` and the dereferenced `.gemini/skills` mirror present; `hooks/hooks.json` present and **generated** (no `modules`, no `onFailure`, no `${CLAUDE_PLUGIN_ROOT}`, only the eleven Gemini events, every command through `hooks/gemini-wrap.sh` naming a shipped script, millisecond timeouts); `policies/tamirs-superpowers.toml` present; no second copy under `platforms/gemini/`; no mod |
| `antigravity` | `plugin.json` carries exactly `name` and `description`; `mcp_config.json` exactly `mcpServers`; skills one level under `skills/`; `agents/` present; no hooks file, mod, `platforms/`, `.agents/`, `.gemini/` or Gemini manifest |
| `opencode` | `opencode.json`, `AGENTS.md` and `.opencode/` present; no `hooks/`, no mod |
| `agent-plugins` | `plugin.json` carries the 1.0.0 `$schema` and a conformant `name`; `mcp.json` has a `$schema`, `stdio` or `streamable-http` transports only (never Claude's `http`), and a `${PLUGIN_ROOT}` command; no hooks, agents, mod or host manifest |
| all | every skill's `name` equals its folder (the Agent Skills rule); the skill count equals the source tree's |

## Where each subset goes

| Target | Delivery |
|---|---|
| `claude` | committed as a generated tree and tagged `v<version>-claude` + `claude` by `release.yml`'s `claude-dist` job; the directory tracks the `claude` tag |
| the rest | built by `release.yml`'s `dist-assets` job from the release tag, each packed as `tamirs-superpowers-<version>-<target>.tar.gz` with a `SHA256SUMS-<version>.txt` beside them and `platforms-<version>.json` (the capability registry) as a further asset, attached to the GitHub Release |

A marketplace that wants a host's subset rather than the repository points at the
tarball; the install docs keep the repository routes (`/plugin marketplace add`,
`codex plugin marketplace add`, a Cursor team import, `gemini extensions install`, an
OpenCode path install), which continue to work because the hosts read only the files
their subset would contain.

## Commands

```bash
bash scripts/build-dist.sh --list-targets
bash scripts/build-dist.sh build/codex --target codex --force
bash scripts/check-dist.sh build/codex --target codex
bash scripts/build-dist.sh build/antigravity --target antigravity --force   # flat skills/, root plugin.json + mcp_config.json
make check-dists            # build and check every target in a temp dir (part of make validate)
bash tests/test-dist.sh     # the planted-finding probes (part of make test-hooks)
```

Adding a target: a `case` arm in `build-dist.sh` (roots, extra prunes, README source), a
`case` arm in `check-dist.sh` (the host's rules, each with its source), probes in
`tests/test-dist.sh`, a loop entry in `release.yml`'s `dist-assets` job, and a row in each
table above.
