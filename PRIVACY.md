# Privacy

What tamirs-superpowers sends off your machine, when, and to whom. The short version: **nothing, unless you turn a feature on and hand it a credential.** The plugin has no telemetry, no analytics, and no server of its own.

This file is the `privacyPolicyUrl` in [`.claude-plugin/plugin.json`](.claude-plugin/plugin.json). It covers every surface the plugin ships to: Claude Code, Claude Desktop, and the other platforms the repository's adapters target.

## Data that stays on your machine

- **Hooks** (`hooks/`) read the tool call or event they are given, and read and write files inside your checkout (worktrees, objective state under `.dev-files/`, handoff files). They make no network requests.
- **Skills and agents** are instructions for the model. They run inside your own Claude session and reach the network only through tools you have already allowed that session to use.
- **The mod** (`mod/register.tsx`, Claude Code 2.1.287+) draws panes and bands, counts workers, and reads objective state from disk. Its only outbound call is the Pushover one described below, and only when configured.
- **Usage capture** (`/usage-capture`, opt-in) writes JSONL files under `~/.local/share/tamirs-superpowers/` and sends nothing.
- **Statusline** reads the JSON Claude Code pipes to it and prints a line. Nothing leaves.

## Data that leaves, and only when you opt in

### Pushover phone notifications (off by default)

Enabled only when both `pushover_token` and `pushover_user` are set as the plugin's sensitive options. Then two things post to `https://api.pushover.net/1/messages.json`:

- `scripts/notify-pushover.sh`, on Claude Code's `Notification` event (the session needs your input), and
- the mod, when a main-session turn longer than `pushover_min_turn_seconds` finishes or dies on an API error.

Each message carries: a title made of `Claude Code —` and the name of your working directory, a priority, and a body of up to 1,024 characters. The body includes up to 300 characters of Claude's last message, converted to plain text. Set `PUSHOVER_INCLUDE_SNIPPET=0` in the shell that starts Claude Code to drop that excerpt from the hook's messages. Pushover's own handling of what it receives is governed by [Pushover's privacy policy](https://pushover.net/privacy).

The credentials themselves are read **only** from those two options, which the host keeps in its credential store. The plugin never reads `PUSHOVER_TOKEN` from your environment or a file on disk.

### GitHub MCP server (off by default)

The bundled `github` MCP server starts only when `github_token` is set as the plugin's sensitive option. The plugin passes that token, as `GITHUB_PERSONAL_ACCESS_TOKEN`, to exactly one process: the official `github-mcp-server` binary on your machine, or, when that is absent and Docker is present, the `ghcr.io/github/github-mcp-server` container, which Docker pulls from GitHub's registry on first use. That server then talks to `https://api.github.com` with your token on the session's behalf. The plugin never reads a token from `gh auth token`, `GITHUB_TOKEN`, or any file.

### Semantic skill suggestion (off by default)

With `semantic_skill_suggest` on, the mod sends the first 2,000 characters of a prompt of 12 words or more to a small model through your session's own model client, to pick a matching skill name. That request goes to the same provider your session already talks to, under the same account, and nowhere else.

## Data the plugin never collects

No session transcripts, file contents, prompts, or identifiers are collected, stored, or sent by the plugin for its own purposes. Nothing is sent to the plugin's author.

## Where to ask

Open an issue at <https://github.com/Tamircohen28/tamirs-superpowers/issues>, or see [`SECURITY.md`](SECURITY.md) for a private channel.
