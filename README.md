# tamirs-superpowers

A portable agent toolkit for Claude: six instruction-only skills, 10 role-based specialist
agents and an evidence-first output style, from one plugin.

This is the directory edition, built for Anthropic's plugin directory from the canonical
repository. It is prose only: Markdown and JSON, no scripts, no hooks, no mod, no MCP server
and no statusline command. It carries the skills that work as plain instructions. The full
plugin has 30 skills, including the script-backed development workflow (`plan-dev`,
`start-dev`, `orchestrate-dev`, `pr-dev` and the rest), repository standards, debugging, and
worktree-isolation hooks, a permission guard, a statusline, an in-process mod and a bundled
GitHub MCP server. It installs from the tamirs-marketplace (see Install). Source, issues and
the full documentation: <https://github.com/Tamircohen28/tamirs-superpowers>.

## What you get

- **Skills** — `decision` (turns a pending choice into a plain numbered menu), `find-skill`
  (searches public catalogs for a skill or plugin), `retro` (turns a rough session into
  proposed rules, hooks or memory, and writes nothing without your approval), `platform-sync`
  (checks a repository's agent setup against the newest Claude Code, Codex, Cursor, Gemini CLI
  and OpenCode releases), and two document styles, `field-notebook-ui` and
  `dark-terminal-doc`.
- **Agents** — ten specialists (implementer, test engineer, security reviewer, …), each
  reading its contract from `core/roles/`, which ships with it, and your project's own
  instructions file. The reviewers run read-only (Read, Grep, Glob). The implementer,
  integrator and test engineer use your session's tools, under your normal permission
  prompts.
- **Output style** — `Evidence`: answers that cite the command, file or output behind each
  claim. Opt in with `/output-style Evidence`.

## What it runs, sends and fetches

Nothing runs on its own. This edition has no hooks, no mod and no MCP server, so nothing starts
when a session opens, when a tool is called or when the session ends. A skill runs a command
only when Claude runs it as part of the task you gave, through Claude Code's normal permission
prompts. No skill pre-approves any tool beyond reading files. The plugin
reads no token from your environment, from `gh` or from a file, and sends nothing anywhere.
The privacy policy is in [PRIVACY.md](PRIVACY.md).

## Install

Add it from the directory on claude.ai. For the full plugin (all 30 skills, hooks,
permission guard, mod, statusline, GitHub MCP server), in Claude Code:

```text
/plugin marketplace add Tamircohen28/tamirs-marketplace
/plugin install tamirs-superpowers@tamirs-marketplace
```

## Surfaces

| Surface | Status |
|---|---|
| Claude Code (CLI) | Supported: the six skills, ten agents and the output style. |
| Claude Desktop | Supported: the same. |
| claude.ai (web) | Skills and agents. |

## License

MIT. See [LICENSE](LICENSE).
