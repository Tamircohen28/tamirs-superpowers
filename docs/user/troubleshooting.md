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
- [Platform differences](platform-differences.md) — what your platform can actually do
- [Engineering docs](../engineering/README.md) — how the pieces fit together
- [Open an issue](https://github.com/Tamircohen28/tamirs-superpowers/issues)
