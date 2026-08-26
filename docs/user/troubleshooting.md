# Troubleshooting

Start with the health report — it answers most of what follows:

```bash
bash scripts/doctor.sh .
```

It names the detected platform, any version drift, missing required and optional tools, and
a one-line remedy per gap. It exits non-zero only when the install is genuinely broken.

Before treating something as a bug, check [platform differences](platform-differences.md).
A lot of "it does not work" is documented, honest degradation: hooks do not run under a
Cursor plugin install, parallel subagents exist only on Claude Code, session transcripts are
readable only on Claude Code.

---

## Install and updates

### Skills do not appear after installing

**Cause:** the plugin installed but the session has not picked it up, or the marketplace
suffix was wrong.

**Fix:** the `@` suffix names the *marketplace*, and it differs between the two sources —
`tamirs-superpowers@tamirs-superpowers` from this repo, `tamirs-superpowers@tamirs-marketplace`
from the catalog. Reinstall with the right one, then `/reload-plugins` on Claude Code older
than 2.1.221. Per-platform steps: [install guides](install/README.md).

**If `/reload-plugins` itself reports `0 skills` found:** this plugin's `skills` array in
`plugin.json` points at *category directories* (`./skills/dev-workflow`, `./skills/toolkit`,
…), with each actual `SKILL.md` one level further down (`./skills/dev-workflow/start-dev/SKILL.md`)
— exactly the `skills/*/SKILL.md`-under-a-declared-root layout that `/reload-plugins` on
Claude Code versions before **2.1.246** failed to discover, reporting `0 skills` for the
whole plugin even though every `SKILL.md` was well-formed. Upgrade to 2.1.246 or later;
there is no plugin-side workaround for the older bug.

### An update reports success but nothing changed

**Cause:** Claude Code and Codex cache by the manifest `version` field. A push without a
version bump does not reach installed users, and `/reload-plugins` does not fetch from
GitHub.

**Fix:** check the canonical version, then update the marketplace before updating the plugin:

```bash
jq -r .version plugin-version.json
```

```text
/plugin marketplace update tamirs-superpowers
/plugin update tamirs-superpowers@tamirs-superpowers
```

### `jq: command not found` at session start

Every hook and check script parses JSON with `jq`. Install it — `brew install jq` — and
restart the session.

## Setup and machine config

### `setup` printed a plan and exited without asking me anything

There was no terminal to prompt on. `setup.sh` reads prompts from `/dev/tty` and **never
from stdin** — stdin belongs to the caller, and a hook pipes JSON on it — so when it cannot
open a terminal it prints the plan, says so, and exits **0**:

```console
note: no TTY — cannot prompt. Showing the plan instead; re-run with --yes to apply.
```

That is success, not failure. It never adopts silently. To write without a terminal — a
dotfiles bootstrap, a CI job — pass `--yes` explicitly:

```bash
bash scripts/setup.sh apply --yes --targets claude
SETUP_DESTRUCTIVE=skip bash scripts/setup.sh apply --yes   # never touch a customised file
```

`--yes` takes the *default* action for every change, and for a file that cannot be merged
the default is backup-and-write, the choice that cannot lose data.

### `apply` turned off plugins I was using

Intended, and announced before it happened. The canonical set records 15 plugins as
deliberately disabled; on a machine where they were on, `apply` turns them off. The previous
canonical set was all-on and would have re-enabled plugins you had switched off on purpose,
which is the failure this fixes.

