# Concepts

## What is tamir-library?

`tamir-library` is a **Claude Code plugin** — a bundle of skills, hooks, and configuration that extends what Claude can do inside your terminal. Once installed, it adds slash commands (`/plan-dev`, `/pr-dev`, etc.) to your Claude Code session and wires up automatic behaviors via hooks.

## Plugins vs skills

A **plugin** is a distributable unit that Claude Code installs from a marketplace. It can contain:
- **Skills** — slash commands backed by a `SKILL.md` instruction file
- **Hooks** — shell scripts that run at lifecycle events (session start, before edits, etc.)
- **MCP servers** — declared in `.mcp.json`, providing tools Claude can call
- **A statusline** — a script that renders in your Claude Code footer

`tamir-library` ships all four. The plugin manifest (`.claude-plugin/plugin.json`) also declares **dependencies** — other plugins that auto-install alongside it.

## How the worktree hooks work

The most distinctive feature of this plugin is the worktree hook system. When you start a new Claude Code session in a git repo:

1. **`capture-task-slug.sh`** (UserPromptSubmit) reads your first prompt, derives a short slug (e.g. `add-user-auth`), and creates an isolated git branch + worktree at `~/.claude/worktrees/<repo>/<slug>/`.
2. **`enforce-worktree-edits.sh`** (PreToolUse) blocks any Edit/Write tool call that targets the main checkout — edits must happen inside the worktree.
3. **`worktree-create.sh`** / **`worktree-remove.sh`** handle `EnterWorktree` / `ExitWorktree` lifecycle events, creating and cleaning up the global worktree.

The result: every Claude Code session gets its own isolated branch, you never pollute your main checkout, and `$CLAUDE_SESSION_FILES_DIR` points to a per-session scratch directory for plans and notes.

## How the skills work

Skills are plain Markdown files (`SKILL.md`) with YAML frontmatter. Claude Code loads them as slash commands. When you type `/plan-dev`, Claude reads the `SKILL.md` instructions and follows them — no code is executed by the skill itself; it's a prompt that guides Claude's actions using its standard tools.

## The marketplace structure

This repo doubles as a Claude Code marketplace. `marketplace.json` at the root declares:
- The marketplace name (`tamirs-superpowers`)
- The single plugin it publishes (`tamir-library`, source: `.`)
- Which third-party marketplaces are allowed as cross-marketplace dependency sources

When you run `/plugin marketplace add TamirCohen28/tamirs-superpowers`, Claude Code reads `marketplace.json` and knows how to resolve `tamir-library` and its cross-marketplace dependencies.
