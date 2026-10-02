# Changelog archive (2/3): 3.3.0 – 3.0.0

Continued from [CHANGELOG-archive-1.md](CHANGELOG-archive-1.md). Continues in [CHANGELOG-archive-3.md](CHANGELOG-archive-3.md).

---

## [3.3.0] — 2026-08-20

### Changed

- **The capability registry is now rooted at the platform, with runtime surfaces beneath
  it.** `core/capabilities/platforms.json` held six flat entries — `claude_code`,
  `claude_desktop`, `codex`, `cursor`, `gemini_cli`, `opencode` — and that shape asserted
  something it could not back: that Claude has two runtime surfaces worth distinguishing
  and that Codex, Cursor and OpenCode have one each. All three ship a second surface
  (Codex an IDE extension, Cursor a CLI, OpenCode a desktop client). The single row for
  each was really its **CLI's** row, and nothing on the page said so. The registry now
  keys on the platform (`claude`, `codex`, `cursor`, `gemini`, `opencode`), each carrying
  a `surfaces` map: five platforms, ten surfaces, six of them supported. Every measured
  capability block moved under the surface it was measured on, byte for byte — no status,
  note, fallback or validation command changed value.
- **Nothing gained or lost support.** The six supported surfaces are the same six targets
  as before, with the same install guides, version pins and commands. `platform-targets.json`
  is still keyed by surface id and its `supported_targets` list is unchanged.
- **Consumers read a flattened per-surface view.** Validation runs against a surface, never
  against a vendor, so `scripts/lib/registry.sh` flattens the registry back to
  one-entry-per-surface and the checkers read that. The two contract scripts that ship into
  scaffolded repos vendor the same filter inline, since those repos have no `scripts/lib/`.
  Both forms still read a `schema_version: 1` registry unchanged, so a scaffolded repo that
  has not been reshaped keeps passing.

### Added

- **`support: "unverified"` — a surface named, with nothing claimed about it.** The four
  newly-named surfaces (Codex IDE extension, Cursor CLI, Gemini Code Assist, OpenCode
  desktop app) carry an `unverified_reason` and **no capabilities block at all**, and the
  schema now rejects one that carries capabilities or an install. Nineteen `unknown` rows
  would read as nineteen statements someone checked and came up empty; no block says the
  only true thing — nobody measured it. They are listed so "does this work in the Cursor
  CLI?" gets an honest *not measured* rather than silence, and they are never targets: no
  install guide, no badge, no capability row, never counted in "N supported targets".
- **`platform` on each entry in `platform-targets.json`**, naming the platform the registry
  files that surface under, asserted against the registry by `check-platform-targets.sh` so
  the copy cannot drift.
- **New registry invariants** in `check-capability-registry.sh`: every surface declares a
  support level, unverified surfaces carry a reason and claim nothing, every platform's
  `primary_surface` exists and is one this repo validates, and ids and aliases stay
  collision-free across **both** levels. That last one immediately caught the alias
  `cursor-cli` still resolving to the *IDE* surface — a CLI question answered with IDE
  measurements.

### Documentation

- README, `AGENTS.md`, `CLAUDE.md` and `docs/user/install/README.md` present platforms
  first and surfaces underneath, each surface with its own kind, support status and install
  path. `docs/user/platform-differences.md` keys its capability matrix to the six supported
  surfaces only and lists the four unverified ones in a section that claims nothing in
  either direction. `capability-model.md` and `adding-a-platform.md` document the two-level
  shape and distinguish adding a platform from adding a surface to an existing one.
## [3.2.0] — 2026-08-19

## [3.1.0] — 2026-08-19

### Two behaviour changes to read before upgrading

- **`apply` will switch off plugins that are currently enabled.** `platforms/claude/settings.d/plugins.json` records 23 plugins, **8 true / 15 false**, and the `false` entries are a deliberate record of plugins that were turned off — not missing data. On a machine where those 15 are on, the first `setup apply` turns them off. That is the intent: the previous canonical set was 21 all-true and would have silently re-enabled plugins the user had switched off on purpose. The installer says so itself before writing, with the exact count — `enabledPlugins  modify  WILL DISABLE 15 currently-enabled plugin(s)` — in `plan`, in `--dry-run`, and above the confirmation prompt. Plugins the repo says nothing about are left exactly as they are.
- **`install.sh` no longer rewrites `~/.claude/settings.json` wholesale.** It merges. Every previous run destroyed third-party keys it did not know about; objects now recurse key by key, so `hooks`, `enabledPlugins`, `extraKnownMarketplaces` and `mcpServers` written by other tools survive. Arrays and scalars are still **asserted**, not unioned — see "arrays are asserted" below for why that is the safe choice rather than the aggressive one.

