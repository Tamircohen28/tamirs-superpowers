# Claude Code machine config

How this repo reproduces a Claude Code *machine* — `~/.claude/` — rather than
just a project.

## The rule

**The repo is canonical; the machine is rendered from it.** Everything the
installer writes to `~/.claude/` has a source file here. If a setting exists only
on a machine, it is unreproducible and will be lost the next time that machine
is rebuilt — that is the failure this directory closes.

## What lives where

| Machine artifact | Repo source |
|---|---|
| `~/.claude/settings.json` | `platforms/claude/settings.d/*.json` (7 fragments) |
| `~/.claude/CLAUDE.md` | `templates/global-CLAUDE.md` |
| `~/.claude/agents/*.md` | `agents/*.md` |
| hooks (incl. `docker-guard.py`) | `hooks/` + `hooks/hooks.json`, delivered via the plugin cache |
| statusline | `.claude-plugin/plugin.json` → `scripts/statusline.sh` |
| `~/.claude/pushover.env` | written from env at install time; **no source file, by design** |

## Why `settings.d/` is split

The live `settings.json` is one 7 KB blob with 26 top-level keys, 50 `allow`
entries and 39 `ask` entries. As a single canonical file it is unreviewable: a
diff that changes one permission looks the same as one that flips every plugin.

Splitting it along policy boundaries makes each change legible in review:

- `permissions-allow.json` / `permissions-ask.json` — the permission policy,
  where the reviewer's question is "what did this add or remove?"
- `plugins.json` — where the reviewer's question is "did a `false` become a
  `true`?" This is the fragment with the sharpest failure mode (see below).
- `defaults.json`, `auto-mode.json`, `misc.json`, `marketplaces.json` — small,
  slow-moving, and each about one thing.

Splitting also makes the fragments independently overridable later: a target or
profile can supply its own `plugins.json` without restating the permission
policy.

## The merge contract

1. Strip every top-level key beginning with `_`. JSON has no comments, so
   `_comment` and `_tally` carry the prose that explains the data.
2. Deep-merge the fragments in filename order into one settings object.
3. Deep-merge that over the existing `~/.claude/settings.json`.

Deep, not shallow: `permissions` is split across three fragments (`allow`,
`ask`, and `defaultMode` in `defaults.json`), and a shallow merge would keep
only the last.

**Arrays replace, they do not append.** `permissions.allow` in the fragment is
the entire intended policy. This is deliberate: an appending merge means the
file no longer tells you what the result will be, and removing a stale entry
becomes impossible without a separate "remove" mechanism.

**Merge, never clobber the file.** Third-party keys already present on the
machine — other orchestrators' hook wiring, plus `hooks` and `statusLine` —
survive because step 3 is a
merge over the existing document, not a rewrite of it.

Reference implementation:

```sh
jq -s 'map(with_entries(select(.key|startswith("_")|not)))
       | reduce .[] as $f ({}; . * $f)' platforms/claude/settings.d/*.json
```

Verification that the capture is faithful — this diff is empty today:

```sh
diff <(jq -S 'del(.hooks, .statusLine) | .extraKnownMarketplaces |= del(.gitkraken)' ~/.claude/settings.json) \
     <(jq -s -S 'map(with_entries(select(.key|startswith("_")|not))) | reduce .[] as $f ({}; . * $f)' \
          platforms/claude/settings.d/*.json)
```

## `enabledPlugins` polarity

The captured map is **8 true / 15 false**. The `false` entries are a record of a
decision, not absent data. A canonical "all enabled" set — which is what the repo
asserted before this capture — silently re-enables 15 plugins the user turned
off. The engine must write the map as recorded, and must never read `false` as a
default awaiting correction.

## `docker-guard.py`

`hooks/docker-guard.py` is wired as `PreToolUse` on `Bash`. It blocks (with
`deny`, not `ask`) Docker commands that leave durable state on the machine —
`run`, `create`, `start`, `compose up`, `build`, `pull`, `volume create`,
`network create`, any `prune` — plus `make`/`npm run`/`just` targets that
historically wrap docker. Read-only inspection and `docker stop`/`rm`/`down`
pass unprompted.

It duplicates `permissions.ask` on purpose. `permissions.defaultMode` is
`bypassPermissions` on this machine, which makes `ask` inert; hooks run in every
permission mode, and a `deny` decision sets a blocking error that survives
bypass. `permissions-ask.json` remains the right policy for any machine not in
bypass mode.

Overrides: `PM_ALLOW_DOCKER=1` inline on the command, or exported for a session.
The name in the block message comes from `DOCKER_GUARD_OWNER`. The script reads
stdin under a `select()` timeout (`DOCKER_GUARD_STDIN_TIMEOUT`, default 2s), so
an absent or interactive stdin exits immediately rather than hanging the tool
call.

## Deliberately not captured

| Not captured | Why |
|---|---|
| Pushover token/user, `~/.claude/pushover.env` | Secrets. They come from `PUSHOVER_TOKEN` / `PUSHOVER_USER` at install time and are written mode 600. Naming the env var is the most the repo may do. |
| `~/.claude/settings.local.json` | Machine-local overrides by definition — capturing them would make "local" meaningless and would leak per-machine state into a shared repo. |
| `extraKnownMarketplaces.gitkraken` | Its source is a local *directory* under `$HOME/.claude/plugins/marketplaces/`, which does not exist on another machine. Recording it makes the rendered settings unportable; the GitKraken tooling installs it itself. |
| `settings.json` `hooks` and `statusLine` | Owned by `hooks/hooks.json` and `.claude-plugin/plugin.json`. Duplicating them in `settings.d/` would create two sources for one value. |
| The 20 unwired scripts in `~/.claude/hooks/` | Dead weight from a pre-plugin era; the plugin delivers its own hooks from the cache. Only `docker-guard.py` was live, and it is now in the repo. |
| `~/.claude` being a local git repo with no remote | A competing, undocumented backup mechanism. Out of scope; noted so it is not mistaken for this system. |
| Third-party machine wiring written by other orchestrators | Not authored here. The merge contract exists so it survives untouched. |

## See also

- [`platforms/claude/settings.d/README.md`](../../../platforms/claude/settings.d/README.md) — the per-file breakdown
- [`docs/engineering/architecture/hooks-classification.md`](hooks-classification.md)
