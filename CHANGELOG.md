# Changelog

All notable changes to `tamirs-superpowers` are recorded here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

## [1.6.0] - 2026-07-09

### Added
- **Feature equivalence contract (E-layer)** — `feature-equivalence.json`, `check-feature-equivalence.sh`, and auto-scored gaps for skill bridges, multi-manifest parity, MCP/hooks mapping across Claude Code, Cursor, and Codex
- **Platform target versions (V-layer)** — `docs/engineering/build-and-release/platform-targets.json` records validated platform tool versions; README Row 3 badges show platform versions (not plugin semver)
- **`check-platform-targets.sh`** — offline badge sync, `--sync` for Codex latest-known, `--require-co-change` CI gate when repo skills change
- **`scaffold-claude-plugin-gold`** fixture — flat claude-plugin contract test target
- **`docs/agent-guidelines/platform-equivalence.md`** — capability mapping and intentional asymmetry (Claude-only statusline, Cursor hook substitute)
- **`makefile-agent-targets.mk.tmpl`** — `make agent:check`, `make agent-polish-gate`, `make platform-targets-*` (agents run these; users use skills)

### Changed
- **`multi-agent-repo`** / **`repo-standards`** — phases 5–6 cover feature equivalence + platform target sync via `platform-sync`
- **`readme-badges.md`** — Row 3 uses `platform-targets.json` validated versions
- **`build.mjs` template** — generates `dist/codex/.codex/config.toml` for agent-kit repos
- **`scaffold-gold`** — `.agents/skills/` canonical bridge; platform-targets files
- **`.claude-plugin/plugin.json`** — adds `mcpServers` for cross-manifest MCP parity

### Fixed
- **`score-equivalence-gaps.sh`** — jq `// true` no longer masks boolean `false` from inventory JSON

## [1.5.2] - 2026-07-07

### Added
- **`check-manifest-version-alignment.sh`** — CI gate + `repo-standards` S10-05 check verifying `plugin.json` manifests match each other and the latest release tag (no unreleased manifest bumps sitting on `main`)
- **`rules/dev/plugin-version-bump.md`** — contributor rule: bump all plugin manifests after shipped changes so Claude Code marketplace users receive updates (version is the update cache key)
- **`.cursor/rules/plugin-version-bump.mdc`** — Cursor adapter for the version-bump rule

### Changed
- **`AGENTS.md`**, **`CLAUDE.md`**, **`docs/agent-guidelines/overview.md`**, **`docs/engineering/build-and-release/development-workflow.md`**, **`docs/engineering/build-and-release/versioning.md`**, **`.cursor/rules/plugin-structure.mdc`** — document version-bump requirement and post-release user refresh steps
- **`docs/user/troubleshooting.md`** — "already at latest version" and missing-skills troubleshooting
- **`.github/workflows/ci.yml`** — manifest/tag alignment uses `--manifests-only` on pull requests so release PRs can bump version before the tag exists

### Fixed
- **`release.yml`** — now bumps every present `plugin.json` manifest (`.claude-plugin`, `.cursor-plugin`, `.codex-plugin`) atomically instead of `.claude-plugin` only, which had let the other two manifests drift ahead of the last cut release

## [1.5.1] - 2026-07-02

### Added
- **`cleanup` skill** — full repo-cleanup sweep: prune merged/stale remote branches, drive open PRs to merge-ready in parallel, remove idle local worktrees (rescuing uncommitted work), wipe build/cache artifacts, and reset the local checkout to match remote (`--remote-only` / `--local-only` / `--dry-run`)
- **`switch-dev` skill** — `handoff`, `resume`, and `status` modes for cross-platform work via GitHub issue Resume blocks and `agent:*` labels
- **`skills/dev-workflow/_shared/scripts/`** — `detect-platform`, `resolve-worktree`, `parse-issue-resume`, `update-issue-resume`, `list-agent-worktrees`
- **`.github/ISSUE_TEMPLATE/agent_task.yml`** — agent-task template with Resume + Agent routing sections
- **`hooks/handoff-reminder.sh`** — SessionEnd reminder to run `/switch-dev handoff` from active worktrees
- **`rules/dev/cross-platform-handoff.md`** — contributor rule + Cursor adapter
- **`docs/user/cross-platform-workflow.md`** — user guide for Claude/Cursor/Codex handoff

