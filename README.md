<p align="center">
  <img src="assets/banner.png" alt="tamir-library" width="600" />
</p>

<p align="center">
  <a href="https://github.com/TamirCohen28/tamirs-superpowers/actions/workflows/ci.yml">
    <img src="https://github.com/TamirCohen28/tamirs-superpowers/actions/workflows/ci.yml/badge.svg" alt="CI" />
  </a>
  <a href="LICENSE">
    <img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License" />
  </a>
  <a href=".claude-plugin/plugin.json">
    <img src="https://img.shields.io/badge/claude--code-plugin-blueviolet" alt="Claude Code Plugin" />
  </a>
</p>

# tamir-library

A personal Claude Code plugin that bundles 15 skills, smart worktree hooks, and MCP server stubs — installed with a single `/plugin install` command and kept current via marketplace auto-update.

## Features

- **15 bundled skills** across dev-workflow, integrations, meta, and content — plan, implement, review, debug, audit docs, and more, all from the Claude Code prompt
- **Smart worktree hooks** that automatically create isolated git worktrees per task, derive task slugs from your first prompt, enforce edit isolation, and show Claude Code changelogs on update
- **Auto-installed plugin dependencies** — Atlassian, Sourcegraph, session-report, skill-creator, Warp, and more pull in automatically when you install this plugin
- **MCP server stubs** for GitHub, Slack, Context7, and Desktop Commander — fill in your tokens and they're live
- **Statusline** showing git branch, worktree state, and session context in your Claude Code footer
- **Cross-marketplace dependencies** wired in `marketplace.json` so all third-party plugins resolve automatically

## Prerequisites

- [Claude Code](https://claude.ai/code) v2.0+
- `jq` (for hooks): `brew install jq`
- `git` 2.30+ (for worktree hooks)
- `gh` CLI (for `pr-dev`, `plan-dev`, `start-dev` skills): `brew install gh`

## Quick Start

```bash
# 1. Register third-party marketplaces (one-time, new machine)
/plugin marketplace add warpdotdev/claude-code-warp
/plugin marketplace add anthropics/knowledge-work-plugins
/plugin marketplace add obra/superpowers

# 2. Add this marketplace
/plugin marketplace add TamirCohen28/tamirs-superpowers

# 3. Install — dependencies auto-install alongside
/plugin install tamir-library

# 4. Reload
/reload-plugins
```

To enable MCP servers, open `.mcp.json` in the plugin install directory and set the env vars for any server you want active, then restart Claude Code.

## Bundled Skills

`skills/<topic>/<skill-name>/SKILL.md` — discovery is recursive.

**`skills/dev-workflow/` (8)**

| Skill | What it does |
|---|---|
| `/plan-dev` | Plan work into phases and create GitHub issues. |
| `/start-dev` | Create worktree, implement, validate, push, and open a PR. |
| `/pr-dev` | Address review threads, fix CI, squash-merge, and clean up. |
| `/docs-review` | Audit and fix Markdown docs — freshness, links, stale files. |
| `/task-audit` | Audit a completed branch for quality and PR readiness. |
| `/targeted-debug` | Scope-bounded debug from a stack trace — reads only named files. |
| `/babysit-pr` | Watch a PR and react to checks, review comments, and merges. |

**`skills/integrations/` (2)**

| Skill | What it does |
|---|---|
| `/slack-cli` | Drive Slack via the official CLI. |
| `/proto-docs` | Generate API documentation from proto files. |

**`skills/meta/` (4)**

| Skill | What it does |
|---|---|
| `/changelog-review` | Fetch live Claude Code docs; answer questions and diff versions. |
| `/mcp-builder` | Build MCP servers. |
| `/mcp-pagination` | Always include pagination params on MCP list/search calls. |
| `/user-find-skill` | Discover installed skills and what they do. |

**`skills/content/` (2)**

| Skill | What it does |
|---|---|
| `/algorithmic-art` | Generate algorithmic art with p5.js. |
| `/user-dark-terminal-doc` | Document for dark-terminal display. |

## Plugin Dependencies (auto-installed)

| Plugin | Marketplace | What it does |
|---|---|---|
| `skill-creator` | `claude-plugins-official` | Create / improve / benchmark skills. |
| `session-report` | `claude-plugins-official` | HTML report of session token usage. |
| `sourcegraph` | `claude-plugins-official` | Code search across repos. |
| `atlassian` | `claude-plugins-official` | Jira + Confluence search/create/update. |
| `warp` | `claude-code-warp` | Warp terminal integration. |
| `data` | `knowledge-work-plugins` | SQL, datasets, dashboards. |
| `enterprise-search` | `knowledge-work-plugins` | Enterprise knowledge search. |
| `productivity` | `knowledge-work-plugins` | General productivity toolkit. |
| `superpowers` | `superpowers-dev` | Jesse Vincent's skills framework. |

## Hooks

`hooks/hooks.json` wires 7 lifecycle events:

| Event | Script | Purpose |
|---|---|---|
| `PreToolUse (Bash)` | `protect-other-branches.sh` | Block editing PRs from other authors. |
| `PreToolUse (Edit\|Write\|…)` | `enforce-worktree-edits.sh` | Refuse repo edits outside the task worktree. |
| `SessionStart` | `show-changelog.sh`, `session-init.sh` | Show Claude Code changelog on update; seed session state. |
| `UserPromptSubmit` | `capture-task-slug.sh` | Derive task slug, create worktree, expose `$CLAUDE_SESSION_FILES_DIR`. |
| `WorktreeCreate` | `worktree-create.sh` | Create global worktree under `~/.claude/worktrees/`. |
| `WorktreeRemove` | `worktree-remove.sh` | Tear down global worktree cleanly. |
| `Notification` | inline `osascript` | macOS notification when Claude needs attention. |

## Documentation

- [User docs](docs/user/README.md) — concepts, quick start, troubleshooting
- [Engineering docs](docs/engineering/README.md) — architecture, development workflow, decisions
- [Changelog](CHANGELOG.md)
- [Contributing](docs/CONTRIBUTING.md)

## Contributing

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).

---

Tamir Cohen · https://github.com/TamirCohen28
