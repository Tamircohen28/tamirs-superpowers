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
  line under answers that wrote files.
- **Statusline** — context, rate-limit windows, cost and prompt-cache state on one line.
- **GitHub MCP server** — the official `github-mcp-server`, started with a token you provide.

## What it runs, sends and fetches

Nothing leaves your machine unless you turn a feature on and give it a credential:

- **Pushover phone notifications** (opt-in): set the `pushover_token` and `pushover_user`
  options and the plugin posts a short message, with up to 300 characters of Claude's last
  reply, to `api.pushover.net` when the session needs you or a long turn ends.
- **GitHub MCP server** (opt-in): set the `github_token` option and the plugin starts the
  official `github-mcp-server` binary (or its Docker image, pulled from `ghcr.io` on first
  use) with that token, which then talks to `api.github.com` for the session.
- **Semantic skill suggestion** (opt-in): set `semantic_skill_suggest` and a long prompt is
  classified by a small model through your own session's client.

Credentials are read only from those options, which the host keeps in its credential store.
The plugin never reads a token from your environment, from `gh`, or from a file. Full
details: [PRIVACY.md](PRIVACY.md).

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
