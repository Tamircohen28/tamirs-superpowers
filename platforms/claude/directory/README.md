# tamirs-superpowers

A portable agent toolkit for Claude: the plugin's skills, 10 role-based specialist agents and
an evidence-first output style, from one plugin.

This is the directory edition, built for Anthropic's plugin directory from the canonical
repository. It ships the skills, agents and output style only: no hooks, no mod, no MCP server
and no statusline command. The full plugin, with worktree-isolation hooks, a permission guard,
a statusline, an in-process mod and a bundled GitHub MCP server, installs from the
tamirs-marketplace (see Install). Source, issues and the full documentation:
<https://github.com/Tamircohen28/tamirs-superpowers>.

## What you get

- **Skills** — a development workflow that turns one objective into one pull request
  (`plan-dev`, `start-dev`, `orchestrate-dev`, `worker-dev`, `deliver-dev`, `pr-dev`,
  `switch-dev`), debugging (`targeted-debug`, `diagnose-refusal`), repository standards
  (`repo-scaffold`, `repo-standards`, `multi-agent-repo`, `github-policy`, `cleanup`), and a
  toolkit (`skill-creator`, `find-skill`, `retro`, `session-report`, `mcp-builder`, and more).
  Every skill states what it needs and degrades explicitly where a capability is missing.
  Phone notifications (`notify-setup`) need hooks and come with the full plugin only.
- **Agents** — ten specialists (implementer, test engineer, security reviewer, …), each
  reading its contract from `core/roles/` and your project's own `CLAUDE.md`.
- **Output style** — `Evidence`: answers that cite the command, file or output behind each
  claim. Opt in with `/output-style Evidence`.

## What it runs, sends and fetches

Nothing runs on its own. This edition has no hooks, no mod and no MCP server, so nothing starts
when a session opens, when a tool is called or when the session ends. A skill runs a command
only when Claude runs it as part of the task you gave, through Claude Code's normal permission
prompts; the scripts a skill names ship inside the plugin and are readable as text. The plugin
reads no token from your environment, from `gh` or from a file, and sends nothing anywhere.
The privacy policy is in [PRIVACY.md](PRIVACY.md).

## Install

Add it from the directory on claude.ai. For the full plugin (hooks, permission guard, mod,
statusline, GitHub MCP server), in Claude Code:

```text
/plugin marketplace add Tamircohen28/tamirs-marketplace
/plugin install tamirs-superpowers@tamirs-marketplace
```

## Surfaces

| Surface | Status |
|---|---|
| Claude Code (CLI) | Supported: every skill, agent and the output style. |
| Claude Desktop | Supported: the same. |
| claude.ai (web) | Skills and agents. |

## License

MIT. See [LICENSE](LICENSE).
