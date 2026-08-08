# Changelog

All notable changes to `tamirs-superpowers` are recorded here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Changed
- **Cursor docs: Claude hooks ≠ Cursor hooks.** `docs/user/install/cursor.md` and `platform-equivalence.md` now state that `hooks/hooks.json` is Claude-shaped and does not fire Cursor plugin/cloud hook events; worktree guards on Cursor stay rule/AGENTS-based until a Cursor-native hooks bundle lands.
- **Cursor coverage pin.** Root `.cursor-version` records CLI **3.14.7** plus changelog feature **3.11** / date **2026-08-03**. Cursor `features_adopted` notes Customize (3.9), Team MCP + org-group marketplace access (3.10), side chats, and optional Google Workspace plugins (2026-08-03).
- **Cursor Automations (3.8) working tip.** Install guide documents `/automate` GitHub triggers (Workflow run completed, PR review comment) and computer-use demos for plugin CI / review triage.

## [2.0.0] — 2026-08-07

### Changed
- **BREAKING — marketplace renamed `tamirs-plugins` → `tamirs-marketplace`** (repo `Tamircohen28/plugins` → `Tamircohen28/tamirs-marketplace`). The statusline and Pushover hooks glob the marketplace cache path, so both are repointed. Migrate with:

  ```
  /plugin marketplace remove tamirs-plugins
  /plugin marketplace add Tamircohen28/tamirs-marketplace
  /plugin install tamirs-superpowers@tamirs-marketplace
  ```

- **`install.sh` reproduces a machine instead of bootstrapping a baseline.** It previously wrote defaults and left a manual checklist, so a fresh machine ended up with **zero** plugins enabled. It now writes the canonical 21-plugin `enabledPlugins` set, all three marketplaces, and matching `model`/`effortLevel`/notification preferences. Local entries merge on top, so a deliberately-disabled plugin survives a re-run; pre-2.0.0 `@tamirs-plugins` selectors are migrated automatically.

### Added
- `claude-code-warp` marketplace to the bootstrapped set.
- **`templates/global-CLAUDE.md`** — global working agreements (npm discipline, `/doctor` verification, agent chunking, PR discipline, recovery rule, specialist-role routing) as a shareable template. `install.sh` writes it to `~/.claude/CLAUDE.md` **only when absent**; an existing file is never overwritten — the template carries `<PLACEHOLDER>` values you fill in per machine, so clobbering would discard your edits, and it lands as `CLAUDE.md.new` for a manual diff instead.

### Added
- **`skills/documentation/platform-sync-opencode/` — the fourth per-target sub-skill.** OpenCode was added to `supported_targets` in 1.12.0 but had no sub-skill, so `/platform-sync` analysed the other three, found nothing wrong with OpenCode because it never looked, and reported success. The gap read as "no improvements found" rather than "this target was never checked". The sub-skill carries its own `references/urls.md` and a hard constraint against recommending anything that assumes a marketplace, `hooks.json`, or a plugin-declared statusline — none of which OpenCode has.
- **`make check-marketplace-schema`** — guards `extraKnownMarketplaces` shape in real settings files *and* in the scaffold templates that generate them. Claude Code expects a record keyed by marketplace name; an array is dropped with **no error and no warning**, and a valid global `~/.claude/settings.json` masks the broken project-level file indefinitely. Also rejects the non-existent `sourceUrl` field and a missing `source.source`.
- **`make check-doc-claims`** — asserts prose matches the tree. Every "N skills" claim in any `*.md` and every "N bundled skills" in a plugin/marketplace manifest description must match the actual `SKILL.md` count, and every declared target must be named in README.md and AGENTS.md with an `install_doc` that exists. Both counts had drifted before, in separate releases, with nothing failing.
- **Per-target parity gate (V-01…V-05) in `repo-standards`.** A key in `supported_targets` now owes five artifacts — manifest, install doc, `platform-targets.json` entry, platform-sync sub-skill, and a prose mention. Missing any is P1: partial support is worse than none, because users install against it and the gaps surface as "the plugin is broken".

