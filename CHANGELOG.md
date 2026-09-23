# Changelog

All notable changes to `tamirs-superpowers` are recorded here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

## [Unreleased]

### Added

- **Pushover credentials can come from the manifest's `userConfig` — #178's E5.**
  `.claude-plugin/plugin.json` now declares `pushover_token` and `pushover_user` with
  `"sensitive": true`, which the host prompts for once at enable time and stores in the
  **macOS Keychain** (falling back to `~/.claude/.credentials.json`), exporting them to hook
  processes as `CLAUDE_PLUGIN_OPTION_<KEY>`.

  That is a better route to the constraint `notify-pushover.sh` already documented — credentials
  must live outside the plugin directory, because the marketplace cache is replaced wholesale on
  every update — than the 600-mode dotfile written by `make install` from environment variables.

  **This is not the `variables` field declined on the Cursor issue**, and the difference matters:
  that one was declined partly because `gh auth token` can *derive* a GitHub token, making a
  prompt unnecessary. Pushover credentials have no such source — they must come from the user
  however this is built — so the standing "never prompt for a token paste" rule does not apply.

  Precedence is explicit and tested: an environment `PUSHOVER_TOKEN` still wins, `userConfig`
  beats the credentials file, and **the file alone still works untouched** — which is what keeps
  existing installs working and keeps notifications alive on the Codex CLI, which loads the same
  hook and never sets `CLAUDE_PLUGIN_OPTION_*`.

### Fixed

- **The credentials file could overwrite a higher-precedence value.** Sourcing
  `~/.claude/pushover.env` was unconditional once *either* value was missing, so a token supplied
  from the environment with no accompanying user was silently replaced by the file's token. That
  was reachable before `userConfig` existed and more reachable with a third source, and it failed
  invisibly — the notification simply went out under different credentials. Found by the
  precedence test written for E5, not by inspection.

### Fixed

- **The Cursor manifest now declares its rules path — #179's E3.** `.cursor-plugin/plugin.json`
  declared no `rules` field, and Cursor's automatic component discovery falls back to a default
  `rules/` folder. In this repo `rules/` is the **canonical markdown** (plus a `README.md`), not
  the 13 purpose-built `.mdc` files with Cursor frontmatter under `.cursor/rules/`.

  So the omission never meant "no rules shipped". It meant the wrong ones: canonical `.md` in
  place of the `.mdc` mirror, a README loaded as a rule, and the five rules that exist **only**
  as `.mdc` — `commit-conventions`, `hooks-guide`, `plugin-structure`, `skill-frontmatter`,
  `skills-guide` — never shipping at all. Both halves are silent, so `tests/test-static.sh` now
  asserts the declaration; the guard was verified to fail when the field is removed.

  Recorded alongside it, because it is the same defect class in the same manifest: a Cursor
  plugin's **`hooks`** component defaults to `hooks/hooks.json` and expects Cursor's camelCase
  event format. This repo's file at that path is Claude's PascalCase format, so discovery yields
  no usable events — a cheaper route for a Cursor hook bundle than the `settings.json` import
  path, with no `settings.json` involvement at all.
### Added

- **Pin a Gemini install to a release instead of the default branch — #181's E8.** Both
  `gemini extensions install` and `gemini skills install` track the default branch, so every
  reinstall picks up whatever has landed since. `--ref` takes any git ref, which is how you get
  a stable channel: `--ref v4.5.0`. Verified live on **0.60.0**, alongside the two related flags
  `--auto-update` and `--pre-release`.

  Documented with the interaction that actually bites: `--ref` and `--auto-update` pull in
  opposite directions — pin a tag and then enable auto-update and the pin is the thing that
  moves. This repo's tags follow `plugin-version.json`, so `--ref v<version>` matches the
  version the README badge shows.

- **Gemini headless mode recorded in the cross-platform workflow — #181's E7.** A handoff does
  not have to land in an interactive session: `gemini -p` runs non-interactively, with
  `-o text|json|stream-json` making the result parseable by a next step. Verified live on 0.60.0.

  The flag that matters for an unattended resume is `--approval-mode`: `plan` is read-only,
  `yolo` auto-approves every tool. That is the only thing standing between "read the handoff and
  report" and "act on it unsupervised", so it is documented as a deliberate choice rather than a
  default to inherit. Recorded as a capability note, not a recommendation to automate handoffs —
  nothing in this repo's pipeline assumes a headless receiver.

- **All 26 user-invocable skills are now OpenCode commands — #182's item 1.** OpenCode users
  reached this toolkit's skills through the narrowest door it has: `install/opencode.md` told
  them to "name the skill explicitly," so every skill was discoverable only by already knowing
  it existed. OpenCode has a real command surface — `/name`, listed in the TUI — and this repo
  was not using it.

  `scripts/build-opencode-commands.sh` generates `.opencode/commands/*.md` from
  `skills/*/*/SKILL.md`, following the same generate-and-commit pattern as the existing agent
  adapters, so a user installing from a clone still needs no build step.

  **Each command is a translation, not a copy.** An OpenCode command's body is a *prompt
  template*, not a skill; a SKILL.md body is instructions for an already-loaded skill. So each
  command is a thin launcher that names its skill and points at the canonical file — nothing is
  duplicated, and a command cannot drift from its skill in substance.

  **The TUI `description` is derived, never invented.** A canonical `description` is written for
  triggering: it opens "Use when …" and carries trigger phrases, up to 1536 characters of them.
  That is the right shape for auto-invocation and the wrong shape for a command palette, where
  the user has already typed the name. The derivation is mechanical — strip a leading
  "Use when ", cut at the first sentence boundary, cap at 200 characters — so no new prose is
  written for any skill.

  The three internal skills (`changelog-review`, `docs-review`, `mcp-pagination`, all
  `user-invocable: false`) deliberately get **no** command: they are reachable from a parent
  skill, not from the slash surface, and emitting commands for them would contradict the
  invocation tier on exactly the surface that tier is about.

  Wired as `make opencode-commands` / `make opencode-commands-check`, into `make agent:check`,
  and asserted in `tests/test-static.sh`. The drift check was verified to **fail** on a
  hand-edited command and on a stale command whose skill no longer exists — not only to pass
  when in sync.
- **`StopFailure` hook on the `rate_limit` matcher — #178's E2.** `switch-dev` writes the
  objective, task and handoff state that lets work resume on another platform, and it was
  invoked **zero times across 953 sessions**. The reason was never that nobody needed it: the
  moment you need a handoff is the moment you cannot ask for one, because the turn has already
  ended on an error.

  `hooks/rate-limit-handoff.sh` fires on exactly that moment. `rate_limit` is a documented
  `StopFailure` error-type matcher alongside `overloaded`, `authentication_failed`,
  `billing_error` and `server_error`, so this fires on rate-limit exhaustion specifically and
  stays silent for every other API failure — an auth error is not a handoff situation. It names
  what is actually at risk ("2 uncommitted file(s) on <branch>, objective '<id>'") rather than
  offering generic advice, and says nothing at all when nothing is in flight, because noise is
  how a hook earns its way into being ignored.

  It emits `systemMessage`, **not** `hookSpecificOutput.additionalContext`: the turn has already
  failed, so there is no model turn left to read injected context, and the person who needs the
  message is the user. That is the same reasoning `handoff-reminder.sh` records for `SessionEnd`.

- **`PreCompact` hook — #178's E7.** `hooks/precompact-snapshot.sh` writes the working state
  that compaction destroys and that is expensive to re-derive: branch, uncommitted files, open
  objective, recent commit subjects. Not a transcript — that already exists.

  It writes a **file** rather than returning context, deliberately. `hookSpecificOutput` is not
  documented for `PreCompact` (the decision-control model covers the tool events and the Stop
  family), and while `systemMessage` is universal the docs say plainly that some events discard
  it. A file survives compaction unconditionally and costs nothing to produce, so the hook does
  not depend on either channel; `systemMessage` is emitted on top, best-effort. Output goes to
  `.dev-files/compaction/latest.md`, which is already gitignored.

  Both hooks are advisory: they never block, always exit 0, and stay silent when there is
  nothing worth saying. `tests/test-rate-limit-handoff.sh` (12 assertions) and
  `tests/test-precompact-snapshot.sh` (13) cover the speaking, silent and degenerate-payload
  paths, and the two subtlest guards in the first — output channel, and staying silent — were
  verified by mutating the hook to break each one and confirming the assertions fail.
### Fixed

- **Four stale `claude-sonnet-4-6` pins, not the one #182 reported.** The issue named
  `scripts/build-opencode-agents.sh`'s alias map, whose `sonnet` entry fed all 10 generated
  OpenCode adapters. Grepping for the rest of the class found three more that PR #156's
  27-file sweep also missed: the live `.claude/skills/run-tamirs-superpowers/SKILL.md`,
  the `model:` example in `docs/engineering/architecture/skill-schema.md` — which was
  teaching the stale pin to anyone reading the schema — and the scaffold plugin template
  plus its six gold fixtures, so **every repo this toolkit scaffolds** was inheriting a dead
  model id.

  `sonnet` and `opus` now map to `anthropic/claude-sonnet-5` and `anthropic/claude-opus-5-5`,
  both re-confirmed present in the models.dev catalogue OpenCode resolves against rather than
  assumed. `haiku` is unchanged because Haiku 4.5 is still current, not because it was skipped.
  Everything outside the generator now uses the `sonnet` **alias**, which is what #156
  established and what does not age.

### Changed

- **Cursor install verification — #179's E0, the tracking issue's BLOCKING item, is resolved
  and its premise falsified.** E0 feared that Cursor sync materializes only "nested Markdown
  files", so the plugin's shell assets would not ship and skills depending on them would
  silently no-op, with no repo check able to catch it (the contract tests run against a local
  checkout, never an installed copy).

  A machine with Cursor 3.21.16 and an existing install of this plugin was available, so the
  materialized copy was inspected rather than reasoned about. **It is a git clone.** That is
  the whole answer: there is no file-type filter to get wrong. `git status` inside it reports
  zero modified or deleted tracked files — only an untracked `.cache-complete` marker Cursor
  writes — and its 451 tracked paths diff **identical** against `git ls-tree -r` of the source
  commit. 263 of 452 files are non-Markdown: 103 `.sh` of which 87 are executable, 14 `.py`,
  53 `.json`, plus `hooks/hooks.json` and all 25 hook scripts. An all-files mode comparison
  found **0** exec-bit mismatches. Cursor keeps a second, equally complete materialization
  under `plugins/marketplaces/`.

  Deliberately **not** claimed: this verifies asset *delivery* only. Skill invocation inside
  Cursor — palette listing, invoking one by name — remains unverified, so `validated_against`
  stays 3.21.13 rather than advancing to the 3.21.16 binary on the machine. The install copy
  examined is plugin 2.0.1, which the record states plainly.

  Recorded in `docs/user/install/cursor.md` as a "What an install actually materializes"
  section, since it is the difference between 29 working skills and 29 silent ones, and in the
  `cursor` row of `platform-targets.json`.