### Changed
- **`plan-dev`** — issue bodies include Resume + Agent routing; `agent:any` label on create
- **`start-dev`** — platform-aware worktrees via `resolve-worktree.sh`; loads Resume before coding
- **`pr-dev`** — suggests handoff when blocked on human input; always enables auto-merge (`--auto --squash --delete-branch`); polls until GitHub merges
- **`repo-scaffold` vitest config** — generates `vitest.config.ts` with `passWithNoTests` for node repos so scaffolded CI passes before any tests exist
- **`repo-scaffold` / contract** — `enable-repo-merge-settings.sh` + `ensure-branch-protection.sh` (apply/verify master: 1 review + CI); `repo-standards` S4-04–S4-06 audit
- **`start-dev`** — enables auto-merge immediately after `gh pr create`
- **`scripts/install.sh`**, **`scripts/update.sh`**, **`scripts/uninstall.sh`** — moved from repo root; `Makefile` targets updated
- **`repo-standards` S6-05** — no `.sh` files at repo root; user-facing scripts belong in `scripts/`
- **`scripts/statusline.sh`** — moved from repo root; `plugin.json`, `install.sh`, and docs updated
- **`CODEOWNERS`** — single root file; removed duplicate `.github/CODEOWNERS`
- **`platform-sync`** — detects AI targets in any repo (CLAUDE.md, AGENTS.md, `.cursor/rules/`, manifests, etc.); not plugin-manifest-only
- **`repo-standards` contract v1.2** — Makefile `install`/`update`/`uninstall`, README badge rows, multi-target install docs, versioning policy (`S10-*`)
- **README** — multi-platform install (Claude Code, Cursor, Codex); badge rows; `make install` / `make update` / `make uninstall`
- **`Makefile`** — `install`, `update`, `uninstall` targets; `update.sh` / `uninstall.sh`
- **`rules/dev/`** — contributor rules now document Claude Code, Cursor, and Codex paths (worktrees, plugin manifests, hook loading); added Cursor `.mdc` adapters
- **`AGENTS.md`** — multi-platform install notes and `rules/dev/` index

### Removed
- **`EXTERNAL_REFERENCES.md`** — stale orphan doc (no in-repo links; `superpowers` is a declared dependency)

## [1.5.0] - 2026-06-26

### Added
- **6 specialist subagents** (`agents/`) — `architecture-reviewer`, `debugging-specialist`, `performance-reviewer`, `research-agent`, `security-reviewer`, `test-engineer`; bootstrapped into `~/.claude` by `install.sh` on a fresh plugin install
- **`/retro` command** (`commands/retro.md`) — session-retrospective slash command that captures lessons and proposes rule/hook/skill updates
- **8 environment hooks** — `goal-compact-reminder`, `guard-sensitive-files`, `skill-creator-guard`, `plugin-reload-reminder`, `check-done`, `validate-report-links`, `wix-ip-guard`, and opt-in `ensure-exit`; wired into new `PostToolUse`/`Stop` events and extended `PreToolUse`/`UserPromptSubmit` coverage in `hooks.json`
- **`install.sh`** — idempotent `settings.json` bootstrap that consolidates a complete `~/.claude` environment (agents, commands, hooks) from a fresh plugin install
- **`repo-standards` S1-05** — every repo must ship a hero banner (`assets/banner.svg` referenced in `README.md`); auto-scored as a P2 gap by the inventory and gap scripts
- **Conservative Dependabot defaults** — `dependabot.yml.tmpl` with grouped minor+patch updates, weekly/monthly schedules, no auto-major, and PR limits; `repo-scaffold` emits stack-aware ecosystem blocks (npm/pip/github-actions) plus an AGENTS.md "Dependency management" section
- **HOL Plugin Scanner CI job** — runs the `awesome-ai-plugins` listing scanner in CI (required by `hashgraph-online/awesome-ai-plugins`)

### Changed
- **Model auto-invocation enabled** — `disable-model-invocation: false` on all user-invocable skills (`plan-dev`, `start-dev`, `targeted-debug`, `repo-standards`, `multi-agent-repo`) so Claude can trigger them from context, not only explicit slash commands; internal-only skills unchanged
- **`session-files`** — renamed from `.session-files` (dropped the leading dot) so session artifacts (plans, reviews, investigations) are visible in file explorers; added to `.gitignore`
- **`enforce-worktree-edits`** — only denies edits to files inside the repo root, fixing false-positive blocks on `~/.claude/plans/` and similar paths
- **Multi-platform contributor rules** — `rules/dev/` and `pr-dev` aligned for Claude Code, Cursor, and Codex (platform worktree paths, Cursor `.mdc` adapters, remote branch deletion on merge, portable `SKILL_DIR` resolution)
- **`statusLine` command** — resolves via a `HOME` glob instead of `CLAUDE_PLUGIN_ROOT` so it works regardless of install path
- Plugin version bumped to **1.5.0**

## [1.4.0] - 2026-06-24

### Added
- **`field-notebook-ui` skill** — generates interactive React artifacts in the engineer's field-notebook visual design system (warm stone-paper palette, Space Grotesk / Inter / JetBrains Mono typography, canonical `Card`, `AirGap`, `CodeBlock`, `TabBtn` components). Triggers on "build a UI for", "create a dashboard", "field-notebook style", and similar prompts.

