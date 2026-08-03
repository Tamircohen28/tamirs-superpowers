# Changelog

All notable changes to `tamirs-superpowers` are recorded here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

## [1.12.0] - 2026-08-03

### Added
- **OpenCode is now a supported target — four in total: Claude Code, Cursor, Codex, OpenCode.** Recorded in `platform-targets.json` (`schema_version` 2, new `supported_targets` array) with per-target `capabilities` and, for OpenCode, an explicit `capability_gaps` block. Every version floor now carries a `supported_min_source` explaining how it was set, because two of the old floors were guesses.
- **`.opencode/agent/` — 6 generated agent adapters**, built by `scripts/build-opencode-agents.sh` (`make opencode-agents`). OpenCode validates agent frontmatter strictly and refuses to start on a bad field: Claude's `tools: Read, Grep, Glob, Bash` comma string must be an object of tool→boolean, and `model: sonnet` needs a provider prefix. The translated output is committed so installing from a clone needs no build step; `make agent:check` now runs `--check` and fails on drift.
- **`opencode.json`** declaring `skills.paths`. Entries are per-domain, with the four `skills/repo/*` skills listed individually — pointing at `skills/repo` wholesale also loads the two gold-fixture skills under `skills/repo/_contract/fixtures/`.
- **`.agents/plugins/marketplace.json` is now committed.** This is the manifest Codex actually resolves — *not* `.codex-plugin/marketplace.json`. Without it in the repo, `codex plugin marketplace add` on a clone failed with `marketplace root does not contain a supported manifest`, so standalone Codex install was broken for everyone but the machine that had the file untracked locally.
- **Per-target install guides** under `docs/user/install/` — one each for [Claude Code](docs/user/install/claude-code.md), [Cursor](docs/user/install/cursor.md), [Codex](docs/user/install/codex.md), and [OpenCode](docs/user/install/opencode.md), plus an [index](docs/user/install/README.md) with the version matrix and a component-coverage table. Each guide states what that target does *not* get.
- **`make opencode-agents` / `make opencode-agents-check`**, and `--sync` now refreshes `latest_known` for OpenCode and Claude Code from the npm registry (Cursor has no public version endpoint and stays manual).

### Fixed
- **Platform target versions were badly stale.** Cursor read `0.45.0` — a version that predates Cursor's plugin system entirely — and Codex read `0.40.0` against a current `0.146.0`. Both are now validated against locally installed CLIs (Cursor 3.14.7, Codex 0.146.0, Claude Code 2.1.220, OpenCode 1.18.11) rather than against changelogs. README badges updated to match.
- **All three plugin manifests advertised "25 bundled skills"** against an actual 26.
- **Removed false plugin-dependency claims** from `README.md`, `docs/user/quick-start.md`, and `docs/user/concepts.md`. `.claude-plugin/plugin.json` has no `dependencies` field, so nothing has ever auto-installed alongside this plugin; the quick start also claimed "9 declared dependencies". Companion plugins are now listed as a manual install.
- **`docs/user/quick-start.md` pointed at a different marketplace than the README.** Both paths (catalog and standalone) are now documented side by side, on every target.

### Changed
- `check-platform-targets.sh` and `inventory-agent-setup.sh` enforce the target list from the JSON's own `supported_targets` instead of a hardcoded `claude_code cursor codex`. Files without the field fall back to those three, so `schema_version` 1 repos — including the contract gold fixtures — keep passing unchanged.
- `docs/agent-guidelines/platform-equivalence.md` gains an OpenCode column throughout, plus an Agents section and an install/distribution matrix. The old "specialist agents not mirrored on Cursor/Codex" claim was wrong and is gone.

### Docs
- **OpenCode's published skill docs are wrong about nested discovery.** They state the loader "does not support nested subdirectories" and matches only `skills/*/SKILL.md`. Verified otherwise with `opencode debug skill` on both 1.16.2 and 1.18.11: the domain-nested `skills/<domain>/<name>/SKILL.md` layout is discovered as-is, symlinks are followed, and `skills.paths` accepts absolute, relative, and zero-level paths. OpenCode's own bundled `customize-opencode` skill confirms the loader scans `**/SKILL.md`. `supported_min` is set to 1.16.2 — the oldest version this was actually verified on, not a guess.

## [1.11.0] - 2026-08-03

### Added
- **Statusline shows the running Claude Code version.** Line 1 now ends with a dim `vX.Y.Z` after `ctx:` — useful for confirming which CLI build a session is on when behavior differs across versions, and for spotting that an auto-update landed mid-session. Read from the documented top-level `version` field already present on the statusline stdin payload, so it costs nothing extra (no `claude --version` subprocess on every repaint). Omitted entirely when the field is absent or `null`, matching how every other optional field in the script degrades.

## [1.10.0] - 2026-08-02

