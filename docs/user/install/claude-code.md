# Install on Claude Code

| | |
|---|---|
| **Validated against** | Claude Code **2.1.233** |
| **Minimum supported** | **2.0.0** |
| **Plugin manifest** | `.claude-plugin/plugin.json` |
| **Marketplace manifest** | `.claude-plugin/marketplace.json` |
| **Official docs** | [Plugins reference](https://code.claude.com/docs/en/plugins-reference) · [Marketplaces](https://code.claude.com/docs/en/plugin-marketplaces) · [Skills](https://code.claude.com/docs/en/skills) |

Check your version:

```bash
claude --version
```

## Prerequisites

- Claude Code 2.0.0 or newer (2.1.233 is what this release was validated on)
- `jq` — `brew install jq`
- `git` 2.30+

## Method A — via the tamirs-marketplace catalog (recommended)

The catalog keeps the plugin updated and is where the rest of the plugin family lives.

```
/plugin marketplace add Tamircohen28/tamirs-marketplace
/plugin install tamirs-superpowers@tamirs-marketplace
```

Since Claude Code 2.1.221, `/plugin install` activates the plugin immediately
when safe — no `/reload-plugins` step. It also refreshes a stale marketplace
catalog and retries before reporting a plugin not found, so a fresh
`marketplace add` → `install` sequence no longer races the catalog cache.
Since 2.1.232, `/plugin install tamirs-superpowers@tamirs-marketplace` goes one
better and refreshes the marketplace **first**, so a release published minutes
ago installs without any manual `marketplace update`.
On older versions, finish with `/reload-plugins`.

To pick up a new release later:

```
/plugin marketplace update tamirs-marketplace
/plugin update tamirs-superpowers@tamirs-marketplace
```

> Claude Code caches installed plugins by the `version` field in `plugin.json`. If a release did not bump the version, `/plugin update` is a no-op.

## Method B — standalone, straight from this repo

No catalog needed. The repo carries its own `.claude-plugin/marketplace.json` alongside the plugin manifest, so Claude Code can install it directly:

```
/plugin marketplace add Tamircohen28/tamirs-superpowers
/plugin install tamirs-superpowers
```

(As above — on Claude Code older than 2.1.221, finish with `/reload-plugins`.)

## Method C — clone into the local skills directory

For offline machines or when you want to edit skills in place:

```bash
git clone https://github.com/Tamircohen28/tamirs-superpowers.git \
  ~/.claude/skills/tamirs-superpowers
```

Claude Code auto-loads anything under `~/.claude/skills/`. Reload with `/reload-plugins`.

Trade-off: no automatic updates — `git pull` to refresh.

## Method D — command-source link install (2.1.229+, best for editing in place)

Since Claude Code 2.1.229, a marketplace entry can use a **`command` source**: a
local command prints the plugin directory, the result is re-resolved at each
session start (no restart needed), and `mode: "link"` uses the directory in
place. Register a local marketplace whose entry points at your clone:

```jsonc
{
  "name": "tamirs-superpowers",
  "source": {
    "source": "command",
    "command": ["echo", "/absolute/path/to/tamirs-superpowers"],
    "mode": "link"
  }
}
```

Unlike Method C, the clone is used *as* the installed plugin — skills, hooks,
agents, and manifests all load from your working tree, and there is no cache
copy to fall out of date. This is the recommended path if you edit the plugin;
see [development-workflow.md](../../engineering/build-and-release/development-workflow.md)
for the full dev loop.

> **No-git machines:** Claude Code 2.1.224 added an `archive` plugin source —
> plugins can be installed from a zip archive over HTTPS, without git or npm,
> with optional SHA-256 pinning. This repo does not publish release zip
> artifacts yet, so Methods A–D above remain the supported paths here; if you
> mirror the repo internally, an archive source is now a viable no-git channel.

## Optional companion marketplaces

This plugin declares **no** dependencies, so nothing auto-installs with it. A few bundled skills reference plugins from other catalogs; register those once per machine if you want them:

```
/plugin marketplace add warpdotdev/claude-code-warp
/plugin marketplace add anthropics/knowledge-work-plugins
/plugin marketplace add obra/superpowers
```

## Optional — bootstrap settings, agents, and notifications

`scripts/install.sh` writes a clean `~/.claude/settings.json`, wires the statusline, and copies the 6 specialist agents into `~/.claude/agents/`:

```bash
make install
```

With phone notifications (opt-in — both variables required):

```bash
PUSHOVER_TOKEN=... PUSHOVER_USER=... bash scripts/install.sh
```

Credentials are written to `~/.claude/pushover.env` at mode `600`, outside the version-pathed plugin cache so updates don't delete them. Or run `/tamirs-superpowers:notify-setup` and let the skill walk you through it.

## MCP servers (optional)

The plugin ships stubs for GitHub, Slack, Context7, and Desktop Commander in `.mcp.json`, all using `${ENV_VAR}` placeholders — never committed tokens.

1. `/plugin list` → note the `tamirs-superpowers` install path
2. Open `.mcp.json` there
3. Set the required env vars (e.g. `GITHUB_PERSONAL_ACCESS_TOKEN`)
4. Restart Claude Code

## Verify

```
/tamirs-superpowers:find-skill
```

Should list all 27 skills. Also check the statusline appears at the bottom of the terminal — that confirms `settings.statusLine` resolved.

## What Claude Code gets that others don't

- **Statusline** — declared in `settings.statusLine`, Claude Code only
- **Full hook suite** — `hooks/hooks.json` worktree guards, session init, notifications
- **Marketplace dependency resolution** — available on Claude Code, though this plugin declares no dependencies

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `/plugin update` does nothing | The release didn't bump `plugin.json` `version`. Check the [releases page](https://github.com/Tamircohen28/tamirs-superpowers/releases). |
| `Marketplace file not found` | You're on a revision older than 1.12.0, before `.claude-plugin/marketplace.json` was added. Use the catalog (Method A) or update the clone. |
| Skills don't appear after install | On 2.1.221+ installs activate immediately when safe — if skills still don't appear, run `/reload-plugins`, then restart Claude Code. `/reload-plugins` does **not** re-fetch from GitHub — it only reloads what's cached. |
| Statusline blank | Confirm `~/.claude/settings.json` has `statusLine` as an **object** (`{"type":"command","command":"..."}`), not a string. |
| Hooks not firing | Check the plugin is enabled: `/plugin list`. |

More: [troubleshooting.md](../troubleshooting.md).
