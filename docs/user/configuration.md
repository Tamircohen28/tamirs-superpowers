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

### Where session worktrees live

Each session's worktree is `<root>/<repo>/<slug>` on branch `wt/<slug>`. The root is, in
order of precedence:

| Source | Example | Hosts |
|---|---|---|
| `SUPERPOWERS_WORKTREE_ROOT` env var | `export SUPERPOWERS_WORKTREE_ROOT=~/code/worktrees` | every host |
| `worktree_root` plugin option | `/plugin` > **tamirs-superpowers** > **Configure** | Claude Code (hooks see it as `CLAUDE_PLUGIN_OPTION_WORKTREE_ROOT`) |
| default | `~/.session-worktrees` | every host |

A leading `~` or `$HOME` is expanded. A relative path or `/` is ignored, and the next source
in the table applies.

**Why not `~/.claude/worktrees` any more.** Through 5.6.13 that was the only root. Claude Code
treats every `.claude` directory as a
[protected path](https://code.claude.com/docs/en/permission-modes.md): outside
`bypassPermissions` mode every write there prompts, and no `permissions.allow` rule can
pre-approve it. The worktree policy sends every edit into the session worktree, so that meant
a prompt on almost every edit. Pick a root outside any `.claude` directory if you set your own.

**Pick a root that holds nothing else.** The retention pass removes clean worktrees under
the root once they are older than `WORKTREE_RETENTION_DAYS` (3 days by default). Do not
point it at a directory of hand-made worktrees, or at `~/.agent-worktrees`, which is the
objective layout's name ([ADR 005](../engineering/decisions/005-session-worktree-root.md)).

**Existing worktrees keep working.** Edits under `~/.claude/worktrees/<repo>/<slug>` and
Claude Code's native `<repo>/.claude/worktrees/<name>` are still allowed, and a session that
already has a live worktree under `~/.claude/worktrees` keeps using it. New worktrees are
only created under the configured root.

**Moving the old ones.** `scripts/worktrees-migrate.sh` (or `make worktrees-migrate`) prints
what it would move and changes nothing. Add `--yes` to move:

```bash
bash scripts/worktrees-migrate.sh            # the plan
bash scripts/worktrees-migrate.sh --yes      # move the idle ones
bash scripts/worktrees-migrate.sh --yes --to ~/code/worktrees   # if you set worktree_root
```

It moves a worktree only when it is idle: no uncommitted changes, no live agent claim, no
unfinished objective task, no running process with its working directory inside, and nothing
changed in the last 60 minutes (`--idle-minutes`). Each one moves with `git worktree move`,
and the session-state records that named the old path are updated. Anything it skips is
listed with the reason. The `worktree_root` option reaches hooks only, so pass `--to` when you
set the root there and not through the env var.

Then, in each running Claude Code session, run `/plugin update` and `/reload-plugins` (or
start a new session) so its hooks use the new root.

### Worktree setup

When a worktree is created, the hooks:

- copy gitignored files matched by `~/.claude/defaults/worktreeinclude` and then the repo's
  own `.worktreeinclude` (for example `.env.local`, local credentials);
- assign a deterministic per-branch `DEV_PORT` in `.env.local` so parallel worktrees do not
  collide on a port;
- install dependencies in the background when a lockfile is present, skipping the work when
  the lockfile has not changed since the last install. Only installs that run no project
  code are run (`npm ci --ignore-scripts`, `pnpm`/`yarn`/`bun` with `--frozen-lockfile
  --ignore-scripts`, `cargo fetch`); an install that would run project code is printed for
  you to run yourself. `SUPERPOWERS_WORKTREE_INSTALL_DEPS=0` turns installs off.

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
- **auto-merge is a preference, not an invariant** — it is enabled only when the repository
  configuration and your preference both allow it, and never forced against branch
  protection or a required review;
- **branch-update-before-merge is loose by default** — strictness is a repository setting.

Without `gh`, delivery ends at a pushed integration branch and reports exactly that.

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

---

<p align="center"><a href="https://github.com/Tamircohen28">Have a Question?</a>&nbsp;·&nbsp;<a href="https://github.com/Tamircohen28/tamirs-superpowers/issues/new/choose">Open an Issue</a></p>
