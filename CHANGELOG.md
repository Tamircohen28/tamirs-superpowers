# Changelog

All notable changes to `tamirs-superpowers` are recorded here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

## [1.8.1] - 2026-07-21

### Fixed
- **`pr-dev` `cleanup-after-merge.sh`** is now worktree-aware. Run from inside a linked pr-dev worktree it no longer hard-fails on `git checkout master` when master is checked out in the main worktree (`fatal: 'master' is already used by worktree`); it skips the checkout, never removes or deletes the worktree/branch it is standing in, and reports what it skipped. Also made the `--help` comment-stripping `sed` portable on macOS/BSD (was using GNU-only `\?`).

## [1.8.0] - 2026-07-21

### Changed
- **`cleanup` skill** is now model-invocable (`disable-model-invocation: false`) so it can be orchestrated by sub-agents and Workflows (fan-out one cleanup per repo). Gating a skill also blocks sub-agent/Workflow invocation; safety now lives inside the skill (confirmation gates + dry-run) rather than in the flag.
- **`retro` skill** is now model-invocable so it can catch rough sessions the user forgot to review. Safe because retro only *proposes* changes and never writes without approval; added a timing guardrail so it offers (not derails) mid-task and proactively suggests itself at session end.

### Added
- **`skills/repo/cleanup/scripts/cleanup.sh`** — non-interactive, provably-safe subset of the cleanup sweep for headless fan-out. Only touches merged branches, stale-clean worktrees, git-ignored build dirs, and does a fast-forward-only sync; dry-run unless `--yes`. Never touches dirty/unpushed/unmerged work.

### Docs
- Documented the invocation-tier policy and the "gating also blocks orchestration" warning in `CLAUDE.md` and `rules/dev/skill-quality-standards.md`; corrected the standards table to reflect that user-workflow skills (plan-dev, start-dev, pr-dev) ship `disable-model-invocation: false`.

## [1.7.0] - 2026-07-20

### Added
- **`decision` skill** (`dev-workflow`) — summarizes a pending decision or GitHub issue/PR in plain language and hands it back as an `AskUserQuestion` menu; walks through multiple open decisions/action items one at a time

## [1.6.2] - 2026-07-15

### Fixed
- **PreToolUse hooks (Cursor)** — Cursor fail-closes when hook stdout is empty or non-JSON; Claude Code treated empty stdout as allow. Added `hooks/lib/hook-output.sh` with dual Claude/Cursor JSON helpers and wired them into `protect-other-branches`, `enforce-worktree-edits`, `guard-sensitive-files`, and `skill-creator-guard` so allow/deny always emit valid JSON.
- **`hooks/hooks.json` matchers** — also match Cursor tool names `Shell` and `StrReplace` alongside Claude `Bash` / `Edit|Write`.

## [1.6.1] - 2026-07-09

### Fixed
- **`ip-scan.sh`** — `scan-allowlist.txt` filters doc-only false positives (policy prohibitions, MCP placeholder tokens); fix `set -e` exit when last match is allowlisted
- **`AGENTS.md`** — skill count aligned to 24 (matches README and bundled skills tree)

### Added
- **`assets/social-preview.png`** — GitHub social preview image

<!-- remainder unchanged; see git history for full changelog prior to this truncation note -->
