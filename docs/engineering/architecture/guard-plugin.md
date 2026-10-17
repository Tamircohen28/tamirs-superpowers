# The guard plugin — in-process holds, shipped separately

`plugins/guard` is a second plugin in this repository: `tamirs-superpowers-guard`, a module
of Claude Code function hooks ("mods", Claude Code ≥ 2.1.287) that **holds** a destructive
shell command until the person answers and **refuses** a file write in the main checkout
while an orchestration objective is active. It is installed from the in-repo marketplace,
versioned in lockstep with the core plugin, and never enters the Claude-only distribution
Anthropic's plugin directory reads. This page records why it is separate, what it holds and
denies, how it relates to the bash guards, and how it is tested.

The core plugin's own mod is documented in [`mods.md`](mods.md); this page assumes it.

## Why a second plugin

[`mods.md`](mods.md#what-the-plugin-directory-requires-of-it) lists the rules Anthropic's
plugin directory applies to a mod. Two of them are about what a hook may *answer*:

| Rule | What trips it |
|---|---|
| `MOD_HOOKS_POLICY_EVENT` (held) | a hook at a site whose answer can refuse what was asked — a `tool.call` hook that may return `{ deny }` |
| `MOD_ANSWERS_PERMISSION` (held) | a hook that answers for the person — a `tool.check` verdict, or a hold the plugin resolves itself |

The core mod meets both by never denying: its `tool.call` hook counts writes and calls
`next(e)`, its `agent.spawn` hook counts a worker and calls `next(e)`, and its four gating
registrations carry a pass-through `.catch` so even a failure cannot read as a refusal. That
is what keeps the core plugin's `calls:` line clean and its listing unheld.

A guard is the opposite: refusing is its job. The
[V5 plan](../roadmap/v5-upgrade-plan.md#enhancements-mods-make-possible-that-bash-hooks-cannot)
put the in-process hold and the main-checkout deny in the "changes the footprint" group and
recommended the structural answer rather than a refusal — ship them as a **separate
marketplace plugin** with its own `hooks/hooks.json` `modules`, so the core plugin keeps its
footprint while people who want the holds install the guard from the marketplace, where the
directory's holds do not apply. The spec allows one module per `hooks/hooks.json`, which is
why the split is at plugin granularity rather than a second file in `mod/`.

Three consequences follow and are enforced by `tests/test-guard-plugin.sh`:

- `plugins/guard/hooks/hooks.json` is `{ "modules": ["./register.tsx"] }` and nothing else.
  No bash hook rides along, so installing the guard never doubles a core hook.
- `.claude-plugin/marketplace.json` lists the guard at `./plugins/guard`. That is the one
  install path. `scripts/build-dist.sh`'s `claude` target roots never include `plugins/`,
  so the Claude-only distribution — and therefore the directory — never sees it.
- `plugin-version.json` names `plugins/guard/.claude-plugin/plugin.json` as a consumer, so
  one release moves both versions and `check-version-truth.sh --sync` keeps them equal.

## What it holds and denies

### 1. Destructive-command hold (`hold_destructive_commands`, default on)

`on('tool.call', { tool: 'Bash' }, …)`. The command is split at `&&`, `||`, `;`, `|` and
newlines and each piece is judged on its own; leading `sudo`/`command`/`exec`/`env`/
`nohup`/`time` and `VAR=value` assignments are dropped. The vocabulary is deliberately
conservative — a command not listed is never held, and a listed one is held only in the
spelling that destroys:

| Rule name | Held | Not held |
|---|---|---|
| `force push` | `git push --force`, `-f`, `--force-with-lease[=…]`, `--force-if-includes`; global options before `push` (`git -C x push …`) | `git push origin main` |
| `git branch -D` | `-D` (in any flag cluster); `--delete`/`-d` together with `--force`/`-f` | `git branch -d merged` |
| `git worktree remove --force` | `remove` with `--force`/`-f` | `git worktree remove path` |
| `git reset --hard` | `--hard` | `git reset --soft`, `git reset HEAD file` |
| `git clean -f` | `--force` or an `f` cluster (`-fd`, `-xdf`) | any with `-n`/`--dry-run` |
| `rm -rf outside a temp directory` | recursive (`-r`/`-R`/`--recursive`) **and** force (`-f`/`--force`) with at least one operand that is not clearly temp | every operand under `/tmp/`, `/private/tmp/`, `/var/folders/`, `/private/var/folders/`, or a variable whose name says temp (`$TMPDIR`, `"$tmp"`, `${TMPROOT}`); `rm -r x`, `rm -f x` |
| `git checkout -- .` | `checkout` with the operand `.` | `git checkout -- file`, `git checkout branch` |
| `git restore .` | `restore` with the operand `.`, unless `--staged`/`-S` without `--worktree`/`-W` | `git restore --staged .` (only unstages) |

On a match the hook calls `$.ui.ask` — the engine's own `AskUserQuestion` dialog — with the
rule's name, the command (one line, cut at 160 characters) and the options **Proceed** and
**Cancel**. Proceed → `next(e)`. Cancel → `{ deny: 'tamirs-superpowers-guard: <rule>
cancelled at the hold: <command>' }`. Dismissing the dialog (Esc) on a surface that drew it
counts as Cancel: the person was asked and did not say Proceed.

**Where nothing can draw the dialog** — `$.session.surfaces()` is empty under `claude -p`,
the Agent SDK and any session with no surface — the call goes through unheld and
`$.ui.log(…, { to: 'debug' })` records it. A hold the person cannot answer must not become a
silent deny; the bash guards are still there. The hook judges *before* `next`, so a hold is a
pause in front of the call, never an undo after it, and the person's time in the dialog is a
`$` call in flight, which the 10-second hook budget does not count.

**What it cannot see**, stated as `guard-sensitive-files.sh` states its own gap: a command
inside quotes (`bash -c '…'`, a `trap '…'` string, a heredoc piped to a shell) is one word to
the splitter and is not held; `find … -delete`, `git push origin +main` and other spellings
outside the table are not held. The hold is a convenience on the common shapes, not a
sandbox.

### 2. Main-checkout write deny (`deny_main_checkout_writes`, default on)

`on('tool.call', { tool: /^(Edit|Write|MultiEdit|NotebookEdit)$/ }, …)`. The matcher is a
RegExp rather than a list because `MultiEdit` is not in 2.1.302's built-in tool table (it was
folded into `Edit`) and the list form types against that table; the RegExp keeps the name
for a build that still registers it. The target is `file_path`, or `notebook_path` for
`NotebookEdit`. The hook refuses when **all** of the following hold, and passes to `next(e)`
otherwise:

1. `$.session.root()` equals `$.session.repo().root` — the session sits in the **main
   checkout**. In a linked worktree the two differ (`repo().root` is the main working tree),
   and every write from there, even one back into the main checkout, is the bash hook's to
   judge.
2. The target resolves inside the repository. Both sides are resolved the same way with
   `$.fs.stat(path, { resolve: true }).realPath` (symlinks and `..` folded); a file not there
   yet is placed by its nearest existing ancestor. A path that cannot be placed passes — this
   mirror refuses only what it can show.
3. The target is **not** under `.dev-files/` (objective state, handoffs), **not** inside an
   agent worktree (`.agent-worktrees/<objective>/…`, `SUPERPOWERS_AGENT_WORKTREE_ROOT`, or a
   legacy `.claude/.worktrees`, `.cursor/.worktrees`, `.codex/.worktrees`, `.claude/worktrees`
   shape — the same set `hooks/lib/objective-common.sh` recognises), and the repository is
   not the Claude config directory (`CLAUDE_CONFIG_DIR` or `~/.claude`, the carve-out
   `enforce-worktree-edits.sh` makes for its versioned backup).
4. An objective is active: `SUPERPOWERS_OBJECTIVE_ID` wins; else the first
   `<repo>/.dev-files/objectives/*/objective.json` (or `SUPERPOWERS_OBJECTIVE_STATE_DIRNAME`)
   whose `status` is `active` — the reading of `objective-common.sh`'s
   `active_objective_id`. A completed or abandoned objective is not active.

The reason is the bash hook's own sentence, prefixed with the plugin's name:

> tamirs-superpowers-guard: Repo edits must happen in an objective worktree, not the main
> checkout (/repo). Objective 'obj-1' is active: work in /repo/.agent-worktrees/obj-1/task-NNN
> (worker) or .../integration (integrator). Ask the orchestrator which one is yours — do not
> create a new worktree.

### 3. `/guard`

Registered in `session.start` (`immediate`, so it answers mid-turn). Prints both options'
current values, what each does, and this session's counts from `$.state`: holds raised,
holds cancelled, the last hold (rule, answer, command), writes refused and the last one
(path, objective). Nothing is persisted; the counts restart with the session.

## The bash guards stay canonical

| Bash hook (core plugin) | Runs on | The guard plugin's relation to it |
|---|---|---|
| `hooks/enforce-worktree-edits.sh` | Claude Code, Codex, Cursor (`platforms/cursor/hooks.json`) | **Mirror.** Same verdict and same reason for the one case the mod judges (main checkout, objective active, target in the repo). The bash hook also handles the single-task model (`~/.claude/worktrees/<repo>/<slug>`), recreates a removed session worktree, and carries the degraded path for disposable checkouts — none of which the mod attempts. |
| `hooks/guard-sensitive-files.sh` | Claude Code, Codex, Cursor | **Complement.** That hook keys on write *targets* (lockfiles, workflows, build output) whatever tool writes them; the mod keys on the *command* and holds rather than denies. A bash PreToolUse hook can deny; only an in-process hook can pause for an answer. |

Nothing here replaces a bash hook. Where the mod cannot load — an org with
`allowManagedModsOnly`, `--safe-mode`, a VS Code chat panel, any non-Claude platform — the
bash hooks are what runs, exactly as before the guard existed. Both `tool.call`
registrations carry `.catch(($, e, next) => next(e))`: a hook that throws or outruns its
budget lets the call through rather than refusing it, which `claude plugin validate` reports
as *gating hook with `.catch`* for each. That line is expected for this plugin.

## Options

| Option | Type | Default | Read by |
|---|---|---|---|
| `hold_destructive_commands` | boolean | `true` | the `Bash` hook; off, every command passes with no dialog |
| `deny_main_checkout_writes` | boolean | `true` | the write hook; off, every write passes |

Neither is sensitive. Set them in `/config` (listed under the plugin's name) or from the
shell with `claude plugin configure tamirs-superpowers-guard`; a change reloads the module
with the new values.

## State contract

`types/index.d.ts` declares `PluginState['tamirs-superpowers-guard']`: `holds`,
`cancelled`, `lastHold` (`GuardHold`: command, rule, answer ∈ proceed | cancel | dismissed |
unasked, at), `deniedWrites`, `lastDeniedWrite` (`GuardDeniedWrite`: path, objectiveId, at).
The manifest names it as `types`; `claude plugin validate` holds every `$.state` key the
module names to it.

## How to test

```bash
claude plugin validate plugins/guard/.claude-plugin/plugin.json   # hooks, calls, env reads, state keys, gating hooks
claude plugin test plugins/guard                                  # plugins/guard/hooks/guard.test.tsx, 19 tests
bash tests/test-guard-plugin.sh                                   # shape and footprint; runs both of the above when claude is on PATH
```

`claude plugin test` runs `plugins/guard/hooks/guard.test.tsx` against the engine itself. The test's `on`
hooks sit beneath the plugin and stand for the engine: `fs.*` over an in-memory disk whose
`realPath` is the path itself, `session.root`/`session.repo`/`session.surfaces` as the case
needs, and one `tool.call` bottom that answers `$.ui.ask`'s `AskUserQuestion` call with the
label the case picks (or rejects it, for a dismissal) and records every other call that
reached the engine. The cases: a force push held and refused on Cancel / run on Proceed /
refused on Esc; `git status` and the not-held spellings never ask; `rm -rf /tmp/x` passes
and `rm -rf ./src` is held; each vocabulary entry under its own name; `claude -p` (no
surface) lets the hold through with a debug line; the option off passes everything; a
main-checkout write with an objective active is refused with the worktrees named, for
`Write`, `Edit` and `NotebookEdit`; no objective, a completed objective, a path outside the
repo, `.dev-files/`, an agent worktree, a linked-worktree session, no repository, and the
option off all pass; `SUPERPOWERS_OBJECTIVE_ID` activates with nothing on disk; and `/guard`
reports both options and the session's counts.

`tests/test-guard-plugin.sh` is auto-discovered by `make test-hooks` and asserts the
manifest, the one-module `hooks.json`, the marketplace entry, the `.catch` on every
`tool.call` registration, the absence of `$.process`/`$.http`/`$.prompt`/`prompt.submit`,
that `$` is handed to no helper, that no file names a model product, and — when the
`claude` CLI is on PATH — that validate and test pass. It also type-checks the module, the
contract and the tests with `tsc` against the build's `claude-code.d.ts` when `tsc` and a
copy of that file are present, found as `scripts/typecheck-mods.sh` finds it (the engine
lays it in `plugins/guard/.claude-plugin/types/` — gitignored — when an interactive session
loads the plugin with `claude --plugin-dir plugins/guard`), and skips with a notice when
either is missing.

## Changing it

The rules of [`mods.md`](mods.md#changing-it) apply unchanged: every `$` call at its call
site, `$` handed to no helper, string-literal event names, one unmatched registration per
event, `$.state` keys declared in the contract. Two more are the guard's own:

- **Every registration that can refuse carries `.catch(($, e, next) => next(e))`.** A guard
  that fails closed on its own bug would strand a session the bash guards were not going to
  strand. `tests/test-guard-plugin.sh` counts them.
- **Grow the vocabulary by the fact it reads, not by pattern.** Each entry names what it
  holds and what it leaves alone (`git clean -n`, `git restore --staged .`), and gets a row
  in the test table. A spelling that is not clearly destructive is not held.
