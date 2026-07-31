# Changelog

All notable changes to `tamirs-superpowers` are recorded here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

## [1.8.2] - 2026-08-01

### Fixed
- **Worktree hooks no longer mangle paths on long multi-line prompts.** `slugify_text` folds newlines/CR/tabs to spaces before its line-oriented `sed`/`cut` stages, so a multi-line first prompt can no longer produce a multi-line task slug (previously every prompt line was slugified independently, and the derived worktree path / branch name / session title carried literal newlines). All state readers (`enforce-worktree-edits.sh`, `capture-task-slug.sh`, `session-init.sh`, `worktree-create.sh`) also re-sanitize slugs on read and discard newline-poisoned paths, so session-state files written by older versions self-heal instead of re-mangling paths on resume.
- **`enforce-worktree-edits.sh` recognizes registered session worktrees instead of string-matching a rebuilt path.** Any registered git worktree under a `.claude/worktrees/` directory (both the `~/.claude/worktrees/<repo>/<slug>` layout and Claude Code's native `<repo>/.claude/worktrees/<name>` layout) on a `wt/*` or `claude/*` branch is now compliant. Previously a session working in its own registered worktree was denied Edit/Write whenever the rebuilt expected path didn't match — e.g. when the stored slug was mangled — and agents had to fall back to shell heredocs.
- README version badge synced to manifest `1.8.1`; `docs/CHANGELOG.md` updated with 1.8.0/1.8.1 entries.

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
