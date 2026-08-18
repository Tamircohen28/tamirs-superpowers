# Platform reference data — `opencode`

Data consumed by the `platform-sync` engine (`references/analysis-protocol.md`).

- **Display name:** OpenCode
- **Registry id:** `opencode` (same in the registry, in `platform-targets.json`, and in a skill's `compatibility` block)

## Detection signals

| Signal | Path / pattern | Strength |
|--------|----------------|----------|
| Config file | `opencode.json` at repo root | strong |
| Agent adapters | `.opencode/agent/*.md` | strong |
| Plugin modules | `.opencode/plugin/*.{js,ts}` | medium |
| Config directory | `.opencode/` (any contents) | medium |
| Global config only | `~/.config/opencode/opencode.json` | weak — repo may rely on user config |

OpenCode has **no plugin manifest** — there is no `.opencode-plugin/plugin.json` and no
marketplace entry. Absence of a manifest is not absence of the target.

## Sources — P0 (fetch always; failure aborts this platform only)

| Topic | URL |
|---|---|
| npm dist-tags — authoritative `latest` | https://registry.npmjs.org/opencode-ai/latest |
| GitHub releases (the de-facto changelog) | https://github.com/sst/opencode/releases |

OpenCode ships no hand-written changelog page. Use the npm `latest` endpoint for the
version string — it is the same artifact `npm i -g opencode-ai` installs, so it cannot
drift from what users get.

## Sources — P1

| Fetch when local config contains / lacks | URL |
|---|---|
| `skills.paths` present, or a skills tree exists | https://opencode.ai/docs/skills/ |
| `.opencode/agent/*.md` present, or agents to port | https://opencode.ai/docs/agents/ |
| Any `opencode.json` | https://opencode.ai/config.json |
| MCP servers declared elsewhere but not here | https://opencode.ai/docs/mcp-servers/ |

## Sources — P2

| Topic | URL |
|---|---|
| Plugins — JS/TS lifecycle modules | https://opencode.ai/docs/plugins/ |
| Rules / instruction files | https://opencode.ai/docs/rules/ |

## Local config to read

| Path | What to note |
|------|--------------|
| `opencode.json` | `$schema`, `skills.paths` coverage, `mcp`, `agent` blocks |
| `.opencode/agent/*.md` | Which specialist agents are ported, and their frontmatter |
| `.opencode/plugin/*.{js,ts}` | Lifecycle plugin modules |
| `AGENTS.md` | Whether OpenCode inherits canonical agent policy |
| `skills/**/SKILL.md` | Domain nesting depth vs what `skills.paths` enumerates |

## Feature-scan areas

- **`skills.paths` drift — check this first.** OpenCode discovers skills under the paths
  listed in `opencode.json`. A skill added to a **new** domain directory is invisible until
  that domain is added. Compare the set of top-level domains under `skills/` against the
  enumerated paths and flag any domain on disk but absent from config. This is the single
  most common OpenCode drift in a multi-target repo, because every other target discovers
  skills by tree walk and needs no such list.
- **Agent parity** — a repo shipping N specialist agents to Claude Code but fewer as
  `.opencode/agent/*.md` has silent capability loss. Report the delta explicitly.
- **Generated-adapter drift** — `.opencode/agent/*.md` files generated from canonical
  `agents/` must be regenerated, not hand-edited. Flag any that has diverged.
- **Config schema** — is `$schema` pinned? New top-level keys in the published schema?
- **MCP** — servers wired for other targets but not declared here.

## Version detection

Declared: `targets.opencode.validated_against` in
`docs/engineering/build-and-release/platform-targets.json`, else `project-only`.
Latest: `version` from the npm `latest` endpoint.

## Capability boundaries

OpenCode has **no** plugin marketplace, **no** `hooks.json`, and **no** plugin-declared
statusline. Never emit an improvement step that assumes one. These are documented capability
gaps, not drift — report them under "Documented gaps", never under "Improvement steps".
The authoritative list is the capability registry (`core/capabilities/platforms.json`),
falling back to `capability_gaps` under `targets.opencode` in
`docs/engineering/build-and-release/platform-targets.json`.
