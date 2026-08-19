# `setup` — render this repo's config onto your machine

`scripts/setup.sh` is the one writer. It reads the canonical configuration that
lives in this repository and renders it into the config directories the agent
CLIs on your machine actually read — `~/.claude`, and in a later phase
`~/.cursor`, `~/.codex`, `~/.gemini`, `~/.config/opencode`.

The direction is one-way and deliberate: **the repo is the source of truth, the
machine is rendered from it.** Nothing in `setup` reads your machine and writes
back into the repo — that is a separate, reviewed tool.

```bash
make setup             # detect, diff, confirm, write
make setup-plan        # show what would change; writes nothing
```

---

## Three verbs

| Verb | What it does | Writes? |
|------|--------------|---------|
| `plan` | Detects targets and prints exactly what would change. The default when there is no terminal. | Never |
| `apply` | `plan`, then a diff and a confirmation per change before writing. The default at a terminal. | Yes, after you say so |
| `remove` | Undoes what `apply` wrote, scoped to this installer's own backups and keys. | Yes, after you say so |

```bash
bash scripts/setup.sh plan
bash scripts/setup.sh apply --targets claude
bash scripts/setup.sh apply --yes --only notifications
bash scripts/setup.sh remove
```

## Flags

| Flag | Env twin | Meaning |
|------|----------|---------|
| `--targets a,b` | `SETUP_TARGETS` | Restrict to these targets. Also a *request*: a named target is planned even if it is not installed yet, so a fresh machine can be bootstrapped. |
| `--only <module>` | `SETUP_ONLY` | Restrict to one module, or a comma list. A family name selects the family: `--only notifications` picks up both `notifications-creds` and `notifications-hook`. |
| `--yes`, `-y` | `SETUP_YES=1` | Do not prompt; take the default action for every change. |
| `--dry-run` | — | Synonym for the `plan` verb. |
| `--json` | — | Machine-readable plan on stdout; human output moves to stderr. |
| `--verbose`, `-v` | `SETUP_VERBOSE=1` | Detailed logging to stderr. |
| `--help`, `-h` | — | Usage, then exit 0. |
| — | `SETUP_DESTRUCTIVE=skip` | Never touch a file you have customised, even under `--yes`. |

Exit codes: `0` success (including "no TTY, so here is the plan instead"),
`1` failure — a bad flag, an unknown target, a missing prerequisite.
`jq` is required.

---

## The five rules it follows

**1. Detection replaces selection.** You are never asked which targets to set up.
A target is present if its binary is on `PATH` or its config directory exists.
`--targets` filters that list; it is not a menu.

**2. Idempotence is a content comparison.** Each module builds the new file
*from* the file you already have, then compares. Identical means
`already up to date` — printed, skipped, no prompt, nothing written. There is no
state file and no install marker to get out of sync with reality. Run `apply`
twice and the second run does nothing.

**3. The diff comes before the question.** You see a unified diff of the exact
change, then `Proceed? [y/N/a/q]` — **default No**. `a` accepts everything
remaining, `q` stops. The diff shown is computed live against the file as it
stands at that moment, so approving it can never write something you did not see.

**4. Objects merge; arrays and scalars are asserted.** Objects recurse key by
key, so third-party wiring in a file this repo also writes survives — `hooks`,
`enabledPlugins`, `extraKnownMarketplaces`, `mcpServers` are all object-shaped and
all preserved. This is a change from the pre-Phase-2 `install.sh`, which rewrote
`~/.claude/settings.json` wholesale on every run and destroyed every key it did
not know about.

Arrays are **replaced**, not unioned — deliberately. Union would mean the repo
could never *retract* anything: delete an over-broad entry from
`permissions.allow` in the repo and, under union, it would stay live forever on
every machine that had ever applied it, invisibly. Asserting the array keeps each
fragment an honest description of its own result, which is the property that makes
`platforms/claude/settings.d/` reviewable.

Your own additions are safe because they have a home upstream of this installer:
**`~/.claude/settings.local.json`**, which `setup` never reads or writes and which
Claude Code merges on top of `settings.json`. An incremental "always allow" grant
lands there already.

**Repo-side metadata never reaches your files.** JSON has no comments, so the
fragments explain themselves in top-level keys beginning with `_` (`_comment`,
`_tally`). Those are stripped at the merge boundary and never written.

**5. Overwriting a file you customised is a separate question.** A module that
cannot merge — `~/.claude/CLAUDE.md` is markdown, not JSON — shows you what is at
stake and asks `overwrite / backup-and-write / skip`, defaulting to
**backup-and-write**, the choice that cannot lose data. Under `--yes` that
default is what runs; set `SETUP_DESTRUCTIVE=skip` to decline instead.

---

## Backups

The first time `setup` modifies a file, it copies the original to a **fixed,
documented name**:

```
~/.claude/settings.json.pre-tamirs-superpowers
```

That name never changes and is never overwritten, because `remove` keys off it.
Later runs that need another copy rotate to
`…​.pre-tamirs-superpowers-<UTC>`, for example
`settings.json.pre-tamirs-superpowers-2026-08-19T14:03:11Z`.

`remove` restores from the fixed backup — and rotates a dated copy of the current
file before it does, so undoing is itself undoable.

`~/.claude/pushover.env` is never deleted by `remove`. Those are your
credentials; a reinstall should not make you re-enter them. Delete it by hand to
purge.

