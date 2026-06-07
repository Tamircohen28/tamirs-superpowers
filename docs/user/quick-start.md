# Quick Start

Install `tamirs-superpowers` and run your first skill in under 5 minutes.

## Prerequisites

- Claude Code v2.0+ installed
- `jq` installed: `brew install jq`
- `git` 2.30+

## Step 1 — Register third-party marketplaces

These are needed once per machine so Claude Code can resolve all plugin dependencies:

```
/plugin marketplace add warpdotdev/claude-code-warp
/plugin marketplace add anthropics/knowledge-work-plugins
/plugin marketplace add obra/superpowers
```

## Step 2 — Add this marketplace

```
/plugin marketplace add TamirCohen28/tamirs-superpowers
```

## Step 3 — Install the plugin

```
/plugin install tamirs-superpowers
```

Claude Code resolves and installs the 9 declared dependencies automatically. You'll see them listed in the install output.

## Step 4 — Reload

```
/reload-plugins
```

Or restart Claude Code entirely.

## Step 5 — Try a skill

Open Claude Code in any git repo and try:

```
/tamirs-superpowers:changelog-review what hooks are available in Claude Code?
```

This fetches live Claude Code docs and answers from them — a good sanity check that the plugin loaded correctly.

For a dev workflow demo, try:

```
/tamirs-superpowers:plan-dev add a README to this repo
```

Claude will propose a phased plan and create GitHub issues after you approve.

## Alternative: install without a marketplace

If you don't want to use the marketplace system, clone directly into Claude Code's local skills directory:

```bash
git clone https://github.com/TamirCohen28/tamirs-superpowers.git \
  ~/.claude/skills/tamirs-superpowers
```

Claude Code auto-loads any plugin placed under `~/.claude/skills/`. No `/plugin marketplace add` or `/plugin install` needed. Reload with `/reload-plugins`.

Note: plugin dependencies (Atlassian, Sourcegraph, etc.) will not auto-install via this method — you'll need to install them separately.

## Enable MCP servers (optional)

The plugin ships stubs for GitHub, Slack, Context7, and Desktop Commander. To activate one:

1. Find the plugin install directory: `/plugin list` → look for `tamirs-superpowers` path
2. Open `.mcp.json` in that directory
3. Set the required env vars (e.g. `GITHUB_PERSONAL_ACCESS_TOKEN`)
4. Restart Claude Code

Each server's required env vars are documented in `.mcp.json`.
