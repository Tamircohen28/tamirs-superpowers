# `platforms/claude/settings.d/` — canonical Claude Code settings

These files are the **source of truth** for `~/.claude/settings.json`.
The machine file is *rendered* from them. Hand-editing `~/.claude/settings.json`
is not the workflow: the next `setup apply` merges these fragments over it and
your edit is either overwritten or silently diverges. Change the fragment, then
re-run setup.

Captured from the live machine on **2026-08-19**.

## The contract

Every file is a **partial `settings.json` object** — the same key shape Claude
Code expects, holding only the keys that fragment owns. The setup engine:

1. strips every top-level key beginning with `_` (documentation only — JSON has
   no comments, so `_comment` and `_tally` carry the prose),
2. deep-merges the fragments in filename order into one object,
3. deep-merges that object over the existing `~/.claude/settings.json`.

Deep merge matters: `permissions` is deliberately split across three files
(`permissions-allow`, `permissions-ask`, `defaults` for `defaultMode`), and a
shallow merge would drop two of the three.

**Arrays are replaced wholesale, never appended.** `permissions.allow` here is
the *whole* intended allow policy, not an addition to whatever is on disk. That
is what makes the fragments reviewable — the file says exactly what the result
will be.

Reference implementation of the merge:

```sh
jq -s 'map(with_entries(select(.key|startswith("_")|not)))
       | reduce .[] as $f ({}; . * $f)' platforms/claude/settings.d/*.json
```

## The files

| File | Owns | Notes |
|---|---|---|
| `defaults.json` | `$schema`, `model`, `effortLevel`, `theme`, `tui`, `permissions.defaultMode`, 11 UX booleans | `model` is `opus[1m]` (the 1M-context variant), `effortLevel` is `medium` |
| `permissions-allow.json` | `permissions.allow` — 50 entries | 14 general + 36 docker read-only |
| `permissions-ask.json` | `permissions.ask` — 39 entries | every mutating docker/colima command + 3 `make` targets that wrap docker |
| `auto-mode.json` | `autoMode.soft_deny` | `$defaults` plus the docker-containers prose rule |
| `misc.json` | `skillOverrides`, `disableClaudeAiConnectors`, `disabledMcpjsonServers`, `env` | |
| `plugins.json` | `enabledPlugins` — 23 keys, **8 true / 15 false** | the `false` entries are intentional; see below |
| `marketplaces.json` | `extraKnownMarketplaces` — 3 github sources | `gitkraken` excluded; see below |

## Two things worth reading before you edit

**`enabledPlugins` polarity.** The `false` values are a deliberate record of
plugins the user turned off, not missing data. An "all true" canonical set would
re-enable 15 plugins on the next install. The engine must write the map exactly
as recorded and must never treat `false` as a default to be corrected.

**`gitkraken` is excluded from `marketplaces.json`.** Its live source is a local
directory under `$HOME/.claude/plugins/marketplaces/gitkraken`, which does not
exist on another machine; recording it would make the rendered settings
unportable. The GitKraken tooling installs it itself.

## Not captured here, on purpose

- **Secrets.** No credential value ever enters this directory. Pushover is
  configured from `PUSHOVER_TOKEN` / `PUSHOVER_USER` at install time and written
  to `~/.claude/pushover.env` (mode 600).
- **`hooks`** — wired by `hooks/hooks.json` (plugin-delivered) and, for the
  Pushover `Notification` hook, by the installer when the env vars are present.
- **`statusLine`** — comes from `.claude-plugin/plugin.json`.
- **`settings.local.json`** — machine-local overrides by definition.

Full rationale: [`docs/engineering/architecture/claude-machine-config.md`](../../../docs/engineering/architecture/claude-machine-config.md).
