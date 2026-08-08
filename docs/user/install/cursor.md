# Install on Cursor

| | |
|---|---|
| **Validated against** | Cursor **3.14.7** (CLI); public changelog covered through feature **3.11** + **2026-08-03** |
| **Minimum supported** | **3.14.7** — see note below |
| **Manifest** | `.cursor-plugin/plugin.json` |
| **Pin file** | [`.cursor-version`](../../../.cursor-version) |
| **Official docs** | [Plugins](https://cursor.com/docs/plugins) · [Rules](https://docs.cursor.com/context/rules) · [Hooks](https://cursor.com/docs/agent/hooks) |

Check your version:

```bash
cursor --version
```

> **About the minimum.** Cursor's plugin documentation states no minimum version for the plugin system. Rather than invent a floor, this repo sets `supported_min` equal to the version it was actually validated on. Older Cursor releases with plugin support may well work — they are simply untested here. The public changelog's latest *feature* number may lag the CLI patch line (e.g. changelog **3.11** vs CLI **3.14.7**).

## What Cursor picks up

Cursor auto-discovers these from the plugin root, no per-item registration needed:

| Directory | Contents |
|-----------|----------|
| `skills/` | 27 skills (also listed explicitly in `.cursor-plugin/plugin.json`) |
| `.cursor/rules/` | 10 `.mdc` rule files — commit conventions, worktree workflow, skill standards |
| `agents/` | 6 specialist agents |
| `hooks/hooks.json` | Lifecycle hooks (PreToolUse / SessionStart / …) |
| `.mcp.json` | MCP server stubs, referenced via `mcpServers` in the manifest |

Manage plugins, skills, MCPs, rules, commands, and hooks from Cursor's **Customize** page (3.9+).

## Method A — team marketplace (recommended)

This is Cursor's supported path for installing a plugin from a GitHub repo.

1. Open the Cursor **Dashboard → Plugins**
2. Under **Team Marketplaces**, choose **Add Marketplace**
3. Select **Import from Repo**
4. Point it at either:
   - `Tamircohen28/tamirs-marketplace` — the full catalog, then **Add to Marketplace** → `tamirs-superpowers`
   - `Tamircohen28/tamirs-superpowers` — this repo standalone; its `.cursor-plugin/plugin.json` is picked up directly
5. Optionally restrict marketplace access to **organization groups** (Cursor 3.10+, Dashboard → Plugins → Team Marketplaces) in addition to SCIM directory groups
6. In **Marketplace Settings**, enable **Auto Refresh** so pushes to `master` propagate
7. Save

Then, in the editor: **Customize** in the sidebar → your team marketplace → install `tamirs-superpowers`.

> Auto Refresh re-reads the **whole** manifest on each push, so a version bump is not required for Cursor to see changes — unlike Claude Code.

> **Team MCPs (3.10+):** admins can also distribute approved MCP servers (not just plugins) through the same team marketplace from Dashboard → Integrations & MCP. This plugin's `.mcp.json` stubs stay opt-in via env vars; Team MCPs are the path when you want a shared, pre-approved server for the whole org.

## Method B — clone into the project

For a single repo, without any marketplace setup:

```bash
git clone https://github.com/Tamircohen28/tamirs-superpowers.git /tmp/tsp
cp -r /tmp/tsp/.cursor/rules/. <your-repo>/.cursor/rules/
cp -r /tmp/tsp/skills          <your-repo>/skills
```

Cursor reads `.cursor/rules/*.mdc` from the project root automatically. Update by re-running the copy after a `git pull`.

## MCP servers (optional)

`.mcp.json` is wired through the `mcpServers` field of `.cursor-plugin/plugin.json`. Fill the `${ENV_VAR}` placeholders in your local environment — never commit tokens — and restart Cursor.

Optional first-party Cursor Marketplace plugins (2026-08-03) for **Google Drive / Gmail / Calendar** are separate from this plugin — install them from Customize when a workflow needs Workspace context.

## Cloud agents & conversation hooks (3.11+)

When a Cursor **Cloud** agent runs against a repo, it loads that repo's project
[`.cursor/hooks.json`](https://cursor.com/docs/agent/hooks) (not your user
`~/.cursor/hooks.json`). New conversation hooks include `beforeSubmitPrompt`,
`afterAgentResponse`, `afterAgentThought`, `subagentStart` / `subagentStop`, and
`stop`. Put cloud-facing guards in the **consumer repo**; this plugin's
`hooks/hooks.json` continues to cover IDE tool/session lifecycle when the plugin
is installed locally.

**Side chats (3.11):** `/side` or `/btw` opens a durable secondary agent for research
without interrupting the main thread — useful while `/plan-dev` or `/start-dev` is running.

## Verify

Ask Cursor's agent:

```
/tamirs-superpowers:find-skill
```

And confirm the rules loaded by opening any file and checking that `.cursor/rules` entries appear in the agent's active context.

## What does not port

| Feature | Status on Cursor |
|---------|------------------|
| Statusline | ❌ Claude Code only — `settings.statusLine` is ignored |
| Plugin dependency resolution | ❌ No cross-marketplace dependency install; add other plugins manually |

Skills, rules, agents, hooks, and MCP all work. See [platform-equivalence.md](../../agent-guidelines/platform-equivalence.md) for the full mapping.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Marketplace import fails | Confirm the repo is reachable by the Cursor team account and that `.cursor-plugin/plugin.json` exists on the default branch. |
| Plugin installs but skills are missing | The `skills` array in `.cursor-plugin/plugin.json` lists domain directories; confirm your clone has all of `skills/*`. |
| Rules not applying | `.mdc` files must be under `.cursor/rules/` in the **project**, not only in the plugin. Method B copies them across. |
| Changes not showing after a push | Enable **Auto Refresh** in Marketplace Settings, or re-import. |
| Cloud agent ignores your user hooks | Expected on 3.11+: only project `.cursor/hooks.json` runs in cloud VMs. |
| Marketplace visible to the wrong people | Use organization-group restrictions (3.10+) under Team Marketplace settings. |