### Changed
- Plugin version bumped to **1.4.0**

## [1.3.0] - 2026-06-23

### Added
- **`repo-standards` skill** — merges legacy `repo-polish` + `repo-review` into one user-invocable skill with review/plan/polish modes, orchestrating `multi-agent-repo` plus internal `docs-review`/`changelog-review`; polish ends at a feature-branch PR without auto-publish
- **`multi-agent-repo` skill** — multi-platform agent setup consolidated into a review/plan/dev pipeline with deterministic inventory scripts (absorbs the former `plugin-compat` platform generation)
- **SKILL.md frontmatter CI gate** — `scripts/validate-skill-frontmatter.py` enforces all 16 official Claude Code frontmatter fields plus `metadata.updated-date` on every skill, wired into `make validate` and CI
- **Cursor + Codex plugin manifests** — `.cursor-plugin/plugin.json` and `.codex-plugin/plugin.json` (plus `AGENTS.md` and `.cursor/rules/*.mdc`) so the same skill bundle installs across Claude Code, Cursor, and Codex
- **`repo-scaffold --type plugin`** — scaffolds agent-kit distribution repos (canonical rules/skills, build/validate stubs, marketplace + plugin wrapper, `dist/` adapters)
- **`plugin-gold` contract profile** — `detect-contract-profile.sh`, `score-plugin-gaps.sh`, `scaffold-plugin-gold` fixture; CI runs both app-gold and plugin-gold in `make test-repo-contract`
- **`repo-standards` plugin awareness** — auto-detects contract profile; `references/plugin-review.md` for agent-kit manual review axes
- **multi-agent-repo Layer 9** — agent-kit distribution rubric + target layout in `target-layouts.md`
- **User docs** — README skill table, `docs/user/reference.md`, `docs/user/concepts.md`, and **`docs/user/agent-kit.md`** (full walkthrough); quick-start Step 6; troubleshooting agent-kit section

### Changed
- **16-skill quality pass via `skill-creator`** — added evals, strengthened trigger descriptions, and added scripts/references/templates across every skill that was missing them
- Renamed skill domain `meta` → `toolkit` (`find-skill`, `session-report`, `skill-creator`)
- Plugin version bumped to **1.3.0**

### Removed
- **`babysit-pr` skill** — removed; `pr-dev` restored as the PR lifecycle skill, reversing the 1.2.0 merge

### Fixed
- **Plugin scaffold CI** — template and gold fixture now include `package-lock.json` so generated workflows can run `npm ci`
- **Plugin build stub** — `build.mjs` concatenates all `canonical/rules/*.md` files into Codex/Cursor adapters (not just `core.md`)
- **Plugin-gold contract** — `PK1-14` requires `package-lock.json` so scaffolds fail the local gate before CI hits `npm ci` without a lockfile

## [1.2.0] - 2026-06-13

### Added
- **`babysit-pr`** — unified PR lifecycle skill (replaces `pr-dev`): Watch mode (monitor CI/reviews) and Drive mode (address threads, merge after approval)
- **`rules/dev/skill-quality-standards.md`** — tamirs-superpowers skill authoring standards aligned with Claude Code plugins reference
- **Internal skill invocation** — `repo-polish` → `repo-review` / `docs-review` / `changelog-review`; `mcp-builder` → `mcp-pagination`
- **Supporting assets** for `babysit-pr` (scripts, templates, references), `docs-review`, and `repo-review`
- **Per-worktree dev ports** — new worktrees get a deterministic `DEV_PORT` (hashed from the branch name) written to `.env.local`, so parallel worktrees no longer collide on the same dev-server port (`write_worktree_env_local`)
- **Automatic dependency install** — fresh worktrees install dependencies in the background, matching the project's package manager (`npm ci` / `yarn --immutable` / `pnpm --frozen-lockfile` / `poetry install`), skipped when `node_modules` is already present. Logs to `.session-files/worktree-setup.log` (`run_worktree_post_setup`)
- **Global `.worktreeinclude` defaults** — `copy_worktreeinclude_files` now reads `~/.claude/defaults/worktreeinclude` before the repo-level `.worktreeinclude`, so a default set of gitignored files copies into every worktree
- **Archive retention pruning** — `session-end.sh` now prunes archived session-files older than `WORKTREE_RETENTION_DAYS`, alongside the existing stale-worktree cleanup (`prune_session_files_archive`)

### Changed
- **15 skills** (down from 16): removed standalone `pr-dev`; merged into `babysit-pr`
- Skill frontmatter pass — `disable-model-invocation`, `effort: high`, internal `user-invocable: false` on companion skills
- README, `docs/user/reference.md`, and architecture docs synced to current skill layout
- PR template IP scan command updated to `skills/repo/repo-polish/ip-scan.sh`
- Plugin version bumped to **1.2.0**
- **`.worktreeinclude` is now gitignore-aware** — patterns copy only gitignored files and support trailing-slash directory patterns and globs (`copy_pattern_if_gitignored`)
- **Notifications include the task slug** — `notify.sh` prefixes the desktop notification with the session's task slug (`<slug>: …`) so you can tell which parallel session pinged you