### Added
- **`scripts/setup.sh` — one writer for machine-level config, with three verbs.** `plan` detects targets and prints exactly what would change and never writes (the default when there is no terminal); `apply` shows a unified diff and asks `[y/N/a/q]`, **defaulting to No**, before each change; `remove` undoes what `apply` wrote, scoped to this installer's own markers and backups. Flags `--targets`, `--only`, `--yes`, `--dry-run`, `--json`, `--verbose`, each with an env twin for CI. Detection replaces selection — you are never asked which platforms you have. Idempotence is a **content comparison**, not a state file: each module builds the new file from the file you already have and skips when they are equal, so a second `apply` does nothing. Prompts are read from `/dev/tty`; **stdin is never read**, so the script is safe to call from a hook, and a run with no terminal and no `--yes` prints the plan and exits 0 rather than adopting silently. Guide: [docs/user/setup.md](docs/user/setup.md).
- **Machine-level setup for all five platforms, from one canonical source.** [`core/global-rules.md`](core/global-rules.md) is rendered into `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.gemini/GEMINI.md`, `~/.cursor/rules/tamirs-superpowers.mdc` and `~/.config/opencode/AGENTS.md`, plus a merged fragment in each platform's config file. Everything outside the `>>> tamirs-superpowers >>>` markers is yours and is preserved. Renderers live in `scripts/lib/setup-{claude,cursor,codex,gemini,opencode}.sh`; each is a pure renderer and the engine owns all comparing, diffing, backing up and writing. Guide: [docs/user/platform-setup.md](docs/user/platform-setup.md).
- **`platforms/claude/settings.d/` — the Claude machine config as reviewable repo data.** Seven JSON fragments now reproduce the intended Claude Code configuration exactly, where `install.sh` previously wrote roughly half of it: `permissions.allow` (50 entries), `permissions.ask` (39), `permissions.defaultMode`, `autoMode.soft_deny`, `skillOverrides`, `disableClaudeAiConnectors`, `disabledMcpjsonServers`, `extraKnownMarketplaces`, and the correct `model` (`opus[1m]`) and `effortLevel` (`medium`). No secret ever enters that directory. See [`platforms/claude/settings.d/README.md`](platforms/claude/settings.d/README.md) and [docs/engineering/architecture/claude-machine-config.md](docs/engineering/architecture/claude-machine-config.md).
- **`hooks/docker-guard.py`**, wired as `PreToolUse:Bash`. It enforces the docker approval policy and previously existed on exactly one machine and nowhere in the repo.
- **`scripts/capture-config.sh` — the reviewed inverse of setup.** `setup` renders repo → machine; `capture` proposes machine → repo. `detect` classifies every difference as `portable` / `machine-local` / `secret` / `third-party` / `unknown` and never writes; `review` asks per hunk and stages adopted ones into the **canonical source** (a Claude permission lands in `platforms/claude/settings.d/`, a rule lands in `core/global-rules.md`) so a value adopted once renders to all five platforms; `deliver` runs `make validate`, branches, and opens a PR — it never merges. Token-shaped values are refused outright, absolute home paths (`/Users/you/...`) are reclassified machine-local, and the repo's IP scan blocks any hunk it hits.
- **`skills/toolkit/capture-config/`** wraps that script so an agent can offer it at the right moment — right after helping you hand-edit a machine config file, or when `setup`/`doctor` reports the machine has drifted from the repo and the machine is the side that is right. Guide: [docs/user/capture.md](docs/user/capture.md).
- **`make setup`, `make setup-plan` and `make capture`.**
- **`hooks/skill-suggest.sh`** on `UserPromptSubmit`, one suggestion per skill per session, replacing `plugin-version-watch.sh`.

