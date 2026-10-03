# tamirs-superpowers

A portable agent toolkit for Claude Code and Claude Desktop: **29 skills**, 10 role-based
specialist agents, worktree-isolation hooks, a statusline, an in-process mod, and a bundled
GitHub MCP server, from one plugin.

This is the Claude-only distribution built for Anthropic's plugin directory. It is generated
from the canonical repository, which also ships the same skills to Codex, Cursor, Gemini CLI
and OpenCode. Source, issues and the full documentation:
<https://github.com/Tamircohen28/tamirs-superpowers>.

## What you get

- **Skills** — a development workflow that turns one objective into one pull request
  (`plan-dev`, `start-dev`, `orchestrate-dev`, `worker-dev`, `deliver-dev`, `pr-dev`,
  `switch-dev`), debugging (`targeted-debug`, `diagnose-refusal`), repository standards
  (`repo-scaffold`, `repo-standards`, `multi-agent-repo`, `github-policy`, `cleanup`), and a
  toolkit (`skill-creator`, `find-skill`, `retro`, `session-report`, `notify-setup`,
  `mcp-builder`, and more). Every skill states what it needs and degrades explicitly where a
  capability is missing.
- **Agents** — ten specialists (implementer, test engineer, security reviewer, …), each
  reading its contract from `core/roles/` and your project's own `CLAUDE.md`.
- **Hooks** — worktree isolation for parallel workers, sensitive-file guards, a Docker guard,
  session snapshots before compaction, a done-check on stop, and a desktop notification when
  the session needs you. All run locally; none makes a network request.
- **Mod** (Claude Code 2.1.287+) — a live objective pane and `/objective` command, a
  rate-limit band with a one-press handoff, usage figures on Desktop, and a definition-of-done
  line under answers that wrote files. It makes no network call and runs no process; what it
  does with what it sees is listed below.
- **Statusline** — context, rate-limit windows, cost and prompt-cache state on one line.
- **GitHub MCP server** — the official `github-mcp-server`, started with a token you provide.

## What it runs, sends and fetches

Nothing leaves your machine unless you turn a feature on and give it a credential:

- **Pushover phone notifications** (opt-in): set the `pushover_token` and `pushover_user`
  options and the Notification hook posts a short message, with up to 300 characters of
  Claude's last reply, to `api.pushover.net` when the session needs you. Only that hook
  sends; the mod does not.
- **GitHub MCP server** (opt-in): set the `github_token` option and the plugin starts the
  official `github-mcp-server` binary (or its Docker image, pulled from `ghcr.io` on first
  use) with that token, which then talks to `api.github.com` for the session.
- **Semantic skill suggestion** (opt-in): set `semantic_skill_suggest` and a long prompt is
  classified by a small model through your own session's client.

Credentials are read only from those options, which the host keeps in its credential store.
The plugin never reads a token from your environment, from `gh`, or from a file. Full
details: [PRIVACY.md](PRIVACY.md).

### What the hooks do with the calls they see

- `enforce-worktree-edits` and `guard-sensitive-files` run before `Edit`/`Write`/`Bash`:
  they allow the call, or deny it with a reason (a write outside the worker's worktree, a
  write to a secret, CI or lockfile path). They change no input and send nothing.
- `docker-guard` denies destructive Docker commands with a reason. `notify` raises a desktop
  banner; `notify-pushover` posts to Pushover only when both options are set.
- `session-init`, `precompact-snapshot`, `check-done`, `handoff-reminder`, `skill-suggest`
  and the worktree hooks read and write files inside your checkout (`.dev-files/`,
  `.agent-worktrees/`) and add short context lines. None makes a network request.

### What the mod reads and submits

- **Reads**: the objective, task and handoff JSON files under `.dev-files/objectives/` in
  your checkout, your project's `CLAUDE.md` (for a declared commit trailer line) and
  `.git/HEAD` (for the branch name), plus the usage and rate-limit figures Claude Code
  pushes to it. It counts file-writing tool calls; it does not read their contents.
- **Changes**: on `tool.call` and `agent.spawn` it only counts and passes the call through
  unchanged. On `attribution.text` it appends the commit trailer your project's `CLAUDE.md`
  declares, if any. On `session.compact` it adds the branch and objective to the
  compaction instructions. It registers one command, `/objective`.
- **Submits** (the mod's one `prompt.submit` call): one fixed prompt, only when you press
  **Write handoff** on the rate-limit band. The text names the rate-limit window and its percentage and asks the
  `switch-dev` skill to write the objective state to disk. Nothing else is ever submitted,
  and with `semantic_skill_suggest` on, a one-line note naming a matching skill is attached
  as context to your own prompt.

## Install

Add it from the directory on claude.ai, or in Claude Code:

```text
/plugin marketplace add Tamircohen28/tamirs-marketplace
/plugin install tamirs-superpowers@tamirs-marketplace
```

Then, optionally, open `/plugin` > tamirs-superpowers > **Configure** to set the options
above. The skills need no configuration.

## Surfaces

| Surface | Status |
|---|---|
| Claude Code (CLI) | Supported. Hooks, mod, statusline, MCP server and every skill. |
| Claude Desktop | Supported. Same plugin; the statusline does not draw (no terminal chrome) and the mod draws the usage figures in its place. |
| claude.ai (web) | Skills and agents. Hooks, the mod and the stdio MCP server are Claude Code and Desktop features. |

## License

MIT. See [LICENSE](LICENSE).
