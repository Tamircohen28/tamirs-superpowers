# Mods — the in-process layer (Claude Code ≥ 2.1.287)

`mod/register.tsx` is this plugin's **mod**: a module of function hooks that Claude
Code runs inside its own process. It is named by the `modules` key of `hooks/hooks.json`,
beside the settings hooks the same file has always declared, and its `$.state` contract is
`mod/types/index.d.ts`, named by `types` in `.claude-plugin/plugin.json`. Claude Code's own validator requires that field for a mod (the `$.state` contract must be named); the directory lists it as an unknown key, which is expected and stays.

The module is five files, split so that every hook and every `$` call sits in one of them:

| File | Holds | Receives `$` |
|---|---|---|
| `mod/register.tsx` | every `on(...)` registration and every `$.noun.method(...)` call, written in full at its call site | yes — the only file that does |
| `mod/objective.ts` | readers and formatters of the `.dev-files/objectives/<id>/` JSON (pick the active objective, task rows, the `/objective` text, the `objective_status` JSON, the skill-context line, agent-to-task mapping) — already-read text or data in, data or text out | no |
| `mod/usage.ts` | the rate-limit band's headline, instruction, toast and notification text, the usage line, the crossing key, the store-value readers | no |
| `mod/skills.ts` | `SKILL_LABELS` for the classifier, the 27 public skills' one-line descriptions, the typeahead rows, the dev-workflow set | no |
| `mod/compat.ts` | version comparison and the feature gates (`hasTypography`, `hasNotify`, `hasAgentView`) taking a version string | no |

`mod/mods.test.tsx` is the test file; `mod/types/index.d.ts` the contract.

