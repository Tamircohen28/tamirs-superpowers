# Mods — the in-process layer (Claude Code ≥ 2.1.287)

`mod/register.tsx` is this plugin's **mod**: a module of function hooks that Claude
Code runs inside its own process. It is named by the `modules` key of `hooks/hooks.json`,
beside the settings hooks the same file has always declared, and its `$.state` contract is
`mod/types/index.d.ts`, named by `types` in `.claude-plugin/plugin.json`.

This page says what the mod does, why each feature is a mod and not a bash hook, where it
runs, how it is validated, and what to know before changing it. The host-side reference is
the [mods overview](https://code.claude.com/docs/en/plugins/mods) and
[reference](https://code.claude.com/docs/en/plugins/mods/reference); the per-build API is the
`types/claude-code.d.ts` the engine writes (see [Validation](#validation)).

## The rule: additive, never a replacement

This plugin ships to six surfaces across five platforms from one source. Twenty-seven of
its twenty-eight settings hooks are bash precisely so that Codex (which loads
`hooks/hooks.json` natively) and Cursor (which loads `platforms/cursor/hooks.json`) run
them too. A mod runs on **Claude Code and the Claude Desktop Code tab only** — its hooks
also run under `claude -p`, the VS Code chat panel and cloud sessions, but nothing it draws
appears there, and an organisation's `allowManagedModsOnly` or a `--safe-mode` start drops
it entirely while leaving the settings hooks running.

So every bash hook in [`hooks-classification.md`](hooks-classification.md) stays canonical,
and the mod does only what a bash hook structurally cannot:

| It can | Because |
|---|---|
| **Draw** — a pane, the band above the prompt, the spinner, a transcript row | A settings hook has no UI surface |
| **React to pushed state** — `session.measure` carries rate-limit windows after every turn | No settings hook event carries rate limits; the statusline command sees them but cannot act |
| **Act before a turn dies** — a handoff button at 85 %, not a `StopFailure` message after | `StopFailure` fires when it is already too late to ask |
| **Answer a command instantly** — `/objective` runs the function, no model turn, even mid-turn | A skill is a prompt; it needs a turn |

Nothing in the mod denies a tool call, creates a worktree or replaces a guard. Where a
feature overlaps a bash hook, the bash hook is the fallback that still fires when the mod
cannot load.

## What it does

| # | Feature | Hooks | Overlaps / fallback |
|---|---|---|---|
| 1 | **Objective pane + `/objective`** — the orchestration state `orchestrate-dev`/`worker-dev` keep in `.dev-files/objectives/<id>/` (`objective.json`, `tasks/*.json`, `handoffs/*.json`) drawn live, re-read every 5 s; `/objective` answers at once (`immediate`); the spinner counts workers in flight; a task-notification row is drawn compact | `session.start`, `command.run`, `ui.render{Pane}`, `agent.spawn`, `turn.complete`, `ui.render{Spinner}`, `ui.render{UserMessage}` | New capability. `objective-state.sh show` from a shell is the fallback |
| 2 | **Rate-limit band** — at `rate_limit_warn_percent` (default 85) of any window a band shows `[ Write handoff ]`, which submits a `switch-dev handoff` prompt, and `[ Dismiss ]`; one toast per 5-point crossing | `session.measure`, `ui.render{AbovePrompt}` | `hooks/rate-limit-handoff.sh` (`StopFailure`, after the fact). Both stay |
| 3 | **Usage line on Desktop** — `ctx 12% · 5h 40% (resets 2h10m) · 7d 31% · $1.50`, Desktop only | `session.measure`, `ui.render{AbovePrompt}` | `scripts/statusline.sh` on the CLI (Desktop has no status line). The mod never draws it on the terminal |
| 4 | *(removed in 4.11.1)* A Pushover post on long or failed turns lived here as the mod's one network call. The plugin directory holds a mod that both reads the conversation and sends data out, and the `Notification` bash hook already covers phone alerts, so the mod now makes no network call at all | — | `scripts/notify-pushover.sh` on the `Notification` event is the one Pushover path |
| 5 | **Semantic skill suggestion** — opt-in `semantic_skill_suggest`: a prompt of 12+ words is classified by the engine's small model against the bundled skill names; a match is attached as context once per skill per load | `prompt.submit`, `$.model.classify` | `hooks/skill-suggest.sh` keyword matching stays on either way |
| 6 | **Definition-of-done line** under an answer whose turn wrote files | `turn.start`, `tool.call`, `turn.complete` | `hooks/check-done.sh` (`Stop`, stderr) |
| 6 | **Compaction snapshot** — branch, uncommitted files and the objective folded into the summariser's instructions | `session.compact`, `$.process.run` | `hooks/precompact-snapshot.sh` (writes a file; `PreCompact` has no context channel) |
| 6 | **Commit trailer policy** — when the repo's `CLAUDE.md` declares a `Co-Authored-By: Claude <…>` line and the attribution text lacks one, it is appended | `attribution.text{commit}` | The CLAUDE.md prose. Only enforced where the repo declares it; a repo without the line gets nothing |

Reviewed and deliberately **not** ported: `show-changelog.sh` (its `systemMessage` already
renders in the transcript; a mod re-implementation via `$.session.append` would duplicate
it), and every guard (`enforce-worktree-edits`, `guard-sensitive-files`,
`protect-other-branches`, `docker-guard`): they are core-safety-invariant and tested against
Codex `apply_patch` payloads and Cursor's bundle, and the mod docs' own recommended
guard pattern (`$.fs.stat(path, { resolve: true }).realPath`) is what `hooks/lib/write-targets.py`
already approximates.

## Options

Three non-sensitive `userConfig` fields, shown as rows in `/config` and editable with
`claude plugin configure tamirs-superpowers`:

| Field | Default | Effect |
|---|---|---|
| `rate_limit_warn_percent` | 85 | Band threshold (50–100) |
| `semantic_skill_suggest` | false | One small-model call per long prompt when on |

`pushover_token`/`pushover_user` are the existing sensitive fields; since 4.11.1 the mod does not
read them at all (only `scripts/notify-pushover.sh` does). A test in `mod/mods.test.tsx` holds the
line: a long or failed main turn makes no network call, options or not.

## What the plugin directory requires of it

Anthropic's plugin directory scans a mod the way `claude plugin validate` does and adds rules
of its own (the first review of 4.10.0 raised them; the codes are the portal's). The mod meets
them on `master`, and `scripts/check-claude-dist.sh` holds the line:

| Rule | How the mod meets it |
|---|---|
| `MOD_CAPABILITY_USE_NOT_PLAIN` (blocks) — every `$.noun.method` call written at its call site, `$` handed to no helper | the helpers in `mod/register.tsx` are pure (text or data in, text or data out); the objective loader is a closure inside `session.start` where its `$.fs` calls are spelled out, reused by the 5 s timer; only the `claude-code` state helpers (`read`, `update`) take `$` |
| `MOD_FORWARDS_CREDENTIAL_ENV` (blocks) / `MOD_READS_CREDENTIAL_ENV` — no credential read from the environment or a file and sent | the mod reads no credential and makes no network call (4.11.1 removed its Pushover post) |
| `MOD_RUNS_PROCESS` / `MOD_PROCESS_COMMAND_COMPUTED` / `MOD_CAN_FETCH_AND_RUN` (held) | no `$.process` at all: the main working tree from `$.session.repo()`, the branch from reading `.git/HEAD` |
| `COMMAND_NAMES_MOD_FILE` (held) — no shipped command, script or configuration names the mod's files or folders | the mod lives in its own top-level `mod/`, named only by the `modules` entry of `hooks/hooks.json` (which does not count); `scripts/typecheck-mods.sh` and the `Makefile`, which do name it, are not shipped |
| `MOD_LOCAL_DATA_LEAVES` / `MOD_SESSION_DATA_LEAVES` (held in 4.11.0) | gone with the network call in 4.11.1 |
| `MOD_DATA_LEAVES_BY_PROMPT` (held) | the handoff prompt is fixed text, submitted only when the person presses the button; the directory README says exactly what it contains |
| `MOD_ANSWERS_PERMISSION` / `MOD_HOOKS_POLICY_EVENT` (held) — the `agent.spawn` hook can deny a spawn | it only counts a worker and calls `next(e)`; the comment says so |

## Where it runs, and the Codex trade-off

| Surface | Hooks | Drawing |
|---|---|---|
| Claude Code CLI (terminal, JetBrains, editor terminals) | yes | yes |
| Claude Desktop Code tab | yes | yes (not WSL sessions) |
| VS Code extension chat panel, `claude -p`, Agent SDK, cloud sessions | yes | no — `/objective` still answers in text |
| Codex, Cursor, Gemini CLI, OpenCode | no | no |

The `modules` key sits in the same `hooks/hooks.json` the Codex CLI loads through
`.codex-plugin/plugin.json`. Whether Codex ignores an unknown top-level key there is
**unverified** (recorded in `core/capabilities/platforms.json`, codex → hooks). The
decision to keep one hooks file and one plugin rather than a sibling plugin was taken
knowingly: fewer platforms over a second distribution. If a Codex run ever rejects the
file, `.codex-plugin/plugin.json` can point `hooks` at a generated copy without `modules`.

## Validation

Three gates, in `make validate` and CI (`make test-mods`):

1. `claude plugin validate .claude-plugin/plugin.json` — reads the manifest and the
   module's source the way the engine will, and refuses what the engine would refuse
   (a second unmatched `on("turn.complete")`, `$` passed to a closure, a `$.state` key the
   contract does not declare). Note `claude plugin validate .` validates the **marketplace**
   manifest only and never reads the mod; CI runs both.
2. `claude plugin test .` — runs `mod/*.test.tsx` against the engine itself. The
   test's `on` hooks sit beneath the mod and stand for the engine, so each test stubs the
   world the feature touches (`fs.*`, `prompt.submit`, `model.classify`, …) and records what the
   mod asked for. UI tests mount the band, the pane and the spinner on both `terminal` and
   `desktop`.
3. `make typecheck-mods` — `tsc` over the module, the contract and the tests against the
   build's `claude-code.d.ts`. The engine writes that file beside the mod
   (`.claude-plugin/types/`, gitignored) when an interactive session loads the plugin from
   a folder you own (`claude --plugin-dir .`); `claude plugin test` does not. The target
   finds it there, or in the `plugin-authoring` skill's bundled copy, or at
   `$CLAUDE_CODE_TYPES`, and **skips with a notice** when none is present — which is why
   it is not a CI gate: a CI runner has no session to lay the file. Gates 1 and 2 are.

The API is marked early access and moves between releases. `platform-sync` reviews it per
release; when the engine's types change, regenerate rather than edit, and re-run all three.

## Changing it

- Keep every helper that receives `$` a **top-level function** — the validator follows `$`
  only into those, and refuses a closure.
- One unmatched `on("<event>")` per event per module; a second registration needs a
  matcher. Fold new per-turn work into the existing `turn.complete` hook.
- State a drawing reads lives in `$.state` (declared in `types/index.d.ts`), never a module
  variable: a hot reload loses module variables, the host keeps state. Module variables are
  fine for what may legitimately reset (`writesThisTurn`, the per-load suggestion set).
- A hook has 10 s of its own time per dispatch and `session.end` hooks share 1.5 s; nothing
  here sleeps, and the objective re-read is a handful of small JSON files.
- Add a test for every feature. `claude plugin test` reports a hook the engine skipped and
  why, so a silently-failing hook shows up as a failing test.
