# Install on Codex

| | |
|---|---|
| **Validated against** | Codex CLI **0.146.0** |
| **Minimum supported** | **0.40.0** |
| **Plugin manifest** | `.codex-plugin/plugin.json` |
| **Marketplace manifest** | `.agents/plugins/marketplace.json` |
| **Official docs** | [AGENTS.md guide](https://developers.openai.com/codex/guides/agents-md) · [Config basics](https://developers.openai.com/codex/config-basic) |

Check your version:

```bash
codex --version
```

> **Where the marketplace manifest lives.** Codex resolves marketplaces from `.agents/plugins/marketplace.json` at the repo root — *not* from `.codex-plugin/marketplace.json`. Point `codex plugin marketplace add` at a root without that file and it fails with `marketplace root does not contain a supported manifest`. This repo ships one, which is what makes standalone install work.

## Method A — standalone, straight from this repo

```bash
codex plugin marketplace add Tamircohen28/tamirs-superpowers
codex plugin add tamirs-superpowers@tamirs-superpowers
```

Confirm:

```bash
codex plugin list --marketplace tamirs-superpowers
```

```
Marketplace `tamirs-superpowers`

PLUGIN                                 STATUS              VERSION  PATH
tamirs-superpowers@tamirs-superpowers  installed, enabled  1.12.0   ...
```

Refresh after a new release:

```bash
codex plugin marketplace upgrade
```

## Method B — via the tamirs-marketplace catalog

```bash
codex plugin marketplace add Tamircohen28/tamirs-marketplace
codex plugin add tamirs-superpowers@tamirs-marketplace
```

## Method C — local clone

Useful when you want to edit skills and see the change immediately — a local marketplace reads straight from the working tree.

```bash
git clone https://github.com/Tamircohen28/tamirs-superpowers.git ~/src/tamirs-superpowers
codex plugin marketplace add ~/src/tamirs-superpowers
codex plugin add tamirs-superpowers@tamirs-superpowers
```

Update with `git pull` — no re-add needed.

> A marketplace **name** may only be registered once. If you already added this repo from a different path, remove it first: `codex plugin marketplace remove tamirs-superpowers`.

## What Codex picks up

`.codex-plugin/plugin.json` declares:

| Field | Contents |
|-------|----------|
| `skills` | The 7 skill domain directories — 27 skills |
| `hooks` | `./hooks/hooks.json` |
| `mcpServers` | `./.mcp.json` |

Plus, by convention at the repo root:

| Path | Purpose |
|------|---------|
| `AGENTS.md` | Contributor policy — Codex's primary instruction file |
| `.codex/config.toml` | Project-level Codex overrides |
| `agents/` | 6 specialist agents |

## MCP servers (optional)

Two routes:

```bash
codex mcp list          # what Codex currently has
```

The plugin's stubs come from `.mcp.json` via the `mcpServers` field. Fill the `${ENV_VAR}` placeholders in your shell environment — never commit tokens — then restart Codex.

## Verify

```bash
codex plugin list --marketplace tamirs-superpowers    # STATUS should read "installed, enabled"
codex doctor                                          # config, auth, and runtime health
```

Then in a session:

```
/tamirs-superpowers:find-skill
```

## What does not port

| Feature | Status on Codex |
|---------|-----------------|
| Statusline | ❌ Claude Code only |
| `.cursor/rules/*.mdc` | ❌ Cursor only — the same guidance lives in `AGENTS.md` |

Skills, hooks, agents, and MCP all work.

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| `marketplace root does not contain a supported manifest` | The source has no `.agents/plugins/marketplace.json`. Check you're on a branch that includes it. |
| `already added from a different source` | `codex plugin marketplace remove tamirs-superpowers`, then re-add. |
| Plugin listed but `not installed` | Run `codex plugin add tamirs-superpowers@tamirs-superpowers`. |
| Stale version after a release | `codex plugin marketplace upgrade` refreshes the Git snapshot. |
