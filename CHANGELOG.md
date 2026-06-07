# Changelog

All notable changes to `tamirs-superpowers` are recorded here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

## [1.0.1] - 2026-06-08

Comprehensive quality pass: latest Claude Code feature adoption, Wix IP cleanup, and documentation gaps filled.

### Added
- `effort: high` on `plan-dev`, `start-dev`, `pr-dev` — ensures full model capability for complex workflow skills
- `disallowed-tools` on `task-audit` (blocks Edit/MultiEdit/NotebookEdit — audit is read+report only) and `docs-review` (blocks Task/Agent/Workflow — sweep is local)
- `paths` frontmatter on `docs-review` — skill auto-activates when Markdown files are in context
- `when_to_use`, `argument-hint`, `metadata` added to all 15 skills (previously missing on 5: `babysit-pr`, `mcp-builder`, `mcp-pagination`, `algorithmic-art`, `dark-terminal-doc`)
- `notify.sh` hook — replaces inline `osascript` in hooks.json; uses `terminalSequence` output field (v2.1.141+) with osascript fallback
- `docs/engineering/statusline.md` — full engineering doc for the statusline: input schema, output format, color coding, helper functions, branch hyperlinking
- `docs/user/quick-start.md` — documents `.claude/skills/` auto-load as marketplace-free install alternative
- Makefile `plugin-validate` target and orphan-script check; CI orphan-script step added
- `${CLAUDE_SKILL_DIR}` variable used in `targeted-debug` SKILL.md for portable script references

### Fixed
- `protect-other-branches.sh` — removed hardcoded `TamirCohen-Wix` GitHub handle and internal colleague names; hook now reads `GITHUB_OWNER_LOGIN` env var or falls back to `gh api user`
- `session-init.sh` — now emits `sessionTitle` in `hookSpecificOutput` (new field, improves session labeling in Claude Code UI)
- `algorithmic-art/SKILL.md` — corrected `license: MIT` → `license: Apache-2.0` (the bundled `LICENSE.txt` is Apache 2.0)
- `slack-cli/SKILL.md` — removed 3 hardcoded `/Users/rango/` paths; generalized all install and log paths
- `proto-docs/SKILL.md` — full rewrite removing all Wix-specific content (tech writer guidelines, SPI annotations, internal Slack channels, Jira project, `dev.wix.com` URLs); now a generic gRPC/protobuf documentation skill
- `docs/user/README.md` — added link to `reference.md`
- `docs/engineering/README.md` — added links to `statusline.md` and `ci-workflow.md`
- Notification hook: removed empty `"matcher": ""` field; replaced inline osascript with `notify.sh` script

### Removed
- `hooks/init-output-dir.sh` — orphaned dead code (superseded by `session-init.sh`)

## [1.0.0] - 2026-06-07

First public release. Cleaned of all internal tooling references and scaffolded with full open-source infrastructure.

### Added
- **7 new general-purpose skills:**
  - `plan-dev` — plan work into phases and create GitHub issues
  - `start-dev` — create worktree, implement, validate, push, open PR
  - `pr-dev` — address review threads, fix CI, squash-merge, clean up
  - `docs-review` — audit and fix Markdown docs (5 axes)
  - `task-audit` — audit a completed branch for quality and PR readiness
  - `targeted-debug` — scope-bounded debug from stack trace (reads only named files)
  - `changelog-review` — fetch live Claude Code docs; answer questions, diff versions
- **`marketplace.json`** at repo root — repo now doubles as a Claude Code marketplace (`TamirCohen28/tamirs-superpowers`). Cross-marketplace dependencies (`claude-code-warp`, `knowledge-work-plugins`, `superpowers-dev`) are allowlisted so no manual `/plugin marketplace add` steps are required after install.
- Full documentation tree: `docs/user/` (concepts, quick-start, troubleshooting, skill reference) and `docs/engineering/` (architecture overview, dev workflow, CI workflow, 2 ADRs).
- `CLAUDE.md` — contributor guidance for Claude Code sessions.
- `Makefile` — `validate`, `lint`, `test` targets (shellcheck + JSON validation + SKILL.md frontmatter check).
- `.github/workflows/ci.yml` — 4-job CI: shellcheck, JSON validation, SKILL.md frontmatter, secret scan.
- `.github/workflows/release.yml` — manual version bump + tag + GitHub Release workflow.
- `.github/dependabot.yml` — weekly GitHub Actions dependency updates.
- `.github/pull_request_template.md`, issue templates (`bug_report.yml`, `feature_request.yml`), `CODEOWNERS`.
- `SECURITY.md` — responsible disclosure policy.
- `assets/banner.png` — 1280×640 banner image.

