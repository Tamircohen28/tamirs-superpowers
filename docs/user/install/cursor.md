# Install on Cursor

| | |
|---|---|
| **Validated against** | Cursor **3.16.17** |
| **Minimum supported** | **3.16.17** — see note below |
| **Changelog covered through** | feature **3.11** + date-only entries to **2026-08-17** (see [`.cursor-version`](../../.cursor-version)) |
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

**Installed plugin hooks (CLI, Aug 11 2026+):** Cursor CLI now executes hooks defined by installed plugins (including those loaded with `--plugin-dir`) and refreshes them on plugin reload. That only helps once this package ships a **Cursor-native** hooks file (Cursor event names + paths) via the plugin `hooks` manifest field — Claude-shaped `hooks/hooks.json` still will not fire. Until that MINOR lands, *installed* plugin consumers keep worktree / sensitive-file discipline from `.cursor/rules/*.mdc` + `AGENTS.md` (see [platform-equivalence.md](../../agent-guidelines/platform-equivalence.md)).

**Third-party Claude hooks (opt-in):** Cursor can also load hooks from `.claude/settings.json` / `~/.claude/settings.json` when **Settings → Rules, Skills, Subagents → Include third-party Plugins, Skills, and other configs** is enabled ([Third-party hooks](https://cursor.com/docs/reference/third-party-hooks.md)). That maps Claude event names (`PreToolUse` → `preToolUse`, …). It does **not** auto-load the plugin package's `hooks/hooks.json` — you still need settings wiring or a Cursor-native plugin `hooks` manifest entry.

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

## Working tips (3.11 → 2026-08-17; desktop CLI 3.16.17; Grok 4.6)

- **Desktop CLI patch line** — public changelog feature numbers can lag `cursor --version`. This repo's pin is **3.16.17** (download line 2026-08-11; [CLI changelog](https://cursor.com/docs/cli/changelog) Aug 11 release); newest feature write-up remains **3.11**, newest date-only entry **2026-08-17** (Origin).
- **Origin (2026-08-17, early beta)** — Cursor's git forge for hosting/sharing code ([docs](https://cursor.com/docs/origin), [codebase](https://cursor.com/codebase)). You can create Origin-hosted repos or **mirror this GitHub plugin repo** for browse/PR review inside Cursor (two-way comment sync). **GitHub remains the source of truth** for marketplace installs (`Tamircohen28/tamirs-marketplace` → this repo) and CI (`ubuntu-latest`). Do not replace the public GitHub remote with Origin-only hosting. Claiming a codebase name is optional personal/admin setup.
- **Cloud Agent Builds (2026-08-13; default as of 2026-08-17)** — Cursor prepares warm environment snapshots (repos + `install` already done; recurring refresh) so Cloud Agents boot faster; broken builds never go live. **Builds is now the default** for all Cloud Agent environments. Confirm each environment has a recent successful Build, `Update stale builds` on with a sensible Staleness threshold (default 24h), and install credentials as team/environment secrets. Private-registry credentials for `install` must be **team/environment secrets** (user secrets are not available during Builds). Recurring Builds **Skip** when nothing changed since the last completed Build (no new default-branch commits / config / secret changes) — a Skipped stream is healthy. Enable **Update stale builds** and set the **Staleness threshold** (default **24 hours**; `0` = always pull latest default-branch at agent start). Phase split: durable work in `install` (Build-time), fresh services in `start`, shared app processes in `terminals` (both at agent start). Inspect builds via the dashboard or `cursor-cloud` MCP tools. See [announcement](https://cursor.com/blog/builds) · [Builds docs](https://cursor.com/docs/cloud-agent/builds).
- **CLI sticky skills (Aug 11)** — in Cursor CLI, a skill slash entry attaches once on Enter; **Option+Enter** invokes a mode-backed skill as a sticky custom mode until you exit it. Useful for `/tamirs-superpowers:repo-standards` or `/tamirs-superpowers:pr-dev` sessions that should keep the skill active across turns.
- **CLI steer + `/goal` (Aug 11)** — while the agent is working, **Enter** steers the active turn (queues guidance at a safe boundary); Enter again interrupts. Optional durable **`/goal`** keeps an active/paused goal across idle and headless runs (rolling out / gated) — useful for long `/tamirs-superpowers:pr-dev` or validation sessions.
- **Skill layout** — CLI skill discovery skips hidden directories. Keep skills under `skills/<domain>/` (not under `.cursor/` or other dot-dirs) so they stay discoverable — this repo already does.
- **CLI plugin hooks execute (Aug 11)** — installed-plugin hooks now run in the CLI once a Cursor-native hooks bundle ships; see Hooks section. Claude-shaped `hooks/hooks.json` remains inert for Cursor plugin installs.
- **Agent Plugins standard** — Cursor loads [Agent Plugins](https://agent-plugins.org) (root `plugin.json` + skills/MCP) alongside Cursor Plugins (`.cursor-plugin/plugin.json`). This repo ships the Cursor Plugin shape; portable skills/MCP stay compatible with the open standard.
- **`workspaceOpen` hook** — app-lifecycle hook (desktop/CLI; not Cloud Agents) can return `pluginPaths` so workspace-specific plugins load on open / folder change. Useful when contributing to this repo from a multi-root workspace; not required for marketplace installs.
- **Side chats (3.11)** — `/side`, `/btw`, or the chat-panel plus button opens a durable secondary agent. Use it to research a skill or rule without interrupting the main thread; at-mention the side chat to pull findings back.
- **Conversation search (3.11)** — Cmd+K in the Agents Window searches transcripts; Cmd+F searches within a conversation.
- **Cursor Router / Auto (2026-07-22)** — Auto modes Cost / Balance / Intelligence. Prefer Balance for daily plugin work; Intelligence when porting hooks or auditing platform parity.
- **Grok 4.6 (2026-08-14)** — frontier model tuned for long-running agents and stronger interactive/visual first passes ([announcement](https://cursor.com/blog/grok-4-6)). Available in Cursor and Grok Build. Prefer it for multi-step skill ports, visual install demos, and long `/tamirs-superpowers:pr-dev` / validation sessions; keep Router **Balance** for routine catalog/plugin edits. Host-side model pick only — no plugin manifest change.
- **Cursor Automations (3.8)** — can **delete memory files** from the UI (or when prompted). Use `/automate` (or Dashboard → Automations) for always-on agents. Useful GitHub triggers here: **Workflow run completed** (triage `make validate` / CI reds), **PR review comment** (auto-address review threads). Enable **computer use** when you want a smoke-demo artifact attached. Marketplace templates cover failed-Actions triage and review auto-fix.
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
| Expected worktree hooks did not fire | Plugin `hooks/hooks.json` is Claude-shaped. As a Cursor *plugin* install, rely on `.cursor/rules` / `AGENTS.md`, or wait for a Cursor-native plugin hooks bundle (CLI Aug 11+ will execute that bundle once it ships). When this repo is the *workspace*, project hooks in `.cursor/hooks.json` do run (soft contributor guards only). |
| Claude settings hooks not loading | Enable **Include third-party Plugins, Skills, and other configs** in Cursor Settings; hooks must live under `.claude/settings.json`, not only `hooks/hooks.json`. |
