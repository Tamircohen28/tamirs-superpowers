# Platform capability equivalence

Maps **tamirs-superpowers** capabilities across the five supported targets: Claude Code, Cursor, Codex, Gemini CLI, and OpenCode (Claude Desktop is a runtime surface of the Claude adapter, not a separate target).

Platform tool versions: [`../engineering/build-and-release/platform-targets.md`](../engineering/build-and-release/platform-targets.md).
Per-target install guides: [`../user/install/`](../user/install/README.md).

**This page is a human rendering, not a source.** The machine-readable status of every
capability on every target is [`core/capabilities/platforms.json`](../../core/capabilities/platforms.json).
If this table and the registry disagree, the registry is right and this page is stale —
`make check-feature-equivalence` fails when the platform sets diverge.

## Instructions

| Capability | Claude Code | Cursor | Codex | Gemini CLI | OpenCode |
|------------|-------------|--------|-------|------------|----------|
| Repo policy | `CLAUDE.md` → `@AGENTS.md` | `.cursor/rules/*.mdc` → `AGENTS.md` | `AGENTS.md` | `.gemini/GEMINI.md` via `gemini-extension.json` `contextFileName` | `AGENTS.md` |

## Skills

| Capability | Claude Code | Cursor | Codex | Gemini CLI | OpenCode |
|------------|-------------|--------|-------|------------|----------|
| Bundled skills | `skills/` via `.claude-plugin/plugin.json` | same paths in `.cursor-plugin/plugin.json` | same paths in `.codex-plugin/plugin.json` | generated flat mirror at `.gemini/skills/` | `skills.paths` in `opencode.json` (absolute paths) |

OpenCode scans `.opencode/skills/`, `.claude/skills/`, and `.agents/skills/` (project and global) natively, and the scan **is** recursive — the domain-nested `skills/<domain>/<name>/SKILL.md` layout is discovered as-is. OpenCode's published docs claim otherwise; verified against 1.16.2 and 1.18.11 with `opencode debug skill`.

**OpenCode does not follow symlinks for skill discovery, at any level** — a symlinked
`skills` directory, a symlinked domain directory, and a symlinked individual skill
directory all yield zero discovered skills (verified 1.18.11). Use absolute
`skills.paths`; do not recommend a symlink install.

**Gemini CLI reads a skills root exactly one level deep** (verified 0.55.1):
`skills/<name>/SKILL.md` is discovered, `skills/<domain>/<name>/SKILL.md` is not — so the
canonical domain-nested tree resolves to zero. `scripts/build-gemini-extension.sh` generates
a flat mirror at `.gemini/skills/`, one symlink per skill, so the repo still holds exactly
one copy of each. Gemini reads it natively: in-workspace with no install at all, or through
a single `gemini skills install <url> --path .gemini/skills --consent`. Regenerate it; never
hand-edit it.

**The two mirror strategies are not interchangeable.** Gemini follows symlinks for skill
discovery; OpenCode does not, at any level. A flat symlink mirror is the fix on one and a
silent zero-skill install on the other.

## Agents

| Capability | Claude Code | Cursor | Codex | Gemini CLI | OpenCode |
|------------|-------------|--------|-------|------------|----------|
| Specialist agents | `agents/*.md` via the Agent tool | `agents/` auto-discovered from the plugin root | `agents/` at the repo root | `.gemini/agents/*.md` — generated adapters | `.opencode/agent/*.md` — generated adapters |

**Gemini needs a translation, and now has one.** The canonical `agents/*.md` are rejected
with `tools.0: Invalid tool name`: Gemini wants `tools` as an array of its own tool names
while this repo declares Claude's (`Read`, `Grep`, `Glob`, `Bash`) as a string.
`scripts/build-gemini-extension.sh` emits `.gemini/agents/*.md` with real Gemini tool names
(`read_file`, `search_file_content`, `glob`, `run_shell_command`) verified against the
loader, and omits `model:` entirely — a Claude alias such as `sonnet` passes validation and
then fails at invocation, which is worse than absent. A Gemini-shaped translation cannot
live at `agents/` without breaking Claude, which is exactly why it is generated, like
`.opencode/agent/`.

