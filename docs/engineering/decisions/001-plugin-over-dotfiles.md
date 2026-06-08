# ADR 001 — Plugin over dotfiles for Claude config distribution

**Status:** Accepted

## Context

Claude Code configuration (skills, hooks, MCP servers, settings) can be distributed in two ways:

1. **Dotfiles** — checked into a personal dotfiles repo, symlinked to `~/.claude/`. Each machine requires a setup script to link files into place. Updates require git pulls and re-running setup.

2. **Plugin** — published to a Claude Code marketplace, installed via `/plugin install`. Claude Code handles installation, placement, and auto-update at startup.

The goal was to have a single install command that brings the full Claude Code environment to a new machine, stays current automatically, and pulls in third-party plugins as declared dependencies.

## Decision

Distribute as a Claude Code plugin hosted on a personal GitHub marketplace.

## Consequences

**Easier:**
- Single install command: `/plugin marketplace add Tamircohen28/tamirs-superpowers` + `/plugin install tamirs-superpowers`
- Auto-update at Claude Code startup — no manual `git pull` needed
- Third-party plugins (Atlassian, Sourcegraph, Warp, etc.) auto-install as declared dependencies
- Skills, hooks, and MCP stubs are all co-located in one versioned bundle
- `marketplace.json` + `allowCrossMarketplaceDependenciesOn` removes the need to manually register third-party marketplaces before install

**Harder:**
- User-level settings (`permissions`, `env`, `theme`, `worktree`) cannot be bundled — the plugin system intentionally scopes these to the user, not the plugin. They must still be configured manually in `~/.claude/settings.json`.
- Iterating locally requires either symlinking or reloading the plugin, rather than editing files in-place.
