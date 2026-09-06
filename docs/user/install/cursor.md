# Install — Cursor

Registry id: `cursor`. Validated against Cursor desktop **3.18.9** (feature changelog
**3.11**, covered through date-only **2026-09-02**); that floor is the version this repo
actually tested, not a guess.

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
| skills | native | since desktop 3.18.9 pin; pin as **Custom Mode** (2026-08-19) via ⌥⏎ / Alt+Enter from `/` |
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

### Working tips (3.11 → 2026-09-02; desktop CLI 3.18.9)
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
