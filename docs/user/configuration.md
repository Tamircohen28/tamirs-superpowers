# Configuration

Everything here is optional. The toolkit works with no configuration at all — the settings
below turn on features that need credentials, or adapt behavior to your project.

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

## Checking your configuration

```bash
bash scripts/doctor.sh .
```

Reports the detected platform, version drift, present and missing tools, which optional
features are consequently usable, and a remedy line for each gap.