To see the list before agreeing, `make setup-plan` and read the `enabledPlugins` diff. To
keep one on afterwards, re-enable it in Claude Code — but note the next `apply` will assert
the recorded value again. The durable fix is to change `platforms/claude/settings.d/plugins.json`
in the repo (`scripts/capture-config.sh` proposes exactly that from your machine's state).
Plugins the repo says nothing about are never touched.

### A platform I have was detected but skipped

Read the reason in the plan line; `setup` reports why rather than failing silently. The
usual ones:

- **`no PUSHOVER_TOKEN/PUSHOVER_USER in env`** — an optional module whose prerequisites are
  absent. Run `/notify-setup`, or ignore it.
- **`--only` or `--targets` filtered it out.** `--targets` is a *filter over detection*, not
  a menu — but naming a target explicitly also plans it even if the platform is not
  installed yet, which is how a fresh machine gets bootstrapped.
- **A module has nothing to do.** `already up to date` means the content comparison found
  the file identical; nothing is written and nothing is wrong.

Run with `--verbose` for the full decision trace, or `--json` for the plan as data.

### I want my old config back

Every file `setup` modifies is copied first to a **fixed name** that is never overwritten:

```bash
ls ~/.claude/settings.json.pre-tamirs-superpowers
```

`bash scripts/setup.sh remove` restores from that copy — and rotates a dated copy of the
current file first, so undoing is itself undoable. Later runs that need another copy rotate
to `<file>.pre-tamirs-superpowers-<UTC>`. `remove` strips only the marker blocks and the
values that are still what setup wrote; anything you have since changed is yours and stays.
`~/.claude/pushover.env` is deliberately never deleted — delete it by hand to purge.

One honest limitation on the other four platforms: an array entry that was in **both** your
config and our fragment is removed on `remove`, because the merge leaves no record of who
put it there first. The `.pre-tamirs-superpowers` backup is the recovery path.

### My Codex hooks are not managed by setup

Correct, and deliberate. `~/.codex/config.toml` stores a per-hook `trusted_hash` under
`[hooks.state."..."]`, and Codex invalidates that trust whenever the hook's content or path
changes — re-trusting is a user action. Rewriting, reordering, or even reindenting that
table would silently break wiring this installer does not own, so **the Codex renderer never
reads or writes hook entries**. Its block sits at the end of the file and contains comments
only. Codex loads `~/.codex/AGENTS.md` on its own, so no config key is needed to enable the
rules. Manage Codex hooks with whatever wrote them.

### A hand edit I made to `~/.claude/settings.json` disappeared

That file is rendered from `platforms/claude/settings.d/`, so a hand edit to a key the repo
owns is overwritten on the next `apply`. Two correct homes for an edit:

- **`~/.claude/settings.local.json`** for something true only on this machine. Setup never
  reads or writes it and Claude Code merges it on top.
- **The fragment in the repo** for something you want on every machine and platform.
  [capture](capture.md) diffs your machine against what the repo would render and classifies
  each difference; `review` stages the ones you adopt into the canonical source; `deliver`
  opens a PR. It never commits silently, refuses token-shaped values outright, and
  reclassifies absolute home paths (`/Users/you/...`) as machine-local.

## Workflow

### A worker did not open a PR

Working as designed. A task ends at **commit + handoff**; the objective opens exactly one PR
at the end, from `/deliver-dev`. See
[work unit ≠ delivery unit](concepts.md#2-work-unit--delivery-unit).

### Everything ran sequentially

The capability registry records `parallel_subagents` as `native` only on Claude Code.
Everywhere else it is `unknown`, so the orchestrator degrades honestly instead of pretending
to fan out. Same task graph, same handoffs, same single PR — only wall-clock time differs.
[Details](orchestration.md#execution-modes).

### An objective was interrupted and I do not know where it stands

State is files on disk, so nothing is lost:

```bash
S=skills/dev-workflow/_shared/scripts/objective-state.sh
bash $S list
bash $S tasks <objective-id>
bash skills/dev-workflow/_shared/scripts/handoff.sh list <objective-id>
```

Re-invoke `/orchestrate-dev <objective-id>` to resume. **Do not re-run a task whose handoff
already exists** — that duplicates commits and invalidates the integration plan.
[Details](orchestration.md#resuming-an-interrupted-objective).

### A worker refuses to edit a file

The file is outside the task's `scope[]`. That is the mechanism that keeps concurrent
workers from colliding. The work becomes a `followup` in the handoff, or the orchestrator
adds a task. `handoff.sh emit` rejects out-of-scope writes deliberately.

### "Repo edits must happen in a dedicated worktree"

The `enforce-worktree-edits` hook (Claude Code only). Either move into the task worktree —
one is created under `~/.claude/worktrees/<repo>/<slug>/` after your first prompt — or, if
you deliberately mean to edit the main checkout, disable that hook entry in your install.

### Delivery stopped at a pushed branch

`gh` is missing or unauthenticated. It is an *optional* feature dependency, so the workflow
reports exactly what it did rather than claiming a PR exists. Run `gh auth login` and
re-invoke `/deliver-dev`.

## Platform-specific

### Hook guards are not firing in Cursor

Expected. Claude-shaped plugin hooks (`hooks/hooks.json`, `CLAUDE_PLUGIN_ROOT`) do not run
under a Cursor plugin install. Project-level `.cursor/hooks.json` provides soft guards, and
Claude hooks via `.claude/settings.json` are an opt-in Cursor setting. The same rules are
enforced in CI, which is where they bind. [Install guide](install/cursor.md).

### No hooks at all in OpenCode

OpenCode has no `hooks.json`; its only lifecycle mechanism is a JS/TS plugin API, and this
repo ships no plugin module by design. Guards become explicit in-skill steps plus CI checks.
[Install guide](install/opencode.md).

### `/session-report` returns nothing

It parses Claude Code's JSONL transcripts under `~/.claude/projects` and no other format.
Everywhere else `session_transcripts` is `unknown` and the skill refuses rather than
reporting zeros.

### The statusline does not appear

Claude Code only, and cosmetic — nothing depends on it. It is wired automatically through
the plugin manifest's `settings.statusLine`. If the footer is empty:

```bash
echo '{}' | bash scripts/statusline.sh    # must print something and must not block
which git                                  # branch rendering needs git on PATH
```

A `statusLine` entry in your `~/.claude/settings.json` **shadows** the manifest's. If you
added one by hand, either remove it or keep it version-agnostic — a pinned version directory
stops matching after an update, and the command guard then renders an empty statusline
rather than an error, so the breakage is silent.

## Still stuck

- [Configuration](configuration.md) — what each feature needs to be turned on
- [Setup](setup.md) · [Platform setup](platform-setup.md) · [Capture](capture.md) — the machine-config engine, both directions
- [Platform differences](platform-differences.md) — what your platform can actually do
- [Engineering docs](../engineering/README.md) — how the pieces fit together
- [Open an issue](https://github.com/Tamircohen28/tamirs-superpowers/issues)
