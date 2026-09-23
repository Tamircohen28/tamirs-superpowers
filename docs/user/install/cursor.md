# Install — Cursor

Registry id: `cursor`. Validated against Cursor desktop **3.21.13** (feature changelog
**3.11**, covered through date-only **2026-09-10**); that floor is the version this repo
actually tested, not a guess.

---

## Install

Cursor imports a plugin marketplace straight from a repo:

1. Open the Cursor **Dashboard** → **Plugins**.
2. **Team Marketplaces** → **Add Marketplace** → **Import from Repo**.
3. Point it at `Tamircohen28/tamirs-superpowers` (or `Tamircohen28/tamirs-marketplace`).
4. Install **tamirs-superpowers** from the imported listing.

Cursor reads [`.cursor-plugin/plugin.json`](../../../.cursor-plugin/plugin.json), the
canonical `skills/` tree, [`.cursor/rules/`](../../../.cursor/rules) — declared explicitly,
see below — `agents/`, and the MCP stubs. Enable **Auto Refresh** on the marketplace and pushes propagate without a version
bump.

## Hooks do not come with the install

Worth knowing before you assume the safety guards are active: **a Cursor install of this
plugin wires none of its hooks.**

Cursor *can* import Claude Code hooks, and the setting is on by default
(Settings → Agents → Third-Party Imports → "Include Third-Party Plugins, Skills, and Other
Configs"). But it reads them from exactly three paths:

- `.claude/settings.local.json`
- `.claude/settings.json`
- `~/.claude/settings.json`

This plugin ships its hooks in `hooks/hooks.json`, wired through the plugin manifest — which
is not one of those three. The files are all present on disk after an install (see the
section below), but nothing loads them.

**One exception, and it is not part of the install.** This repo ships
[`.cursor/hooks.json`](../../../.cursor/hooks.json) with a single advisory
`beforeShellExecution` hook for people working *on this repo* in Cursor. Cursor reads
`.cursor/hooks.json` from the **project root**, so that file applies when this repo is your
open project — it is not delivered to your project by installing the plugin, and
`.cursor-plugin/plugin.json` declares no `hooks` field. It is a useful proof that the
Cursor-native format works here, not a counterexample to the paragraph above.

Of the 10 events this repo wires, Cursor's published mapping covers 6 — `PreToolUse`,
`PostToolUse`, `UserPromptSubmit`, `Stop`, `SessionStart`, `SessionEnd`. The other four —
`Notification`, `DirectoryAdded`, `WorktreeCreate`, `WorktreeRemove` — have no Cursor
equivalent, so even a hand-copied translation would be lossy.

A Cursor-native bundle, in Cursor's own richer 21-event format, is tracked as
[#179 E1](https://github.com/Tamircohen28/tamirs-superpowers/issues/179).

## What an install actually materializes

Worth knowing, because it is the difference between 29 working skills and 29 that silently
no-op: **a Cursor install is a full git clone of the repo, not a Markdown-only sync.** Cursor
materializes it twice, under `~/.cursor/plugins/cache/` and `~/.cursor/plugins/marketplaces/`,
and both copies carry every tracked file.

Measured against a real install on macOS (Cursor 3.21.16, install copy at plugin 2.0.1):

| | |
|---|---|
| Tracked paths vs. the source commit | **identical** — zero files dropped |
| Non-Markdown files | 263 of 452 |
| Shell scripts | 103 `.sh`, **87 executable** |
| Executable-bit mismatches vs. source | **0**, across all 451 files |
| `hooks/hooks.json` + hook scripts | present, all 25 |
| Python helpers / JSON config | 14 `.py`, 53 `.json` |

`git status` inside the installed copy reports no modified or deleted tracked files — only an
untracked `.cache-complete` marker that Cursor writes itself.

This matters because the repo's contract tests run against a local checkout and never an
installed copy, so nothing in CI would catch an install path that dropped shell assets. It
does not drop them; the mechanism is a clone, so there is no file-type filter to get wrong.

**Still unverified:** skill *invocation* inside Cursor — palette listing and invoking a skill
by name. Asset delivery being sound does not establish that, and the capability registry
reflects the narrower claim.
## Rules are declared, not discovered

The manifest points `rules` at `./.cursor/rules/` on purpose. Cursor's automatic component
discovery falls back to a default `rules/` folder when the field is omitted — and in this
repo `rules/` is the **canonical markdown** (plus a `README.md`), not the 13 purpose-built
`.mdc` files with Cursor frontmatter.

So an omitted field would not have meant "no rules". It would have meant the wrong ones:
canonical `.md` shipped in place of the `.mdc` mirror, a README loaded as a rule, and the
five rules that exist **only** as `.mdc` — `commit-conventions`, `hooks-guide`,
`plugin-structure`, `skill-frontmatter`, `skills-guide` — never shipping at all.

Both halves of that are silent, so `tests/test-static.sh` asserts the declaration rather
than leaving it to a comment.

**The same trap applies to `hooks`.** A Cursor plugin's `hooks` component has the identical
discovery behaviour: it defaults to `hooks/hooks.json` and expects **Cursor's** camelCase
event format (`preToolUse`, `beforeShellExecution`, `sessionEnd`). This repo's file at that
exact path is Claude's **PascalCase** format, so discovery finds it and yields no usable
events. That is a cheaper route for a Cursor hook bundle than the `settings.json` import
path — a Cursor-format file declared in the manifest, with no `settings.json` involvement —
and is tracked as [#179 E1](https://github.com/Tamircohen28/tamirs-superpowers/issues/179).

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
| skills | native | since desktop 3.21.13 pin; pin as **Custom Mode** (2026-08-19) via ⌥⏎ / Alt+Enter from `/` |
| subagents | native | declared capability; cloud subagents can use **isolated VMs** (2026-08-19) |
| slash commands | native | |
| MCP | native | `.mcp.json` |
| git · shell · GitHub CLI | native | `gh` is an optional host dependency everywhere |
| auto-invocation | partial | CLI sticky skills + Custom Modes; description-based selection across all surfaces is unverified — **name the skill** or pin a mode |
| hooks | partial | **Claude-shaped plugin hooks (`hooks/hooks.json`, `CLAUDE_PLUGIN_ROOT`) do not run under a Cursor plugin install.** Project-level `.cursor/hooks.json` ships soft contributor guards; third-party Claude hooks via `.claude/settings.json` are opt-in in Cursor Settings |
| worktree isolation | emulated | The skill runs `git worktree` itself; no hook automation |
| parallel subagents | partial | Cloud swarm on isolated VMs (2026-08-19); local concurrency unmeasured |
| background tasks · structured questions · session transcripts | unknown | Not measured — treated as unavailable, with stated fallbacks |
| statusline · artifacts · extension install | unsupported | Cosmetic, absent, and not a Cursor mechanism, respectively |

### Working tips (3.11 → 2026-09-10; desktop CLI 3.21.13; CLI 2026-08-26)
- **Projects (2026-09-10)** — Cursor **Projects** (left nav) suit multi-week / multi-agent work. A **coordinator** plans and delegates (does not write code); **shared context** files sync across cloud and local agents; **subscriptions** can watch Slack, schedules, or all PRs. Use a Project when validating this plugin across a long refactor or multi-PR initiative; keep ordinary `/diagnose-refusal` / one-shot skill runs in a normal Agent chat. Projects compose with (do not replace) Cloud Agents, Custom Modes, and Self-Hosted Machines ([changelog](https://cursor.com/changelog)).
- **CLI persistent sessions (2026-08-26)** — keep a long `agent` validation / `make validate` session alive across disconnects with `agent persist`, `/detach`, and `agent persist attach` ([CLI changelog](https://cursor.com/docs/cli/changelog)). Useful for cloud-headless and overnight plugin checks; prefer over killing the client mid-run.
- **Self-Hosted Machines (2026-09-02)** — Cursor can run Cloud Agent tool execution on **My Machines**, **Team Pools** (dynamic scale + hibernation), or partner sandboxes (AWS Lambda, Coder, Cloudflare, Daytona, Modal, Namespace, Vercel, E2B), with **computer use** on Linux/Mac ([docs](https://cursor.com/docs/cloud-agent/self-hosted)). Inventory workers with `list-self-hosted-workers`. **Not** the same as GitHub Actions `runs-on: [self-hosted]` — this public plugin repo stays on `ubuntu-latest` forever. Prefer managed Cloud Agents for validation; self-hosted only when private network / custom hardware requires it.

- **Start from scratch / no SCM (2026-08-27)** — Cloud Agents can begin without a connected GitHub repo: pick **Start from scratch**, prompt immediately, then **Create repo** to save into Origin (private/internal). Use **browser port-forward preview** (design mode) while the agent runs; optional **Vercel publish** for a live URL. GitHub remains canonical for marketplace installs and CI.

- **Custom Modes (2026-08-19)** — from `/`, pick a skill and press ⌥⏎ (Mac) or Alt+Enter (Windows) → **Use as Mode**. The skill stays pinned for the chat. Prefer this for `repo-standards`, `targeted-debug`, `platform-sync`, or any long playbook instead of re-invoking each turn.
- **`/goal` + steering (2026-08-19)** — give a long-lived objective with `/goal` (pair with a Custom Mode). Follow-ups now wait for the next tool call instead of cutting mid-action; type a follow-up and Send, or press ⏎ twice. Cloud Agents also expose native **CreateGoal** / **UpdateGoal** tools for the same long-lived objective pattern. CLI Aug 11 steer/`/goal` notes still apply for `agent` runs.
- **Subscriptions (Cloud Agents, 2026-08-19)** — agents can wake on PR events, Slack threads, or schedules; agents auto-subscribe to PRs they create and drive CI/review comments. Useful for unattended plugin validation Automations.
- **Subagents on their own machines (2026-08-19)** — cloud subagents get isolated project copies. Prefer for collision-free `make validate` / swarm checks.
- **Origin (2026-08-17)** / **Builds (default 2026-08-17)** — GitHub remains canonical for marketplace installs and CI; Origin is optional mirror. Confirm Cloud environments have a recent successful Build.

**The one to internalize:** hook guards are advisory in Cursor. The same rules are enforced
in CI, which is where they actually bind.

Source of truth: [`core/capabilities/platforms.json`](../../../core/capabilities/platforms.json).
Comparison: [platform differences](../platform-differences.md).
