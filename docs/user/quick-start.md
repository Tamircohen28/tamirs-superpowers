# Quick Start

Install `tamirs-superpowers` and run your first skill in under 5 minutes.

Four targets are supported — **Claude Code, Cursor, Codex, and OpenCode**. This page walks the Claude Code path; the other three have full guides:

| Target | Guide |
|--------|-------|
| Claude Code | this page, or [install/claude-code.md](install/claude-code.md) |
| Cursor | [install/cursor.md](install/cursor.md) |
| Codex | [install/codex.md](install/codex.md) |
| OpenCode | [install/opencode.md](install/opencode.md) |

## Prerequisites

- Claude Code v2.0+ installed
- `jq` installed: `brew install jq`
- `git` 2.30+

## Step 1 — Add a marketplace

Either the catalog (recommended — it carries the whole plugin family):

```
/plugin marketplace add Tamircohen28/tamirs-marketplace
```

…or this repo standalone, which ships its own manifest:

```
/plugin marketplace add Tamircohen28/tamirs-superpowers
```

## Step 2 — Install the plugin

```
/plugin install tamirs-superpowers@tamirs-marketplace
```

Use `/plugin install tamirs-superpowers` if you added the standalone marketplace.

The plugin declares **no** dependencies — nothing else installs alongside it.

## Step 3 — Reload (Claude Code < 2.1.221 only)

Since Claude Code 2.1.221, plugins installed with `/plugin install` activate
immediately when safe — skip this step. On older versions:

```
/reload-plugins
```

Or restart Claude Code entirely.

## Step 4 — Try a skill

Open Claude Code in any git repo and try:

```
/tamirs-superpowers:find-skill
```

That lists all 26 bundled skills — a good sanity check that the plugin loaded.

For a dev workflow demo:

```
/tamirs-superpowers:plan-dev add a README to this repo
```

Claude will propose a phased plan and create GitHub issues after you approve.

## Step 5 — Optional companion marketplaces

A few bundled skills reference plugins from other catalogs. Register them once per machine if you want those skills to resolve everything they mention:

```
/plugin marketplace add warpdotdev/claude-code-warp
/plugin marketplace add anthropics/knowledge-work-plugins
/plugin marketplace add obra/superpowers
```

## Step 6 — Agent-kit repo (optional)

To scaffold a **multi-platform rule and skill distribution repo** (canonical source → Claude/Cursor/Codex adapters):

```
/tamirs-superpowers:repo-scaffold my-agent-kit -- "Shared engineering rules for the team" --type plugin
```

See the full guide: [Agent-kit repos](agent-kit.md).

## Alternative: install without a marketplace

Clone directly into Claude Code's local skills directory:

```bash
git clone https://github.com/Tamircohen28/tamirs-superpowers.git \
  ~/.claude/skills/tamirs-superpowers
```

Claude Code auto-loads any plugin placed under `~/.claude/skills/`. No `/plugin marketplace add` or `/plugin install` needed. Reload with `/reload-plugins`.

Trade-off: no automatic updates — `git pull` to refresh.

## Enable MCP servers (optional)

The plugin ships stubs for GitHub, Slack, Context7, and Desktop Commander. To activate one:

1. Find the plugin install directory: `/plugin list` → look for `tamirs-superpowers` path
2. Open `.mcp.json` in that directory
3. Set the required env vars (e.g. `GITHUB_PERSONAL_ACCESS_TOKEN`)
4. Restart Claude Code

Each server's required env vars are documented in `.mcp.json`.