### Fixed
- **The scaffold template emitted an invalid marketplace declaration.** `legacy-scaffold-templates.md` wrote `extraKnownMarketplaces` as an array, so every repo scaffolded from it got a settings file Claude Code silently ignored. Now emits the record form, with the silent-drop behaviour and the `claude doctor` verification documented inline.
- **All four manifest descriptions advertised "26 bundled skills"** against an actual 27 — the same drift 1.12.0 fixed at 25→26. Now enforced by `check-doc-claims` rather than by remembering.
- **`check-platform-targets.sh` accepted a supported target with no sub-skill.** It validated `validated_against` and README badges but never checked that `/platform-sync` could actually audit the target. Now fails on a missing `skills/documentation/platform-sync-<target>/`, and on an unrecognised target key rather than skipping it silently.
- **`docs/engineering/architecture/overview.md` claimed "16 skills in 7 domains"** while the tree shipped 27, with a stale per-domain listing to match.

### Changed
- **`rules/dev/plugin-version-bump.md` rewritten for four targets.** It said "bump all three manifests" without explaining that `opencode.json` has no version field and shouldn't get one; had two steps numbered `3.`; claimed the alignment CI job fails on bump PRs when pull requests actually run `--manifests-only`; and — worst — told agents to **edit files directly under `~/.claude/plugins/cache/`**. That is the anti-pattern that cost real time this cycle: `autoUpdate` replaced the version directory mid-session and the `sort -rV | head -1` version glob moved to the newer unpatched copy, so a hand-applied patch vanished and the symptom looked like a bug in the feature. Now: symlink-only guidance, the two destruction mechanisms spelled out, a post-release step that diffs the `vX.Y.Z` tag against `origin/master` before announcing, and sync steps for marketplace declarations, install guides, skill counts, and `platform-targets.json`.

## [1.12.0] - 2026-08-03

### Added
- **OpenCode is now a supported target — four in total: Claude Code, Cursor, Codex, OpenCode.** Recorded in `platform-targets.json` (`schema_version` 2, new `supported_targets` array) with per-target `capabilities` and, for OpenCode, an explicit `capability_gaps` block. Every version floor now carries a `supported_min_source` explaining how it was set, because two of the old floors were guesses.
- **`.opencode/agent/` — 6 generated agent adapters**, built by `scripts/build-opencode-agents.sh` (`make opencode-agents`). OpenCode validates agent frontmatter strictly and refuses to start on a bad field: Claude's `tools: Read, Grep, Glob, Bash` comma string must be an object of tool→boolean, and `model: sonnet` needs a provider prefix. The translated output is committed so installing from a clone needs no build step; `make agent:check` now runs `--check` and fails on drift.
- **`opencode.json`** declaring `skills.paths`. Entries are per-domain, with the four `skills/repo/*` skills listed individually — pointing at `skills/repo` wholesale also loads the two gold-fixture skills under `skills/repo/_contract/fixtures/`.
- **`.claude-plugin/marketplace.json` — standalone Claude Code install now works.** The repo had a plugin manifest but no marketplace manifest, so `/plugin marketplace add Tamircohen28/tamirs-superpowers` failed with `Marketplace file not found`. Verified end to end: add → `install tamirs-superpowers@tamirs-superpowers` → 1.12.0 enabled.
- **`.agents/plugins/marketplace.json` is now committed.** This is the manifest Codex actually resolves — *not* `.codex-plugin/marketplace.json`. Without it in the repo, `codex plugin marketplace add` on a clone failed with `marketplace root does not contain a supported manifest`, so standalone Codex install was broken for everyone but the machine that had the file untracked locally. Verified against the pushed branch: `codex plugin marketplace add Tamircohen28/tamirs-superpowers@<ref>` → `installed, enabled 1.12.0`.
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
- **ADR 002 amended.** It claimed `marketplace.json` sits at the repo root and that the `v<version>` tag drives version resolution. Neither held: Claude Code reads `.claude-plugin/marketplace.json` (which did not exist), and the catalog pins `ref: master`, so installs follow the branch, not the tag. The ADR now records the marketplace manifest path per target.
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
