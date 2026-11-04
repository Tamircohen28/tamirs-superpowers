# Configuration

Everything here is optional. The toolkit works with no configuration at all — the settings
below turn on features that need credentials, or adapt behavior to your project.

There are two layers, and confusing them is the usual source of surprise:

| Layer | Lives in | Written by |
|---|---|---|
| **Project config** — MCP stubs, hooks, skill discovery, worktree behavior | this repo / your repo | you, in the files below |
| **Machine config** — global rules, permissions policy, agents, statusline | `~/.claude`, `~/.codex`, `~/.cursor`, `~/.gemini`, `~/.config/opencode` | `scripts/setup.sh`, rendered from canonical repo data |

This page covers the first layer, then explains how the second one is generated. Operating
instructions for the second: [setup](setup.md) and [platform setup](platform-setup.md).

---

## MCP servers

[`.mcp.json`](../../.mcp.json) declares a `github` server that shells out to
`scripts/github-mcp.sh`. Its token is the plugin's sensitive `github_token` option, which
the host passes to the server in the environment variable the official server reads — set it once in `/plugin`
> tamirs-superpowers > Configure, or with `claude plugin configure tamirs-superpowers`
(the gh CLI can print its own token if you want to reuse it). Leave it blank and the
server refuses to start with a message saying so; nothing else needs it. No secret is ever
committed — any credential in this repo is a `${user_config.KEY}` placeholder. The plugin
never reads a token off your machine: the Anthropic directory policy forbids it.

| Platform | Where MCP config is read |
|---|---|
| Claude Code | `.mcp.json` in the plugin |
| Claude Desktop | the Desktop app's own MCP settings |
| Codex CLI | `.codex/config.toml` |
| Cursor | `.mcp.json` |
| Gemini CLI | `mcpServers` in `gemini-extension.json` |
| OpenCode | `mcp` in `opencode.json` |

Verify yours parses: `jq empty .mcp.json`.

## Skill discovery (OpenCode)

[`opencode.json`](../../opencode.json) lists the skill directories OpenCode scans in its
`skills` array. Add or remove domains there to change what OpenCode loads. Other platforms
discover `skills/` without configuration.

## Hooks

Hooks are Claude Code's mechanism (the hook manifest) and run as
shipped only there. They automate worktree creation, edit isolation, sensitive-file guards,
changelog display on update, and session bookkeeping.

Elsewhere: Codex has a differently shaped manifest `hooks` field; Cursor runs project-level
`.cursor/hooks.json` guards and can opt into Claude hooks in its settings; Gemini CLI
documents hooks as an extension payload; OpenCode has no `hooks.json` at all. Where hooks do
not run, the same guarantees are enforced as explicit steps inside the skills and as checks
in CI — never assumed. Classification per platform:
[engineering/architecture/hooks-classification.md](../engineering/architecture/hooks-classification.md).

To disable a hook, remove its entry from the hook manifest in your install and restart the
session — except for the two groups below, which are switched by a plugin option instead.

### Hook tiers (`notification_hooks`, `contributor_hooks`)