This page says what the mod does, why each feature is a mod and not a bash hook, where it
runs, how it is validated, and what to know before changing it. The host-side reference is
the [mods overview](https://code.claude.com/docs/en/plugins/mods) and
[reference](https://code.claude.com/docs/en/plugins/mods/reference); the per-build API is the
`types/claude-code.d.ts` the engine writes (see [Validation](#validation)).

## The rule: additive, never a replacement

This plugin ships to six surfaces across five platforms from one source. Twenty-seven of
its twenty-eight settings hooks are bash precisely so that Codex (which loads
`hooks/hooks.json` natively) and Cursor (which loads `platforms/cursor/hooks.json`) run
them too. A mod runs on **Claude Code, the Claude Desktop Code tab and (since 2.1.299) the
VS Code extension's chat panel** — its hooks also run under `claude -p` and cloud sessions,
but nothing it draws appears there, and an organisation's `allowManagedModsOnly` or a
`--safe-mode` start drops it entirely while leaving the settings hooks running.

So every bash hook in [`hooks-classification.md`](hooks-classification.md) stays canonical,
and the mod does only what a bash hook structurally cannot:

| It can | Because |
|---|---|
| **Draw** — a pane, the band above the prompt, the spinner, a transcript row | A settings hook has no UI surface |
| **React to pushed state** — `session.measure` carries rate-limit windows after every turn | No settings hook event carries rate limits; the statusline command sees them but cannot act |
| **Act before a turn dies** — a handoff button at 85 %, not a `StopFailure` message after | `StopFailure` fires when it is already too late to ask |
| **Answer a command instantly** — `/objective` runs the function, no model turn, even mid-turn | A skill is a prompt; it needs a turn |
| **Answer the model's tool call** — `objective_status` reads orchestration state without a shell | A settings hook cannot register a tool |
| **Fill the prompt box's typeahead** — a `/` offers the public skills with a line each | No settings hook sees the draft as it is typed |
| **Rewrite a skill's expanded text** — the live objective appended as a dev-workflow skill expands | `UserPromptSubmit` runs before expansion and sees the typed line only |

Nothing in the mod denies a tool call, creates a worktree or replaces a guard. Where a
feature overlaps a bash hook, the bash hook is the fallback that still fires when the mod
cannot load.

## What it does

| # | Feature | Hooks | Overlaps / fallback |
|---|---|---|---|
| 1 | **Objective pane + `/objective [id]`** — the orchestration state `orchestrate-dev`/`worker-dev` keep in `.dev-files/objectives/<id>/` (`objective.json`, `tasks/*.json`, `handoffs/*.json`) drawn live, one row per task, re-read every 5 s; `/objective` answers at once (`immediate`), and with an id reads that objective from disk; the spinner counts workers in flight; a task-notification row is drawn compact | `session.start`, `command.run`, `ui.render{Pane}`, `agent.spawn`, `turn.complete`, `ui.render{Spinner}`, `ui.render{UserMessage}` | New capability. `objective-state.sh show` from a shell is the fallback |
| 1 | **Reload after `/clear`, `/resume`, `/branch`** — those reset `$.state` while `session.start` does not fire again; the classic `SessionStart` event does, with `source`, and the objective is re-read and the stored dismissals restored (the band re-derives from the next `session.measure`) | `classic.SessionStart{source: clear\|resume\|fork}` | Before 5.0.0 the pane went blank until the 5 s re-read and a dismissal was forgotten |
| 1 | **Worker rows** (2.1.300) — a task whose worker `$.agent.list()` reports (matched by the task id in the agent's description, else by order of running agents) shows the agent's status (`pending`/`running`/`waiting`/`idle`/`completed`/`failed`/`killed`) and a `[ view ]` button whose press calls `$.ui.view({ agentId })` to put that worker's transcript in the main view; drawn only on a host at 2.1.300 or later (`hasAgentView`) | `ui.render{Pane}`, `$.agent.list`, `$.ui.view` | `/tasks` and the agent detail dialogs (host UI) |
| 2 | **Rate-limit band** — at `rate_limit_warn_percent` (default 85) of any window a band tells the user to type `/switch-dev handoff` (the mod submits no prompt; a `prompt.submit` call beside its file reads is a `MOD_DATA_LEAVES_BY_PROMPT` hold) and shows `[ Dismiss ]`; one toast per 5-point crossing. A dismissal is kept per window kind in `$.state` and written through to `$.store` (`rate-limit.dismissed`), so it outlives the session; the window dropping 10 points under the threshold clears both | `session.measure`, `ui.render{AbovePrompt}`, `$.store.get/set/delete` | `hooks/rate-limit-handoff.sh` (`StopFailure`, after the fact). Both stay |
| 2 | **Native notification** (2.1.295) — the band's first appearance for a window also calls `$.ui.notify`, once per crossing, so the warning reaches the person's own `preferredNotifChannel` (a Desktop with no terminal bell included); host-local, no network; a host before 2.1.295 is left alone (`hasNotify`) | `session.measure`, `$.ui.notify` | `scripts/notify-pushover.sh` (`Notification`) stays the one out-of-band channel |
| 3 | **Usage line on Desktop and VS Code** — `ctx 12% · 5h 40% (resets 2h10m) · 7d 31% · $1.50`, held to 200 characters, on the two surfaces with no status line | `session.measure`, `ui.render{AbovePrompt}` | `scripts/statusline.sh` on the CLI. The mod never draws it on the terminal |
| 4 | *(removed in 4.11.1)* A Pushover post on long or failed turns lived here as the mod's one network call. The plugin directory holds a mod that both reads the conversation and sends data out, and the `Notification` bash hook already covers phone alerts, so the mod now makes no network call at all | — | `scripts/notify-pushover.sh` on the `Notification` event is the one Pushover path |
| 5 | **Semantic skill suggestion** — opt-in `semantic_skill_suggest`: a prompt of 12+ words is classified by the engine's small model against the bundled skill names; a match is attached as context once per skill across sessions (`$.store` `skill-suggest.seen`, the session set as cache) | `prompt.submit`, `$.model.classify`, `$.store.get/set` | `hooks/skill-suggest.sh` keyword matching stays on either way |
| 7 | **Typeahead rows** (2.1.292) — while the first word of the draft opens with `/`, the 27 public skills, `/objective` and `/switch-dev handoff` join the prompt box's typeahead as `{ text, label, description }`, the description a static line per skill in `mod/skills.ts` (derived from the skill's frontmatter at authoring time, under 80 characters; nothing reads a `SKILL.md` at run time). The three internal companions are left out | `prompt.autocomplete{start: 0, token: /^\//}` | The engine's own command list, without descriptions of the plugin's choosing |
| 8 | **Skill context** (2.1.299 fields) — when a dev-workflow skill of this plugin (`e.pluginName === 'tamirs-superpowers'`) expands while an objective is active, one `[tamirs-superpowers]` line with the objective id, title, status, the session's worktree (`$.session.root()`) and the open-task count is appended to the expanded text, so `worker-dev` and `orchestrate-dev` start with state they otherwise ask a shell for | `skill.prompt{pluginName}` | `objective-state.sh show` inside the skill |
| 9 | **`objective_status` tool** (2.1.293 `isDeferred`) — registered at `session.start` with `isDeferred: false` (schema in the prompt's tool list from turn one, not behind ToolSearch) and answered by a `tool.call` hook on `mcp__tamirs-superpowers__objective_status`: the objective summary (id, status, open-task count, tasks with status/role/branch/handoff) as JSON text from the same files; one optional argument, `objective`, an id. The hook answers for itself and its `.catch` answers the model with the failure, never leaving the call unanswered | `session.start`, `$.tool.register`, `tool.call{tool}` | `objective-state.sh show` through Bash |
| 6 | **Definition-of-done line** under an answer whose turn wrote files | `turn.start`, `tool.call`, `turn.complete` | `hooks/check-done.sh` (`Stop`, stderr) |
| 6 | **Compaction snapshot** — branch and the objective folded into the summariser's instructions (the branch from `.git/HEAD`, read with `$.fs`; no process runs) | `session.compact`, `$.fs.read` | `hooks/precompact-snapshot.sh` (writes a file; `PreCompact` has no context channel) |
| 6 | **Commit trailer policy** — when the repo's `CLAUDE.md` declares a `Co-Authored-By: Claude <…>` line and the attribution text lacks one, it is appended | `attribution.text{commit}` | The CLAUDE.md prose. Only enforced where the repo declares it; a repo without the line gets nothing |

Reviewed and deliberately **not** ported: `show-changelog.sh` (its `systemMessage` already
renders in the transcript; a mod re-implementation via `$.session.append` would duplicate
it), and every guard (`enforce-worktree-edits`, `guard-sensitive-files`,
`protect-other-branches`, `docker-guard`): they are core-safety-invariant and tested against
Codex `apply_patch` payloads and Cursor's bundle, and the mod docs' own recommended
guard pattern (`$.fs.stat(path, { resolve: true }).realPath`) is what `hooks/lib/write-targets.py`
already approximates.

## Options

Four non-sensitive `userConfig` fields, shown as rows in `/config` and editable with
`claude plugin configure tamirs-superpowers`:

| Field | Default | Effect |
|---|---|---|
| `rate_limit_warn_percent` | 85 | Band threshold (50–100) |
| `semantic_skill_suggest` | false | One small-model call per long prompt when on |
| `notification_hooks` | true | Notification-tier bash hooks run (desktop and phone notifications, VPN exit check, usage-capture collector start) |
| `contributor_hooks` | false | Contributor-tier bash hooks run (reload reminder, `report.md` link validation, hand-written `SKILL.md` guard) |

The first two are the mod's. The two hook-tier options are **read by the bash hooks, not by
the mod**: Claude Code exports them to each hook process as `CLAUDE_PLUGIN_OPTION_*`, and
`hooks/lib/hook-output.sh`'s `hook_tier_gate` applies them (see
[hooks-classification.md § Tiers](hooks-classification.md#tiers)). The mod neither reads
them nor needs to — nothing it draws belongs to either tier.

`pushover_token`/`pushover_user` are the existing sensitive fields; since 4.11.1 the mod does not
read them at all (only `scripts/notify-pushover.sh` does). A test in `mod/mods.test.tsx` holds the
line: a long or failed main turn makes no network call, options or not.

## What the plugin directory requires of it

Anthropic's plugin directory scans a mod the way `claude plugin validate` does and adds rules
of its own (the first review of 4.10.0 raised them; the codes are the portal's). The mod meets
them on `master`, and `scripts/check-claude-dist.sh` holds the line:

| Rule | How the mod meets it |
|---|---|
| `MOD_CAPABILITY_USE_NOT_PLAIN` (blocks) — every `$.noun.method` call written at its call site, `$` handed to no helper | every `$` call is in `mod/register.tsx`; the four imported files are pure (text or data in, text or data out) and none receives `$`; the objective loader is a closure inside `session.start` where its `$.fs` calls are spelled out, reused by the 5 s timer, the `SessionStart` reload, `/objective <id>` and the tool; only the `claude-code` state helpers (`read`, `update`) take `$`. Feature presence is gated by version (`mod/compat.ts`), never by reading a `$` member as a value: `claude plugin validate` refuses `typeof $.ui.view` outright |
| `MOD_FORWARDS_CREDENTIAL_ENV` (blocks) / `MOD_READS_CREDENTIAL_ENV` — no credential read from the environment or a file and sent | the mod reads no credential and makes no network call (4.11.1 removed its Pushover post) |
| `MOD_RUNS_PROCESS` / `MOD_PROCESS_COMMAND_COMPUTED` / `MOD_CAN_FETCH_AND_RUN` (held) | no `$.process` at all: the main working tree from `$.session.repo()`, the branch from reading `.git/HEAD` |
| `COMMAND_NAMES_MOD_FILE` (held) — no shipped command, script or configuration names the mod's files or folders | the mod lives in its own top-level `mod/`, named only by the `modules` entry of `hooks/hooks.json` (which does not count); `scripts/typecheck-mods.sh` and the `Makefile`, which do name it, are not shipped |
| `MOD_LOCAL_DATA_LEAVES` / `MOD_SESSION_DATA_LEAVES` (held in 4.11.0) | gone with the network call in 4.11.1 |
| `MOD_DATA_LEAVES_BY_PROMPT` (held) | the mod submits no prompt at all (the handoff button went in 4.11.6); the band tells the person what to type. The portal still names the pair `fs.read` + `prompt.submit` because a `prompt.submit` *hook* is registered for the opt-in suggestion, so the hold stays and the directory README says so |
| `MOD_ANSWERS_PERMISSION` / `MOD_HOOKS_POLICY_EVENT` (held) — the `agent.spawn` hook can deny a spawn | it only counts a worker and calls `next(e)`; the comment says so. The mod answers no `tool.check`, returns no `{ deny }` anywhere, and the one `tool.call` hook that answers for itself serves the plugin's own `objective_status` tool |
| `$.store` — a JSON file of the plugin's own under the Claude Code configuration directory, shared by every session on the machine, 4 MiB in all | two keys, both small: `rate-limit.dismissed` (percentage per window kind) and `skill-suggest.seen` (a list of skill names); every write re-reads the key first and merges, since another session may have written meanwhile; a store the host cannot read starts the session empty, nothing worse |

## Where it runs, and the Codex trade-off

| Surface | Hooks | Drawing |
|---|---|---|
| Claude Code CLI (terminal, JetBrains, editor terminals) | yes | yes |
| Claude Desktop Code tab | yes | yes (not WSL sessions) |
| VS Code extension chat panel (extension 2.1.299+) | yes | yes — the reduced element set: no `Button` `hotkey`/`plain`/`autoFocus`/`action`, no `Text` `size`/`mono`/`tabular`, no `Box` `position`/`hover`, no `Client`; status lines cut at 200 characters, toasts at 500. The mod's trees use none of those, so one tree serves all three surfaces |
| `claude -p`, Agent SDK, cloud sessions | yes | no — `/objective` and `objective_status` still answer in text |
| Codex, Cursor, Gemini CLI, OpenCode | no | no |

The `modules` key sits in the Claude `hooks/hooks.json`. Codex's hooks-file parser is strict
at the top level (exactly `description` and `hooks`; source-read, not run live), so a file
carrying `modules` would load no hook there at all. Since 5.0.0 the question is closed by
construction: `.codex-plugin/plugin.json` points `hooks` at `platforms/codex/hooks.json`, a
copy `scripts/build-codex-hooks.sh` generates from the canonical file **without** `modules`
(and without the events Codex lacks), so Codex never sees the key and the mod never loads
there. The Claude file keeps the key because Claude Code reads the mod from it. `make
validate` regenerates the copy and fails on drift.

## Validation

Three gates, in `make validate` and CI (`make test-mods`):

1. `claude plugin validate .claude-plugin/plugin.json` — reads the manifest and the
   module's source the way the engine will, and refuses what the engine would refuse
   (a second unmatched `on("turn.complete")`, `$` passed to a closure, a `$.state` key the
   contract does not declare). Note `claude plugin validate .` validates the **marketplace**
   manifest only and never reads the mod; CI runs both.
2. `claude plugin test .` — runs `mod/*.test.tsx` against the engine itself (40 tests).
   The test's `on` hooks sit beneath the mod and stand for the engine, so each test stubs the
   world the feature touches (`fs.*`, `prompt.submit`, `model.classify`, `agent.list`,
   `ui.notify`, `ui.view`, `tool.register`, …), `mock.store`/`mock.env`/`mock.clock`/
   `mock.session` answer those nouns from memory, and recorders hold what the mod asked
   for. Every drawing test mounts the band, the pane and the spinner on `terminal`,
   `desktop` and `vscode`, and asserts the `part: { plugin }` stamp on the root that
   `ui.drawn()` hands back. This is the CI gate. Two things to know about the 2.1.302 kit:
   its typings' `EventCalls` leave `prompt.autocomplete` off the `prompt` noun although the
   kit's `$` offers the call at run time, so the autocomplete test reaches it through a cast
   (and asserts it is there); and `claude plugin test <dir>` runs every `*.test.tsx` **under** `dir` while loading
   only the mod **at** `dir`, so a second plugin kept in a subfolder of this repository
   (`plugins/<name>/`) must be tested from its own folder, and its test file fails when
   the root run discovers it with the root mod loaded in its place.
3. `make typecheck-mods` — `tsc` over the module, its four pure imports, the contract and
   the tests against the build's `claude-code.d.ts`. The engine writes that file beside
   the mod (`.claude-plugin/types/`, gitignored) when an interactive session loads the
   plugin from a folder you own (`claude --plugin-dir .`); `claude plugin test` does not.
   The script finds it there, or in the `plugin-authoring` skill's bundled copy (which
   that skill lays under the session's temp directory when it loads, the copy this cycle
   type-checked against), or at `$CLAUDE_CODE_TYPES`, and **skips with a notice** when
   none is present. It stays a local, non-CI gate because the engine's type file is not
   redistributed with the repository: it is ~750 KB, regenerated per build and marked
   early access, so vendoring it would pin the check to a stale API. Gates 1 and 2 are
   the CI gates.

The API is marked early access and moves between releases. `platform-sync` reviews it per
release; when the engine's types change, regenerate rather than edit, and re-run all three.

## Changing it

- Keep every `$` call in `mod/register.tsx`, written in full at its call site; a helper
  that needs `$` is a closure inside the hook that owns it (the objective loader), never an
  import. New pure logic goes in `objective.ts`, `usage.ts`, `skills.ts` or `compat.ts`.
- Never read a `$` member as a value (`typeof $.ui.view`): the validator refuses it. Gate
  a newer method or prop by version through `mod/compat.ts` against `$.session.version()`,
  with the 2.1.287 tree or no call as the fallback.
- One unmatched `on("<event>")` per event per module; a second registration needs a
  matcher. Fold new per-turn work into the existing `turn.complete` hook.
- State a drawing reads lives in `$.state` (declared in `types/index.d.ts`), never a module
  variable: a hot reload loses module variables, the host keeps state. Module variables are
  fine for what may legitimately reset (`writesThisTurn`, the toast and notification keys).
  What must outlive the session goes to `$.store` too, re-read before every write.
- `/clear`, `/resume` and `/branch` reset `$.state` without a `session.start`: anything
  that must come back goes in the `classic.SessionStart` reload.
- A hook has 10 s of its own time per dispatch and `session.end` hooks share 1.5 s; nothing
  here sleeps, and the objective re-read is a handful of small JSON files.
- Add a test for every feature. `claude plugin test` reports a hook the engine skipped and
  why, so a silently-failing hook shows up as a failing test.