### Changed
- **LICENSE** replaced — was proprietary "all rights reserved"; now MIT.
- **Version** bumped to 1.0.0.
- **Skill renames:** `user-find-skill` → `find-skill`; `user-dark-terminal-doc` → `dark-terminal-doc`. Slash commands are now `/find-skill` and `/dark-terminal-doc`.
- **`babysit-pr`** — added missing `allowed-tools` frontmatter field.
- **`mcp-pagination`** — added missing `allowed-tools` frontmatter field.
- **`mcp-builder`**, **`algorithmic-art`** — fixed `license: Complete terms in LICENSE.txt` → `license: MIT` (file is `LICENSE`, not `LICENSE.txt`).
- **`.gitignore`** — added `.claude/worktrees/`, `.claude/outputs/`, `.claude/sessions/`.
- **`hooks/hooks.json`** — fixed trailing comma (was invalid JSON).
- **Author** updated throughout: `tamirc@wix.com` → `https://github.com/TamirCohen28`.

### Removed
- **11 Wix-internal skills** — all tools specific to internal infrastructure:
  - `skills/observability/` (entire directory, 8 skills): `query-app-logs`, `query-bi`, `query-captains-log`, `query-error-logs`, `query-fire-console`, `query-ft-conductions`, `query-prod-db`, `query-request`
  - `skills/dev-workflow/strict-tdd-scala` — "Loom Prime" internal framework
  - `skills/dev-workflow/fix-flaky-test` — Wix-specific Bazel examples
  - `skills/dev-workflow/run-bazel-tests` — Wix-specific package naming
- **`hooks/validate-report-links.sh`** — Wix-specific domain checks (`wix-analytics`, `app-analytics`); removed from `hooks/hooks.json` PostToolUse entry.

---

## [0.6.0] - 2026-05-25

### Added
- Four new auto-installed dependencies:
  - `data` (from `knowledge-work-plugins`) — datasets/SQL/visualizations.
  - `enterprise-search` (from `knowledge-work-plugins`) — enterprise knowledge search.
  - `productivity` (from `knowledge-work-plugins`) — productivity toolkit.
  - `superpowers` (from `superpowers-dev` / `obra/superpowers`) — Jesse Vincent's skills framework.

### Required marketplaces
- `anthropics/knowledge-work-plugins` and `obra/superpowers` must each be registered once on a fresh machine via `/plugin marketplace add`. See README for the exact commands.

## [0.5.0] - 2026-05-25

### Added
- Three new auto-installed dependencies:
  - `sourcegraph` (from `claude-plugins-official`) — code search & navigation.
  - `atlassian` (from `claude-plugins-official`) — Jira + Confluence access.
  - `warp` (from `claude-code-warp` marketplace) — Warp terminal integration.

## [0.4.0] - 2026-05-25

### Added
- Vendored global hooks under `hooks/` with `hooks/hooks.json` wiring:
  - `protect-other-branches.sh` — blocks closing PRs from other authors.
  - `enforce-worktree-edits.sh` — refuses repo edits outside the dedicated worktree.
  - `show-changelog.sh` + `session-init.sh` — display changelog on update; seed per-session state.
  - `capture-task-slug.sh` — derive task slug, create global worktree, expose `$CLAUDE_SESSION_FILES_DIR`.
  - `worktree-create.sh` / `worktree-remove.sh` — manage global worktrees.
  - `validate-report-links.sh` — sanity-check URLs in written reports *(removed in 1.0.0)*.
  - Inline Notification osascript hook (macOS).
  - Shared `hooks/lib/worktree-common.sh`.
- Vendored `statusline.sh` wired via `statusLine` in `plugin.json`.

## [0.3.0] - 2026-05-25

### Removed
- Dropped the `production-master` internal dependency.

### Fixed
- Removed invalid `Task(agent-name)` matcher syntax from `allowed-tools`.
- Added missing `name:` fields to several skills.
- Updated `babysit-pr` description from Codex to Claude.

### Changed
- Pruned `.mcp.json` to four real, installable MCP servers.

### Added
- `LICENSE` file.
- `CHANGELOG.md`.
- `.gitignore`.

## [0.2.1] - prior

Initial private version of the personal library plugin.
