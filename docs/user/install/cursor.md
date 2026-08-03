# Install on Cursor

| | |
|---|---|
| **Validated against** | Cursor **3.14.7** |
| **Minimum supported** | **3.14.7** — see note below |
| **Manifest** | `.cursor-plugin/plugin.json` |
| **Official docs** | [Plugins](https://cursor.com/docs/plugins) · [Rules](https://cursor.com/docs/context/rules) |

Check your version:

```bash
cursor --version
```

> **About the minimum.** Cursor's plugin documentation states no minimum version for the plugin system. Rather than invent a floor, this repo sets `supported_min` equal to the version it was actually validated on. Older Cursor releases with plugin support may well work — they are simply untested here.

## What Cursor picks up

Cursor auto-discovers these from the plugin root, no per-item registration needed:

| Directory | Contents |
|-----------|----------|
| `skills/` | 27 skills (also listed explicitly in `.cursor-plugin/plugin.json`) |
| `.cursor/rules/` | 10 `.mdc` rule files — commit conventions, worktree workflow, skill standards |
| `agents/` | 6 specialist agents |
| `hooks/hooks.json` | Lifecycle hooks |
| `.mcp.json` | MCP server stubs, referenced via `mcpServers` in the manifest |

## Method A — team marketplace (recommended)

This is Cursor's supported path for installing a plugin from a GitHub repo.

1. Open the Cursor **Dashboard → Plugins**
2. Under **Team Marketplaces**, choose **Add Marketplace**
3. Select **Import from Repo**
4. Point it at either:
   - `Tamircohen28/plugins` — the full catalog, then **Add to Marketplace** → `tamirs-superpowers`
   - `Tamircohen28/tamirs-superpowers` — this repo standalone; its `.cursor-plugin/plugin.json` is picked up directly
5. In **Marketplace Settings**, enable **Auto Refresh** so pushes to `master` propagate
6. Save

Then, in the editor: **Customize** in the sidebar → your team marketplace → install `tamirs-superpowers`.

> Auto Refresh re-reads the **whole** manifest on each push, so a version bump is not required for Cursor to see changes — unlike Claude Code.

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
