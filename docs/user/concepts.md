# Concepts

## What is tamirs-superpowers?

`tamirs-superpowers` is a **Claude Code plugin** — a bundle of skills, hooks, and configuration that extends what Claude can do inside your terminal. Once installed, it adds slash commands (`/plan-dev`, `/start-dev`, `/pr-dev`, etc.) to your Claude Code session and wires up automatic behaviors via hooks.

## Plugins vs skills

A **plugin** is a distributable unit that Claude Code installs from a marketplace. It can contain:
- **Skills** — slash commands backed by a `SKILL.md` instruction file
- **Hooks** — shell scripts that run at lifecycle events (session start, before edits, etc.)
- **MCP servers** — declared in `.mcp.json`, providing tools Claude can call
- **A statusline** — a script that renders in your Claude Code footer

`tamirs-superpowers` ships all four. The plugin manifest (`.claude-plugin/plugin.json`) also declares **dependencies** — other plugins that auto-install alongside it.

## How the worktree hooks work

The most distinctive feature of this plugin is the worktree hook system. When you start a new Claude Code session in a git repo:

1. **`capture-task-slug.sh`** (UserPromptSubmit) reads your first prompt, derives a short slug (e.g. `add-user-auth`), and creates an isolated git branch + worktree at `~/.claude/worktrees/<repo>/<slug>/`.
2. **`enforce-worktree-edits.sh`** (PreToolUse) blocks any Edit/Write tool call that targets the main checkout — edits must happen inside the worktree.
3. **`worktree-create.sh`** / **`worktree-remove.sh`** handle `EnterWorktree` / `ExitWorktree` lifecycle events, creating and cleaning up the global worktree.

The result: every Claude Code session gets its own isolated branch, you never pollute your main checkout, and `$CLAUDE_SESSION_FILES_DIR` points to a per-session scratch directory for plans and notes.

## How the skills work

Skills are plain Markdown files (`SKILL.md`) with YAML frontmatter. Claude Code loads them as slash commands. When you type `/plan-dev`, Claude reads the `SKILL.md` instructions and follows them — no code is executed by the skill itself; it's a prompt that guides Claude's actions using its standard tools.

## The marketplace structure

This plugin is published through the [`tamirs-plugins`](https://github.com/Tamircohen28/plugins) catalog — a separate marketplace repo that lists `tamirs-superpowers` as an installable plugin. Install with:

```text
/plugin marketplace add Tamircohen28/plugins
/plugin install tamirs-superpowers@tamirs-plugins
```

The plugin source lives in this repo; the catalog repo handles discovery and versioning.

## Repo contract profiles (`repo-scaffold` / `repo-standards`)

Both skills share `skills/repo/_contract/`:

| Profile | Repo type | How it's chosen |
|---------|-----------|-----------------|
| `app-gold` | Apps, libraries, flat Claude plugins (e.g. tamirs-superpowers) | Default when no `canonical/rules/` |
| `plugin-gold` | Agent-kit distribution repos | Auto-detected when `canonical/rules/` exists, or scaffolded with `repo-scaffold --type plugin` |

**Full walkthrough:** [Agent-kit repos](agent-kit.md) — architecture, scaffold, contributor workflow, marketplace install, security.

**Quick commands:**

- Scaffold: `/tamirs-superpowers:repo-scaffold <name> -- "<description>" --type plugin`
- Polish: `/tamirs-superpowers:repo-standards polish` (on a repo with `canonical/rules/`)