OpenCode validates agent frontmatter strictly and refuses to start on a bad field: `tools` must be an object of tool→boolean (not Claude's comma string) and `model` needs a provider prefix. `scripts/build-opencode-agents.sh` translates `agents/*.md` into `.opencode/agent/*.md`; the output is committed so a clone needs no build step. Regenerate with `make opencode-agents`; `make agent:check` fails on drift.

## MCP servers

| Capability | Claude Code | Cursor | Codex | Gemini CLI | OpenCode |
|------------|-------------|--------|-------|------------|----------|
| Stubs | `.mcp.json` | `mcpServers` in `.cursor-plugin/plugin.json` | `mcpServers` in `.codex-plugin/plugin.json` + optional `.codex/config.toml` | `mcpServers` in `gemini-extension.json` | manual — port entries into the `mcp` block of `opencode.json` |

MCP is the one capability that is `native` on every supported target.

Fill `${ENV_VAR}` placeholders locally — never commit tokens.

## Hooks / lifecycle automation

| Capability | Claude Code | Cursor | Codex | Gemini CLI | OpenCode |
|------------|-------------|--------|-------|------------|----------|
| Worktree hooks | `hooks/hooks.json` (when present) | Claude-shaped plugin `hooks/hooks.json` does **not** run for Cursor plugin installs. **Project** Cursor hooks ship in `.cursor/hooks.json` (soft contributor guards for this repo as a workspace / Cloud Agent). Optional: Cursor can load Claude hooks from `.claude/settings.json` when third-party skills/hooks are enabled. Full Claude→Cursor plugin hooks port (manifest `hooks`) still pending | `hooks` field in `.codex-plugin/plugin.json` when Claude hooks ship | ⚠️ unverified — the manifest field loads, but firing is unproven | ❌ none — lifecycle automation is JS/TS plugin modules only |

**Cursor note (3.11+):** Cursor has native plugin hooks and project/cloud hooks (`.cursor/hooks.json`). They use a different schema from Claude Code's `PreToolUse` / `SessionStart` suite. Do not treat presence of plugin `hooks/hooks.json` as proof the worktree guards run for Cursor plugin installs. See [Third-party hooks](https://cursor.com/docs/reference/third-party-hooks.md) for settings-based Claude compatibility.

**Cursor substitute today:** project `.cursor/hooks.json` for contributor/cloud soft guards on this repo; for installed consumers, enforce worktree and sensitive-file rules via `AGENTS.md` and path-scoped Cursor rules under `.cursor/rules/`.

**Gemini note:** Gemini reads `hooks/hooks.json` from the extension root and accepts the
same outer `{"hooks": {...}}` shape as Claude — but it has its own event vocabulary and
accepts unknown event names without complaint, so acceptance proves nothing about whether a
hook fires. Whether Claude event names ever fire was never measured, so nothing is claimed
in either direction; check the registry for the live status rather than trusting this
paragraph. `gemini hooks migrate --from-claude` exists for users who want to translate them.

**OpenCode gap:** OpenCode has no `hooks.json` equivalent. Its `"plugin"` config field takes JavaScript/TypeScript modules — a different mechanism from a skill bundle — so the worktree guards in `hooks/` do not port. Rely on `AGENTS.md` discipline there.

## Install and distribution

| Capability | Claude Code | Cursor | Codex | Gemini CLI | OpenCode |
|------------|-------------|--------|-------|------------|----------|
| Standalone install from this repo | ✅ `/plugin marketplace add Tamircohen28/tamirs-superpowers` | ✅ Import from Repo | ✅ `codex plugin marketplace add Tamircohen28/tamirs-superpowers` | ✅ `gemini extensions install <repo-url>` then one `gemini skills install <repo-url> --path .gemini/skills --consent` | ✅ by path — absolute `skills.paths` |
| Marketplace manifest | `.claude-plugin/marketplace.json` / catalog | `.cursor-plugin/plugin.json` (+ `marketplace.json` for multi-plugin repos) | `.agents/plugins/marketplace.json` | ❌ no marketplace — installs from a git URL | ❌ no marketplace |
| Update mechanism | `/plugin update` — keyed on `version` | Auto Refresh re-reads the whole manifest | `codex plugin marketplace upgrade` | `gemini extensions update` | `git pull` |

Claude Desktop installs the Claude Code plugin from the same marketplace listing and needs
no manifest of its own — that is what "runtime surface" means.

## Claude-only features (documented asymmetry)

| Feature | Notes |
|---------|-------|
| Statusline | `.claude-plugin/plugin.json` `settings.statusLine` — Claude Code only; `unsupported` on Cursor, Codex, Gemini CLI and OpenCode |
| Plugin dependency resolution | Declared dependencies auto-install on Claude Code only |
| Full hook suite | Worktree guards, session init, notification hooks — Claude Code (and Codex via the `hooks` field) |

These are intentional; they do not block multi-platform skill and policy parity.
