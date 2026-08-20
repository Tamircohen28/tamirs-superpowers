# Platform capability equivalence

Maps **tamirs-superpowers** capabilities across the **six supported surfaces** — Claude Code, Claude Desktop, Codex CLI, Cursor IDE, Gemini CLI and OpenCode CLI — which belong to five platforms: Claude, Codex, Cursor, Gemini and OpenCode.

A *surface* is a thing you install into: a terminal client, a desktop app, an editor extension. Capabilities and install paths belong to the surface, not the vendor, which is why the columns below are surfaces. See [capability-model.md](../engineering/architecture/capability-model.md#platforms-and-surfaces).

The registry also lists four **unverified** surfaces — Codex IDE extension, Cursor CLI, Gemini Code Assist and OpenCode desktop app. They are deliberately absent from every table on this page: nobody has measured them, so a cell for them would be a claim in one direction or the other, and there is no evidence for either. They are not targets. Read their `unverified_reason` in the registry for what is and is not known.

Platform tool versions: [`../engineering/build-and-release/platform-targets.md`](../engineering/build-and-release/platform-targets.md).
Per-surface install guides: [`../user/install/`](../user/install/README.md).

**This page is a human rendering, not a source.** The machine-readable status of every
capability on every supported surface is [`core/capabilities/platforms.json`](../../core/capabilities/platforms.json).
If this table and the registry disagree, the registry is right and this page is stale —
`make check-feature-equivalence` fails when the surface sets diverge.

## Instructions

| Capability | Claude Code | Claude Desktop | Codex CLI | Cursor IDE | Gemini CLI | OpenCode CLI |
|------------|-------------|----------------|-----------|------------|------------|--------------|
| Repo policy | `CLAUDE.md` → `@AGENTS.md` | same file, same plugin — Desktop adds no policy path of its own | `AGENTS.md` | `.cursor/rules/*.mdc` → `AGENTS.md` | `.gemini/GEMINI.md` via `gemini-extension.json` `contextFileName` | `AGENTS.md` |

## Skills

| Capability | Claude Code | Claude Desktop | Codex CLI | Cursor IDE | Gemini CLI | OpenCode CLI |
|------------|-------------|----------------|-----------|------------|------------|--------------|
| Bundled skills | `skills/` via `.claude-plugin/plugin.json` | the same plugin, installed from the same listing — no manifest of its own | same paths in `.codex-plugin/plugin.json` | same paths in `.cursor-plugin/plugin.json` | generated flat mirror at `.gemini/skills/` | `skills.paths` in `opencode.json` (absolute paths) |

**Claude Desktop is a runtime surface of the Claude Code plugin, not a second adapter.** It consumes the Claude Code plugin format and needs no manifest, no build step and no separate install artifact — which is exactly why it is a *surface* of the `claude` platform rather than a platform in its own right. What it is not is a duplicate of Claude Code's capability rows: several of them are `unknown` there, because a Desktop run has never been recorded. Where that matters, the row below says so.

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

| Capability | Claude Code | Claude Desktop | Codex CLI | Cursor IDE | Gemini CLI | OpenCode CLI |
|------------|-------------|----------------|-----------|------------|------------|--------------|
| Specialist agents | `agents/*.md` via the Agent tool | ⚠️ ships with the plugin; whether subagents run there is `unknown` — never measured | `agents/` at the repo root | `agents/` auto-discovered from the plugin root | `.gemini/agents/*.md` — generated adapters | `.opencode/agent/*.md` — generated adapters |

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

| Capability | Claude Code | Claude Desktop | Codex CLI | Cursor IDE | Gemini CLI | OpenCode CLI |
|------------|-------------|----------------|-----------|------------|------------|--------------|
| Stubs | `.mcp.json` | MCP is native, but servers are configured in the Desktop app rather than from the repo | `mcpServers` in `.codex-plugin/plugin.json` + optional `.codex/config.toml` | `mcpServers` in `.cursor-plugin/plugin.json` | `mcpServers` in `gemini-extension.json` | manual — port entries into the `mcp` block of `opencode.json` |

MCP is the one capability that is `native` on all six supported surfaces.

Fill `${ENV_VAR}` placeholders locally — never commit tokens.

## Hooks / lifecycle automation

| Capability | Claude Code | Claude Desktop | Codex CLI | Cursor IDE | Gemini CLI | OpenCode CLI |
|------------|-------------|----------------|-----------|------------|------------|--------------|
| Worktree hooks | `hooks/hooks.json` (when present) | ⚠️ `unknown` — the bundle installs with the plugin, but nobody has confirmed the events fire in a Desktop session. Assume no hooks | `hooks` field in `.codex-plugin/plugin.json` when Claude hooks ship | Claude-shaped plugin `hooks/hooks.json` does **not** run for Cursor plugin installs. **Project** Cursor hooks ship in `.cursor/hooks.json` (soft contributor guards for this repo as a workspace / Cloud Agent). Optional: Cursor can load Claude hooks from `.claude/settings.json` when third-party skills/hooks are enabled. Full Claude→Cursor plugin hooks port (manifest `hooks`) still pending | ⚠️ unverified — the manifest field loads, but firing is unproven | ❌ none — lifecycle automation is JS/TS plugin modules only |

**Claude Desktop note:** this is the clearest case for keeping surfaces apart. Claude Code and Claude Desktop install the same hook bundle from the same listing, and only one of them is known to run it. Merged into one Claude row, the CLI's `native` would have been read as covering both.

**Cursor note (3.11+):** Cursor has native plugin hooks and project/cloud hooks (`.cursor/hooks.json`). They use a different schema from Claude Code's `PreToolUse` / `SessionStart` suite. Do not treat presence of plugin `hooks/hooks.json` as proof the worktree guards run for Cursor plugin installs. See [Third-party hooks](https://cursor.com/docs/reference/third-party-hooks.md) for settings-based Claude compatibility. Everything in this column was measured through an **IDE plugin install**; the Cursor CLI is a separate, unverified surface and none of it carries over.

**Cursor substitute today:** project `.cursor/hooks.json` for contributor/cloud soft guards on this repo; for installed consumers, enforce worktree and sensitive-file rules via `AGENTS.md` and path-scoped Cursor rules under `.cursor/rules/`.

**Gemini note:** Gemini reads `hooks/hooks.json` from the extension root and accepts the
same outer `{"hooks": {...}}` shape as Claude — and it accepts a completely invented event
name just as silently, so the file loading proves nothing about a hook firing.

The vocabularies **partially overlap** rather than differ wholesale, which matters because
"they're different" invites dropping the Claude file in and assuming it does nothing.
Measured against this repo's ten declared events on 0.55.1:

| Claude events | Gemini status |
|---|---|
| `SessionStart`, `SessionEnd`, `Notification` | real Gemini events — but firing was never tested |
| `PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `Stop` | exist only in the `gemini hooks migrate --from-claude` mapping table |
| `DirectoryAdded`, `WorktreeCreate`, `WorktreeRemove` | no counterpart at all |

So the worktree guards need real translation nobody has done, and three handlers might
already be live and unverified. Nothing is claimed in either direction — check the registry
for the live status rather than trusting this paragraph.

**OpenCode gap:** OpenCode has no `hooks.json` equivalent. Its `"plugin"` config field takes JavaScript/TypeScript modules — a different mechanism from a skill bundle — so the worktree guards in `hooks/` do not port. Rely on `AGENTS.md` discipline there.

## Install and distribution

| Capability | Claude Code | Claude Desktop | Codex CLI | Cursor IDE | Gemini CLI | OpenCode CLI |
|------------|-------------|----------------|-----------|------------|------------|--------------|
| Standalone install from this repo | ✅ `/plugin marketplace add Tamircohen28/tamirs-superpowers` | ✅ the same marketplace listing as Claude Code | ✅ `codex plugin marketplace add Tamircohen28/tamirs-superpowers` | ✅ Import from Repo | ✅ `gemini extensions install <repo-url>` then one `gemini skills install <repo-url> --path .gemini/skills --consent` | ✅ by path — absolute `skills.paths` |
| Marketplace manifest | `.claude-plugin/marketplace.json` / catalog | none of its own — that is what "runtime surface" means | `.agents/plugins/marketplace.json` | `.cursor-plugin/plugin.json` (+ `marketplace.json` for multi-plugin repos) | ❌ no marketplace — installs from a git URL | ❌ no marketplace |
| Update mechanism | `/plugin update` — keyed on `version` | same `/plugin update`, same version key | `codex plugin marketplace upgrade` | Auto Refresh re-reads the whole manifest | `gemini extensions update` | `git pull` |

## Claude-only features (documented asymmetry)

| Feature | Notes |
|---------|-------|
| Statusline | `.claude-plugin/plugin.json` `settings.statusLine` — Claude Code only; `unsupported` on Claude Desktop (no terminal chrome to render into), Cursor IDE, Codex CLI, Gemini CLI and OpenCode CLI |
| Plugin dependency resolution | Declared dependencies auto-install on Claude Code only |
| Full hook suite | Worktree guards, session init, notification hooks — Claude Code (and Codex CLI via the `hooks` field). Unverified on Claude Desktop |

These are intentional; they do not block multi-platform skill and policy parity.
