# Architecture Overview

## What this repo is

`tamir-library` is a Claude Code plugin distributed through a self-hosted marketplace. The repo serves a dual role:

1. **Marketplace** — `marketplace.json` at the root registers this GitHub repo as a Claude Code plugin marketplace under the name `tamirs-superpowers`.
2. **Plugin** — `.claude-plugin/plugin.json` at the same root registers the `tamir-library` plugin, pointing `source: "."` so the plugin and marketplace coexist in one repo.

## Component map

```
tamirs-superpowers/              ← GitHub repo root
├── marketplace.json             ← Marketplace manifest (declares the plugin + cross-marketplace allowlist)
├── .claude-plugin/
│   └── plugin.json              ← Plugin manifest (name, version, dependencies, statusLine)
├── .mcp.json                    ← MCP server declarations (4 npm-installable servers)
├── statusline.sh                ← Statusline script (wired via plugin.json statusLine.command)
├── hooks/
│   ├── hooks.json               ← Event wiring (7 hook entries)
│   ├── lib/worktree-common.sh   ← Shared bash library (slugify, session state, worktree paths)
│   ├── capture-task-slug.sh     ← UserPromptSubmit: slug + worktree creation
│   ├── enforce-worktree-edits.sh ← PreToolUse(Edit|Write…): block main-checkout edits
│   ├── protect-other-branches.sh ← PreToolUse(Bash): block PR ops on foreign branches
│   ├── session-init.sh          ← SessionStart: seed session state JSON
│   ├── show-changelog.sh        ← SessionStart: show Claude Code changelog on version bump
│   ├── worktree-create.sh       ← WorktreeCreate: create global worktree
│   ├── worktree-remove.sh       ← WorktreeRemove: clean up global worktree
│   └── init-output-dir.sh       ← Helper: create session output dir
└── skills/
    ├── dev-workflow/            ← 8 skills: plan-dev, start-dev, pr-dev, …
    ├── integrations/            ← 2 skills: slack-cli, proto-docs
    ├── meta/                    ← 4 skills: changelog-review, mcp-builder, …
    └── content/                 ← 2 skills: algorithmic-art, user-dark-terminal-doc
```

## Hook system

Hooks are shell scripts registered in `hooks/hooks.json`. Claude Code executes them at lifecycle events and passes JSON on stdin. Each hook reads the JSON, does its work, and emits either `{"suppressOutput": true}` (silent) or a structured response that injects context into the session.

The most complex hook is `capture-task-slug.sh` (UserPromptSubmit):

1. Reads session state from `~/.claude/sessions/<session_id>.json` (managed by `worktree-common.sh`)
2. On the first prompt of a session, derives a slug from the prompt text via `slugify_text()`
3. Creates a git worktree at `~/.claude/worktrees/<repo>/<slug>/` using `git worktree add`
4. Exposes `CLAUDE_TASK_SLUG`, `CLAUDE_WORKTREE_PATH`, and `CLAUDE_SESSION_FILES_DIR` as env vars via `$CLAUDE_ENV_FILE`
5. Injects `additionalContext` into the session to tell Claude where to work

## Skill loading

Claude Code discovers skills by scanning for `SKILL.md` files recursively under the plugin's root. No registration step is needed — any valid `SKILL.md` with `name:` and `description:` frontmatter becomes a slash command.

Skills are stateless Markdown instructions. They declare `allowed-tools:` in frontmatter to restrict which Claude tools the skill can invoke.

## Dependency resolution

`plugin.json` declares 9 plugin dependencies. When a user runs `/plugin install tamir-library`, Claude Code:

1. Reads the `dependencies` array
2. For each dependency, resolves the plugin from the named marketplace
3. Installs all dependencies in parallel, then the root plugin
4. Cross-marketplace dependencies (e.g. `warp` from `claude-code-warp`) are allowed because `marketplace.json` lists those marketplaces in `allowCrossMarketplaceDependenciesOn`

## Data flow for a skill invocation

```
User types /plan-dev "add auth"
  → Claude Code reads skills/dev-workflow/plan-dev/SKILL.md
  → Claude follows the SKILL.md instructions
  → Claude uses Bash, Read, Edit, etc. as declared in allowed-tools
  → Hook enforce-worktree-edits.sh fires on any Edit/Write tool call
     → Checks if cwd is inside ~/.claude/worktrees/<repo>/<slug>/
     → If not, returns permissionDecision: deny
```