## [4.5.0] — 2026-09-23

### Added

- **Codex marketplace `interface` block** (#180 E3). `.codex-plugin/plugin.json` now carries the
  presentation metadata a Codex marketplace listing renders — `displayName`, `shortDescription`,
  `longDescription`, `developerName`, `category`, `capabilities`, `websiteURL`, `logo`,
  `brandColor`, and six `defaultPrompt` entries. Without it, the listing fell back to the bare
  `description` and showed no example prompts at all.

  **The schema was read off real plugins, not guessed.** Codex publishes no manifest reference for
  this block, so the shape was extracted from two bundled OpenAI plugins shipped with the CLI
  (`messages` and `latex`, under `~/.codex/.tmp/bundled-marketplaces/openai-bundled/`) and then
  confirmed by a full install round-trip on codex 0.156.0: the installed copy carries the block
  intact, all six `defaultPrompt` entries included.

- **`prompt_cache` statusline line** (#178 E8). When the host reports cache telemetry,
  `scripts/statusline.sh` renders a fourth line — `cache 91% warm, 2 misses` when hot,
  `cache 12% cold, 1 miss, 45000 tok to rebuild` when not — coloured green/amber/red by hit ratio.
  It follows the same only-when-present rule as the existing `spend` line: a host that reports no
  `prompt_cache` block prints nothing rather than a misleading `0%`, and the rebuild cost is shown
  only while the cache is cold, since a warm cache is not about to be rebuilt.

  `tests/test-statusline.sh` grows from 17 to 25 assertions covering the warm, cold and absent
  cases. The two subtlest guards — miss-count pluralisation and suppressing the rebuild cost while
  warm — were verified by mutating the renderer and confirming each one fails, rather than only by
  confirming they pass.

- **Marketplace entry metadata** (#178 E11, partial). The `.claude-plugin/marketplace.json` plugin
  entry grows from 3 keys to 11: `displayName`, `author`, `homepage`, `repository`, `license`,
  `category`, `keywords` and `tags`.

  Two documented fields are **deliberately omitted**. `version` would pin the entry and create a
  second cache key alongside the manifest's own — the manifest `version` is what Claude uses to
  decide an update is available, and duplicating it invites the two to drift. `relevance` takes
  effect only for marketplaces an administrator allowlists in managed settings, so it is inert for
  a public marketplace listing like this one.

### Notes

- **#179 E2 (`icon:`/`color:` on Cursor Custom-Mode skills) was investigated and not implemented.**
  Cursor's plugins reference documents exactly two frontmatter fields for a skill, `name` and
  `description`; neither `icon` nor `color` appears, and Custom Modes are not documented there at
  all. Setting them would have meant extending `core/schemas/skill-frontmatter.json` to legitimise
  fields no Cursor document supports, and shipping them to five other platforms that would carry
  them inertly. The finding, and what would unblock the item, are recorded on the issue.

## [4.4.0] — 2026-09-23

### Changed

- **Codex and Gemini CLI validated live, closing the last two rows of the `validated_against` gap**
  (#197). Both were installed and exercised rather than reviewed.

  **Codex 0.146.0 → 0.156.0.** Installed via `npm i -g @openai/codex`, then this repo installed into
  it through a **local** marketplace — nothing published involved: `codex plugin marketplace add .`
  resolved `.agents/plugins/marketplace.json`, and `codex plugin add` reported
  `installed, enabled 4.3.2`. The install copy was inspected rather than assumed: **1,633 files,
  1,264 non-Markdown, 144 executable `.sh`**. A Codex install therefore preserves this plugin's
  shell assets, its 10 agent definitions and `hooks/hooks.json` — not only its Markdown. That is
  the same question #179's **E0** raises as BLOCKING for Cursor, and which no repo check covers,
  because the contract tests run against the local checkout and never an installed copy.

  **Gemini CLI 0.55.1 → 0.60.0.** Upgraded via `npm i -g @google/gemini-cli`, closing a five-minor
  gap in which 0.57–0.60 hardened symlink resolution, extension-loader paths, workspace boundaries
  and env-var sanitization — the four mechanisms this adapter is built on. `gemini extensions
  validate .` passes, the `gemini skills` subcommand surface the install guide depends on is intact,
  and the generated flat mirror at `.gemini/skills/` holds 29 symlinks with **all 29 resolving and
  0 broken** — precisely what the symlink-resolution hardening could have broken.

  Both installs were removed afterwards, leaving the machine as found.

- **OpenCode validated live on v2.** `@opencode/cli` 2.0.14 (`opencode2`) was installed alongside the
  v1 binary — the package ships both `opencode` and `opencode2` for exactly that — and
  `validated_against` advances from `unknown` to **2.0.14**, `supported_min` to **2.0.0**.

  The claim is deliberately **scoped**. *Confirmed live:* `opencode2 debug config` lists this repo's
  own `opencode.json` **and** its `.opencode/` directory among resolved configuration sources, so v2
  accepts the flat-array `skills` form from a project config; and `opencode2 debug agents` loads
  **10 of 10** generated adapters, each carrying this repo's `GENERATED FILE — DO NOT EDIT` header,
  which distinguishes a real load from a stale global copy. *Not confirmed:* per-skill discovery.

### Fixed

- **The OpenCode install guide told users to run two commands that no longer exist.** v2 removed the
  `debug skill` subcommand and renamed `debug agent <name>` to `debug agents` (plural, no per-agent
  argument); its entire debug surface is `agents`, `config`, `paths`. The guide referenced
  `opencode debug skill` three times as the way to verify installation. Its verification section is
  now split by major, with the v2 commands and what their output should contain.

  This is also why skill discovery on v2 is recorded as unverified: there is no CLI equivalent to
  enumerate discovered skills, and the `/skill` API route requires a running server.

## [4.3.2] — 2026-09-23

### Changed

- **Claude Code platform-sync review advances through 2.1.280** (from 2.1.278, the last
  version reflected on master). The official changelog has no numbered 2.1.279 release, so
  this covers 2.1.280 only. **`validated_against` advances to 2.1.280 as well — the first
  live advance on this row since 2.1.274.** The automated job that opened the PR recorded this
  cycle as changelog-only because no live CLI existed in that environment; the branch that
  landed it had one. Evidence, all on the 2.1.280 build: `claude --version` reports 2.1.280,
  `claude plugin validate .` passes, `/skill-doctor` lists all 29 tamirs-superpowers skills,
  and `claude plugin eval . --case canary-can-write --ablation with-without` scores 1.00 in
  both arms — exercising plugin load, PreToolUse hook execution and Skill-tool invocation end
  to end. `reviewed_through` and `latest_known` also move to **2.1.280**, and the README
  badge/support row advance with `validated_against`.
  - **2.1.280** — fixed skills being wrongly trashed to `.trash/` on a `manifest.json` name
    collision, directly closing the data-loss shape of the name-collision risk the 2.1.275
    claude.ai-skill-sync note already flagged for this plugin's 29 `SKILL.md` names; fixed
    `installed_plugins.json` losing its recorded commit info after a GitHub-repo plugin
    update, relevant since this plugin installs exactly that way; added
    `CLAUDE_CODE_MAX_MCP_DESCRIPTION_LENGTH`, documented as an available knob for the
    `github` MCP server rather than a repo default; made Claude Opus 5.5 the default Opus
    model, reviewed and not applicable since every `agents/*.md` here pins `model: sonnet`.
    Everything else in the release (fullscreen-list mouse support, an OTel hook-output-size
    stat, an auto-mode retry-loop fix, a symlink write-path permission fix, several
    terminal-UI fixes, and a Code Review check-run notice improvement) is host-side or
    UI-only with nothing here to adopt.

  No breaking change in the 2.1.278→2.1.280 range affects this repo. Full narrative:
  `CLAUDE.md`'s Subagents, MCP and Marketplace cache sections, and `platform-targets.json`'s
  `verification_method`.

## [4.3.1] — 2026-09-23

### Changed

- **Codex reviewed through 0.156.0** (from 0.155.1), against the official `openai/codex` release
  notes for `rust-v0.156.0`. `validated_against` stays at 0.146.0 — no live `codex` CLI exists in
  this environment, so the advance is documentary. Nothing in the release breaks this repo's
  manifest, hooks or skills. Two entries matter downstream: **worktree support is now enabled by
  default**, which retires the premise of the backlog item that declined native Codex worktrees as
  experimental in 0.154.0 (#180 E2 needs re-evaluating rather than staying declined on staleness
  grounds), and `/usage` now reports "plugin and skill activity", adjacent to `usage-capture` and
  `session-report`.

All five platform targets are now current: the probe reports **0 drifted, 0 unreachable**.

## [4.3.0] — 2026-09-23

### Changed

- **OpenCode target rebased onto the v2 line.** OpenCode 2 ships under a **new npm scope**,
  `@opencode/cli` (2.0.14, published 2026-09-22); v1's `opencode-ai` is frozen at 1.18.32.
  `opencode.json` is converted to v2's config shape: `skills` is now a **flat array of strings**
  (`packages/schema/src/config.ts:84` — `Schema.String.pipe(Schema.Array)`), replacing v1's
  `skills: { paths: [...] }` object. **This is not a breaking change for v1 users:** verified on a
  live OpenCode **1.18.32**, which accepts the array and normalizes it to `{"paths": [...],
  "urls": []}`, and discovers this repo's skills from it. v1 already carries
  forward-compatible handling for the v2 shape. Config file names and search locations are
  unchanged; `SKILL.md` remains the skill format.
- **Target pins moved to v2 with an honest evidence level.** `reviewed_through`/`latest_known`
  advance to 2.0.14 on a documentary review of the v2 docs and the v2 source at tag `v2.0.14`.
  `validated_against` is set to **`"unknown"`** — no `opencode2` run has exercised these skills —
  rather than left at 1.18.11, which is a version of the other package lineage. `supported_min` is
  2.0.0, the major boundary rather than an evidenced floor. README badge and support row are
  downgraded to `⚠️ unverified` to match. Tracked in #200.

### Fixed

- **The nightly probe was blind to the OpenCode major.** It watched `registry.npmjs.org/opencode-ai`,
  which is frozen at 1.18.32, and so reported "no drift" for the entire v2 line. It now watches
  `@opencode/cli`. A probe that pins a package name cannot see a major that renames the package —
  the same class of blind spot as comparing the wrong field.

## [4.2.2] — 2026-09-22

### Changed

- **The probe no longer fetches Cursor's desktop build.** 4.2.1 stopped counting that build as
  drift but still called the download API on every nightly run and printed the result as
  informational. Since the build can never be acted on here — advancing `latest_known` without a
  readable changelog is exactly what V1-04 rejects — the call gated nothing. Cursor's block is now
  two lines mirroring `claude_code`, with no network call. The build baseline remains recorded in
  `platform-targets.json`'s `targets.cursor.latest_known` for anyone who needs it.

## [4.2.1] — 2026-09-22

### Fixed

- **The nightly probe no longer reports Cursor as drifted.** It compared Cursor's live desktop
  *build* (3.21.x, from the public download API) against `targets.cursor.latest_known`, but Cursor
  documents changes at *feature* granularity (`changelog_feature`, currently `3.11`) and publishes
  no per-build release notes. `latest_known` therefore could never honestly advance to match a
  build number — the contract's V1-04 rejects `reviewed_through < latest_known`, and no
  build-granularity changelog exists to review — so the probe emitted a permanent, un-closeable
  `DRIFT` line every night. Cursor is now reported the way `claude_code` already is: no automated
  upstream source, advance via changelog review. The live build is still printed for a human to
  judge but no longer counts toward `drift_count` or `unreachable_count`.
- **`--help` no longer truncates mid-sentence.** `usage()` printed a hardcoded line range
  (`sed -n '2,26p'`), so it silently cut off the moment the header comment grew. It now prints
  every leading comment line and stops at the first non-comment, which future header edits cannot
  break.

## [4.2.0] — 2026-09-22

### Fixed

- **`parse_skill_md` truncated multi-line quoted descriptions.** The reader gathered
  continuation lines only for YAML *block* scalars (`>`, `|`, `>-`, `|-`); a multi-line *quoted*
  scalar — equally valid YAML, and what several skills here use — ended at its first physical
  line. `run_eval.py` and `run_loop.py` score triggering against that string and then rewrite it,
  so those skills were being benchmarked and optimised against roughly 17% of their own
  description, with every trigger phrase past line one invisible: `targeted-debug` 92 of 568
  characters, `diagnose-refusal` 99 of 590, `changelog-review` 93 of 517, `docs-review` 96 of 297.
  The frontmatter is now parsed with `yaml.safe_load`, with the original line reader kept as a
  fallback where pyyaml is absent. Pre-existing, not introduced by the trim in this release —
  parsed lengths were identical before and after it. Found by automated review on #195.

### Changed

- **Skill descriptions trimmed 28%, trigger coverage up 10 points.** The `description` +
  `when_to_use` frontmatter across all 29 skills went from 26,686 to 19,092 characters — roughly
  6,600 to 4,700 tokens resident in the system prompt on *every* turn. Empirical ablation (four
  plugin variants against the same eval case) attributes ~82% of this plugin's token overhead to
  these fields, against ~9% for all 25 hooks combined, so this is where the cost actually lives.

  The cut applies the repo's own authoring contract rather than an arbitrary budget:
  `description` is specified as triggering conditions only — "describing skill output/workflow in
  the `description` frontmatter field" is listed under *What NOT to do* — and `when_to_use` as 3–5
  phrases that *add* to it rather than restate it. Most of what was removed was what-it-does prose
  that was never supposed to be in those fields.

  Triggering measurably improved: against each skill's own `evals/trigger-evals.json`,
  should-trigger coverage rose from 205/242 (84%) to 228/242 (94%). Every literal quoted trigger
  phrase was preserved verbatim, verified against `git show HEAD:` for all 29 files. Budget freed
  by deleting prose was spent re-earning vocabulary the eval queries needed but the old text did
  not carry — `pagination` was not independently matchable in `mcp-pagination` (3/6 → 6/6), and
  `land` was unreachable inside `ship/land/close` in `pr-dev` (6/10 → 9/10).

  Gating was considered and rejected. `user-invocable: false` does *not* remove a description from
  context; only `disable-model-invocation: true` does, and that flag blocks subagent and workflow
  orchestration — the mistake that cost `switch-dev` its purpose (0 invocations across 953
  sessions). Trimming is the lever that reduces cost without weakening triggering or breaking
  orchestration.

## [4.1.0] — 2026-09-22

### Fixed

- **`enforce-worktree-edits.sh` no longer dead-locks a session that cannot create a worktree.**
  When the session worktree is missing *and* cannot be recreated, the write is now allowed with a
  visible warning instead of denied — but only where the checkout is provably disposable (under a
  system temp root) or an operator sets `TAMIRS_ALLOW_DEGRADED_WRITES=1`. An ordinary
  `git worktree add` failure in a real checkout (branch already checked out elsewhere, stale session
  state, a permissions blip) still denies, so the guard's core protection is unchanged. Previously
  every write was refused with no reachable remedy, which made the plugin unusable anywhere
  `git worktree add` cannot run — an eval sandbox, a CI checkout, a container. Measured as
  Δ −1.00 on creating a one-word file. (#191)
- **`make validate` passes from inside a `wt/*` worktree.** `tests/test-hook-stdin.sh` clones the
  repo under test, and `git clone` checks out the source's current branch as a *local* branch; from
  a `wt/<slug>` worktree that tripped an absolute-absence assertion on a branch no hook created. The
  assertion now baselines the `wt/*` set after the clone and checks what appears. CI only runs from
  a plain checkout, so only contributors following the repo's own worktree policy hit it. (#192)

### Changed

- **`evals/` graders calibrated against real generated output for the first time.** `frontmatter-valid`
  now anchors to a complete frontmatter block (it previously matched a `name:` line anywhere in the
  file); `explains-mechanism` accepts any substantively correct account of description-driven skill
  selection rather than one phrasing. Cases write to `skills/<name>/` — `.claude/` is a protected
  path in the run sandbox and every write to it is denied.
- `evals/README.md` and `CLAUDE.md` record the calibrated results, the corrected usage figures, and
  the three operator footguns (`--allow-tools Write` is mandatory, use `--judge-model sonnet`, never
  point a case at `.claude/`).

## [4.0.0] — 2026-09-22

- **Cursor 3.11 (+2026-09-10 / desktop 3.21.13):** advance Cursor coverage through **Projects** (coordinator, shared context, subscriptions) and desktop **3.18.9 → 3.21.13**. Feature pin remains **3.11**. `make validate` expected green. Cursor-only.

- **Claude Code platform-sync review advances through 2.1.278** (from 2.1.274, the last
  version reflected on master), covering 2.1.275, 2.1.276, 2.1.277 and 2.1.278. No live
  `claude` CLI was available this cycle, so the advance is changelog-only, the same
  evidence basis the 2.1.263→2.1.273 reconciliation used. `reviewed_through` and
  `latest_known` advance to **2.1.278**; `validated_against` stays at **2.1.274** — the
  last version an actual live `claude` CLI run confirmed. An earlier draft of this entry
  claimed `validated_against` had advanced too; an automated review caught that it hadn't
  been earned, and it was reverted before merge.
  `.claude-code-version`, the README badge/table row, and `platform-targets.md`'s
  table/prose all advance to `2.1.278` for the Claude Code row only — Cursor, Codex,
  Gemini CLI and OpenCode rows are untouched, since those are owned by sibling
  automated tasks.
  - **2.1.275** — `/plugin install <plugin> --marketplace <source>` installs from a
    marketplace in one step, tracked as a Future opportunity against
    `docs/user/install/claude-code.md`'s existing two-step sequence rather than
    rewritten this cycle; skills/plugins enabled on a user's claude.ai account now sync
    into terminal sessions automatically, opt-out via `syncClaudeAiSkills: false` /
    `syncClaudeAiPlugins: false`, now documented in `CLAUDE.md`'s Marketplace cache
    section alongside a name-collision note; plugin/marketplace messages no longer leak
    a URL-embedded secret (host-side, not exposed here); `claude plugin marketplace
    update` no longer deletes the local cache on a failed fetch — directly relevant to
    this repo's own `/plugin marketplace update tamirs-marketplace` instruction.
  - **2.1.276** — no changelog entry relevant to this repo in the reviewed delta.
  - **2.1.277** — Claude Code now reads `AGENTS.md` instead of `CLAUDE.md` when a
    project has none; this repo's own root and everything `repo-scaffold`/
    `multi-agent-repo` generate always ship both files, so the fallback has nothing to
    engage on here, reviewed and recorded as not applicable rather than silently
    skipped. **Removed the deprecated `TaskOutput` tool** (breaking upstream) — every
    `agents/*.md` `tools:` line and every skill/hook/doc here was grepped for
    `TaskOutput`; zero references, so nothing here ever relied on it.
  - **2.1.278** — Auto mode for API/Enterprise/Bedrock/Vertex/Foundry/gateway users now
    defaults to a server-side classifier; reviewed and not applicable, same as every
    other Bedrock/Vertex/Foundry/gateway item in this repo's review history, since this
    repo targets direct Claude Code/Desktop sessions.

  No breaking change in the 2.1.275→2.1.278 range affects this repo. Full narrative:
  `CLAUDE.md`'s Subagents, Marketplace cache and Project instructions bullets, and
  `platform-targets.json`'s `verification_method`.

- **`platform-truth`: make platform claims checkable.** Added the `dynamic_workflows`
  capability key end-to-end (registry, schema enum, `capability-model.md` documentation,
  and a new `check-capability-registry.sh` cross-reference against `core/roles/*.md`'s
  backtick-quoted capability names — closes the "named-but-wrong key" case, not the
  "unnamed anywhere" case). Fixed three registry rows that had drifted from live behavior
  (`gemini.plugin_marketplace`, `gemini.parallel_subagents`, `opencode.parallel_subagents`)
  and the `opencode` vendor name (SST → Anomaly). Wired `gemini-extension-check` into
  `make validate`'s dependency chain — it was declared but never actually invoked, despite
  being documented as CI-enforced. Fixed a real `printf` bug in `handoff.sh` (missing `--`
  before a `-`-prefixed force-emit string) found by a worker legitimately hitting that
  path. Corrected stale skill/effort counts in `CLAUDE.md` (27 → 29).

- **`platform-currency`: a continuous platform-currency loop**, so the next audit doesn't
  require another full manual research pass. `scripts/probe-platform-versions.sh`
  live-checks upstream version endpoints for Cursor, Codex, Gemini CLI and OpenCode against
  the pinned baseline (Claude Code has no public version API, reported `n/a` by design); a
  new nightly `platform-currency.yml` workflow runs it and opens a GitHub issue on drift;
  `platform-sync` now consumes the probe's output to skip re-fetching sources for an
  already-current target and to scope fetches to the known delta range otherwise; every row
  in `core/capabilities/platforms.json` now carries a `last_verified` date enforced by a new
  90-day staleness SLA in `check-capability-registry.sh`. Corrected a stale, disproven
  comment in `check-platform-targets.sh` claiming Cursor has no public version endpoint.

## [3.9.1] — 2026-09-21

### Fixed

- `resolve-merge-policy.sh` derived `admin_bypass_available` purely from the caller's repo
  `viewerPermission` (ADMIN/MAINTAIN → true), never from the branch's actual ruleset
  `bypass_actors`. Correct by coincidence on repos where those two align, wrong wherever they
  don't — a caller with repo permission but no real bypass actor would get a false "yes, use
  `--admin`". Now resolves the ruleset(s) that apply to the base branch, fetches each one's
  `bypass_actors`, and only reports `true` when the caller's permission matches a
  `RepositoryRole` bypass with `bypass_mode: "always"` (falls back to classic protection's
  `enforce_admins` semantics when no rulesets apply).
- `cleanup.sh`'s `classify_worktree` — the "provably-safe" unattended path — checked only
  `git status --porcelain` before `git worktree remove --force`, so a worktree holding real
  content in a gitignored directory (invisible to `status` by design) could be force-removed
  by `cleanup.sh --yes` even after the interactive `cleanup` skill gained the same guard.
  Now checks `git ls-files --others --ignored --exclude-standard` too and keeps anything it
  finds.

Both found by an automated PR review on #185, which also caught that the PR's own two
`SKILL.md` corrections would not have reached installed sessions without this version bump.

## [3.9.0] — 2026-09-21

### Fixed — a core safety invariant enforced nothing on Codex

`hooks/enforce-worktree-edits.sh` silently permitted **every** edit on Codex, and nothing
reported that it didn't. The guard allowlisted five Claude tool names and fell through to
`*) hook_allow`; Codex's editing tool is `apply_patch`, which appeared nowhere in any of the
25 hook scripts. Codex selects the hook via Claude-compat matcher aliases
(`hook_names.rs:29-38` declares `matcher_aliases: ["Write","Edit"]`) but delivers the raw name
in the payload — so the hook fired, read `apply_patch`, matched nothing, and allowed the write.
The invariant that should have been portable — *block writes outside the worktree* — had been
encoded as *block five Claude tool names*.

`hooks/guard-sensitive-files.sh` failed alongside it for a different reason: `apply_patch`'s
`tool_input` is `{"command": <patch text>}`, so `write-targets.py` found no path key and
returned no targets.

### Added

- `hooks/lib/platform-tools.sh` — `normalize_tool_name` maps a platform's own tool name onto
  this repo's canonical vocabulary (`apply_patch` → `Edit`); unknown names pass through
  unchanged, so no mapping is invented without evidence.
- `tests/hooks/**` — 5 suites, 90 assertions: the `cwd` × `target` matrix across `apply_patch`
  and every canonical Claude tool, multi-target loop proof, the shell-heredoc bypass,
  tool-path/shell-path target agreement, a static check of `hooks.json`'s own matchers, and
  pinned assertions against the authoritative `codex-rs` marker constants.

### Changed

- `enforce-worktree-edits.sh` now judges **every** write target rather than only the first.
  `hook_allow`/`hook_deny` both `exit(0)`, so the previous single inline check could only rule
  on one target — a multi-file patch with one innocuous and one dangerous target was allowed on
  the strength of the first. Decision logic moved into `judge_target_dir()`, which returns a
  verdict and is applied per candidate.
- `write-targets.py` parses the `apply_patch` envelope (`Add`/`Update`/`Delete File`, and
  `Move to`, a rename destination that can otherwise be used to write to a guarded path), and
  closes a shell-heredoc bypass: `strip_heredocs()` discarded patch bodies before the parser
  saw them, so `apply_patch <<'PATCH' … PATCH` via the `Bash` matcher was invisible to the guard.
- `guard-sensitive-files.sh` resolves `repo_root` from the nearest *existing* ancestor, fixing a
  silent no-op when the target's directory did not exist yet.
- `skill-creator-guard.sh` gates its primary and fallback extraction under one shared tool-name
  check, removing a false positive on `Read`/`Grep`.
- `make test-hooks` sweeps `tests/` at depth 2 — the new suites were not being run.

### Fixed — false platform claims

- `docs/user/install/codex.md` claimed `hooks/hooks.json` "does not port" to Codex. It does:
  `.codex-plugin/plugin.json` points at this repo's own file and Codex consumes the same
  `HooksFile` type. Coverage is *partial* — `WorktreeCreate`, `WorktreeRemove`, `DirectoryAdded`
  and `Notification` have no Codex equivalent. The same table's `subagents` row (`native` →
  `unknown`) and MCP row (`.codex/config.toml` → the manifest `mcpServers` field) were also wrong.
- `core/capabilities/platforms.json` carried the identical false "not the same shape" claim;
  correcting only the doc would have moved the contradiction rather than resolved it.
- Documents Codex's hook trust gate: hooks ship untrusted and are skipped until reviewed.

### Caveat

Every Codex behavioural claim above is source- or test-derived from `openai/codex` main. **No
live `codex` binary was run**, and no real captured `apply_patch` payload exists in this
environment — the parser is written against the authoritative constants in
`apply-patch/src/parser.rs:37-45` and Codex's own fixtures. Measured degradation if a marker
spelling is wrong: the guard falls back to judging `cwd` — a partial fix, never a regression.

## [3.8.2] — 2026-09-17

Consolidates five Claude Code platform-sync review cycles that had accumulated on this
repo's rolling `claude-code-update` PR under provisional version headings 3.6.3
(2026-09-09), 3.6.4 (2026-09-10) and 3.6.5 (2026-09-12), plus the 2.1.273 cycle
(2026-09-16) and tonight's 2.1.274 cycle. Those provisional headings are renumbered
away here: they never actually shipped — the PR stayed open the whole time — while
master's own release process independently, and concurrently, cut real `3.6.3`, `3.7.0`
and `3.8.0` releases from three separate sibling PRs (#153/#152, #150, and #149
respectively — see the three entries below this one). Reusing 3.6.3, 3.6.4, 3.6.5, 3.7.0
or 3.8.0 for this content would collide with an already-shipped version, so this
reconciliation lands as a fresh `3.8.2`, the next patch after master's newest real cut at
merge time. The per-release narrative below is the merged, de-duplicated story; nothing
here changes `hooks/`, `skills/`, or `agents/` content, so the co-authored notes on
individual host fixes are compressed. Tonight's cycle had a live `claude` CLI available
in the automation environment, reporting exactly `2.1.274` — the same version this
changelog delta covers — so the compatibility claims below are live-validated, not
changelog-only.

### Changed
- **Claude Code platform-sync review advances through 2.1.274** (from 2.1.263, the last
  version reflected on master), covering 2.1.267, 2.1.268, 2.1.269, 2.1.270, 2.1.271,
  2.1.272, 2.1.273 and 2.1.274. No breaking changes or deprecations anywhere in the
  range. `validated_against`, `reviewed_through` and `latest_known` all advance to
  **2.1.274** together — this cycle's advance is live-CLI-validated (`claude --version`
  reported `2.1.274`; `claude plugin validate .` re-ran clean). `.claude-code-version`,
  the README badge/table row, and `platform-targets.md`'s table/prose all advance to
  `2.1.274` for the Claude Code row only — Cursor, Codex, Gemini CLI and OpenCode rows
  are untouched, since those are owned by sibling automated tasks.
  - **2.1.267** — `effort:` frontmatter on skills/subagents/commands is no longer
    silently ignored on a model with a pinned default effort, directly relevant since 27
    `SKILL.md` files here set `effort:`; `maxEffortLevel` (an org/user ceiling that can
    cap it); a marketplace entry-path containment hardening protective of this plugin's
    `tamirs-marketplace` distribution.
  - **2.1.268** — `claude plugin install/uninstall/update/enable/disable` gained
    `--json`, adopted below in `scripts/update.sh`/`scripts/uninstall.sh`; `/mcp`/
    `/plugin`/MCP-login errors no longer leak a `${VAR}`-placeholder secret;
    `/plugin install/enable/disable` no longer needing `/reload-plugins` after the menu
    closes; a respawned in-process teammate no longer inherits tools/system-prompt from
    a same-named untrusted agent file.
  - **2.1.269** (largest delta) — a `PreToolUse` deny rule and the `Edit()` write-path
    check now also apply to a Bash `tee` write, and a `Bash(tee:*)` allow rule is
    correctly scoped — this closes, host-side, exactly the gap
    `hooks/guard-sensitive-files.sh`'s header comment names and already covers
    independently via `hooks/lib/write-targets.py`'s own `tee` parsing (neither bug was
    ever exposed here, since this repo declares no `Bash(tee:*)` rule of either kind);
    plugin archives extracted for a session are no longer readable by other local users
    or left world-writable; `claude plugin eval` (a plugin eval-suite runner) is new and
    relevant to this toolkit's skills but is tracked as a Future opportunity rather than
    adopted blind — its `case.yaml`/`prompt.md`+`graders` shape does not match this
    repo's existing per-skill `evals/evals.json`/`trigger-evals.json` trigger-accuracy
    harness, so wiring it is a design decision, not a config change.
  - **2.1.270** — bug-fix-only (a same-week regression in 2.1.269): read-only git
    commands in Bash no longer unexpectedly ask for permission after a long-running
    session; relevant since `permissions-allow.json` pre-allows several git commands
    specifically to avoid this class of friction.
  - **2.1.271** — a stale `.git/config.lock` after a sandboxed command failure no longer
    breaks `git checkout -b`/`git push -u`/`git config` for the rest of the session
    (Linux), relevant since `permissions-allow.json` pre-allows `git push *`/
    `git remote add *`/`git init` for the same reason, and `hooks/worktree-create.sh`
    runs through the same sandboxed Bash surface; cross-session `SendMessage` delivery
    now gives the headless sender a delivery notice instead of holding the message
    silently. `omitClaudeMd` (new agent frontmatter) and per-command `allowed_domains`
    for auto-mode sandboxing were reviewed and deliberately not adopted — no `agents/*.md`
    here should skip the target project's own `CLAUDE.md`, and no shipped rule runs Bash
    under auto mode with sandboxing.
  - **2.1.272** — bug-fixes-and-reliability-improvements only, per the official
    changelog; no adoptable item, just the version bump.
  - **2.1.273** — a 2.1.268 change that checked `Read`/`Edit` deny rules on Bash lines
    the permission checker cannot fully analyze (`eval`, `env -C`) is reverted, so a
    command like `time -p make build` prompts again instead of being silently denied —
    this repo's `permissions-ask.json`/`permissions-allow.json` name no such rule
    pattern, so the revert changes host behavior generically but nothing this repo
    declares. `OTEL_LOG_TOOL_DETAILS=1` now also tags cost/token metrics with real
    agent, skill, plugin and MCP server names — not wired here, since this repo ships no
    OpenTelemetry config of its own. The `New Features` list repeats 2.1.271's entries
    verbatim (fast mode in Remote sessions, `/config` mouse support,
    `--drain-marker-file`, per-command `allowed_domains`, `omitClaudeMd`,
    `--accept-command <sha256>`, `modelPricing` multiplier, a gateway spinner tip) — all
    already reviewed in the 2.1.271 pass above; no new review needed for those.
  - **2.1.274 (this cycle's new coverage)** — a sub-agent's progress summary is no
    longer replaced by a runaway multi-paragraph reply, directly relevant to
    `worker-dev`'s handoff vocabulary (`completed`/`partial`/`failed`/`blocked`) and any
    `orchestrate-dev` fan-out that reads a worker's summary back; `claude agents` no
    longer loses `--model`/`--effort`/`--permission-mode`/
    `--allow-dangerously-skip-permissions`/`--agent` after an auto-update — not exercised
    by any script here (nothing in this repo shells out to `claude agents` directly),
    but relevant to a contributor invoking one of the ten `agents/*.md` from that CLI
    subcommand by hand; a visible low-memory warning is added (host UI, nothing to
    adopt); `CLAUDE_CODE_MCP_STARTUP_WAIT_MS` is added to extend how long the host waits
    for a slow-starting MCP server — reviewed against this plugin's one MCP server
    (`github`, via `scripts/github-mcp.sh`), whose Docker fallback path
    (`docker run ... ghcr.io/github/github-mcp-server stdio`) can be slow to start on a
    cold image pull; documented as an available knob in `CLAUDE.md`'s MCP bullet rather
    than set as a repo default, since it is workstation-dependent. Reviewed and found
    not applicable: an `effort` attribute on the OTel span (this repo ships no
    OpenTelemetry config); Bedrock/Vertex/Foundry/telemetry-disabled sessions switching
    to MCP client v2 by default (this repo targets direct Claude Code/Desktop sessions,
    not a Bedrock/Vertex/Foundry gateway); a sub-agent `model: "opus"` leaving the wrong
    session model on Bedrock/Vertex/Foundry (all ten `agents/*.md` here pin
    `model: sonnet`, and again, no Bedrock/Vertex/Foundry usage); `/code-review` moving
    from spawning many review subagents to leaner inline prompts — this repo does
    reference the official `code-review@claude-plugins-official` marketplace plugin in
    `platforms/claude/settings.d/plugins.json`, but has it deliberately disabled
    (`false`), so no behavior here changes either way.

### Added
- **`scripts/update.sh` and `scripts/uninstall.sh` now request `claude plugin update`/
  `uninstall ... --json`** (added in Claude Code 2.1.268) and surface the returned
  `message`/`failureCode` on failure, instead of only a generic "run the slash command
  yourself" fallback. A JSON parse failure (older CLI, unexpected output) still falls
  back to the previous generic message, so this degrades safely on a `claude` CLI older
  than 2.1.268.
- **Root `.claude-code-version` baseline pin**, now `2.1.274`, referenced from
  `CLAUDE.md`'s "Claude Code CLI baseline" section so a future review does not have to
  reverse-engineer "the highest version mentioned in prose."
  `docs/engineering/build-and-release/platform-targets.json`'s `targets.claude_code`
  block stays authoritative on any disagreement.
- **`CLAUDE.md`'s MCP bullet now documents `CLAUDE_CODE_MCP_STARTUP_WAIT_MS`** (Claude
  Code 2.1.274) as a knob for anyone hitting slow startup on `scripts/github-mcp.sh`'s
  Docker fallback path.

### Documentation
- `core/capabilities/platforms.json` (and its 3 contract-mirrored copies, kept in sync
  via `sync-contract-scripts.sh`) and `platform-targets.json`/`.md` advance
  `last_reviewed` to 2026-09-17; the `claude_code` capability rows for `subagents`,
  `hooks`, `mcp`, `shell`, `git`, `background_tasks` and `plugin_marketplace` gain dated
  notes for the full 2.1.263→2.1.274 delta, and `platform-targets.json` gains new
  `features_adopted` entries. `CLAUDE.md`'s Subagents, Hooks, MCP, Marketplace cache,
  and Remote and headless Claude sessions sections carry the per-release narrative.

## [3.8.0] — 2026-09-17

### Added
- **Local usage capture** (`/usage-capture`). Opt-in, localhost-only recorder: Claude
  Code native OTEL logs/traces into a stdlib Python collector, plus an optional
  zero-dep OpenCode plugin writing the same Israel-dated JSONL. Metadata by
  default (model, duration, tokens, skill/command names); API bodies are an
  explicit `--bodies` sidecar. Nothing is sent off-machine. Env-gated
  `usage-capture-ensure.sh` on SessionStart. Complements `/session-report`
  (transcript rollups), it does not replace it. LiteLLM is an opaque labelled
  gateway (`--gateway-kind litellm`); URLs and raw request IDs are not stored.

## [3.7.0] — 2026-09-17

### Added
- **`/diagnose-refusal` skill (debugging).** Isolates which layer refused a
  request — harness policy, project instructions, LiteLLM guardrail/routing,
  upstream provider filter, model refusal, tool permission, or context
  contamination — and writes a sanitized `.refusal-debug/` bundle
  (`report.md`, `request.json`, `response.json`, `routing.md`,
  `environment.md`, `manifest.txt`). Diagnostics only: never retries the
  refused task, never bypasses policy, and never records secret values (env
  names as SET/UNSET; `redact-secrets.py` for pasted bodies). Bundled scripts:
  `init-bundle.sh`, `collect-environment.sh`, `redact-secrets.py`. Surfaced
  from `AGENTS.md` when a session refuses/blocks and the user needs the
  refusal origin. Skill count is now **28**.

## [3.6.3] — 2026-09-16

### Fixed
- **SessionEnd hooks no longer print "Hook cancelled" on every exit.** Claude
  Code cancels a plugin's SessionEnd hook after 1.5 s regardless of the
  `timeout` in `hooks/hooks.json`. `release-agent-claims.sh` spawned one `jq`
  per file in `~/.agent-work-claims`, which is never swept — 1,443 files took
  4.5 s, so the hook was killed and released nothing. `claim_release_all` now
  prefilters with a single `grep -lF` on the agent id (242 ms against 1,503
  claims) and still confirms ownership with `jq`. `session-end.sh` now runs its
  archive sync and prunes detached, returning in milliseconds. Pinned by
  `tests/test-session-end-budget.sh`.
- **`handoff-reminder.sh` no longer fails SessionEnd hook validation.** It wrapped
  its reminder in `hookSpecificOutput.hookEventName: "SessionEnd"`, but Claude
  Code's schema has no `SessionEnd` variant of `hookSpecificOutput` (only
  `PreToolUse`, `PermissionRequest`, `UserPromptSubmit`, `PostToolUse`,
  `PostToolBatch`, and `Stop`/`SubagentStop` support it) — every session close
  from an active worktree threw a "Hook JSON output validation failed" error
  instead of showing the handoff nudge. It now emits the reminder via the
  top-level `systemMessage` field, matching `session-end.sh`'s existing
  SessionEnd output.
- **27 of the bundled skills silently switched the running session onto the paid 1M-context tier.**
  Their `model: claude-sonnet-4-6` frontmatter pin no longer resolves to a
  standard-context model — Claude Code now resolves it to
  `claude-sonnet-4-6[1m]` instead of ignoring the stale ID, so invoking any of
  them (`decision`, `plan-dev`, `start-dev`, `pr-dev`, `orchestrate-dev`,
  `cleanup`, `retro`, and 20 others) switched the session's model mid-run. On
  an account without usage credits enabled for extended context, the very
  next request failed outright with "Usage credits required for 1M context" —
  independent of session age or context usage, since the switch happens at
  skill-invocation time, not from genuine context growth. Repointed all 27 to
  the bare `sonnet` alias already used by every `agents/*.md` role definition,
  which resolves to the current standard-context model instead of a version
  string that can go stale again.
- **Gold fixture capability registries now claim only what their fixture trees
  actually deliver.** `core/capabilities/platforms.json` under `scaffold-gold`,
  `scaffold-plugin-gold`, and `scaffold-claude-plugin-gold` claimed native
  plugin-manifest-based skills/mcp/subagents/hooks capabilities the fixture
  directory trees never shipped. `scaffold-gold` (the app-gold profile, not a
  plugin-distribution repo) now has its own
  `core/capabilities/platforms.app.json` registry instead of fake plugin
  claims; `scaffold-plugin-gold` and `scaffold-claude-plugin-gold` gained the
  real supporting files (`.mcp.json`, `hooks/hooks.json`, `.codex-plugin/`,
  `.cursor-plugin/`, `agents/`,
  `docs/agent-guidelines/platform-equivalence.md`) their registries already
  claimed, and a schema-invalid `agents`/`commands` array-of-directory-path
  shape in `scaffold-plugin-gold`'s inner plugin manifest — which failed
  `claude plugin validate .` — was corrected to rely on folder discovery.
  `scripts/check-manifest-declares.sh` is now vendored into the contract sync
  chain and all three fixtures as a prerequisite for the new validations.

### Changed
- **The platform-targets co-change gate now judges the capability registry by its
  claims, not by its bytes.** `core/capabilities/platforms.json` was watched by
  the same rule as the prose paths, so any edit demanded a co-change in
  `docs/engineering/build-and-release/platform-targets.json`. But that file's
  `capabilities`/`capability_gaps` are a *derived* mirror of the registry, and a
  normal run of `check-platform-targets.sh` already asserts semantically that the
  mirror matches — so a notes-only correction fired a gate whose only remedy was
  committing an unrelated edit to the derived doc. It is now decided by the
  capability **status** and platform/surface projection: a demotion, a new
  platform or a dropped surface still fires, a prose fix does not, and a
  projection that cannot be made (registry absent at base, a flat
  `schema_version` 1 registry, a `jq` failure) falls back to the byte answer
  rather than to silence. Six paired cases added to
  `tests/test-platform-targets-cochange.sh` (21 passing).
- **The `codex/subagents` demotion now cites the upstream issue, not just the
  absence of a field.** The note argued from what the plugin manifest spec does
  *not* list, which is weak evidence: a spec can omit a field by oversight.
  openai/codex#28491 — "declare custom subagents inside a plugin manifest
  (plugin.json)", closed as a duplicate of #18988 — establishes it positively:
  Codex subagents are standalone `.toml` files in `$CODEX_HOME/agents/` or a
  per-repo `.codex/agents/`, and bundling one inside a plugin is an open feature
  request, so there is no plugin-packaging path to the capability today. The
  status stays `unknown` rather than moving to `unsupported`: the capability
  exists on the surface, and `unsupported` would claim Codex lacks subagents,
  which is false. What is unestablished is a route from this plugin to it.

## [3.6.2] — 2026-09-08

### Added
- **`make assert-contract` now runs in CI, against this repo.** The target existed,
  passed locally, and guarded nothing: no workflow invoked it, so the one gate that
  scores this repo against its own standards contract had never blocked a merge. The
  existing `Repo contract (scaffold-gold)` job asserts the *fixtures*, not the repo.
  Wiring it exposed that it was also red — see below.
- **`reviewed_through` in `platform-targets.json`.** A second, separate version claim
  per target: the newest upstream release whose notes have actually been read for
  adapter impact, as distinct from `validated_against`, which this repo defines as a
  live maintainer-machine run. They drift apart on purpose.
- **README `## Prerequisites`.** The requirements existed as a sentence buried in the
  install section; they are now a section, split into what using the plugin needs
  (`git` 2.30+, `jq`, optionally `gh`) and what `make validate` additionally needs
  (shellcheck, Node 22, Python + `pyyaml`).
- **OpenCode reviewed through 1.18.29.** All 18 releases from 1.18.12 were retrieved
  individually and read against this repo's five points of contact; none unverified.
  No breaking change, no schema-URL change, no change to skill discovery, agent
  frontmatter, or MCP declaration. `validated_against` stays at 1.18.11 — the review
  is documentary, and claiming a live run nobody performed is the defect this repo
  exists to prevent.

### Fixed
- **The contract's drift checker could not see a class of drift, and caused it.**
  `sync-contract-scripts.sh` keeps 25 vendored copies byte-identical to their canonical
  sources. It compared `"$expected" == "$(cat "$dst")"`, and `$(...)` strips every
  trailing newline on both sides — so a copy differing from canonical by exactly its
  terminating newline was reported identical. The same stripping ran through the writer
  (`printf '%s' "$expected"`), so the script had itself written 19 of its 25 copies
  without a terminating newline, including the gold fixtures' `core/capabilities/*.json`,
  which every scaffolded repo inherits. Render, compare and write are now byte-faithful,
  and all 25 copies were regenerated. Proven: the old checker reports
  "25 copies identical to canonical" (exit 0) on a file it disagrees with by one byte;
  the new one reports `DRIFT` and exits 1.
- **The registry's own review clock was never read.** `core/capabilities/platforms.json`
  carries `last_reviewed`, and three scripts read the field only to copy it into a fact
  block; none compared it to a date. The repo therefore policed the 90-day review budget
  on `platform-targets.json` (V1-05) while the file that actually makes the capability
  claims aged unwatched. `check-capability-registry.sh` — already in `make validate` —
  now fails on a missing, stale, or future-dated `last_reviewed`, on the same 90-day
  budget, so the two review clocks run on one policy.
- **The `platform-targets.json` 90-day check could not fail, and skipped in silence.**
  Its comment read "warn only unless assert", but no assert branch was ever written and
  `warn()` does not touch `FAILED`. It now errors under `--assert-current` and warns
  otherwise, as the comment always claimed. Separately, when neither `date -v-90d` nor
  `date -d '90 days ago'` worked, `cutoff` was empty and the `[[ -n "$cutoff" && ... ]]`
  guard skipped the comparison without a word — an unverifiable check reported as a pass.
  It now fails loudly.
- **V1-04 measured a number the repo deliberately keeps behind.** The rule fired on
  `validated_against < latest_known`, but `validated_against` means "last exercised on
  a live maintainer machine" and lags by design — `platform-targets.md` already said
  so in prose. So the rule reported a gap for Codex that the documentation had already
  closed, and could only ever be silenced by a live run or by inventing a version. It
  now fires on `reviewed_through < latest_known` — releases nobody has read, the gap a
  contributor can actually close — and falls back to `validated_against` when a repo
  has no `reviewed_through`, so consumer repos and the gold fixtures score exactly as
  before. The `validated_against` lag stays bounded by `last_reviewed` and V1-05's
  90-day budget. Verified the rule can still fail: rolling OpenCode's
  `reviewed_through` back to 1.18.11 reproduces V1-04.

### Security
- **Every workflow action is now pinned to a commit SHA, and a check keeps it
  that way.** `uses: actions/checkout@v7` names a tag, not a version, and a tag
  is a pointer its owner can move — `v7` meant v7.0.0 when `release.yml` was
  written and means v7.0.1 today, with no commit here and no PR to review. That
  is a third party holding write access to this repo's CI. `ci.yml` was already
  SHA-pinned throughout; `release.yml:18` was not, and nothing noticed, because
  the standard was *practised rather than checked* — the same failure mode as a
  validator nobody runs.
- The gold fixtures mattered more than either. `scaffold-gold` and
  `scaffold-plugin-gold` shipped eight unpinned `@v4` refs, and those workflows
  are copied into every repository scaffolded from this plugin, so the unpinned
  default propagated rather than staying local. All eight now carry the SHA the
  `v4` tag pointed at, with `# v4.4.0` beside it.
- New `scripts/check-action-pinning.sh`, wired into `make validate`. It exempts
  local `./...` actions (nothing external to pin), accepts a `docker://` image
  pinned to `@sha256:<64 hex>` and fails any other docker tag, and honours an
  explicit `action-pin-ok: <reason>` waiver on the line — never a path-shaped
  carve-out, which is how a mutable ref creeps back. `--self-test` builds a
  violating workflow and its corrected twin, so the detector is proven to fire
  and proven to go quiet.
- **The pinning check now scans the whole repository, and the scaffold templates
  are pinned too.** The first version named two roots — `.github/workflows` and
  `skills/repo/_contract/fixtures` — and so reported "all action refs are
  SHA-pinned" while 18 mutable refs sat in `skills/repo/_contract/templates/`,
  the files `repo-scaffold` actually renders into a new repository. A list of
  places to look is only ever as complete as its author's memory; the checker
  now walks the tree and waives by comment instead. `ci.yml.tmpl`,
  `ci-plugin.yml.tmpl` and `legacy-scaffold-templates.md` are pinned to the same
  SHAs the gold fixtures use, so one Dependabot PR moves both.

### Added
- **A regression test for the standards-inventory path coverage**,
  `tests/test-standards-inventory-paths.sh` (22 assertions, picked up
  automatically by `make test-hooks` and so by `make validate` and CI). It pins
  every location GitHub honours for `CODEOWNERS` and every spelling it accepts
  for `LICENSE`, and pins them **in both directions**: each recognised location
  is paired with a repo that has the file nowhere, so a "fix" that hardcodes
  `true` fails the suite; `src/CODEOWNERS` must still read as absent, so the
  search is widened to the platform's rule rather than to the whole tree; and
  root-only conventions are asserted to stay root-only. Against the pre-fix
  inventory it reports `passed: 11  failed: 6`.
- **The four licence spellings the suite above still left unasserted.** The
  inventory probes eight names (`LICENSE`, `LICENCE` and `COPYING`, with `.md`
  and `.txt` where GitHub accepts them); only four of them were covered, so half
  the widened list was unprotected. Adds `LICENCE`, `LICENCE.md`, `LICENCE.txt`
  and `COPYING.md`, plus the negative control the licence half was missing:
  `docs/LICENSE` must **not** count, so the search is widened to the eight names
  GitHub honours at the root rather than to any file called LICENSE anywhere in
  the tree. 22 assertions; against the pre-fix inventory, `passed: 12
  failed: 10`.

### Fixed
- **The platform-targets co-change gate judged a push by its last commit, and
  matched its watch list as a regex.** Two independent defects in
  `scripts/check-platform-targets.sh --require-co-change`. It diffed
  `HEAD~1 HEAD`, so a push of several commits — and every PR longer than one
  commit — was decided by whichever commit happened to be on top: a change to
  `skills/repo/repo-standards/` in the first of three commits passed the gate
  outright. The range now starts at the merge-base with the base the branch left
  (`GITHUB_BASE_REF` on a `pull_request`, the event payload's before-SHA on a
  `push`), falling back to `HEAD~1` when neither exists so a local
  `make platform-targets-cochange` still works with no CI environment, and
  falling back rather than crashing when a shallow clone cannot see the base.
  Separately, each watch path was passed to `grep -q "^${p}"` as a *pattern*, so
  every `.` matched any character and `core/capabilities/platforms.json` also
  fired on `core/capabilities/platforms_json.txt` — a gate that fires on files
  nobody asked it to watch is a gate people learn to ignore. Matching is now
  literal, with the intended semantics made explicit: an entry ending in `/` is a
  directory prefix, every other entry is an exact file. New
  `tests/test-platform-targets-cochange.sh` (15 assertions, auto-discovered by
  `make test-hooks`) pins both directions — the over-match cases are paired with
  the real watched paths and the range cases with a clean multi-commit range, so
  neither "never fire" nor "always fire" passes. Against the pre-fix script it
  reports `passed: 9  failed: 6`.
- **Ten capability rows were validated by a command that could not tell whether
  the capability existed.** Nine read `jq empty <manifest>` and one read
  `test -d "$HOME/.claude/projects"`. Both shapes *can* fail — delete the file
  and they do — but only for a reason unrelated to the claim: drop the `skills`
  key from `.codex-plugin/plugin.json`, delete every skill directory, and a
  manifest with no skills in it is still valid JSON, so the row stays green
  while the capability is gone. This is the same defect as the `opencode/mcp`
  one below, seen one step further out: the verdict was decided by something
  other than the claim it was attached to. All ten now run a command that
  asserts what the row says, and every one of them was executed against this
  tree as evidence rather than reasoned about.
- **New `scripts/check-manifest-declares.sh`**, wired into `make validate` as
  `make check-manifest-declares`. Given a manifest and the keys a capability row
  depends on, it asserts the key is present, is not an empty array/object/string,
  and that every `./…` or `${CLAUDE_PLUGIN_ROOT}/…` path anywhere under it
  resolves in this tree. `--or-discovers <dir>` handles the folder-discovery
  case: Cursor reads `agents/` only while the manifest names no `agents` path,
  so the check follows that rule rather than assuming it — the moment someone
  adds an `agents` key, discovery stops and the check switches to the declared
  paths, where `test -d agents` would have kept passing regardless.
  `--self-test` runs 20 fixtures and 6 live manifest rows with their path counts
  pinned, and was verified by mutating the checker four ways and confirming each
  mutation turns it red.
- **Two capability statuses were wrong, and are now demoted rather than
  re-worded.** `codex/subagents` `native` → `unknown`: the published Codex
  plugin manifest spec lists no agents or subagents field and documents no
  `agents/` folder discovery, this repo ships no Codex agent mirror (unlike
  `.gemini/agents/`), and the row's supporting sentence about cloud subagents
  was the *same sentence, date included*, that sat on the Cursor row — one note
  copied, not two facts established. `cursor/slash_commands` `native` →
  `partial`: the limit is on this repo's side, not Cursor's — there is no
  `commands/` directory and no `commands` key, so it ships zero of them.
  `cursor/subagents` was investigated for the same demotion and **stays
  `native`**: the vendor documentation, read verbatim rather than summarised,
  establishes that folder discovery does deliver it.
- **Five rows cited, as their evidence, a file this registry generates.**
  `platform-targets.json`'s per-target `capabilities` array is a derived mirror
  of `core/capabilities/platforms.json`, regenerated by
  `check-platform-targets.sh --sync-capabilities`, so a row citing it was citing
  itself. A new rule in `check-capability-registry.sh` (§3g) rejects the
  phrasing outright — 114 rows checked. One rewritten note tripped the new rule
  by quoting the banned phrase verbatim; the note was reworded, not the rule
  weakened.
- **The "cannot distinguish" rule is now mechanical, and it reaches the second
  place these commands live.** `check-capability-registry.sh` rejects a
  validation that is *entirely* `jq empty <file>` or `test -[fed] <file>`; only
  the whole command counts, so `jq empty hooks/hooks.json && make test-hooks`
  remains correct by construction. It also scans `platforms/*/adapter.yaml`,
  which carries its own `validation.command` and had two copies of the identical
  defect — a rule that polices one copy of a claim and not the other relocates
  the class instead of removing it. 60 commands now checked, up from 50.
  `platforms/codex/adapter.yaml` additionally claimed MCP servers are configured
  in `.codex/config.toml`, a user-level runtime file that declares nothing this
  plugin ships; they are declared in the plugin manifest.
- **`opencode/mcp` was validated by a command that could not fail, naming a key
  this repo has never shipped.** The row read
  `validation: jq -e '.mcp // {}' opencode.json`. The `// {}` substitutes an
  empty object when `.mcp` is absent and `jq -e` only exits non-zero on `false`
  or `null`, so the command returned 0 for every possible input — and
  `opencode.json` has only ever had `$schema` and `skills`. Its note also read
  "Configured in opencode.json", which was untrue: `docs/user/install/opencode.md`
  tells the user to port the `mcp` entries they want. The status stays `native`
  (OpenCode does read MCP servers natively, from the `mcp` block rather than
  `.mcp.json`); the validation now asserts the documented path, which can
  actually fail, and the note says what this repo ships and what it does not.
- **`check-capability-registry.sh` now rejects a validation command that cannot
  fail** — mechanically, a `//` fallback inside a `jq -e`. The schema requires a
  validation for every `native` claim so the claim is evidence rather than
  assertion; a command that exits 0 on every input converts it back into an
  assertion while looking rigorous. Scans all 50 validation commands and refuses
  to report success on a zero-row read.

- **`codex.hooks` claimed `since: 0.147.0`, a version that is not when Codex
  hooks arrived and is ahead of the `0.146.0` anyone actually ran.** The number
  had been copied from the `features_adopted` entry next to it,
  `portable-agent-plugins-0.147.0` — a different change (plugin catalog
  install) — while the `hooks-field` entry beside it is unversioned precisely
  because the floor was never established. Codex accepted a manifest `hooks`
  field roughly twenty releases earlier (openai/codex PR #19705, merged
  2026-04-28). The `since` is now absent rather than wrong: the exact floor is
  still unestablished, and the row says so. `validated_against` was left at
  `0.146.0` — raising it would assert a validation nobody performed.
- **`check-capability-registry.sh` now fails a `since` that is ahead of its
  platform's `validated_against` and carries no `since_source`.** A version we
  have not run is a documentation claim, and it must name the document; the new
  optional `since_source` field (added to `schema.json`) is where it goes.
  Two traps the check deliberately avoids, both hit while writing it: it reads
  `REGISTRY_CANONICAL`, not the flattened `REGISTRY` temp copy that has no
  `.surfaces` (the first draft read the wrong one, jq failed, the loop got zero
  rows, and the check reported `ok`); and it joins surface → target, not
  platform → target, because the registry keys platforms `claude`/`gemini`
  while `platform-targets.json` keys them `claude_code`/`gemini_cli` — the
  platform join silently finds no target for 14 of the 21 rows. It refuses to
  report success on a zero-row scan, and names any surface it could not check.
- **`docker://` was documented as exempt, reported unconditionally, and could
  not be silenced by the fix it recommended.** The header filed it under "what
  is exempt" as *reported, not failed*, but every finding exits 1 and the branch
  printed before any digest handling — so
  `uses: docker://ghcr.io/owner/img@sha256:<64 hex>`, which is already
  immutably pinned, failed the check and was told to pin by digest. A gate whose
  own remedy does not clear it is exactly what teaches people to add the
  path-shaped carve-out the header warns against two lines later. Docker refs
  now go through the same immutability test as actions, in docker's syntax:
  `@sha256:` followed by 64 lowercase hex passes, anything else (`:v1`,
  `:latest`, a truncated digest) fails. Third instance in this one script of a
  verdict decided by where the code looked rather than by what is true, and the
  second of the three inside the exemption path — the part whose job is to make
  findings disappear, and therefore the part where a bug is silent.
- **`check-action-pinning.sh` matched `uses:` as a substring, so
  `**Common errors and their causes:**` parsed as a workflow step** (`ca-uses:`).
  It now requires `uses:` to be the YAML key. In Markdown it reads only fenced
  blocks, so prose *about* a movable tag — including the Security entries above
  — is no longer reported as one. Found by running the detector against the real
  tree rather than against its own fixtures: fixtures encode what the author
  already thought of, the tree contains what they did not.
- **`--help` printed a hardcoded line range** (`sed -n '2,36p'`) and silently
  truncated as soon as the header grew. It now prints the header block itself.
- **The `action-pin-ok:` waiver was itself a substring match**, so a ref carrying
  the token waived itself and was never reported —
  `uses: docker://ghcr.io/owner/action-pin-ok:v1` is the shape, the docker
  `name:tag` syntax supplying the colon the glob wanted. Only the comment part of
  a line can waive now. Same defect as the `uses:` glob above, in the code that
  was supposed to be the deliberate escape hatch.
- **The self-test could not see the scan root, which is the half that hid the 18
  refs.** Every assertion called `scan()` directly, so reverting `scan "."` to
  `scan ".github/workflows"` left the whole suite green — the coverage bug was
  invisible to the test written to catch coverage bugs. There is now an
  end-to-end case: the script re-invokes itself against a planted tree whose only
  unpinned ref sits outside `.github`, and requires exit 1 exactly. Asserting the
  exact code matters — the first version ran the planted tree under `sh`, which
  cannot parse this script's process substitution, and the syntax error's exit
  read as "the ref was found".
- **The standards scorer invented gaps from an incomplete read.**
  `standards-inventory.sh` probed a single path for two controls the platform
  reads from several, so `score-standards-gaps.sh` asserted the control was
  missing on repos where it is present and working:
  - **S4-01 (P2), CODEOWNERS.** GitHub honours `.github/CODEOWNERS`, root
    `CODEOWNERS` and `docs/CODEOWNERS` with equal weight, and `.github/` is the
    most common of the three. Only the root was checked, so `st-claude` — whose
    `.github/CODEOWNERS` reads `* @TamirCohen28` — scored a P2 gap against a
    control it has.
  - **S5-01 (P1), LICENSE.** Only the exact name `LICENSE` was checked, so a repo
    carrying `LICENSE.md` was told at the highest severity that it has no licence.
    `LICENCE`, `COPYING` and the `.md`/`.txt` spellings are now accepted too.

  The S4 section of that same file already warns that "a gap invented from a
  failed read is the defect this family used to have" — about its API-backed
  checks. The lesson had never been applied to the local-filesystem checks
  sitting twenty lines above it. `.gitignore` is genuinely single-name and
  single-location; `CLAUDE.md` and `AGENTS.md` are deliberately left root-only,
  because the inventory asks whether the repo has a root entrypoint, and a
  nested file is supplementary context rather than that entrypoint.

- **`github-policy` was unreachable on OpenCode, and invisible in the docs.** The
  skill shipped, but `opencode.json` enumerates `skills/repo/*` one directory at a
  time (to keep the `_contract` gold fixtures out) and the enumeration was never
  extended when the skill landed. The same omission had propagated to the
  user-facing catalog in `docs/user/skills.md` and to the copy-paste config block
  in `docs/user/install/opencode.md`, so a user following the install guide
  reproduced the broken config by hand. All three now list it.

### Added
- **Drift checks that can see an omission, not only a rename.** The old contract
  assertion walked the manifest and checked each declared path existed, so a skill
  the manifest never mentions passed silently — which is exactly how the above
  shipped. `contract_skill_coverage` walks the other direction, from every
  canonical `SKILL.md` on disk back to the declared paths, and runs in the Claude,
  Cursor, Codex and OpenCode suites. `check-agent-drift.sh` gained a matching
  catalog half for `docs/user/skills.md`, and a thin-adapter half that fails when a
  `## ` section body is byte-identical in `AGENTS.md` and `CLAUDE.md`. The script
  previously validated frontmatter only, and reported "no drift detected" while an
  entire section sat duplicated between the two files.
- **`make test-contract`**, wired into `make validate`, so the platform contract
  suites run in CI with the rest of the local-parity gate instead of by hand.
- **`.opencode/` build artifacts are ignored by the repo, not by a stray local
  file.** The contract suite asserts `.opencode/node_modules` is gitignored, and
  it passed on a maintainer machine only because the OpenCode CLI drops its own
  `.opencode/.gitignore` there — a file that ignores *itself*, so it can never be
  committed and does not exist on a fresh checkout. The root `.gitignore` did not
  cover the path either: `node_modules/` is a directory-only pattern, which
  `git check-ignore` matches only when the directory exists. Explicit,
  trailing-slash-free entries now hold on any checkout. Surfaced by running the
  contract suites in CI for the first time.
- **OpenCode `latest_known` refreshed** from 1.18.18 (published 2026-08-13) to
  1.18.29 (published 2026-09-04), read from `registry.npmjs.org/opencode-ai`
  `dist-tags.latest`. `validated_against` stays at 1.18.11 — that is the build
  actually run, and moving it would be invention.

### Changed
- **`CLAUDE.md` points at `AGENTS.md` for the skill-surfacing rule** rather than
  restating it verbatim, and the Cursor `plugin-structure` adapter now names five
  platforms and six surfaces, matching the registry and `AGENTS.md` instead of
  dropping Claude Desktop.

- **A removed session worktree stays removed.** `capture-task-slug.sh` ran
  `[[ ! -d $worktree_path ]] && git worktree add -B` on *every* prompt, which
  undid every removal — `git worktree remove`, the `cleanup` skill's worktree
  phase, and this plugin's own stale-worktree retention pass — restoring the
  `wt/*` branch along with it. Creation now happens once and is recorded; a path
  that disappears afterwards is treated as a deliberate removal and the session
  is retired. An `Edit` is the demand signal, so `enforce-worktree-edits.sh`
  rebuilds on demand and still denies, but with a destination that exists.

  Four defects found alongside it: `session-init.sh` mistook the `session-files`
  directory it had just created for a live worktree; a session editing a second
  repo was pointed at the first repo's worktree; rebuilding with `-B` **reset**
  a retained `wt/*` branch to the base ref, stranding commits that existed
  nowhere else; and a rebuild was blocked outright by a prunable registration
  left by `rm -rf`, or by a leftover `session-files` shell on the path.

### Removed
- **The employer IP-guard hook, and every remaining reference to the employer it
  named.** The hook shipped one employer's internal namespace — registries, API
  hostnames, credential prefixes and scoped packages, as literal strings — to
  every user of a public plugin. It was a real need for its author and
  meaningless to everyone else, and the names it existed to keep out of other
  repos were sitting in this one. It is deleted and unwired from `hooks.json`.

  Removed rather than converted to a configurable deny-list, which is what
  `docs/engineering/architecture/repo-shape-conditionality.md` §5 had open. That
  seam already exists: `scripts/lib/capture-common.sh` drives an IP scan from
  generic internal-hostname shapes plus an optional per-machine
  `$TAMIRS_EMPLOYER_PATTERN` / `~/.config/tamirs-superpowers/scan-patterns.txt`.
  A second deny-list in a `PostToolUse` hook would have duplicated it, with the
  same maintenance and one more place for a private name to land.

### Changed
- **Cursor 3.11 (+2026-09-02):** advance `changelog_date` **2026-08-27 → 2026-09-02** (desktop **3.18.9** / feature **3.11** unchanged). Document Cursor **Self-Hosted Machines** (My Machines / Team Pools / partner sandboxes) + **computer use on Linux/Mac**, and the hard distinction from GitHub Actions self-hosted runners (this public plugin stays on `ubuntu-latest`). Cursor-only.
- **Platform target: Claude Code 2.1.263** (`validated_against` 2.1.257 → 2.1.263; this cycle covers 2.1.259,
  2.1.260, 2.1.261 and 2.1.263 — 2.1.262 does not exist in the official changelog). This
  cycle's automation environment had a live `claude` CLI, and it reported exactly `2.1.263` —
  matching the changelog target — so `validated_against` advances all the way to it.
  `claude plugin validate .` (plain and `--json`) and `bash scripts/doctor.sh .` were both
  re-run for real and passed: marketplace manifest valid, every capability row
  native/native-experimental/partial as expected. 2.1.260 fixes
  `permissions.blockReadsOutsideWorkingDirectories` hiding a worktree-isolated sub-agent's own
  checkout on macOS (this repo does not set that permission — reviewed and left out of
  `platforms/claude/settings.d/` in an earlier cycle as a personal auto-mode preference, not a
  plugin default — but the fix benefits worktree isolation for anyone who enables it alongside
  `hooks/worktree-create.sh`/`hooks/enforce-worktree-edits.sh`, now documented in `CLAUDE.md`'s
  Hooks bullet), and adds `/reload-plugins` to headless (`-p`/SDK) sessions (documented in
  `CLAUDE.md`'s Remote/headless section). 2.1.261 adds `/skill-doctor`, which surfaces unused
  loaded skills and their context cost — directly relevant to this toolkit's "27 skills", and
  now called out as a maintenance tip in
  `docs/engineering/build-and-release/development-workflow.md` — and `bashOutputMaxChars`/
  `taskOutputMaxChars` (raises inline command/task output before it spills to a file); the
  latter is not wired anywhere, since no hook or `make validate` output here is known to hit
  the default threshold. Reviewed and found not applicable:
  `--append-subagent-system-prompt-file` (2.1.261) — this repo's subagents run natively via
  `agents/*.md` frontmatter rather than a `claude` CLI system-prompt flag, and the one place a
  large prompt feeds a `claude -p` subprocess (`skill-creator`'s `improve_description.py`)
  already sends it over stdin, not argv, so the argv-length problem this flag solves does not
  exist here; the 2.1.260 revert of 2.1.259's `Read()`-deny-on-Bash-args change — this repo's
  worktree/sensitive-file isolation is enforced by hooks, not `Read(...)` deny rules in
  settings, so neither the original change nor its revert touched anything here; and Workflow
  tool `agent({schema})` validation (2.1.260) — this repo authors no Workflow scripts
  (`core/workflow/` is an unrelated, repo-internal objective-state schema). 2.1.263 is bug
  fixes and reliability improvements only, per the official changelog; nothing plugin-facing to
  adopt. Re-verified 2026-09-07 against a live `claude` CLI still reporting `2.1.263` and the
  official changelog still topping out at `2.1.263`: no newer release exists.
  `docs/engineering/build-and-release/platform-targets.{json,md}` and the README Claude Code
  badge/table row advance to 2.1.263 alongside this entry.
- **The employer scanners no longer name a company.** `tests/test-static.sh` and
  the `run-tamirs-superpowers` check 7 both matched a hardcoded company regex —
  so the check against shipping an employer reference was itself an employer
  reference. Both now use generic internal-hostname shapes plus
  `$TAMIRS_EMPLOYER_PATTERN`, and exclude RFC 2606 / RFC 6761 documentation
  domains so `find-skill`'s `registry.internal.example` stays clean. The static
  suite's positive control still fires — on a synthetic internal hostname built
  from a placeholder company, not a real one.
- **`hooks/validate-report-links.sh`** keys its Grafana URL check on `grafana`
  and `app-analytics` only; the employer-specific analytics hostname is gone.
  The generic GitHub / Slack / placeholder checks are unchanged.
- **`assets/banner.png`** re-encoded losslessly. Its compressed IDAT stream
  happened to contain a three-byte sequence spelling the employer's name, so a
  case-insensitive `grep -r` over the repo reported the image as a match.
  Decoded pixel data, `IHDR` and every metadata chunk are byte-identical; the
  file is 235 KB smaller as a side effect.

### Fixed
- **`hooks/docker-guard.py` was bypassable through the `Shell` tool** (#107).
  The guard opened with `if data.get("tool_name") != "Bash"` and dropped every
  other payload, while `hooks/hooks.json` wires it on `"Bash|Shell"`. So the
  no-local-Docker rule was enforceable through `Bash` and unenforceable through
  `Shell` — the same bypass-by-sibling-tool shape closed in
  `guard-sensitive-files.sh`, and worse for sitting inside a matcher that
  *claims* to cover `Shell`. The tool set is now the constant `TOOLS`, pinned by
  a test against the matcher in `hooks.json`, so the two cannot drift apart
  silently again.
- **The guard's allow paths emitted nothing at all.** Empty stdout is not a
  portable pass: Claude Code reads it as allow, Cursor fail-closes on it, so one
  verdict meant "permit" on one host and "deny" on the other. Every exit now
  prints the allow shape `hooks/lib/hook-output.sh` defines — `{}` on Claude
  Code, `{"permission":"allow"}` on Cursor, chosen from the payload.

### Added
- **`tests/test-docker-guard.sh`** — the guard had no tests. `test-hook-stdin.sh`
  sweeps `hooks/*.sh`, so the one Python hook was never swept, which is how the
  gap above went unwatched. Every risky and safe command is asserted through
  *every* name in `TOOLS`, because a `Bash`-only suite passes unchanged against
  the broken code — the defect exists only as the difference between two tools
  on the same command. Verified by reverting the fix: 5 assertions fail, all of
  them `Shell`, and every `Bash` assertion still passes.

### Fixed
- **`scripts/check-branch-literals.sh` was red, and nothing ran it.** Its single
  hit was prose, not code: a comment in
  `skills/repo/_contract/scripts/standards-inventory.sh` recounting the real
  2026-09-01 incident in which a checkout one commit behind `origin/master`
  reported the canonical version as 3.4.0 when it was 3.5.0. That literal *is*
  the historical fact being recorded — there is no branch to resolve — so it now
  carries the waiver the scanner was built for (`branch-literal-ok: <reason>`)
  rather than being reworded to satisfy a matcher. PR #119 saw this failure and
  correctly scoped it out; this is that follow-up.

### Changed
- **`make validate` now runs `check-branch-literals`.** The script was reachable
  from no target and no CI job, which is why the failure above could sit red
  without failing anything — precisely the rot its own header names: "a check
  that has never been shown to fail is indistinguishable from a check that greps
  nothing, and this repo has shipped several of those." The new target invokes it
  as `. --self-test`, so each run first proves the detector fires on 9 planted
  literals and stays silent on 6 legitimate ones, then scans the tree. Wiring it
  into `validate` carries it into CI, which already gates on `make validate`.


---

Older entries (3.6.1 and earlier) live in [CHANGELOG-archive-1.md](CHANGELOG-archive-1.md), [CHANGELOG-archive-2.md](CHANGELOG-archive-2.md), and [CHANGELOG-archive-3.md](CHANGELOG-archive-3.md) — split out 2026-09-17 to keep this file a size the repo's own tooling and its GitHub write path can reliably round-trip. No content was removed, only relocated.
