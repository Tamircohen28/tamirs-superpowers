# Changelog

All notable changes are recorded here and in [`../CHANGELOG.md`](../CHANGELOG.md) at the repository root.

## [Unreleased]

See root [CHANGELOG.md](../CHANGELOG.md#unreleased) for in-progress entries.

## [3.6.2] — 2026-09-08

`make assert-contract` now runs in CI against this repo itself — the one gate that scores the repo against its own standards contract had never blocked a merge, only the `scaffold-gold` fixture had. Also adds `reviewed_through` to `platform-targets.json` as a second, separate version claim, and judges the platform-targets co-change gate by whether a capability's claim actually changed rather than by whether the registry file's bytes did. See root [CHANGELOG.md](../CHANGELOG.md#362--2026-09-08).

## [3.6.1] — 2026-09-02

Fixes `tests/lib/harness.sh` leaking a temp directory on every call: `harness_tmpdir` appended to an array, but every caller invoked it via command substitution — a subshell — so the append was discarded on return and the exit-trap cleanup ran against an empty list. The registry moved to a file, which survives a subshell. See root [CHANGELOG.md](../CHANGELOG.md#361--2026-09-02).

## [3.6.0] — 2026-09-02

Statusline gains a `spend` line when a Claude apps gateway reports `rate_limits.spend_limit`, rendered only when the payload actually carries it — the same only-when-present pattern as the existing 7-day line. See root [CHANGELOG.md](../CHANGELOG.md#360--2026-09-02).

## [3.5.0] — 2026-09-01

Fixes the protected-file guard being blind to `Bash`: it matched editing *tools*, not file *paths*, so lockfiles, `.github/workflows/`, `.yarn/releases/`, generated shadcn UI, and gitignored build output stayed writable through `cat > f <<EOF`, `sed -i`, `tee`, `cp`, or a shell redirect. See root [CHANGELOG.md](../CHANGELOG.md#350--2026-09-01).

## [3.4.0] — 2026-08-31

Adds `goal-condition-lint.sh`, refusing to arm a `/goal` condition that cannot terminate. Claude Code's `/goal` evaluator re-judges its condition from scratch every turn with no memory of having already blocked, so an unsatisfiable condition doesn't fail once — it blocks every turn until the harness block cap trips or the user clears it. Has happened twice. See root [CHANGELOG.md](../CHANGELOG.md#340--2026-08-31).

## [3.3.0] — 2026-08-20

The capability registry is rebuilt platform-first: `core/capabilities/platforms.json` moves from six flat entries to platforms with their runtime surfaces nested beneath them, so a surface's own capability gaps are no longer flattened onto the whole platform. See root [CHANGELOG.md](../CHANGELOG.md#330--2026-08-20).

## [3.2.0] — 2026-08-19

Version bump only; the root file carries no entry for this release. See root [CHANGELOG.md](../CHANGELOG.md#320--2026-08-19).

## [3.1.0] — 2026-08-19

Two behavior changes worth reading before upgrading: `setup apply` now switches off any currently-enabled plugin the repo's canonical set records as `false` (warning with the exact count first), and `install.sh` merges `~/.claude/settings.json` object-by-object instead of overwriting it wholesale, so third-party keys — other tools' `hooks`, `enabledPlugins`, `mcpServers` — survive. See root [CHANGELOG.md](../CHANGELOG.md#310--2026-08-19).

## [3.0.0] — 2026-08-19

BREAKING — portable orchestration framework: a user objective decomposes into tasks with disjoint write scopes, each ending at commit + handoff rather than a pull request, integrated onto one branch and delivered as a single PR. Adds `orchestrate-dev`/`worker-dev`/`deliver-dev`, the capability registry (`core/capabilities/platforms.json`), Gemini CLI as a first-class target, ten canonical roles, and validation tiers 0–3. See root [CHANGELOG.md](../CHANGELOG.md#300--2026-08-19).

## [2.0.1] — 2026-08-12

Worktree guard anchored to the file being edited rather than the session `cwd` (an incidental `cd` no longer arms it for every later edit, and the Claude config dir is exempt). Platform targets advanced to Claude Code 2.1.226 and Codex 0.147.0; Cursor coverage pinned with project hooks and corrected hooks documentation. See root [CHANGELOG.md](../CHANGELOG.md#201--2026-08-12).

## [2.0.0] — 2026-08-07

BREAKING — the marketplace was renamed `tamirs-plugins` → `tamirs-marketplace`, and `install.sh` became a full mirror install. See root [CHANGELOG.md](../CHANGELOG.md#200--2026-08-07).

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

Contributor version-bump rule, troubleshooting for stale plugin cache, and manifest/tag alignment CI. The root [CHANGELOG.md](../CHANGELOG.md) no longer carries a section this far back — its history starts at 1.6.1.

## [1.5.1] - 2026-06-28

See root [CHANGELOG.md](../CHANGELOG.md) for full release history.
