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
`scripts/github-mcp.sh`, which derives its token from `gh auth token`. There is **no token
to paste anywhere**, and no secret is ever committed — any credential in this repo is a
`${ENV_VAR}` placeholder.

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

[`opencode.json`](../../opencode.json) lists the skill directories OpenCode scans under
`skills.paths`. Add or remove domains there to change what OpenCode loads. Other platforms
discover `skills/` without configuration.

## Hooks

Hooks are Claude Code's mechanism ([`hooks/hooks.json`](../../hooks/hooks.json)) and run as
shipped only there. They automate worktree creation, edit isolation, sensitive-file guards,
changelog display on update, and session bookkeeping.

Elsewhere: Codex has a differently shaped manifest `hooks` field; Cursor runs project-level
`.cursor/hooks.json` guards and can opt into Claude hooks in its settings; Gemini CLI
documents hooks as an extension payload; OpenCode has no `hooks.json` at all. Where hooks do
not run, the same guarantees are enforced as explicit steps inside the skills and as checks
in CI — never assumed. Classification per platform:
[engineering/architecture/hooks-classification.md](../engineering/architecture/hooks-classification.md).

To disable a hook, remove its entry from `hooks/hooks.json` in your install and restart the
session.

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
- **auto-merge is a preference, not an invariant** — it is enabled only when the repository
  configuration and your preference both allow it, and never forced against branch
  protection or a required review;
- **branch-update-before-merge is loose by default** — strictness is a repository setting.

Without `gh`, delivery ends at a pushed integration branch and reports exactly that.

## Phone notifications (opt-in)

`/notify-setup` wires [Pushover](https://pushover.net) so an agent can reach you away from
the desk. Credentials are read from `PUSHOVER_TOKEN` / `PUSHOVER_USER` in the environment,
or from `~/.claude/pushover.env`. The hook is inert until configured. Details:
[phone-notifications.md](phone-notifications.md).

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
