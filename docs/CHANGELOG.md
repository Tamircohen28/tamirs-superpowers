# Changelog

All notable changes are recorded here and in [`../CHANGELOG.md`](../CHANGELOG.md) at the repository root.

## [Unreleased]

See root [CHANGELOG.md](../CHANGELOG.md#unreleased) for in-progress entries.

## [1.12.0] - 2026-08-03

OpenCode joins Claude Code, Cursor, and Codex as a supported target — four in total — and the plugin now installs standalone from this repo on every one of them. Adds per-target install guides under [`user/install/`](user/install/README.md), generated OpenCode agent adapters, and a committed `.agents/plugins/marketplace.json` (the manifest Codex actually resolves) that unbroke standalone Codex install. Also refreshes badly stale Cursor and Codex version floors and removes long-standing false claims about auto-installed plugin dependencies. See root [CHANGELOG.md](../CHANGELOG.md#1120---2026-08-03).

## [1.11.0] - 2026-08-03

The statusline now ends line 1 with a dim Claude Code version (`v2.1.220`), read from the `version` field already present on the statusline stdin payload. Makes it visible which CLI build a session is running — including when a plugin auto-update lands mid-session. See root [CHANGELOG.md](../CHANGELOG.md#1110---2026-08-03).

## [1.10.0] - 2026-08-02

Claude Code 2.1.214–2.1.220 adoption: new `DirectoryAdded` hook warns when `/add-dir` registers a main checkout, forked sessions reload session-files again, `targeted-debug` stays inline, and `plugin-reload-reminder` no longer nags on SKILL.md edits. Also fixes the master-CI manifest/tag alignment race. See root [CHANGELOG.md](../CHANGELOG.md#1100---2026-08-02).

## [1.9.0] - 2026-08-02

Opt-in Pushover phone notifications (`scripts/notify-pushover.sh`), the `notify-setup` skill, and Markdown-to-plain-text snippet flattening. See root [CHANGELOG.md](../CHANGELOG.md#190---2026-08-02).

## [1.8.2] - 2026-08-01

Worktree-hook fixes: multi-line prompts no longer mangle task slugs/paths, and `enforce-worktree-edits.sh` accepts any registered `.claude/worktrees` session worktree. See root [CHANGELOG.md](../CHANGELOG.md#182---2026-08-01).

## [1.8.1] - 2026-07-21

`pr-dev` `cleanup-after-merge.sh` worktree-aware fix. See root [CHANGELOG.md](../CHANGELOG.md#181---2026-07-21).

## [1.8.0] - 2026-07-21

`cleanup` and `retro` model-invocable; headless `cleanup.sh` script. See root [CHANGELOG.md](../CHANGELOG.md#180---2026-07-21).

## [1.7.0] - 2026-07-20

New `decision` skill (`dev-workflow`). See root [CHANGELOG.md](../CHANGELOG.md#170---2026-07-20).

## [1.5.2] - 2026-07-07

Contributor version-bump rule, troubleshooting for stale plugin cache, and manifest/tag alignment CI. See root [CHANGELOG.md](../CHANGELOG.md#152---2026-07-07).

## [1.5.1] - 2026-06-28

See root [CHANGELOG.md](../CHANGELOG.md) for full release history.
