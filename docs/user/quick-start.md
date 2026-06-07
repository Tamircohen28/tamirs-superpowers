# Quick Start

Install `tamir-library` and run your first skill in under 5 minutes.

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
/plugin install tamir-library
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
/changelog-review what hooks are available in Claude Code?
```

This fetches live Claude Code docs and answers from them — a good sanity check that the plugin loaded correctly.

For a dev workflow demo, try:

```
/plan-dev add a README to this repo
```

Claude will propose a phased plan and create GitHub issues after you approve.

## Enable MCP servers (optional)

The plugin ships stubs for GitHub, Slack, Context7, and Desktop Commander. To activate one:

1. Find the plugin install directory: `/plugin list` → look for `tamir-library` path
2. Open `.mcp.json` in that directory
3. Set the required env vars (e.g. `GITHUB_PERSONAL_ACCESS_TOKEN`)
4. Restart Claude Code

Each server's required env vars are documented in `.mcp.json`.
