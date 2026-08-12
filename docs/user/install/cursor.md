# Install on Cursor

| | |
|---|---|
| **Validated against** | Cursor **3.15.19** |
| **Minimum supported** | **3.15.19** — see note below |
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

`hooks/hooks.json` in this repo is the **Claude Code** (and Codex) plugin lifecycle suite (`PreToolUse`, `SessionStart`, …, with `${CLAUDE_PLUGIN_ROOT}` paths). Cursor Plugins may discover a `hooks/hooks.json` path too, but expect **Cursor event names** (`beforeShellExecution`, `afterFileEdit`, `sessionStart`, … — see [Hooks](https://cursor.com/docs/hooks.md)). The Claude-shaped plugin file does **not** give you the worktree guards when this package is installed as a Cursor plugin.

**Project / cloud hooks (shipped here):** when this repo is the workspace (local Agent or Cloud Agent), Cursor loads [`.cursor/hooks.json`](../../.cursor/hooks.json). That file is Cursor-native and soft-asks on force-push to `master`/`main` and on `self-hosted` runner edits (contributor policy). User `~/.cursor/hooks.json` does **not** apply in cloud VMs.

**Third-party Claude hooks (opt-in):** Cursor can also load hooks from `.claude/settings.json` / `~/.claude/settings.json` when **Settings → Rules, Skills, Subagents → Include third-party Plugins, Skills, and other configs** is enabled ([Third-party hooks](https://cursor.com/docs/reference/third-party-hooks.md)). That maps Claude event names (`PreToolUse` → `preToolUse`, …). It does **not** auto-load the plugin package's `hooks/hooks.json` — you still need settings wiring or a Cursor-native plugin `hooks` manifest entry.

For *installed* plugin consumers, full worktree / sensitive-file discipline still comes from `.cursor/rules/*.mdc` + `AGENTS.md` (see [platform-equivalence.md](../../agent-guidelines/platform-equivalence.md)). A Cursor-native **plugin** hooks bundle (manifest `hooks` field porting the highest-value Claude guards) remains a future opportunity.

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

## Working tips (3.11 → 2026-08-03; desktop CLI 3.15.19)

- **Desktop CLI patch line** — public changelog feature numbers can lag `cursor --version`. This repo's pin is **3.15.19** (download line 2026-08-11); newest feature write-up remains **3.11**, newest date-only entry **2026-08-03**.
- **Agent Plugins standard** — Cursor loads [Agent Plugins](https://agent-plugins.org) (root `plugin.json` + skills/MCP) alongside Cursor Plugins (`.cursor-plugin/plugin.json`). This repo ships the Cursor Plugin shape; portable skills/MCP stay compatible with the open standard.
- **`workspaceOpen` hook** — app-lifecycle hook (desktop/CLI; not Cloud Agents) can return `pluginPaths` so workspace-specific plugins load on open / folder change. Useful when contributing to this repo from a multi-root workspace; not required for marketplace installs.
- **Side chats (3.11)** — `/side`, `/btw`, or the chat-panel plus button opens a durable secondary agent. Use it to research a skill or rule without interrupting the main thread; at-mention the side chat to pull findings back.
- **Conversation search (3.11)** — Cmd+K in the Agents Window searches transcripts; Cmd+F searches within a conversation.
- **Cursor Router / Auto (2026-07-22)** — Auto modes Cost / Balance / Intelligence. Prefer Balance for daily plugin work; Intelligence when porting hooks or auditing platform parity.
- **Cursor Automations (3.8)** — can **delete memory files** from the UI (or when prompted); — `/automate` (or Dashboard → Automations) for always-on agents. Useful GitHub triggers here: **Workflow run completed** (triage `make validate` / CI reds), **PR review comment** (auto-address review threads). Enable **computer use** when you want a smoke-demo artifact attached. Marketplace templates cover failed-Actions triage and review auto-fix.
- **Google Workspace plugins (2026-08-03)** — optional Marketplace plugins (Drive / Gmail / Calendar). Unrelated to this plugin; install from Customize / Marketplace if you want them. Never commit Workspace credentials here.
- **Inbox + multi-PR sessions (2026-07-29)** — Inbox tracks in-progress / needs-attention / in-review work. When one chat opens several PRs (e.g. catalog + plugin), open **every** PR from the session — not only the last. **iPad** / **Cursor Start** remain client/plan surfaces.
- **Third-party hooks toggle** — if you keep Claude Code hooks in `.claude/settings.json` for dual-tool workflows, enable third-party skills/hooks in Cursor Settings so those settings-based hooks can load (see Hooks section above).

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
| Expected worktree hooks did not fire | Plugin `hooks/hooks.json` is Claude-shaped. As a Cursor *plugin* install, rely on `.cursor/rules` / `AGENTS.md`, or wait for a Cursor-native plugin hooks bundle. When this repo is the *workspace*, project hooks in `.cursor/hooks.json` do run (soft contributor guards only). |
| Claude settings hooks not loading | Enable **Include third-party Plugins, Skills, and other configs** in Cursor Settings; hooks must live under `.claude/settings.json`, not only `hooks/hooks.json`. |
