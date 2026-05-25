# tamir-library

Tamir Noy's personal library of agents, skills, and configurations for Claude — a Cowork plugin that bundles his own work and pulls everything else in via plugin dependencies so it stays current.

## How it works

This plugin uses two mechanisms to avoid duplicating code:

**Plugin dependencies** (declared in `.claude-plugin/plugin.json`) — when you install `tamir-library`, Claude Code auto-installs these alongside it and lists them in the install output. They track upstream versions and update via marketplace auto-update at startup. Documented at [code.claude.com/docs/en/plugin-dependencies](https://code.claude.com/docs/en/plugin-dependencies).

**Bundled skills** — skills under `skills/` that have no upstream plugin equivalent or are personal uploads. These are vendored copies.

## Dependencies (auto-installed)

| Plugin | Marketplace | What it does |
|---|---|---|
| `skill-creator` | `claude-plugins-official` | Create / improve / benchmark skills. |
| `session-report` | `claude-plugins-official` | HTML report of session token usage, subagents, skills, expensive prompts. |
| `sourcegraph` | `claude-plugins-official` | Code search & navigation across repos via Sourcegraph. |
| `atlassian` | `claude-plugins-official` | Jira + Confluence search/create/update. |
| `warp` | `claude-code-warp` | Warp terminal integration. |
| `data` | `knowledge-work-plugins` | Explore datasets, write SQL, build visualizations & dashboards. |
| `enterprise-search` | `knowledge-work-plugins` | Search across enterprise knowledge sources via Claude Cowork. |
| `productivity` | `knowledge-work-plugins` | General productivity toolkit (Cowork). |
| `superpowers` | `superpowers-dev` | Jesse Vincent's skills framework — TDD, debugging, brainstorming, skill authoring. |

`claude-plugins-official` is auto-available — nothing to register. The other
three marketplaces must be registered once on a fresh machine:

```
/plugin marketplace add warpdotdev/claude-code-warp
/plugin marketplace add anthropics/knowledge-work-plugins
/plugin marketplace add obra/superpowers
```

If a dependency can't resolve, the plugin is disabled until you install the missing piece. Run `/plugin list` to see the error.

## Bundled skills (19)

`skills/<topic>/<skill-name>/SKILL.md` — discovery is recursive.

**`skills/dev-workflow/` (4)**

| Skill | What it does |
|---|---|
| `fix-flaky-test` | Diagnose and fix flaky Bazel tests; remove `flaky=True` tags. |
| `strict-tdd-scala` | Enforces red-green-refactor for Scala/Loom Prime. |
| `run-bazel-tests` | Run specific Bazel test classes/methods. |
| `babysit-pr` | OpenAI's PR-watching skill — wait on checks, replies, merges. |

**`skills/observability/` (8)** — query & investigate production

| Skill | What it does |
|---|---|
| `query-app-logs` | Query application logs. |
| `query-error-logs` | Query and analyze application errors. |
| `query-request` | Trace a request through app and access logs. |
| `query-bi` | Query the BI data warehouse. |
| `query-fire-console` | Get production entities by ID via FireConsole. |
| `query-prod-db` | Query production DBs via SDL config. |
| `query-captains-log` | Query Captain's Log for production change events. |
| `query-ft-conductions` | Query feature toggle conduction timeseries. |

**`skills/integrations/` (2)**

| Skill | What it does |
|---|---|
| `slack-cli` | Drive Slack via the official CLI. |
| `proto-docs` | Generate API documentation from proto files. |

**`skills/meta/` (3)**

| Skill | What it does |
|---|---|
| `mcp-builder` | Build MCP servers (from anthropics/skills — not yet a plugin). |
| `mcp-pagination` | Always include pagination params on MCP list/search calls. |
| `user-find-skill` | Personal copy of the find-skill skill. |

**`skills/content/` (2)**

| Skill | What it does |
|---|---|
| `algorithmic-art` | Generate algorithmic art with p5.js. |
| `user-dark-terminal-doc` | Personal copy of the dark-terminal-doc skill. |

## MCP server stubs

`.mcp.json` declares 4 servers known to be installable from npm:
`github`, `context7`, `slack`, `desktop-commander`. Fill in the env vars listed
there for any you want enabled, or remove the entry.

> Earlier versions of this plugin shipped stubs for `gmail`, `google-calendar`,
> `google-drive`, `excalidraw`, and `powerpoint`. Those packages are not
> published under the names that were referenced, so they were removed in 0.3.0.
> If you have working community packages for those services, add them locally.

## Install

This plugin is distributed via a Claude Code marketplace.

1. Register the marketplace that hosts `tamir-library`:
   ```
   /plugin marketplace add <your-marketplace-hosting-tamir-library>
   ```
2. Install:
   ```
   /plugin install tamir-library
   ```
   Claude Code resolves and installs the two dependencies automatically.
3. Set the env vars in `.mcp.json` for any MCP servers you want active.
4. Restart Claude Code (or `/reload-plugins`).

## Skills referenced but not bundled

`obra/superpowers` is now bundled as a dependency above. See `EXTERNAL_REFERENCES.md` for `mattpocock/skills` — that one is a separate marketplace; install it with `/plugin marketplace add mattpocock/skills` and pick the skills you want.

## Hooks & statusline

`hooks/hooks.json` wires up 8 hook entries that mirror Tamir's global
`~/.claude/settings.json`:

| Event | Script | Purpose |
|---|---|---|
| PreToolUse (Bash) | `protect-other-branches.sh` | Block closing PRs from other authors. |
| PreToolUse (Edit\|Write\|MultiEdit\|NotebookEdit) | `enforce-worktree-edits.sh` | Refuse repo edits outside the dedicated worktree. |
| SessionStart | `show-changelog.sh`, `session-init.sh` | Show Claude Code changelog on update; seed session state. |
| UserPromptSubmit | `capture-task-slug.sh` | Derive task slug, create worktree, expose `$CLAUDE_SESSION_FILES_DIR`. |
| WorktreeCreate | `worktree-create.sh` | Create global worktree under `~/.claude/worktrees/`. |
| WorktreeRemove | `worktree-remove.sh` | Tear down a global worktree cleanly. |
| Notification | inline `osascript` | macOS notification when Claude needs attention. |
| PostToolUse (Write) | `validate-report-links.sh` | Sanity-check URLs in generated reports. |

Shared helpers live in `hooks/lib/worktree-common.sh`. All hook commands use
`${CLAUDE_PLUGIN_ROOT}` so they relocate cleanly with the plugin install dir.

`statusline.sh` at the plugin root is wired via the manifest's `statusLine`
field.

> The plugin **does not** vendor user-level settings such as `permissions`,
> `env`, `enabledPlugins`, `extraKnownMarketplaces`, `theme`, `worktree`, or
> `defaultMode`. Those stay in your personal `~/.claude/settings.json`.

## Layout

```
tamir-library/
├── .claude-plugin/plugin.json   # Manifest (dependencies, statusLine)
├── .mcp.json                    # MCP server stubs
├── statusline.sh                # Bundled statusline
├── hooks/
│   ├── hooks.json               # PreToolUse/SessionStart/UserPromptSubmit/...
│   ├── *.sh                     # 9 hook scripts
│   └── lib/worktree-common.sh   # Shared helpers
├── skills/
│   ├── dev-workflow/   (4 bundled)
│   ├── observability/  (8 bundled)
│   ├── integrations/   (2 bundled)
│   ├── meta/           (3 bundled)
│   └── content/        (2 bundled)
├── README.md
├── CHANGELOG.md
├── LICENSE
└── EXTERNAL_REFERENCES.md
```

## Adding new skills

Ask Claude to "create a new skill called X" — the bundled `skill-creator` dependency handles the rest. New skills land under `skills/<topic>/<name>/`. Re-zip to share.

## Author

Tamir Noy · tamirc@wix.com
