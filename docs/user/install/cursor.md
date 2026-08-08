# Install on Cursor

| | |
|---|---|
| **Validated against** | Cursor **3.14.7** |
| **Minimum supported** | **3.14.7** — see note below |
| **Changelog covered through** | feature **3.11** + date-only entries to **2026-08-03** (see [`.cursor-version`](../../.cursor-version)) |
| **Manifest** | `.cursor-plugin/plugin.json` |
| **Official docs** | [Plugins](https://cursor.com/docs/plugins) · [Rules](https://cursor.com/docs/context/rules) · [Hooks](https://cursor.com/docs/hooks) · [Customize](https://cursor.com/docs/customize-cursor) |

Check your version:

```bash
cursor --version
```

> **About the minimum.** Cursor's plugin documentation states no minimum version for the plugin system. Rather than invent a floor, this repo sets `supported_min` equal to the version it was actually validated on. Older Cursor releases with plugin support may well work — they are simply untested here.
>
> The public changelog's latest *feature* number can lag the desktop CLI patch line (`cursor --version`). This repo pins the CLI observation in `validated_against` and records the newest covered changelog feature/date in `.cursor-version`.

## What Cursor picks up

Cursor auto-discovers these from the plugin root (see [Plugins reference](https://cursor.com/docs/reference/plugins)):

| Directory | Contents |
|-----------|----------|
| `skills/` | 27 skills (also listed explicitly in `.cursor-plugin/plugin.json`) |
| `.cursor/rules/` | 10 `.mdc` rule files — commit conventions, worktree workflow, skill standards (project/contributor rules; also useful when this repo is the workspace) |
| `agents/` | 6 specialist agents |
| `.mcp.json` | MCP server stubs, referenced via `mcpServers` in the manifest |

### Hooks — Claude format vs Cursor format

`hooks/hooks.json` in this repo is the **Claude Code** lifecycle suite (`PreToolUse`, `SessionStart`, …). Cursor Plugins discover `hooks/hooks.json` too, but expect **Cursor event names** (`beforeShellExecution`, `afterFileEdit`, `sessionStart`, … — see [Hooks](https://cursor.com/docs/hooks.md)). The Claude-shaped file does **not** give you the worktree guards on Cursor.

On Cursor today, worktree and sensitive-file discipline comes from `.cursor/rules/*.mdc` + `AGENTS.md` (see [platform-equivalence.md](../../agent-guidelines/platform-equivalence.md)). Shipping a Cursor-native hooks bundle (separate path via the manifest `hooks` field) is tracked as a future opportunity — do not assume Claude hooks fire here.

Cloud agents load **project** hooks from `.cursor/hooks.json` at the repo root (user `~/.cursor/hooks.json` does not apply in cloud VMs). This plugin does not yet ship a project cloud-hooks file.

## Method A — team marketplace (recommended)

This is Cursor's supported path for installing a plugin from a GitHub repo.

1. Open the Cursor **Dashboard → Plugins**
2. Under **Team Marketplaces**, choose **Add Marketplace**
3. Select **Import from Repo**
4. Point it at either:
   - `Tamircohen28/tamirs-marketplace` — the full catalog, then **Add to Marketplace** → `tamirs-superpowers`
   - `Tamircohen28/tamirs-superpowers` — this repo standalone; its `.cursor-plugin/plugin.json` is picked up directly
5. In **Marketplace Settings**, enable **Auto Refresh** so pushes to `master` propagate
6. Optionally restrict **Marketplace Access** to Organization Groups (Cursor **3.10**) so only selected groups see the catalog
7. Save

Then, in the editor: **Customize** in the sidebar → your team marketplace → install `tamirs-superpowers`.

> Auto Refresh re-reads the **whole** manifest on each push, so a version bump is not required for Cursor to see changes — unlike Claude Code.

### Customize page (3.9+)

**Customize** is the single place to manage plugins, skills, MCPs, subagents, rules, commands, and hooks (user / team / workspace). After install, use it to toggle MCP stubs on, set rule modes (Always / Agent Decides / Manual), and confirm skills are visible. Team marketplaces also surface a leaderboard of popular plugins/skills/MCPs across your team.

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

On Teams/Enterprise, admins can also distribute **Team MCP** servers via the Default team marketplace (**Dashboard → Integrations & MCP → Add to Team Marketplace**, Cursor **3.10**) so members install approved servers from Customize without hand-editing JSON.

## Working tips (3.11 → 2026-08-03)

- **Side chats (3.11)** — `/side`, `/btw`, or the chat-panel plus button opens a durable secondary agent. Use it to research a skill or rule without interrupting the main thread; at-mention the side chat to pull findings back.
- **Conversation search (3.11)** — Cmd+K in the Agents Window searches transcripts; Cmd+F searches within a conversation.
- **Cursor Router / Auto (2026-07-22)** — Auto modes Cost / Balance / Intelligence. Prefer Balance for daily plugin work; Intelligence when porting hooks or auditing platform parity.
- **Cursor Automations (3.8)** — `/automate` (or Dashboard → Automations) for always-on agents. Useful GitHub triggers here: **Workflow run completed** (triage `make validate` / CI reds), **PR review comment** (auto-address review threads). Enable **computer use** when you want a smoke-demo artifact attached. Marketplace templates cover failed-Actions triage and review auto-fix.
- **Google Workspace plugins (2026-08-03)** — optional Marketplace plugins (Drive / Gmail / Calendar). Unrelated to this plugin; install from Customize / Marketplace if you want them. Never commit Workspace credentials here.
- **Inbox (2026-07-29)** — useful for reviewing cloud-agent / automation PRs; no plugin code change. **iPad** / **Cursor Start** remain client/plan surfaces.

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
| Claude `hooks/hooks.json` suite | ❌ Different event schema — see Hooks note above |

Skills, rules, agents, and MCP all work. See [platform-equivalence.md](../../agent-guidelines/platform-equivalence.md) for the full mapping.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| Marketplace import fails | Confirm the repo is reachable by the Cursor team account and that `.cursor-plugin/plugin.json` exists on the default branch. |
| Plugin installs but skills are missing | The `skills` array in `.cursor-plugin/plugin.json` lists domain directories; confirm your clone has all of `skills/*`. |
| Rules not applying | `.mdc` files must be under `.cursor/rules/` in the **project**, not only in the plugin. Method B copies them across. |
| Changes not showing after a push | Enable **Auto Refresh** in Marketplace Settings, or re-import. |
| Expected worktree hooks did not fire | Those hooks are Claude-shaped. On Cursor, rely on `.cursor/rules` / `AGENTS.md`, or wait for a Cursor-native hooks bundle. |