### Changed
- **Arrays are asserted, not unioned — deliberately.** Objects merge key by key (which is what keeps third-party wiring alive), but an array in a fragment is the *whole* intended value. Union looked safer and is not: under union the repo could never **retract** anything — delete an over-broad entry from `permissions.allow` and it would stay live forever, invisibly, on every machine that had ever applied it. Asserting also keeps each fragment an honest description of its own result, which is the property that makes `settings.d/` reviewable. Incremental "always allow" grants have a home upstream that setup never reads or writes: `~/.claude/settings.local.json`.
- **`install.sh`, `update.sh` and `uninstall.sh` are thin shims over `setup.sh`** — one writer, one set of rules. `make install` ≈ `setup.sh apply --yes --targets claude`; `make uninstall` ≈ `setup.sh remove --yes --targets claude`.
- **Repo-side documentation stops at the render boundary.** JSON has no comments, so the fragments explain themselves in top-level keys beginning with `_` (`_comment`, `_tally`). Those keys are stripped when the fragments are merged and never reach a user's config.
- **Skill descriptions rewritten for the skills nobody reached.** 15 of the 25 that shipped at the time were never invoked across 953 real sessions, and gating was not the cause. `session-report` and `notify-setup` opened with a compatibility disclaimer, so the first clause a matcher read was about file formats rather than the user's situation; `platform-sync` opened with the list of files it reads; `field-notebook-ui` and `dark-terminal-doc` competed with harness-level design skills on generic phrasings and lost, and are now narrowed to their distinctive aesthetic; `targeted-debug` now states its differentiator (a bounded search agent that reads only the frames in the trace) rather than describing debugging in general.
- **`disable-model-invocation` removed from `switch-dev` and the three internal companions.** The flag blocks **sub-agent and orchestration** invocation too — a sub-agent calling a skill *is* model invocation — which made `switch-dev` unreachable at the one moment it matters, a rate limit hit mid-objective. `user-invocable: false` still keeps the internal companions off the slash menu. The validator no longer requires the two flags to be set together; they gate different callers.
- Skill count is now **26** across 7 domains — 23 user-invocable, 3 internal companions (`changelog-review`, `docs-review`, `mcp-pagination`). Five were removed and `capture-config` was added. Counts in the README, user docs, and all four manifest descriptions were updated; `scripts/check-doc-claims.sh` derives the number from the tree and fails on drift.

### Not managed, on purpose
- **Codex hook entries.** `~/.codex/config.toml` stores a per-hook `trusted_hash`; any edit to hook content or path invalidates it, and re-trusting is a user action. The Codex renderer never reads or writes hook entries, and the block it appends contains comments only.
- **`permissions.deny`, provider, auth and cache keys** on every platform. In Cursor deny beats allow, so an installer able to widen it could lock you out of your own tool.
- **Third-party hook wiring.** `~/.cursor/hooks.json` is not touched by any module; the Gemini and OpenCode fragments assert one key each and leave `hooks`, `mcp` and `plugin` alone.

### Removed
- **The `--profile claude-strict` validation profile.** 3.0.0 retired the "all 16 official Claude fields on every skill" contract but kept a flag that re-enforced it. Nothing invoked it outside its own documentation, and a mode that reinstates the contract the refactor removed is not a safety net — it is a second, contradictory source of truth. `scripts/validate-skill-frontmatter.py` now has no `--profile` flag; the `claudeStrictRequired` `$defs` block is gone from `core/schemas/skill-frontmatter.json`; and `quick_validate.py` no longer forwards a profile. The three tiers (portable / tamirs / claude) are unchanged — Claude extension fields are still validated whenever a skill carries them.
- **`skills/creative/algorithmic-art/`.** Dropped from the shipped set.
- **`hooks/plugin-version-watch.sh`.** It had three independent defects, any one fatal: it emitted `systemMessage`, which renders in the user's UI but is never injected into the model's context, so the agent could not act on it (every working reminder hook here uses `additionalContext`); its 24-hour timestamp was written when the nudge fired rather than when the user acted, so one ignored banner bought a day of silence; and its cache was a single global file with no repo key, so a fire in any repo silenced every other repo. Replaced by `hooks/skill-suggest.sh`.
- **`skills/documentation/platform-sync-{claude,codex,cursor,opencode}/`.** They were pure deprecation shims that delegated back to `/platform-sync`, which already carries all five platforms' source data under `references/platforms/`. Nothing in the tree invoked them.

### Upgrade note

Nothing changes until you run it: installing or updating the plugin does not write machine config. When you do run `make setup` for the first time, expect three things. **One:** it detects the agent CLIs you have and plans changes for all of them — run `make setup-plan` first if you want the full list before anything is written. **Two:** it will report `WILL DISABLE 15 currently-enabled plugin(s)` if your machine has them on; that is intended, and the diff is shown before the prompt. **Three:** the first time a file is modified, the original is copied to a fixed name — `<file>.pre-tamirs-superpowers` — which is never overwritten and never rotated away, because `remove` restores from exactly that name. `bash scripts/setup.sh remove` strips the marker blocks and un-merges the values that are still what we wrote; a value you have since changed is yours and stays. `~/.claude/pushover.env` is never deleted by `remove` — those are your credentials.

## [3.0.0] — 2026-08-19