Two plugin options switch whole groups of hooks on or off without editing the manifest.
Set them in `/plugin` > **tamirs-superpowers** > **Configure**, or from the shell with
`claude plugin configure tamirs-superpowers`. `/config` also lists them, but only in the
Claude Code CLI (2.1.269+) and only for non-sensitive options; Claude Desktop does not open
`/config` ("Repo drift" 3 in the
[Claude permissions research](../engineering/research/permissions/platforms/claude.md#repo-drift)):

| Option | Default | Hooks it switches |
|---|---|---|
| `notification_hooks` | on | the desktop notification (`notify.sh`), the Pushover phone notification (`notify-pushover.sh`), the VPN exit-node check (`ensure-exit.sh`) and the usage-capture collector start (`usage-capture-ensure.sh`) |
| `contributor_hooks` | off | the `/reload-plugins` reminder after a plugin-file edit (`plugin-reload-reminder.sh`), `report.md` link validation (`validate-report-links.sh`) and the hand-written `SKILL.md` guard (`skill-creator-guard.sh`) |

Turn `contributor_hooks` on when you work on this plugin or on agent configuration; for
everyone else those three are noise and stay off. Turn `notification_hooks` off for a
session that must not ping you — the safety, worktree and convenience hooks are not
affected either way. A hook's own opt-in still applies when its tier is on: the exit-node
check needs `CLAUDE_EXIT_PROXY`/`CLAUDE_EXIT_PUBLIC_IP`, the collector start needs
`TAMIRS_USAGE_CAPTURE`, and the phone notification needs both Pushover credentials.

Claude Code hands each option to the hooks as `CLAUDE_PLUGIN_OPTION_NOTIFICATION_HOOKS` /
`CLAUDE_PLUGIN_OPTION_CONTRIBUTOR_HOOKS` (`true`/`false`, `1`/`0`, `yes`/`no`, `on`/`off`).
Codex and Cursor have no plugin options, so there the defaults apply; a contributor on
either can export the variable by hand. Why these are options and not separate plugins:
[ADR 003](../engineering/decisions/003-hook-tiers-as-options.md).

## Worktree behavior

When a worktree is created, the hooks:

- copy gitignored files matched by `~/.claude/defaults/worktreeinclude` and then the repo's
  own `.worktreeinclude` (for example `.env.local`, local credentials);
- assign a deterministic per-branch `DEV_PORT` in `.env.local` so parallel worktrees do not
  collide on a port;
- install dependencies in the background when a lockfile is present, skipping the work if
  `node_modules` already exists.

Create a `.worktreeinclude` at your repo root — one glob per line — to control the first of
those. Branch and worktree layout: [`core/policies/git.md`](../../core/policies/git.md).

## Workflow state

Objective state is written to `.dev-files/objectives/<id>/`, which is **gitignored by
default** — it is scratch coordination state that names local paths and churns constantly.
A project that wants durable, reviewable workflow state can un-ignore
`.dev-files/objectives/` in its own `.gitignore`. Nothing depends on it being committed.

## Delivery policy

Defaults live in [`core/policies/delivery.md`](../../core/policies/delivery.md):

- **one objective = one PR** — extra PRs need a reason from the enumerated exception list;
- **auto-merge is off unless configured** — it is the action `pr.merge.auto`, decided by
  your [permission level](#permission-levels) (or a trusted repo file), enabled only when
  the repository allows auto-merge too, and never forced against branch protection or a
  required review;
- **branch-update-before-merge is loose by default** — strictness is a repository setting.

Without `gh`, delivery ends at a pushed integration branch and reports exactly that.

## Permission levels

The plugin's skills push branches, open PRs, comment, arm auto-merge, delete branches and
write config. The **permission level** decides which of those it does without asking you.
It governs **the plugin's own actions only**: no level widens what the host itself asks,
and `unattended` does not silence Claude Code's, Codex's or any other host's prompts. The
design, evidence and every rule below: [ADR 004](../engineering/decisions/004-permission-levels.md).

### The three levels

Every action the plugin can take has an id and a risk class R0–R4 in
[`core/permissions/actions.json`](../../core/permissions/actions.json): R0 reads, R1
changes this checkout, R2 is visible but routine (push your own branch, open a PR,
comment), R3 is hard to undo or merges and deletes, R4 is never automatic (releases,
tags, creating or deleting a repository, branch protection, host and policy config,
spawning another agent host, typing into a terminal: `tmux send-keys` with any global
option, `cmux send`, `wezterm cli send-text`, `kitty @ send-text`, `zellij action write`,
`osascript` keystrokes, `xdotool`). An action the catalog does not know is R4.

| class | `supervised` (default) | `standard` | `unattended` |
|---|---|---|---|
| R0, R1 | allow | allow | allow |
| R2 | ask | allow | allow |
| R3 | ask | ask | allow **only** for the listed actions below, and only while their precondition holds; otherwise ask |
| R4 | ask on the host prompt, per call, naming the target | same | same — never automatic |
| an explicit `deny`, a [safety invariant](../../core/policies/safety.md) | deny | deny | deny |
| `pr.merge.auto` (auto-merge) | ask | ask (= off) unless a file sets `actions["pr.merge.auto"]: "allow"` | allow when its precondition holds |

Under `unattended` only these R3 actions run without asking: `pr.merge.auto` (the PR has a
required check with a pinned source or a required review, and touches no workflow,
`CODEOWNERS` or `.tamirs-superpowers/` file), `branch.delete.remote` (the PR is merged, the
branch is not the default and not cross-repo), `pr.close` and `issue.close` (your own PR, or
the `Closes #N` of a merged one), `git.push.force` (your own branch, with
`--force-with-lease`) and `pkg.*` installs from a pinned lockfile. A precondition the plugin
cannot establish counts as not holding.

Auto-merge means `gh pr merge --auto` only, so GitHub's protection still decides; the plugin
never merges directly on its own.

**No human present, no ask.** A headless run (`claude -p`, CI, a host that cannot carry an
ask) turns every ask into a deny, and the deny names the setting that would allow it — the
durable one (no host ships a one-run `--perms=` raise today, see below), or, for R4, that no
setting allows it automatically.

**The R4 rule.** An R4 action is allowed only by the host's own permission prompt on that
very call, which shows the action, the target and its effect. No level, file, `--perms=`
ticket or environment variable makes it automatic, and a file may set an R4 id only to
`ask` or `deny`. On a host with no such prompt (below) an R4 call is denied with the command
for you to run yourself.

### Choosing a level at install

| platform | at install | change it later |
|---|---|---|
| Claude Code | the `permission_level` option in the install dialog: `supervised`, `standard` or `unattended` (default `supervised`) | `/plugin` > **tamirs-superpowers** > **Configure**, `claude plugin configure tamirs-superpowers` in your own terminal, or `/config` in the CLI only (2.1.269+; Desktop does not open it) |
| Gemini CLI | the `TS_PERMISSION_LEVEL` setting, prompted at `gemini extensions install` unless you pass `--skip-settings` (empty = `supervised`; anything else unknown = `supervised` with a warning) | `gemini extensions config tamirs-superpowers TS_PERMISSION_LEVEL` in your own terminal |
| Codex CLI, Cursor, OpenCode | no install-time option exists; `bash scripts/setup.sh apply --permission-level <level>` (or `SETUP_PERMISSION_LEVEL=<level>`), or answer the level prompt `setup.sh apply` shows on a terminal when one of them is in scope | `/plugin-config` to tighten in a session; to widen, `scripts/plugin-config.sh` in your own terminal or `setup.sh` again |

`setup.sh --permission-level` writes the user file below (0600, plus its lock) through the
one writer. A run with no terminal never prompts: without the flag it writes nothing; with
it, a level that widens nothing is written, while a raise is written only on your own
terminal after the writer shows it and you answer `y` — anywhere else (CI, a pipe, an
agent) it is recorded pending with the `confirm` command to run in your terminal (for CI
use `provision`, below). An existing file changes only after you confirm its diff on a
terminal.
`--only permission-level` runs that step alone, and `remove` leaves the file in place, since
it is your policy. For Claude Code and Gemini CLI, setup prints the host's own route instead
of asking twice. On Codex, `setup.sh apply --codex-rules` (or `SETUP_CODEX_RULES=1`) also
writes optional, user-owned execpolicy `prompt` rules for the R4 command forms at
`~/.codex/rules/tamirs-superpowers.rules` — a belt while the plugin's hooks are untrusted;
Codex marks rules experimental, so it is off unless you opt in, and `--no-codex-rules`
leaves an existing file alone.

**Which level applies.** The lower of the host's option (Claude `permission_level`, Gemini
`TS_PERMISSION_LEVEL`) and the user file's `level`. A source that is absent is skipped, so a
Claude install that chose `unattended` with no user file runs `unattended`, while
`unattended` in the option and `standard` in the file runs `standard`. Neither ⇒
`supervised`. A per-skill or per-group level (below) replaces the file's `level` for that
skill, but never escapes a lowering: a lower host option or environment switch caps it
too. The host is the one the plugin actually runs under: a hook that names another host
(say Gemini, because a repository's environment set `GEMINI_SESSION_ID`) gets the
stricter of the two answers, so Claude's option still caps it. A host below its permission floor (see [What is enforced
where](#what-is-enforced-where)) runs every level as `supervised`: the resolver clamps it and
says so in the answer, and `make doctor` warns about it.

### The files

| file | what it holds | who writes it |
|---|---|---|
| `~/.config/tamirs-superpowers/permissions.json` (0600, dir 0700) | your level, per-skill and per-group levels, per-action `allow`/`ask`/`deny`, repo trust entries | `/plugin-config`, `scripts/plugin-config.sh`, `setup.sh` |
| `~/.config/tamirs-superpowers/permissions.lock` | `{sha256, by, at}` of the file above | the same writer |
| `~/.local/state/tamirs-superpowers/` | short-lived pending records, staged confirms (`staged/`), tickets, call and confirm stamps, the active-skill contexts (`intent/`) and the cached host-version probe (`hostver/`) | the writer, the prompt hook, the guard, `permission-approved.sh` and the resolver |
| `<repo>/.tamirs-superpowers/permissions.json` | a committable project file: tightens, and may widen only auto-merge once trusted | you, by hand |

`~` here is your account's home from the passwd entry, never the session's `HOME` or
`XDG_*`, which a repository can set. Every reader requires the files to be yours, 0600 in
0700 directories, with no group- or world-writable parent and outside every git work tree.
Both files validate against [`core/schemas/permissions.schema.json`](../../core/schemas/permissions.schema.json):

```json
{ "version": 1, "level": "standard",
  "skills": { "pr-dev": "unattended" },
  "actions": { "pkg.install.network": "deny" } }
```

The most specific key decides: `skill_actions.<skill>.<id>` > `actions.<id>` > `skills.<id>` >
`groups.<g>`; any `deny` from any layer is final. **Do not hand-edit the user file**: a file
whose hash no longer matches its lock is read tighten-only — its denies hold, its allows and
raises are dropped — until you re-confirm it through `/plugin-config`. An invalid file runs
as `supervised` with a warning.

Environment switches only ever tighten — per-skill levels included: `TS_PERMISSION_LEVEL`,
`CLAUDE_PLUGIN_OPTION_PERMISSION_LEVEL`, `TAMIRS_AUTO_MERGE=never`; `TAMIRS_AUTO_MERGE=always`
is ignored with a warning naming the durable setting.

### Changing it later: `/plugin-config`

```text
/plugin-config show [<skill|group|action-id>]
/plugin-config <level>                          the global level
/plugin-config <skill|group> <level>            e.g. /plugin-config pr-dev unattended
/plugin-config <action-id> [<skill>] allow|ask|deny   e.g. /plugin-config pr.merge.auto allow
/plugin-config reset [<skill|group|action-id>|level|all]
/plugin-config trust                            trust this repo's project file
/plugin-config confirm <nonce>                  apply a pending widening or --perms= request
```

The command runs only when you type it — never on the model's own initiative. Every change
goes through one writer, [`scripts/plugin-config.sh`](../../scripts/plugin-config.sh), which
validates, writes atomically and re-locks. `show` prints each value with its source and
whether the file still matches its lock, the pending requests, the staged confirms that
are not active yet, and the active lowering tickets of every session. Every run of the
writer also deletes expired tickets and staged confirms (the resolver ignores an expired
ticket either way).

The writer compares every action's decision before and after the change:

- **A change that widens nothing** (a lower level, a `deny`) is written at once, from
  anywhere, in any session.
- **A change that widens anything** — a higher level, an `allow`, a `reset` that drops a
  deny, `trust` — is recorded **pending** with its rows and a nonce, and the writer exits 4
  printing `confirm <nonce>`. `confirm` passes only through a prompt the host itself shows
  you: on Claude Code the permission dialog on that very call, on Gemini CLI the extension's
  `ask_user` rule. Codex, Cursor, OpenCode and Claude Desktop have no such prompt, so there
  `confirm` is refused (exit 3) and the message names the command to run **in your own
  terminal**, outside any agent session:

  ```bash
  bash <plugin root>/scripts/plugin-config.sh standard
  ```

- It never writes an R4 `allow`, and never writes a host's option store: a Claude or Gemini
  level raise also prints the host route above, since the lower of the two applies.

**On Claude Code, `confirm` takes effect in two steps.** The dialog appearing proves only
that you were asked, not that you said yes, so the call you approve merely *stages* the
change (in `~/.local/state/tamirs-superpowers/staged/`, bound to that tool call's id), and
the plugin's PostToolUse hook ([`hooks/permission-approved.sh`](../../hooks/permission-approved.sh))
makes it active when that same call completes — Claude Code runs PostToolUse only for a
call that actually ran. You see *"the permission change you approved is now active"* right
after the call. If you press **No** (or Esc), the call never runs and nothing is staged or
applied. A staged change also never becomes active through any other call: the hook
promotes only the PostToolUse of the call the dialog was raised on, and only when that call
is the plain `plugin-config.sh confirm <nonce>` — not a wrapper around it, not another
command chained to it. A staged change that is never promoted lapses after 15 minutes;
`show` lists it meanwhile. On Gemini CLI `confirm` is still one step (the `ask_user` rule
is the prompt, and nothing ties a post-call hook to it yet).

**"Your own terminal" is checked, not assumed.** The writer applies a widening at once only
when nothing it can see says an agent is involved, and only after showing you the rows and
reading `y` on the terminal (`Apply it? [y/N]`; anything else, or no answer within five
minutes, writes nothing and exits 3). It refuses the direct route — recording the change
pending instead, with the `confirm` to run — when any of these holds:

- an agent host (Claude Code, Codex, Gemini CLI, Cursor, OpenCode, the Claude desktop app)
  is among its parent processes, or its environment carries an agent's marker;
- it was cut off from its own terminal session: started in the background by a double fork
  (`( … & )`, `nohup`, a daemon) or re-parented to the system's init process;
- it has no terminal: standard input is not a TTY, or `/dev/tty` cannot be opened (CI,
  `… </dev/null`, an agent's shell tool);
- its environment was cleared (`env -i`: no `HOME`, `PATH` or `TERM`);
- a program that can type into a terminal runs above it: `script`, `expect`, `unbuffer`,
  `socat`, `osascript`, or an interpreter such as `python`, `perl`, `ruby` or `node` (so
  run it from your shell, not from `poetry shell` or a Python wrapper);
- its parent chain cannot be read.

`make setup` and `setup.sh` go through the same writer, so a raise there shows the rows and
asks `y` once more on the terminal. None of this is proof that a person typed `y` — a
process running as you can still drive your terminal (the ADR's open risks) — but no
agent route reaches the immediate path without one of the signs above.

Exit codes: 0 done (or staged, on Claude Code), 1 failed, 2 usage error, 3 refused, 4
recorded pending. Every subcommand takes `--json`. For CI, `plugin-config.sh provision
--level <level>` (or `--file <path>`) writes the file and lock in a workflow step
**before** the agent starts, with no prompt. It refuses inside an agent session, in a run
cut off from its session or with a cleared environment, without a CI marker (`CI`,
`GITHUB_ACTIONS`, `GITLAB_CI`, `BUILDKITE`, `TF_BUILD` or `JENKINS_URL`), and over a user
file it did not write itself; `show` marks such a lock `by: provision`.

### One run: `--perms=<level>`

A `--perms=<level>` token on the first line of a slash command (`/pr-dev 42
--perms=standard`) asks for a different level for that one skill and target. It is read
only as a standalone token you typed, never from file, PR, issue or tool output. The
permission guard applies the resulting ticket on every call it judges
([`resolve-permission.sh`](../../scripts/resolve-permission.sh), precedence row 1).

- **Lowering** (`--perms=supervised`) needs no proof: the prompt hook on Claude Code, Codex
  CLI and Gemini CLI records it as a lowering ticket at once, and it holds for the rest of
  the session (24 hours at most) — for that skill when the token was on a Claude Code slash
  command, for the whole session on Codex and Gemini — on every agent and target, and over
  any raise. Cursor and OpenCode have no prompt hook for it; there only a skill's own check
  reads the token.
- **Raising is disabled on Claude Code today.** The prompt hook would record a pending
  request only for a prompt the host attests you typed (`UserPromptSubmit.source ==
  "user"`), and Claude Code does not send that field at all (measured on 2.1.318, in the
  interactive CLI, `claude -p` and the SDK). So every `--perms=` raise there is refused with
  a note that says *Claude Code does not send prompt origin; use /plugin-config to set a
  durable per-skill level* — `/plugin-config pr-dev standard` gets you the same effect for
  every run of that skill (see [Per-skill levels](#per-skill-levels)). The fail-closed path
  stays in place, so the raise comes back unchanged once the host sends the field: then the
  request becomes a ticket only after `/plugin-config confirm <nonce>` passes the host
  dialog, which shows the skill, level, target and expiry (and, as above, only once that
  approved call completes), and the ticket lets that skill's
  actions on that target run at the requested level for **15 minutes**: R2 at `standard`,
  and at `unattended` also the listed R3 actions whose precondition holds. A ticket never
  covers R4, never lifts a `deny` from any file or the environment, and binds to the
  session and the agent that typed it: Claude Code marks every subagent call with its own
  agent id, so a subagent's call never gets the main thread's ticket. A confirmed raise
  does not retire an active lowering of the same session for that skill: the lowering
  still wins until it expires, and `confirm` says so.
- **The target** is the slash command's first argument plus this checkout's repository.
  `/pr-dev 42` covers PR (or issue) #42 there and repository-level steps in that repository
  (create an issue or a label, rerun CI). It does not cover another PR, another repository,
  `gh pr create` (no number yet) or a branch push: a ticket names no branch, so those still
  ask.
- **Disabled** as a raise on Codex, Cursor, OpenCode and Claude Desktop, and on Gemini CLI
  until its skill-pairing hook is wired: nothing there can prove you typed it, so
  `--perms=` only lowers and the note names the out-of-session route
  (`scripts/plugin-config.sh` in your own terminal).

Use `/plugin-config` for a durable change.

### Per-skill levels

`skills.<id>` and `groups.<g>` in your user file (`/plugin-config pr-dev standard`) set a
level for one skill or one category. Such a level **lowers** whenever that skill is running.
It never rises above a lower host option (Claude `permission_level`, Gemini
`TS_PERMISSION_LEVEL`) or a lowering environment switch. It **raises** the guard's answers
only when all of these hold:

- the user file is your own, verified against its lock (a hand-edited file is read
  tighten-only, so its raises are dropped);
- Claude Code itself recorded the skill as active: either you typed its slash command (the
  host's `UserPromptExpansion`, paired with the `UserPromptSubmit` of the same prompt by
  their shared `prompt_id`) or the agent invoked it with the `Skill` tool (a `PreToolUse`
  the plugin's `Skill` matcher records); it does not need the prompt's origin, which Claude
  Code does not send;
- the call is that agent's: a skill the main thread runs never raises a subagent's call, a
  subagent's skill never touches the main thread's, and a subagent never runs above the main
  thread's level (it is judged under both and the stricter answer stands).

The skill stays active for that agent until its next slash command or `Skill` call, or the
end of the session. A project file's `skills`/`groups` only ever lower. On every other host a
per-skill raise is advisory (the skill's own check) or not wired; see the table below.

### Auto-merge for one repository

To let the plugin arm auto-merge in one repository without raising your global level,
commit a project file:

```json
{ "version": 1, "actions": { "pr.merge.auto": "allow" } }
```

at `<repo>/.tamirs-superpowers/permissions.json`, then run `/plugin-config trust` in that
checkout. Trust records the file's sha256 under the repository's real path and its `origin`
in your user file, and it is a widening, so it needs the confirm above. From then on the
widening applies only to PRs whose repository equals both the recorded remote and the
checkout's `origin`. A changed hash or a fresh clone drops the widening with a notice until
you trust it again. A project file may always tighten (`deny`, a lower `level`), trusted or
not; it can never widen anything other than `pr.merge.auto`.

The legacy inputs only tighten: `.dev-files/policy.json` `delivery.auto_merge: false` acts
as `pr.merge.auto: deny` (and `true` is ignored with a warning, for one minor release), and
an objective's `delivery.auto_merge: false` denies while `true` grants nothing.

### What is enforced where

**ENFORCED** means a hook or host rule stops the call even if the model ignores the skill's
instructions; **ADVISORY** means only the skill's own check stands, which a model can skip.
The skill-level check (L1) is advisory on every platform; the table is about the layers
under it.

| platform | shell commands | GitHub MCP tools | host prompt for asks and R4 | per-skill levels | `--perms=` | floor |
|---|---|---|---|---|---|---|
| Claude Code | ENFORCED: `permission-guard.sh`, fail closed | ENFORCED: the MCP matcher fires for the bundled server's tools (measured), plus server flags | ENFORCED: the hook `ask` dialog, in every permission mode (measured: the reason verbatim, Yes/No, Esc rejects); headless ⇒ deny | lowering ENFORCED; a raise from your locked user file ENFORCED once the host records the skill for that agent | lowering ENFORCED; no raise (the host sends no prompt origin) | 2.1.317 |
| Claude Desktop | unverified | server flags | unverified | ADVISORY | no raise; lowering unverified | as Claude Code |
| Codex CLI | ENFORCED, deny only | server flags | none: an R4 call is denied with the command to run | ADVISORY | lowering ENFORCED, session-wide; no raise | 0.166.0 |
| Cursor | ENFORCED, deny only, `failClosed` | ENFORCED, deny only | none yet: R4 is denied | ADVISORY | no prompt hook: ADVISORY | CLI 2026.10.22 / app 3.27.22 |
| Gemini CLI | ENFORCED, deny only, plus static policy rules | hook plus static rules | ENFORCED: static `ask_user` rules for R4 and `confirm` | not wired yet | lowering by hook, session-wide; raise not wired yet | 0.66.0 |
| OpenCode | ENFORCED when it is the only plugin (plugin order is unmeasured) | unmeasured | ADVISORY: `opencode --auto` approves an ask, so only R2 asks; R3 and R4 deny | not wired yet | no prompt hook: ADVISORY | 2.2.5 |

The same facts, per surface, are the `permission_levels` rows of
[`core/capabilities/platforms.json`](../../core/capabilities/platforms.json). The floor is
the host version the level semantics were measured or source-cited on
([`platform-targets.json`](../engineering/build-and-release/platform-targets.json)
`permissions_min`, and `permissions_min_cli` for `cursor-agent`). `make doctor`
([`scripts/doctor.sh`](../../scripts/doctor.sh)) compares every host CLI on your PATH with
its floor — `cursor-agent` against the CLI floor, the Cursor app against the app's (read
from the app bundle, never by launching it) — and below it warns, naming what the floor
stands for (for Claude Code also the lower floors: `onFailure: "block"` from 2.1.295, the
install dialog's `permission_level` picker from 2.1.271). Each probe has a 3-second
deadline; a version that is unreadable or does not answer in time is a warning only.

The resolver enforces the floor: with `--host` (the guard always passes it), a host CLI
below its floor runs every level above `supervised` as `supervised`, and the answer and
`--level` say so (`host floor (D9)`). It reads the version as `doctor` does — the host
CLI's `--version` on your PATH (`cursor-agent` for Cursor), under the same 3-second
deadline — only when an answer would be looser than `supervised`'s, so a `supervised`
call and the guard's fast path never run it; the result is cached per session in
`~/.local/state/tamirs-superpowers/hostver/` for 10 minutes or until the binary changes. A
version it cannot read is a warning, never a clamp.

The guard reads the default branch and the required checks from GitHub through `gh` with a
3-second deadline; a condition it cannot establish in time takes the stricter answer. The guard and the resolver themselves fail closed: a missing, crashing or unparseable
resolver is a deny for R2 and above.

The GitHub MCP server starts with the tool set your level allows
([`scripts/github-mcp.sh`](../../scripts/github-mcp.sh); `github-mcp.sh --print-flags`
prints what it would pass and why, starting nothing): `supervised` ⇒ `--read-only`;
`standard` and `unattended` ⇒ every tool except merge, repository create/delete/fork and the
tools whose arguments can reach R3/R4 (file writes, `issue_write`, `update_pull_request`,
`pull_request_review_write`). Merging through MCP is excluded at every level. The flags are
fixed for the server's lifetime, so a level change mid-session reaches the MCP tool set at
the next session. The server binary, which receives your token, is never looked up on
`PATH` (a repository's environment can change it): it is the first acceptable
`github-mcp-server` in `/opt/homebrew/bin`, `/usr/local/bin`, Linuxbrew's `bin` (its
default prefix), `~/.local/bin` or `/usr/bin` — then `docker` from the
same places or Docker Desktop's — and a binary owned by another user, writable by group or
others, or in a world-writable directory is refused (`--print-flags` shows the choice and
what it refused).

Channels outside the plugin — another GitHub MCP server, `gh` run by another tool, browser
automation on github.com — are governed by no level.

### For scripts: the resolver and the merge policy

[`scripts/resolve-permission.sh`](../../scripts/resolve-permission.sh) is the one
implementation of every decision above; the guard, the skills and `/plugin-config show` all
call it.

```bash
resolve-permission.sh <action-id> [--skill <id>] [--target <t>] [--repo <path>] \
  [--host claude|codex|cursor|gemini|opencode] [--headless] [--objective <id>] \
  [--session <id> [--agent <id>]] [--call <token>] [--cond <name>=true|false ...] \
  [--explain] [--json]
resolve-permission.sh --level [--skill <id>] [--host <h>] [--repo <path>] [--session <id> [--agent <id>]]
```

It prints one JSON verdict (`verdict` allow/ask/deny, `r`, `level`, `level_source`,
`decided_by`, `reason`, `precondition`, `setting_that_would_allow`, `warnings`, …).
Without `--host` a host option may only lower the level. `--cond` passes a precondition the
caller established; one not passed never holds. `--session` (and `--agent`, default `main`)
reads that session's `--perms=` tickets, and `--target` names what the call acts on — a PR
or issue number or `.` (the repository `gh` would use), `<owner>/<repo>[#n]`, a PR or issue
URL — which a raise ticket must match; `ticket` in the output names the one that decided.
`--level` also lists the active lowering tickets (`lowering_tickets`: the session's with
`--session`, every session's without), and a `host_floor` entry in `level_sources` reports
the D9 check when it ran. `--explain` prints a readable trace. Exit 0
is a decided verdict; 2 (usage) and 3 (internal error) also print a deny, and a caller that
gets anything else must deny.

[`resolve-merge-policy.sh`](../../skills/dev-workflow/pr-dev/scripts/resolve-merge-policy.sh)
`[--repo <owner/name>] [--host <h>] <PR> [objective]` asks the resolver for `pr.merge.auto`
and answers `auto_merge: enable` only when the verdict is allow **and** the repository
allows auto-merge; the default is `skip`. `--host` is passed through to the resolver. Its
JSON now also carries `auto_merge_verdict` (`allow`, `ask`, `deny`, `error` or `not-asked`)
and `auto_merge_allow_with` (the durable setting that would allow it, or `null`), beside
`auto_merge_source`.

## Phone notifications (opt-in)

`/notify-setup` sets up [Pushover](https://pushover.net) so an agent can reach you away from
the desk. The hook ships in the hook manifest; the credentials are the plugin's sensitive
`pushover_token` / `pushover_user` options and nothing else — no environment variable, no
dotfile. The hook is inert until both are set, and silent whenever the `notification_hooks`
option above is off. Details: [phone-notifications.md](phone-notifications.md).

## Statusline

Claude Code only, and cosmetic — nothing depends on it. It is wired automatically through
the plugin manifest's `settings.statusLine`. If it does not appear, see
[troubleshooting](troubleshooting.md#the-statusline-does-not-appear).

## Machine config: how `platforms/claude/settings.d/` works

`~/.claude/settings.json` is **rendered**, not hand-maintained. Its source is seven JSON
fragments in [`platforms/claude/settings.d/`](../../platforms/claude/settings.d/), each a
partial `settings.json` object holding only the keys it owns:

| Fragment | Owns |
|---|---|
| `defaults.json` | `$schema`, `model`, `effortLevel`, `theme`, `tui`, `permissions.defaultMode`, the UX booleans |
| `permissions-allow.json` | the whole `permissions.allow` policy |
| `permissions-ask.json` | the whole `permissions.ask` policy |
| `auto-mode.json` | `autoMode.soft_deny` |
| `misc.json` | `skillOverrides`, `disableClaudeAiConnectors`, `disabledMcpjsonServers`, `env` |
| `plugins.json` | `enabledPlugins` — recorded per key, `false` included |
| `marketplaces.json` | `extraKnownMarketplaces` |

The engine strips `_`-prefixed keys, deep-merges the fragments in filename order into one
object, then deep-merges that over your existing `~/.claude/settings.json`. Splitting
`permissions` across three files only works because the merge is deep; a shallow merge would
drop two of the three.

**Change the fragment, not the machine file.** Hand-editing `~/.claude/settings.json` is not
the workflow — the next `apply` merges the fragments over it, and your edit is either
overwritten or silently diverges. If you have already hand-edited something and want to keep
it, [capture](capture.md) is the reviewed path back into the repo.

### `_`-prefixed keys are documentation, and stop at the boundary

JSON has no comments, so each fragment explains itself in top-level keys beginning with `_`
— `_comment` for the rationale, `_tally` for counts that would otherwise have to be trusted.
They exist so the next person to read the fragment knows *why* an entry is there.

Every `_`-prefixed key is **stripped at the merge boundary**. Nothing beginning with `_`
ever reaches your `~/.claude/settings.json`, any other platform's config file, or a captured
hunk on the way back into the repo. That is what makes it safe for a fragment to explain
itself at length, and to name the third-party tool whose wiring a fragment deliberately
leaves alone, without that prose becoming part of your configuration.

The same convention applies to the per-platform fragments in `platforms/<target>/templates/`.

### Objects merge; arrays and scalars are asserted

Two different rules, and the difference is deliberate:

- **Objects recurse, key by key.** This is what keeps configuration you did not write alive.
  `hooks`, `enabledPlugins`, `extraKnownMarketplaces` and `mcpServers` are all object-shaped,
  so entries another tool wrote survive an `apply` untouched. (Before this, `install.sh`
  rewrote `~/.claude/settings.json` wholesale and destroyed every key it did not know about.)
- **Arrays are replaced wholesale, never appended to.** `permissions.allow` in the fragment
  is the *whole* intended allow policy, not an addition to whatever is on disk.

Union is the tempting choice for arrays and it is the wrong one, for a reason worth stating
plainly: **union would make a permission impossible to retract.** Delete an entry judged too
broad from `permissions.allow` in the repo, and under union it would remain live forever, on
every machine that had ever applied it, invisible to everyone. Asserting also keeps each
fragment an honest description of its own result — read the file and you know what the
merged output contains — which is the property that makes the directory reviewable at all.

Your own incremental additions are not at risk, because they have a home upstream of this
installer: **`~/.claude/settings.local.json`**, which setup never reads or writes and which
Claude Code merges on top of `settings.json`. An interactive "always allow" grant lands
there already.

### The other four platforms

Same engine, different formats: one canonical [`core/global-rules.md`](../../core/global-rules.md)
rendered into `~/.codex/AGENTS.md`, `~/.gemini/GEMINI.md`, `~/.cursor/rules/tamirs-superpowers.mdc`
and `~/.config/opencode/AGENTS.md`, each inside `>>> tamirs-superpowers >>>` markers so
everything outside them stays yours, plus a small asserted fragment in each platform's config
file. What each one writes — and what it deliberately does not, Codex hook entries and
`permissions.deny` above all — is in [platform setup](platform-setup.md).

## Checking your configuration

```bash
bash scripts/doctor.sh .
```

Reports the detected platform, version drift, present and missing tools, which optional
features are consequently usable, and a remedy line for each gap.
