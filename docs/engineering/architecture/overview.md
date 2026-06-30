# Architecture Overview

## What this repo is

`tamirs-superpowers` is a Claude Code plugin distributed through the [`tamirs-plugins`](https://github.com/Tamircohen28/plugins) marketplace catalog. The repo is the plugin source — install with `/plugin install tamirs-superpowers@tamirs-plugins`.

## Component map

```
tamirs-superpowers/              ← GitHub repo root
├── .claude-plugin/
│   └── plugin.json              ← Plugin manifest (name, version, skills paths, statusLine)
├── .mcp.json                    ← MCP server stubs (github via scripts/github-mcp.sh)
├── scripts/statusline.sh        ← Statusline script (wired via plugin.json settings.statusLine)
├── scripts/
│   └── github-mcp.sh            ← GitHub MCP stdio launcher (gh auth token → server)
├── hooks/
│   ├── hooks.json               ← Event wiring
│   ├── lib/worktree-common.sh   ← Shared bash library (slugify, session state, worktree paths)
│   ├── capture-task-slug.sh   ← UserPromptSubmit: slug + worktree creation
│   ├── enforce-worktree-edits.sh ← PreToolUse: block main-checkout edits
│   ├── protect-other-branches.sh ← PreToolUse: block PR ops on foreign branches
│   ├── session-init.sh          ← SessionStart: seed session state
│   ├── show-changelog.sh        ← SessionStart: Claude Code changelog on version bump
│   ├── worktree-create.sh       ← WorktreeCreate
│   ├── worktree-remove.sh       ← WorktreeRemove
│   ├── session-end.sh           ← SessionEnd
│   └── notify.sh                ← Notification
└── skills/                      ← 16 skills in 7 domains (see CLAUDE.md)
    ├── creative/                ← algorithmic-art
    ├── debugging/               ← targeted-debug
    ├── dev-workflow/            ← plan-dev, pr-dev, start-dev
    ├── documentation/           ← changelog-review, dark-terminal-doc, docs-review
    ├── mcp/                     ← mcp-builder, mcp-pagination
    ├── toolkit/                 ← find-skill, session-report, skill-creator
    └── repo/                    ← multi-agent-repo, repo-scaffold, repo-standards
        └── _contract/           ← shared templates, scripts, scaffold-gold + scaffold-plugin-gold fixtures (not a skill)
```

Contract profiles: `app-gold` (default apps), `plugin-gold` (agent-kit repos with `canonical/`). Detected via `detect-contract-profile.sh`; scored by `score-contract-gaps.sh` + `score-plugin-gaps.sh`. **User guide:** [docs/user/agent-kit.md](../../../docs/user/agent-kit.md).

## Hook system

Hooks are shell scripts registered in `hooks/hooks.json`. Claude Code executes them at lifecycle events and passes JSON on stdin.

The most complex hook is `capture-task-slug.sh` (UserPromptSubmit):

1. Reads session state from `~/.claude/sessions/<session_id>.json`
2. On the first prompt, derives a slug from the prompt text
3. Creates a git worktree at `~/.claude/worktrees/<repo>/<slug>/`
4. Exposes `CLAUDE_TASK_SLUG`, `CLAUDE_WORKTREE_PATH`, and `CLAUDE_SESSION_FILES_DIR` via `$CLAUDE_ENV_FILE`
5. Injects `additionalContext` so Claude knows where to work

## Skill loading

Claude Code discovers skills via the `skills` array in `plugin.json`, which points at domain directories under `skills/`. Each skill is a folder with a `SKILL.md` file. The **directory name** is the slash-command name (e.g. `skills/dev-workflow/plan-dev/` → `/plan-dev`).

Internal skills (`user-invocable: false`) are hidden from the `/` menu but invokable via `Skill("name")` from parent skills (e.g. `repo-standards` → `docs-review`).

## Dependency resolution

`plugin.json` declares one dependency: `superpowers@superpowers-dev`. When a user installs via `tamirs-plugins`, Claude Code resolves and installs the dependency marketplace plugin alongside this one.

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