### Added
- **Portable orchestration framework — objective → one PR.** A user objective is now decomposed into tasks with disjoint write scopes, each ending at **commit + handoff** rather than at a pull request, merged onto a single `objective/<slug>` integration branch, reviewed as one combined diff, and delivered as **one** PR. State lives in plain files under `.dev-files/objectives/<id>/` (schemas in `core/workflow/`), so an objective resumes after a crash, a `/clear`, a new session — or under a different platform, because nothing in the state names a provider. Policy: `core/policies/delivery.md`.
- **`orchestrate-dev`, `worker-dev`, `deliver-dev`.** `orchestrate-dev` owns the objective (task graph, capability-gated dispatch, integration, combined-diff review, delivery); `worker-dev` executes exactly one task and is explicitly forbidden from opening a PR, enabling auto-merge, merging the base branch, or running the full repo suite; `deliver-dev` is the only place an objective's PR is created. **The sequential, no-subagent path is a first-class mode**, not a fallback footnote: same task graph, same handoffs, same integration, same single PR, only the concurrency is gone.
- **Capability registry.** `core/capabilities/platforms.json` records, per platform per capability, a status (`native` / `adapter` / `emulated` / `partial` / `unknown` / `unsupported`), a validation command where one exists, and a stated fallback everywhere else. Skills read it before promising concurrency; docs render from it; `scripts/check-capability-registry.sh` validates it. `unknown` means *this repo has not measured it* and is treated as unavailable — no capability is claimed without evidence.
- **Gemini CLI as a first-class target.** `gemini-extension.json`, a registry entry, `platform-targets.json` coverage, `tests/test-gemini-adapter.sh`, and an install guide. Installed as a git-URL extension (`gemini extensions install …`); `gemini extensions link .` for local development. Skills and agents reach Gemini through a **generated adapter**, not the canonical files: Gemini discovers skills exactly one level below a skills root (so the two-level canonical tree resolves to zero), and rejects Claude-shaped `agents/*.md` with `tools.0: Invalid tool name`. `scripts/build-gemini-extension.sh` emits a flat symlink mirror at `.gemini/skills/` and `.gemini/agents/*.md` using Gemini's own tool vocabulary, verified against the loader; `make gemini-extension-check` and `make check-gemini-adapter` fail on drift. `hooks` is recorded `unknown` — the outer schema shape is accepted but nobody verified whether Claude event names fire, and this adapter ships no hooks by design. No Node dependency was introduced.
- **Canonical roles and role-aware agents.** Ten roles in `core/roles/` (planner, orchestrator, implementer, test-engineer, reviewer, security-reviewer, performance-reviewer, debugger, integrator, research-agent); every `agents/*.md` declares a `role:`, and `scripts/validate-roles.sh` fails on drift. Four new agents: `orchestrator`, `implementer`, `integrator`, `spec-reviewer`.
- **Validation tiers 0–3.** Tier 0 edit-time, Tier 1 worker (targeted only), Tier 2 integration, Tier 3 delivery/CI. Every skill and script must declare the tier it invokes; a step with an unstated tier is a bug. Only commands that actually ran may be reported, and a skipped tier is reported as skipped with a reason.
- **Canonical version source.** `plugin-version.json` is now the single source of truth; the four manifests, the README badge, and `platform-targets.json` are declared *consumers*, verified by `scripts/check-version-truth.sh` and repaired by `--sync`. Hand-editing a consumer is no longer the workflow.
- **`scripts/doctor.sh`.** One command reporting the detected platform, version drift, present and missing tools, which optional features are consequently usable, and a remedy per gap. Non-interactive by design — every probe reads from `/dev/null`, so it can never block on stdin.
- **Documentation rebuild.** A short README; `docs/user/{getting-started,concepts,configuration,orchestration,skills,agents,platform-differences,troubleshooting}.md`; install guides for all six targets, each with install · verify · update · uninstall and an honest capability table; and engineering docs for the capability model, adapter contract, skill schema, orchestration state machine, branch/worktree model, validation tiers, adding a platform, and the testing matrix.
- **Orchestration simulations and platform contract tests.** `tests/orchestration/scenario-*.sh` exercise dependencies, conflicts, failures, resume, review retries, delivery, sequential-vs-parallel equivalence, and the invariant that **no worker opens a PR** — without invoking a model.

### Changed
- **Portable skill schema replaces the 16-field Claude requirement.** SKILL.md frontmatter is now three tiers: a required portable core (`name`, `description`), the `metadata.tamirs` framework block, and Claude-specific extensions validated **only when present**. Nothing regresses — skills keep every Claude field they already carry, and `--profile claude-strict` still enforces the old gate — but a new skill no longer has to declare fields it does not use to satisfy a non-Claude platform.
- **OpenCode modernized.** Native skill discovery via `opencode.json` `skills.paths` reading the canonical tree in place, with `.opencode/agent/` generated from `agents/` and drift enforced by `make opencode-agents-check`. Documented honestly: OpenCode has no `hooks.json`, its only lifecycle mechanism is the JS/TS plugin API, and this repo ships no plugin module by design.
- **Claude Desktop is documented as a runtime surface of the Claude adapter**, not a separate plugin format. No Desktop manifest exists or should be created; capabilities this repo has not exercised there are recorded as `unknown` rather than assumed.
- **Branch and worktree identity follows the objective, not the harness.** `objective/<slug>` + `worker/<slug>/NNN`, with worktrees under `.agent-worktrees/<objective>/<task-id>/`. Provider is `task.provider` metadata and never appears in a branch name, worktree path, or state directory. Legacy platform-shaped worktrees (`.claude/.worktrees/…` and friends) are still recognized, never orphaned, and migrated only opt-in, one at a time.
- **Auto-merge is a configurable preference, not an invariant**, and branch-update-before-merge is loose by default. Neither is ever forced against branch protection or a stated preference.

