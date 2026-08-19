# Install — Cursor

Registry id: `cursor`. Validated against Cursor **3.16.17**; that floor is the version this
repo actually tested, not a guess.

---

## Install

Cursor imports a plugin marketplace straight from a repo:

1. Open the Cursor **Dashboard** → **Plugins**.
2. **Team Marketplaces** → **Add Marketplace** → **Import from Repo**.
3. Point it at `Tamircohen28/tamirs-superpowers` (or `Tamircohen28/tamirs-marketplace`).
4. Install **tamirs-superpowers** from the imported listing.

Cursor reads [`.cursor-plugin/plugin.json`](../../../.cursor-plugin/plugin.json), the
canonical `skills/` tree, [`.cursor/rules/`](../../../.cursor/rules), `agents/`, and the MCP
stubs. Enable **Auto Refresh** on the marketplace and pushes propagate without a version
bump.

## Verify

```bash
jq empty .cursor-plugin/plugin.json
bash scripts/doctor.sh .
```

In Cursor:

1. Open the command palette and confirm the toolkit's skills are listed.
2. Invoke one by name — *"use the targeted-debug skill"*.
3. Confirm the `.cursor/rules/*.mdc` entrypoint is active in a chat in this project.

## Update

With **Auto Refresh** enabled, Cursor picks up repo pushes on its own. Otherwise, refresh the
marketplace from the Plugins dashboard and reinstall. A version bump is not required for
refresh, but it is what tells you which build you have:

```bash
jq -r .version .cursor-plugin/plugin.json
```

## Uninstall

Remove the plugin from the Cursor Plugins dashboard, then remove the imported marketplace if
you no longer want it. Project-level `.cursor/rules/` and `.cursor/hooks.json` are files in
your repo — delete them separately if you added them by hand.

---

## Machine-level setup

The plugin install covers this repo. Global rules in `~/.cursor` are a separate, optional
step:

```bash
bash scripts/setup.sh plan  --targets cursor    # writes nothing
bash scripts/setup.sh apply --targets cursor
bash scripts/setup.sh remove --targets cursor
```

| Module | Writes | What it does |
|---|---|---|
| `rules` | `~/.cursor/rules/tamirs-superpowers.mdc` | Renders `core/global-rules.md` as a global Cursor rule |
| `cli-config` | `~/.cursor/cli-config.json` | Merges one conservative `permissions.allow` fragment |

The allow fragment is read-only shell inspection (`ls`, `git status`, `git log`, `git diff`)
plus the three GitHub domains the shipped skills fetch. It is deliberately **not** a
mechanical translation of the Claude allow-list: Cursor's `Shell()`/`Read()`/`Write()`/
`WebFetch()`/`Mcp()` syntax does not map one-to-one onto Claude's `Bash()` patterns, and a
guessed translation would be a security claim this repo cannot back.

Not touched, on purpose: **`permissions.deny`** — in Cursor deny beats allow, so an
installer able to widen it could lock you out of your own tool — and `~/.cursor/hooks.json`,
which no module reads or writes, so hook wiring written by other tools survives.

`plan` writes nothing and is the default when there is no terminal, so a hook or CI run can
never adopt anything silently. `apply` shows a diff and asks per change, defaulting to
**No**. Re-running is a no-op — idempotence is a content comparison. Full reference:
[setup](../setup.md) · [platform setup](../platform-setup.md).

## Capabilities and limitations

| Capability | Status | Notes |
|---|---|---|
| skills | native | since 3.16.17 |
| subagents | native | declared capability |
| slash commands | native | |
| MCP | native | `.mcp.json` |
| git · shell · GitHub CLI | native | `gh` is an optional host dependency everywhere |
| auto-invocation | partial | Sticky skills are documented for the Cursor CLI; description-based selection across all surfaces is unverified here — **name the skill** |
| hooks | partial | **Claude-shaped plugin hooks (`hooks/hooks.json`, `CLAUDE_PLUGIN_ROOT`) do not run under a Cursor plugin install.** Project-level `.cursor/hooks.json` ships soft contributor guards; third-party Claude hooks via `.claude/settings.json` are opt-in in Cursor Settings |
| worktree isolation | emulated | The skill runs `git worktree` itself; no hook automation |
| parallel subagents · background tasks · structured questions · session transcripts | unknown | Not measured — treated as unavailable, with stated fallbacks |
| statusline · artifacts · extension install | unsupported | Cosmetic, absent, and not a Cursor mechanism, respectively |

**The one to internalize:** hook guards are advisory in Cursor. The same rules are enforced
in CI, which is where they actually bind.

Source of truth: [`core/capabilities/platforms.json`](../../../core/capabilities/platforms.json).
Comparison: [platform differences](../platform-differences.md).
