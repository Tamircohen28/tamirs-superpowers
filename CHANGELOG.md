# Changelog

All notable changes to `tamir-library` are recorded here.

## [0.6.0] - 2026-05-25

### Added
- Four new auto-installed dependencies:
  - `data` (from `knowledge-work-plugins`) — datasets/SQL/visualizations.
  - `enterprise-search` (from `knowledge-work-plugins`) — enterprise
    knowledge search via Claude Cowork.
  - `productivity` (from `knowledge-work-plugins`) — productivity toolkit.
  - `superpowers` (from `superpowers-dev` / `obra/superpowers`) — Jesse
    Vincent's skills framework.

### Required marketplaces
- `anthropics/knowledge-work-plugins` and `obra/superpowers` must each be
  registered once on a fresh machine via `/plugin marketplace add`. See
  README for the exact commands.

## [0.5.0] - 2026-05-25

### Added
- Three new auto-installed dependencies:
  - `sourcegraph` (from `claude-plugins-official`) — code search & navigation.
  - `atlassian` (from `claude-plugins-official`) — Jira + Confluence access.
  - `warp` (from `claude-code-warp` marketplace) — Warp terminal integration.
    Requires `/plugin marketplace add warpdotdev/claude-code-warp` once.

### Not added (intentionally)
- `data` — Astronomer's Airflow plugin exists in the official marketplace but
  was confirmed not to be the intended target.
- `enterprise-search` and `productivity` — no plugin by those names exists in
  the Anthropic-official or Wix marketplaces. `productivity` is a *category*
  (39 plugins), not a single dependency.

## [0.4.0] - 2026-05-25

### Added
- Vendored Tamir's global hooks under `hooks/` (with `hooks/hooks.json` wiring
  them via `${CLAUDE_PLUGIN_ROOT}`):
  - `protect-other-branches.sh` (PreToolUse / Bash) — blocks closing PRs from
    other authors.
  - `enforce-worktree-edits.sh` (PreToolUse / Edit|Write|MultiEdit|NotebookEdit)
    — refuses repo edits outside the dedicated worktree.
  - `show-changelog.sh` + `session-init.sh` (SessionStart) — display the
    Claude Code changelog on update and seed per-session state.
  - `capture-task-slug.sh` (UserPromptSubmit) — derive task slug from first
    prompt, create global worktree, expose `$CLAUDE_SESSION_FILES_DIR`.
  - `worktree-create.sh` / `worktree-remove.sh` (WorktreeCreate /
    WorktreeRemove) — manage global worktrees under `~/.claude/worktrees/`.
  - `validate-report-links.sh` (PostToolUse / Write) — sanity-check URLs in
    written reports.
  - Inline Notification osascript hook (mac-only) preserved.
  - Shared `hooks/lib/worktree-common.sh`.
- Vendored `statusline.sh` and wired it via `statusLine` in `plugin.json`.

### Note
- Other parts of `~/.claude/settings.json` (env, permissions, enabledPlugins,
  extraKnownMarketplaces, theme, worktree config, etc.) are user-level
  settings and were intentionally **not** bundled. A private API secret
  in the original settings.json was excluded.

## [0.3.0] - 2026-05-25

### Removed
- Dropped the `production-master` dependency (and the prerequisite
  `/plugin marketplace add production-master` step).
  Only `skill-creator` and `session-report` (both from the official
  `claude-plugins-official` marketplace) remain as auto-installed dependencies.

### Fixed
- Removed invalid `Task(agent-name)` matcher syntax from `allowed-tools` in
  `query-app-logs`, `query-bi`, `query-request` skills (now plain `Task`).
- Added missing `name:` field to `run-bazel-tests`, `strict-tdd-scala`,
  `proto-docs`, `query-captains-log`, `query-fire-console`, `query-prod-db`.
- Aligned `name:` with directory name for `user-find-skill` and
  `user-dark-terminal-doc`.
- Removed non-standard frontmatter fields (`user-invocable`, `when_to_use`,
  `model`) from `user-find-skill`.
- Updated `babysit-pr` description from Codex to Claude.

### Changed
- Pruned `.mcp.json` to four real, installable MCP servers
  (`github`, `context7`, `slack`, `desktop-commander`). Removed stubs for
  non-existent npm packages (`@anthropic/excalidraw-mcp`,
  `@anthropic/powerpoint-mcp`) and the not-officially-published
  Gmail / Google Drive / Google Calendar servers.
- Dropped the non-schema `_comment` key from `.mcp.json`.

### Added
- `LICENSE` file (proprietary / all rights reserved).
- `CHANGELOG.md`.
- `.gitignore` covering `.DS_Store` and common noise.

## [0.2.1] - prior

Initial public version of the personal library plugin.