---

## Prompts, stdin, and hooks

`setup.sh` **never reads stdin.** Prompts are written to and read from
`/dev/tty`. Your stdin — a hook's JSON payload, a descriptor inherited from a
harness, an idle terminal — is passed through untouched and can never make this
script block.

When there is no terminal to prompt on and you have not passed `--yes`, `setup`
prints the plan, says so, and **exits 0**:

```console
$ bash scripts/setup.sh apply </dev/null
Plan (5 change(s), 0 already up to date, 3 skipped)
  …
note: no TTY — cannot prompt. Showing the plan instead; re-run with --yes to apply.
$ echo $?
0
```

It never adopts silently, never errors on a missing terminal, and a destructive
change that cannot be shown is **declined**, not assumed. `--yes` is the only way
to write without a terminal, which makes it greppable in a dotfiles bootstrap or
a CI job.

---

## What it writes today

All five targets have implemented modules. A target that is not installed on
this machine is detected and skipped, rather than failing:

```
  ok  Claude Code    ~/.local/bin/claude
  --  Codex CLI      not installed
```

A target whose registry entry declares no modules yet would report
`no modules implemented yet` — that path still exists for a platform added in
future, but no shipped target uses it today.

### Claude Code modules

| Module | Target file | What it does |
|--------|-------------|--------------|
| `settings` | `~/.claude/settings.json` | Merges every fragment in `platforms/claude/settings.d/` — permissions, model, theme, auto-mode policy, marketplaces, env |
| `plugins` | `~/.claude/settings.json` | `enabledPlugins`. The repo's value wins per key, **including `false`** — a plugin recorded as disabled is disabled. Keys only your machine has are preserved. See the warning below |
| `statusline` | `~/.claude/settings.json` | Wires `statusLine` to a command that resolves the newest installed plugin version at runtime, so it survives updates |
| `agents` | `~/.claude/agents/` | Copies the specialist subagent definitions |
| `claude-md` | `~/.claude/CLAUDE.md` | Installs the global rules template. Destructive — see rule 5 |
| `notifications-creds` | `~/.claude/pushover.env` | Mode 600. Requires `PUSHOVER_TOKEN` **and** `PUSHOVER_USER` in the environment |
| `notifications-hook` | `~/.claude/settings.json` | One `Notification` hook; any other Notification hooks are left alone |
| `exit-guard` | `~/.claude/ensure-exit.sh` | Proxy exit-node guard. Requires `CLAUDE_EXIT_PROXY` and `CLAUDE_EXIT_PUBLIC_IP` |

Modules whose prerequisites are absent report why rather than failing:

```
    pushover.env   skip   ~/.claude/pushover.env   no PUSHOVER_TOKEN/PUSHOVER_USER in env — run /notify-setup
```

### Applying will switch some plugins off

The canonical set records 15 plugins as deliberately **disabled**. On a machine
where those are currently on, `apply` turns them off — that is the intended
behaviour, not a bug: the previous canonical set was all-on and would have
re-enabled plugins you had switched off on purpose.

The plan says so before anything is written, with the exact count:

```
enabledPlugins  modify  ~/.claude/settings.json   WILL DISABLE 15 currently-enabled plugin(s); 23 canonical (8 on), 0 local preserved
```

Run `make setup-plan` (or `--dry-run`) first to see the full list in the diff.
Plugins the repo says nothing about are left exactly as you have them.

---

## `install.sh`, `update.sh`, `uninstall.sh`

All three are now thin shims over `setup.sh` — one writer, one set of rules:

| Script | Equivalent |
|--------|-----------|
| `make install` | `setup.sh apply --yes --targets claude`, plus the marketplace next-steps |
| `make update` | the two `claude plugin` marketplace commands, plus `setup.sh apply --yes --targets claude --only agents,statusline` |
| `make uninstall` | `setup.sh remove --yes --targets claude`, plus `claude plugin uninstall` |

Each accepts `--dry-run`, `--verbose` and `--help`, which pass straight through.

---

## Adding a platform

The registry is one file per target, **sourced, not parsed** — macOS ships bash
3.2, which has no associative arrays.

```bash
# platforms/<name>/setup.conf
SETUP_NAME="cursor"
SETUP_DISPLAY="Cursor"
SETUP_DETECT="cursor-agent"                 # binary to look for on PATH
SETUP_CONFIG_DIR="${HOME}/.cursor"
SETUP_ENV_OVERRIDE="CURSOR_CONFIG_DIR"      # the platform's own override var
SETUP_MARKER="tamirs-superpowers"
SETUP_WRITERS="setup-cursor.sh"             # scripts/lib/setup-cursor.sh
SETUP_STATUS="implemented"
SETUP_MODULES="rules cli-config"            # module order is apply order
```

Writers live in `scripts/lib/setup-<name>.sh` — not in the `.conf` — so that
`make lint` shellchecks them. Each module is a **renderer**, not a writer: given
the file as it exists, it prints the file as it should exist, and the engine does
all the comparing, diffing, prompting, backing up and writing. That is why
idempotence and `remove`-symmetry are properties of the engine rather than
promises each module has to keep.

See `scripts/lib/setup-claude.sh` for the full function contract.

---

## Testing

```bash
bash tests/test-setup.sh
```

Every case runs against a `mktemp -d` fake `HOME` and asserts at the end that the
real `~/.claude` was untouched.