### Deprecated
- **`/start-dev` as an implementation→PR pipeline.** It remains a fully supported front door and behaves as before for a simple standalone task, but it is now a routing facade over `worker-dev` and `deliver-dev`. Reach for `/orchestrate-dev` for multi-part work.
- **Hand-editing manifest versions.** Use `plugin-version.json` plus `scripts/check-version-truth.sh --sync`.
- **Hand-editing generated adapters** (`.opencode/agent/`). Regenerate instead; drift fails CI.

### Migration — what existing users need to know

**Still works, unchanged:** every skill you invoke today, including `/start-dev`, `/plan-dev`, `/pr-dev`, `/switch-dev`, `/repo-standards`, and the rest. Existing worktrees in the old platform-shaped layout keep working and are never deleted or bulk-migrated. Existing SKILL.md files keep validating.

**What changed in behavior:**
- A worker no longer opens a pull request. If you dispatch tasks, expect **one** PR at the end of the objective rather than one per task.
- Multi-part requests route to `/orchestrate-dev`. It says so in one line and you can decline.
- Full validation no longer runs inside every task — Tier 1 in workers, Tier 2 once at integration, Tier 3 in CI.
- On platforms where parallel subagents are unverified (everything except Claude Code today), orchestration runs serialized or sequential and **says which mode and why**, instead of silently pretending to fan out.
- Skills report capability gaps out loud. Where you previously got a silent no-op — hooks under Cursor, session analytics off Claude Code — you now get an explicit "unsupported here, this is the fallback".

**What to do:** nothing is required. Run `bash scripts/doctor.sh .` once to see what your platform supports, and read [docs/user/orchestration.md](docs/user/orchestration.md) before your first multi-part objective.