### Fixed
- **Master CI no longer reds on every version-bumping merge.** `Manifest/tag version alignment` compared the manifest to the latest release tag on push-to-master, but a bump merges *before* `release.yml` can tag it — the tag provably cannot exist yet. Observed on PR #72: the job read `v1.8.2` at `12:06:00`; `v1.9.0` published at `12:06:14`. The push event now passes `--allow-pending-release`, which reports "Release pending" as a `::warning::` instead of failing. Manifest *behind* the latest tag still fails under every flag — nothing legitimate moves a manifest backwards past a cut release, and that was the only drift the strict check could actually catch.
- **`check-manifest-version-alignment.sh --help` no longer prints `# ` on every line** on macOS. The comment-stripping `sed` used `\?`, a GNU extension BSD sed ignores — the same portability bug fixed in `pr-dev`'s `cleanup-after-merge.sh` in 1.8.1.
- **Forked sessions reload their session-files again.** Claude Code 2.1.214 changed SessionStart to report source `"fork"` for forked sessions (previously `"resume"`); `session-init.sh` now treats `fork` like `resume`, so a forked session inherits prior session-files context instead of starting cold.
- **`targeted-debug` stays inline.** Claude Code 2.1.218 runs `context: fork` skills in the background by default; added `background: false` so stack-trace root-cause findings keep landing in the current conversation. Frontmatter tooling (`validate-skill-frontmatter.py`, `normalize-skill-frontmatter.py`) now recognizes the official optional `background` field.

### Added
- **`DirectoryAdded` hook (Claude Code 2.1.219+).** When `/add-dir` registers a main checkout mid-session, `hooks/directory-added.sh` warns immediately that repo edits there will be denied by the worktree policy and points at the worktree flow — moving feedback from the first denied Edit to registration time. Advisory only; never blocks.

### Changed
- Error messages from the alignment check now name the direction of the drift (ahead vs behind) and, when ahead, print the exact `gh workflow run release.yml -f version=<v>` command to fix it.
- **`plugin-reload-reminder` no longer nags on SKILL.md edits.** Since Claude Code 2.1.216, skills and commands changed during a session are picked up without a restart; the reminder now fires only for manifests and hooks (`plugin.json`, `hooks.json`, `marketplace.json`, `.claude-plugin/`).

### Docs
- **Platform targets: validated against Claude Code 2.1.220** (was 2.0.0). Reviewed the 2.0.0 → 2.1.220 changelog for plugin-facing changes: hooks stay compatible (all hook commands already use `${CLAUDE_PLUGIN_ROOT}` exec-style paths, unaffected by the 2.1.207 `${user_config.*}` shell-form rejection); hook matchers use exact tool names, unaffected by the 2.1.195 hyphen exact-match fix; no reliance on removed features (`/agents` wizard, `TeamCreate`/`TeamDelete`). Updated `platform-targets.json`, the `platform-targets.md` mirror, and the README Claude Code badge. `supported_min` stays 2.0.0 — no newer-version APIs are required.

## [1.9.0] - 2026-08-02

### Added
- **Opt-in phone notifications via Pushover** (`scripts/notify-pushover.sh` + `scripts/pushover_format.py`). A second `Notification` hook that pushes to your phone, complementing the existing `hooks/notify.sh` macOS desktop banner rather than replacing it — both fire, so you get a banner at the machine and a push when away from it. Chosen over ntfy.sh because ntfy's iOS push can be deferred indefinitely under Low Power Mode, which is precisely when a long session most needs you. Entirely inert until configured: the script exits 0 silently with no credentials, so an un-set-up install never breaks the notification chain.
- **`notify-setup` skill** (`skills/toolkit/notify-setup`, skill #26) — guided setup that collects both Pushover credentials, validates them against `/1/users/validate.json` before writing anything, wires the hook, and sends a test. Also covers priority tuning, snippet privacy, troubleshooting, and disabling.
- **Markdown-to-plain-text conversion for notification snippets.** Transcript excerpts are flattened before sending (headings, tables, code fences, links, emphasis, list markers, box-drawing rules), because raw Markdown is unreadable in a phone notification and truncating it can leave an unterminated code fence. Stripping happens *before* the 300-char cut, so the budget is spent on prose rather than syntax.
- **[Phone notifications](docs/user/phone-notifications.md) user doc** covering setup, tuning, privacy, and a troubleshooting table.

### Changed
- `scripts/install.sh` gained opt-in Pushover wiring gated on `PUSHOVER_TOKEN` + `PUSHOVER_USER` (same pattern as the existing `ensure-exit.sh` block). Credentials are written to `~/.claude/pushover.env` at mode 600 — deliberately outside the version-pathed plugin cache, which is replaced wholesale on update. The hook is appended idempotently and preserves any other `Notification` hooks already in `settings.json`.
- `scripts/uninstall.sh` now unwires the Pushover hook while leaving other `Notification` hooks intact. It does **not** delete `~/.claude/pushover.env` — those are user secrets, and a reinstall should not require re-entering them.

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