### Removed
- **`pr-dev`** skill — superseded by `babysit-pr`

## [1.1.0] - 2026-06-13

### Fixed
- **Statusline now activates on install** — `statusLine` was declared as a top-level `plugin.json` field, which the plugin manifest schema does not define; Claude Code silently ignored it. Moved under the schema-supported `settings` object so it merges into user settings while the plugin is enabled.
- **Install Quick Start corrected** — removed broken `marketplace add Tamircohen28/tamirs-superpowers` instruction (the per-repo `marketplace.json` was removed in v1.0.8). Install via `tamirs-superpowers@tamirs-plugins` instead.
- Removed non-existent `/reload-plugins` command from docs.
- Fixed stale "wired in marketplace.json" dependency claim.

### Added
- Shell-based (`claude plugin …`) install path documented alongside in-Claude slash commands.
- Statusline troubleshooting note for manual fallback if settings-merge path doesn't activate it.
- `repo-polish` skill added to the skills table (was missing despite being bundled since v1.0.9).

## [1.0.7] - 2026-06-08

### Fixed
- **GitHub MCP zero-config** — replaced HTTP Bearer token approach (required manual `GITHUB_PERSONAL_ACCESS_TOKEN` setup) with `hooks/github-mcp.sh`, a wrapper script that auto-derives the token from `gh auth token`. No manual token setup needed — if `gh` is authenticated, GitHub MCP works. Tries the official `github-mcp-server` binary first (`brew install github/tap/github-mcp-server`), falls back to Docker (`ghcr.io/github/github-mcp-server`).

## [1.0.6] - 2026-06-08

### Fixed
- **GitHub MCP** — replaced broken `stdio` + `sh -c` + `npx` approach with the official HTTP-based server (`https://api.githubcopilot.com/mcp/`). Set `GITHUB_PERSONAL_ACCESS_TOKEN` in your environment to activate. No npx, no Docker, no `gh` CLI dependency in the MCP config.

## [1.0.5] - 2026-06-08

### Added
- **`skill-creator` bundled** (`skills/meta/skill-creator/`) — create, improve, and benchmark Claude Code skills, now shipped directly in this plugin
- **`session-report` bundled** (`skills/meta/session-report/`) — HTML token usage reports, now shipped directly in this plugin

### Removed
- **`skills/integrations/slack-cli`** — enterprise-specific, removed for public release
- **`skills/integrations/proto-docs`** — enterprise-specific, removed for public release
- **`skill-creator` and `session-report` from `dependencies`** — both were declared as external dependencies on `claude-plugins-official` plugins that have no `version` field, causing permanent `/doctor` failures; bundling them directly resolves this

## [1.0.2] - 2026-06-08

Full plugin spec compliance pass based on official Claude Code plugins guide.

### Fixed
- **`marketplace.json` location** — was at repo root; moved to `.claude-plugin/marketplace.json`. This was the root cause of `claude plugin marketplace add` failing — Claude Code looks for `.claude-plugin/marketplace.json`, not a root-level file.
- **Skill namespace** — all skill references in README, docs, and quick-start now use the correct `tamirs-superpowers:plan-dev` format instead of bare `/plan-dev`.

### Added
- **`plugin.json`** — `$schema`, `displayName`, `homepage`, `repository`, `defaultEnabled: true`
- **`.claude-plugin/marketplace.json`** — `$schema`, `description`, `displayName`, `category`, `tags`, `homepage`, `repository` on the plugin entry
- **Dynamic context injection** (`!`cmd`` blocks) in `pr-dev`, `start-dev`, `task-audit`, `targeted-debug` — live git/gh state is injected before Claude reads the skill, enabling more accurate responses without waiting for tool calls
- **`context: fork`** on `targeted-debug` — runs in an isolated subagent context (Explore-style), keeping the main conversation clean
- **`SessionEnd` hook** (`hooks/session-end.sh`) — archives session files to persistent store and prunes stale worktrees on session close
- **CI job** — `claude plugin validate` step added; passes `✔ Validation passed`
- **Makefile** — `plugin-validate` target now recommended as primary validator

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
- **`marketplace.json`** at repo root — repo now doubles as a Claude Code marketplace (`Tamircohen28/tamirs-superpowers`). Cross-marketplace dependencies (`claude-code-warp`, `knowledge-work-plugins`, `superpowers-dev`) are allowlisted so no manual `/plugin marketplace add` steps are required after install.
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
- **Author** updated throughout: `tamircohen2468@gmail.com` → `https://github.com/Tamircohen28`.

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