### Changed
- **Cursor Origin + Builds default (2026-08-17).** Documented [Origin](https://cursor.com/docs/origin) (early-beta Cursor git forge; GitHub remains canonical for marketplace installs) and flipped Cloud Agent Builds language to **now default**. Cursor-only pin bump: `changelog_date` **2026-08-13 → 2026-08-17**; desktop **3.16.17** / feature **3.11** unchanged.
- **Cursor Grok 4.6 + Builds T-1 readiness (2026-08-16).** Install guide documents Grok 4.6 for long-running / visual sessions and a T-1 Builds checklist before the **2026-08-17** default. Cursor-only `features_adopted` tags added; pins stay **3.16.17** / feature **3.11** / **2026-08-13**.
- **Cursor desktop 3.16.17 + Builds skipped/staleness docs.** Desktop/`validated_against` pin **3.15.19 → 3.16.17** (stable 2026-08-14; no separate feature write-up). Install guide documents Builds Skipped recurring checks, **Staleness threshold** default **24h**, and `install`/`start`/`terminals`. Feature/date pins stay **3.11** / **2026-08-13**.
- **Cursor Builds Aug-17 readiness + CLI steer/`/goal`.** Install guide documents enable-Builds-now (default **2026-08-17**), team/environment secrets for Builds install, git-staleness threshold, CLI steer-while-running, and durable `/goal`. Cursor-only `features_adopted` gains the matching adoption tags; pins stay **3.16.17** / feature **3.11** / **2026-08-13**.
- **Cursor CLI Aug 11 (desktop 3.16.17) advancement.** Install guide documents CLI sticky skills (Option+Enter), skill discovery skipping hidden dirs, and that installed-plugin hooks now execute in the CLI once a Cursor-native hooks bundle ships. `cli_changelog_date: 2026-08-11` recorded in `.cursor-version`; cursor `features_adopted` gains `cli-plugin-hooks-docs-2026-08-11` + `cli-sticky-skills-docs-2026-08-11`.
- **Cursor changelog through 2026-08-13 (Cloud Agent Builds).** `.cursor-version` / cursor-only `platform-targets.json` fields keep desktop **3.16.17** + feature **3.11** and advance `changelog_date` to **2026-08-13**. Install guide documents Cloud Agent Builds (warm snapshots; install vs start).
- **Cursor desktop pin → 3.16.17.** `.cursor-version`, `platform-targets.json` (cursor target only), README badge, and install docs now track desktop **3.16.17** (2026-08-11 download line). Changelog feature coverage remains **3.11**; newest date-only entry remains **2026-08-03** (no newer feature write-up on cursor.com/changelog).
- **Cursor docs: `workspaceOpen` + Agent Plugins standard.** Install guide notes the app-lifecycle `workspaceOpen` hook (`pluginPaths` for workspace-specific plugins; desktop/CLI only) and that Cursor loads [Agent Plugins](https://agent-plugins.org) alongside `.cursor-plugin` Cursor Plugins.

### Fixed
- **Concurrency guard: a mention of a command is no longer treated as an invocation of it.** Target detection matched the **raw command string**, so `git push` / `gh issue comment` text sitting inside a quoted argument, a `-m` message or a heredoc body was parsed as a command being run: `git commit -m "fixed: git push -q origin feature-x resolved to main"` produced *four* phantom push destinations — one of them `main` — and was denied against a live claim. The same unanchored scan had no notion of where a command begins, so a real invocation hidden after a quoted argument or a `;` could equally be missed or mis-attributed. Detection is now **structure-aware**: `claim_shell_segments` / `claim_effective_segments` (`hooks/lib/agent-claim.sh`) tokenize the string the way a shell reads it — splitting only on separators outside quotes, dropping heredoc bodies, stripping leading `FOO=bar` assignments and wrappers (`sudo`, `env`, `timeout`, …) and descending into `sh -c '<string>'` — and only a segment whose **first word** is `git` (subcommand `push`) or `gh` is guarded at all. Quoted text is an argument and can never be a command. The loud-refusal posture is unchanged: an unresolvable *real* destination still yields `CONCURRENCY GUARD CANNOT RUN`. `tests/test-concurrency-guard.sh` grew 13 assertions covering both directions (a mention allowed with zero destinations; a real push after a quoted argument, after `;`, and inside `sh -c` still blocked; `gh` targets asserted against a planted claim so "not a command" and "a command on a free artifact" are distinguishable) — 22 → 35.
- **Concurrency guard: `git push` destinations are parsed, never guessed.** `hooks/protect-other-branches.sh` read the remote and refspec by argument *position*, so any leading flag (`git push -q origin feature-x`) shifted them, the parse came back empty, and the hook silently fell back to the current branch — blocking a push to an unclaimed feature branch while a claim on `main` was live, and (with multiple refspecs) waving through a push that *did* target the claimed branch. Replaced with a real parser (`claim_push_destinations` in `hooks/lib/agent-claim.sh`) that skips all flags including `--opt=value` and next-argument forms, handles `<branch>`, `HEAD:<branch>`, `<src>:<dst>`, `+<src>:<dst>`, `:<branch>`, `--delete`, and a bare `git push` (resolved via upstream, as git does), and claim-checks **every** destination. When the destination genuinely cannot be determined (`--all`, `--mirror`, no resolvable upstream) the guard now fails loud with `CONCURRENCY GUARD CANNOT RUN` instead of substituting a default branch. Covered end-to-end by `tests/test-concurrency-guard.sh`, wired into `make test-hooks` and the CI `Hook behavior tests` job.

### Changed
- **Platform target: Claude Code 2.1.233** (from 2.1.232). Docs-only bump — no shipped
  plugin content changed, so no version bump. The single-day 2.1.233 delta reviewed
  against the plugin surface: manifests, skills frontmatter, hooks, MCP stubs,
  statusline, and marketplace flow all remain valid; `claude plugin validate .`
  and the full `run-tamirs-superpowers` smoke test both re-run clean on a local
  Claude Code **2.1.233** install (34/34 SKILL.md files, 35/35 concurrency-guard
  assertions). No entry in this delta is adoptable as a repo capability — it is
  bug fixes plus enterprise/infra features this plugin doesn't touch. Reviewed
  with no plugin change needed: **`claude plugin validate` now checks
  `.claude/skills` directories** (this repo's plugin-root skill,
  `.claude/skills/run-tamirs-superpowers/`, was already covered by this
  repo's own `validate-skill-frontmatter.py`; it now also gets native
  coverage — confirmed passing, no doc change required); the Notification-hook
  fix for permission prompts in Claude Desktop/VS Code (this plugin's
  `Notification` hook, `hooks/notify.sh`, benefits automatically, no config
  change needed); the skill/command argument-substitution re-expansion fix and
  the bundled-skill-alias "Unknown command" fix (this plugin defines no skill
  aliases and its `argument-hint`/`arguments` fields are unaffected); GitLab
  merge-request URL support for `--worktree` (this plugin's family is
  GitHub-hosted); `forward_user_identity` apps-gateway spend attribution,
  optional Bash memory-cgroup support, and `CLAUDE_CODE_WEBFETCH_CACHE_TTL_MS`
  (none of `.mcp.json`, hooks, or skills configure a gateway, cgroups, or
  WebFetch caching); and the Todo/task-tracking tools deprecation on newer
  models (Opus 4.8+, Sonnet 5+) — no skill or agent in this repo instructs
  Claude to use `TodoWrite`/task-tracking tools, the six `agents/*.md`
  reviewers carry no `Task`-family tool anyway, and the 34 `SKILL.md` files
  pin an explicit `model:` (e.g. `claude-sonnet-4-6`) rather than the
  floating `sonnet`/`opus` alias the deprecation targets.
- **Platform target: Claude Code 2.1.232** (from 2.1.231). Docs-only bump — no shipped
  plugin content changed, so no version bump. The 2.1.232 delta reviewed against the
  plugin surface: manifests, skills frontmatter, hooks, MCP stubs, statusline, and
  marketplace flow all remain valid. Three entries are adopted into the docs:
  **`/plugin install plugin@marketplace` now refreshes the marketplace first**
  (2.1.232) — the install guide's Method A and troubleshooting's stale-plugin note
  now carry the version-scoped story (refresh-first on 2.1.232+, refresh-and-retry
  since 2.1.221, manual `marketplace update` before that); **marketplace
  settings aliases** (2.1.232) — `additionalMarketplaces` / `allowedMarketplaces`
  accepted as friendlier names for `extraKnownMarketplaces` /
  `strictKnownMarketplaces`. The `repo-standards` skill and the
  `plugin-version-bump` rule note the alias alongside the record-not-array trap
  (which applies identically under both spellings), keeping the old names as the
  compatible default; and **cross-session `SendMessage` refinements** (2.1.232) —
  `@`-mention-to-send, bare-name delivery without a confirm step, and unique
  same-machine session names are now documented in `cross-platform-workflow.md`'s
  Claude-Code-to-Claude-Code callout alongside the existing 2.1.224/2.1.225
  behavior. Also reviewed, host-side with no plugin change needed: the
  startup-race fix for concurrent `known_marketplaces.json` writes that could
  silently unregister a marketplace (removes a failure mode this plugin's install
  docs previously had no answer for), GitLab marketplace URLs and GitLab token
  redaction (this plugin's family is GitHub-hosted), subagent forking on by
  default (tracked separately as a Future opportunity — worth a pass over the
  fork-using skills' `background:` frontmatter), the nested-git-repo trust
  confirmation (worktree hooks guard *edits*, not trust, and are unaffected),
  and the `sandbox.ripgrep` project-settings restriction (this plugin sets no
  sandbox overrides).
- **Platform target: Claude Code 2.1.231** (from 2.1.228). Docs-only bump — no shipped
  plugin content changed, so no version bump. The 2.1.229 + 2.1.231 delta (no 2.1.230
  entry was published) reviewed against the plugin surface: manifests, skills
  frontmatter, hooks, MCP stubs, statusline, and marketplace flow all remain valid.
  One capability is adopted into the docs: **marketplace `command` sources (2.1.229)**
  — a local command prints the plugin directory, re-resolved each session and applied
  without a restart, with `mode: "link"` using the directory in place. This is now
  the documented, recommended local-dev install: `development-workflow.md` gains a
  command-source link-install walkthrough, `install/claude-code.md` gains **Method D**,
  and `versioning.md`'s "local dev, no release yet" row points to it ahead of the
  older cache-edit/symlink paths it effectively supersedes for 2.1.229+ users. Also
  reviewed, host-side with no plugin change needed: the 2.1.231 MCP OAuth
  redirect-URI fix and 2.1.229's `127.0.0.1` OAuth redirect change (the plugin's
  `.mcp.json` stubs are env-var/token-based, not OAuth), scheduled-tasks watcher and
  file-watcher-leak fixes, the `/commit-push-pr` auto-approval tightening for
  dangerous git flags (the dev-workflow skills here already treat force-push as
  guarded), sandbox IPv6-literal bracketing with fail-closed enforcement flagged by
  `/doctor`, and a series of terminal-rendering and crash fixes.
- **Platform target: Claude Code 2.1.228** (from 2.1.226). Docs-only bump — no shipped
  plugin content changed, so no version bump. The 2.1.227 + 2.1.228 delta reviewed
  against the plugin surface: manifests, skills frontmatter, hooks, MCP stubs,
  statusline, and marketplace flow are all untouched. Two entries matter to this
  plugin's own workflows and are now documented: **2.1.228 makes the
  symlinked-dev-checkout flow safe** — background plugin-cache cleanup no longer
  deletes a plugin's cache when its only version is a symlinked development
  checkout, which was a real hazard for the "symlink your dev clone" local-testing
  path (`versioning.md` and `development-workflow.md` now carry the version-scoped
  note); and **2.1.228 hardens skills synced from claude.ai** — synced skills can no
  longer shadow local commands or MCP prompts, so a claude.ai skill can no longer
  mask this plugin's commands or skills under the same name. Also reviewed, host-side
  with no plugin change needed: a Write-tool rule change (newer models may overwrite
  a file they haven't read this session, matching Edit's rules), cross-session
  messaging fixes (first-session inbox, inline sender/body display), and the 2.1.227
  slash-command menu polish this plugin's commands inherit.

## [2.0.1] — 2026-08-12

### Added
- **Cursor project hooks (3.11 cloud/conversation hooks).** `.cursor/hooks.json` + `.cursor/hooks/warn-contributor-policy.sh` soft-ask on force-push to `master`/`main` and on `self-hosted` runner edits when this repo is the workspace / Cloud Agent target. Not a full Claude→Cursor plugin hooks port.

### Changed
- **Platform target: Claude Code 2.1.226** (from 2.1.224). Docs-only bump — no shipped
  plugin content changed, so no version bump. The 2.1.225 + 2.1.226 delta reviewed
  against the plugin surface: 2.1.226 is fix-only ("bug fixes and reliability
  improvements") and 2.1.225 is fix-dominated with nothing touching the plugin's
  manifests, skills frontmatter, hooks, MCP stubs, statusline, or marketplace flow.
  One user-facing capability is worth documenting: `SendMessage` can now *start* a
  conversation with a Remote Control session on another machine by name (previously
  reply-only), and cross-session messages parked for headless sessions are no longer
  held silently — the cross-platform-workflow guide's Claude Code ↔ Claude Code note
  now covers both. Also relevant to users of this plugin's headless/cloud runbook:
  2.1.225 fixes a transient 401 that could replace a long-lived
  `CLAUDE_CODE_OAUTH_TOKEN` with a short-lived stored-login token, breaking headless
  sessions until restart.
- **Cursor coverage pin.** Root `.cursor-version` records CLI **3.14.7** plus changelog feature **3.11** / date **2026-08-03**. Cursor `features_adopted` notes Customize (3.9), Team MCP + org-group marketplace access (3.10), side chats, and optional Google Workspace plugins (2026-08-03).
- **Platform target: Codex 0.147.0** (from 0.146.0). `.codex-version` recorded, `platform-targets.json` and its mirror table re-validated, and `docs/user/install/codex.md` updated. Direct CLI validation remained at 0.146.0; 0.147.0 was reviewed against the official release delta. (No changelog entry was written at the time — reconstructed from commit 76654a1, PR #82.)

### Fixed
- **Worktree guard judged the session `cwd` instead of the file being edited.** `hooks/enforce-worktree-edits.sh` armed itself from wherever the session happened to be: an incidental `cd` into any git repo — reading a config file, inspecting a checkout — then blocked every subsequent edit, including edits to files outside that repo entirely, while editing a main checkout from an unrelated `cwd` slipped through unguarded. The repo is now derived from the edited file's own directory (walking up to the nearest existing ancestor, so a new file in a new subdirectory still resolves), falling back to `cwd` only when no file path is present. The Claude config dir (`$CLAUDE_CONFIG_DIR` or `~/.claude`) is exempt — it is version-controlled for backup, not a project checkout. Verified against an 8-case matrix. (No changelog entry was written at the time — reconstructed from commit 01c4308, PR #84, which is also the commit that bumped the manifests to 2.0.1.)
- **Cursor hooks docs corrected for third-party compatibility.** Install guide + `platform-equivalence.md` document Cursor's opt-in Claude settings hooks ([Third-party hooks](https://cursor.com/docs/reference/third-party-hooks.md)), distinguish project `.cursor/hooks.json` from plugin `hooks/hooks.json`, and note Inbox **multi-PR sessions** (2026-07-29).
- **Cursor docs: Claude hooks ≠ Cursor hooks.** `docs/user/install/cursor.md` and `platform-equivalence.md` now state that `hooks/hooks.json` is Claude-shaped and does not fire Cursor plugin/cloud hook events; worktree guards on Cursor stay rule/AGENTS-based until a Cursor-native hooks bundle lands.
- **Cursor Automations (3.8) working tip.** Install guide documents `/automate` GitHub triggers (Workflow run completed, PR review comment) and computer-use demos for plugin CI / review triage.
- **Install-flow text aligned with 2.1.221 immediate plugin activation.** The README
  install block and `scripts/install.sh` still told every user to run
  `/reload-plugins` after `/plugin install`; both now match the install guide and
  quick-start — reload is only needed on Claude Code older than 2.1.221, where
  plugins don't yet activate immediately when safe.
- **Removed a Cursor adoption commit that landed on the Claude Code nightly branch.**
  The rolling `claude-code-update` branch briefly carried the "Cursor 3.11
  (+2026-08-03)" doc adoption, duplicating the separate `cursor-update` nightly PR
  and putting cursor-scoped files in a Claude Code-scoped PR; it is reverted here and
  lives only in the cursor PR where it belongs.
