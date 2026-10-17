# Install — Codex CLI

**Platform:** Codex. **Surface:** Codex CLI — registry id `codex`. Everything on this page,
install commands and capability table alike, was measured on the CLI. Codex's other surface,
the **Codex IDE extension**, is **unverified**: this repo has never installed the plugin or
invoked a skill there, so it has no install guide and no capability claims in either
direction. See [platform differences](../platform-differences.md#unverified-surfaces).

Skills require Codex **0.40+**; the manifest `hooks` field requires **0.147.0+**. Direct CLI
validation is **0.156.0** — a live `codex` run on 2026-09-23 installed this plugin through a
local marketplace and confirmed the install preserves its 144 executable `.sh` files,
`hooks/hooks.json`, 10 agent definitions and 35 `SKILL.md`. The official release delta is
reviewed through the same **0.156.0**, which is the version tracked by `.codex-version`.

---

## Install

```bash
codex plugin marketplace add Tamircohen28/tamirs-superpowers
codex plugin add tamirs-superpowers@tamirs-superpowers
```

Codex resolves [`.agents/plugins/marketplace.json`](../../../.agents/plugins/marketplace.json)
and then one of two manifests. Codex **0.147+** reads the root Agent Plugins manifest
[`plugin.json`](../../../plugin.json) and takes its Codex settings from
`extensions.com.openai`; when that object is present it **replaces**
[`.codex-plugin/plugin.json`](../../../.codex-plugin/plugin.json) entirely, so the overlay
is the fallback for older hosts only. Both are generated from one source by
`scripts/build-manifests.sh` and cannot disagree ([manifests](../../engineering/build-and-release/manifests.md)).
Skills come from the canonical `skills/` tree (listed as seven roots in the overlay; the
root manifest relies on Codex scanning `skills/`). Hooks come from the **generated**
[`platforms/codex/hooks.json`](../../../platforms/codex/hooks.json), not from
`hooks/hooks.json` — see [Hooks on Codex](#hooks-on-codex). MCP servers are declared by
the manifest: the root [`mcp.json`](../../../mcp.json) on the Agent Plugins route,
[`.mcp.json`](../../../.mcp.json) on the overlay route — never
[`.codex/config.toml`](../../../.codex/config.toml), which holds Codex runtime settings
only and says so itself at its line 11.

**This is the only install route.** The public OpenAI plugin directory refuses packages
with lifecycle hooks and limits local stdio MCP to approved partners; this plugin ships
both, so it is distributed through this self-hosted marketplace and nothing else.

### The github MCP server on Codex

Neither Codex manifest can carry a credential. The root `mcp.json` follows Agent Plugins
1.0, which expands only `${PLUGIN_ROOT}`/`${PLUGIN_DATA}` and defines no credential
mechanism, so it passes no `env` at all; the overlay's `.mcp.json` uses Claude's
`${user_config.github_token}`, which Codex is not documented to expand. Either way the
server starts only if `GITHUB_PERSONAL_ACCESS_TOKEN` reaches `scripts/github-mcp.sh`
from the host's environment, and it refuses to start, with a clear message, when it does
not. How to hand a plugin server an environment variable on Codex is not documented and
has not been verified here; the rest of the plugin does not need the server.

Codex also reads the repo's root [`AGENTS.md`](../../../AGENTS.md) as project instructions.
That file is a **thin entrypoint** into the canonical rules under
[`rules/`](../../../rules/README.md) — it is deliberately not the whole policy source.

### Codex 0.148–0.152 notes

Codex 0.148 added asynchronous command hooks and MCP-tool hook actions. This repo does not
copy those fields into the shared cross-target hook bundle: doing so without a host-specific
split could change Claude/Cursor behavior. Adopt them only in a Codex-specific hook surface
once there is a concrete workflow to replace.

Codex 0.149 adds the interactive `codex agents` dashboard and `codex queue`. For local
multi-agent work, prefer those native controls to ad-hoc terminal/session bookkeeping when
they fit the workflow: `codex agents` is the host-native overview, while `codex queue` can
send follow-up guidance to an existing local or remote session. `/cd`, `/pwd`, and `/cwd`
are also available for TUI workspace navigation, and `codex doctor` now diagnoses endpoint
protection, network/proxy, desktop-app, and update-connectivity problems. These are host
capabilities; no plugin-manifest migration is required.

Codex 0.149.1 adds `codex exec --thread-source <SOURCE>` so automation callers can classify
new and forked threads, plus no-follow filesystem/sandbox correctness fixes. This toolkit
does not wrap `codex exec`, so it does not invent a source label on behalf of callers; use
the native flag in Codex-specific automation when provenance is useful.

Codex 0.150 adds native `@` task references, better task naming/copy ergonomics, and an
`Interrupt` hook that can invoke a command or MCP handler when a top-level turn is
interrupted. The `Interrupt` hook is valuable, but it should land only in a Codex-specific
hook declaration so it cannot change Claude/Cursor lifecycle behavior. Codex 0.150 also
hardens untrusted-project instructions, permissions, remote MCP startup/auth, credential
redaction, and sandbox behavior; those fixes are host-side.

Codex 0.151 adds a configurable grace period for optional MCP tool discovery and lets
extensions inspect or replace MCP tool results before those results reach the model. It also
improves per-repository plugin catalog configuration and reports invalid project marketplaces
without hiding valid plugins. Use the new MCP-result interception only if a future
Codex-specific extension actually needs result transformation; do not add a wrapper merely
to consume the capability. Likewise, tune optional-MCP discovery grace only from measured
startup behavior.

Codex 0.152 allows package-style MCP server names containing `:`, `@`, `/`, and `.`, adds a
per-tool `output_token_limit` setting, and lets app-server clients configure long
`thread/shellCommand` timeouts. Prefer these native MCP controls over custom name-normalizing
or output-truncation wrappers when a Codex-specific MCP setup needs them. The planning tool
is now opt-in (`tools.update_plan.enabled = true`); this repo does not depend on it, so no
config change is needed. Codex 0.152.1 is a Guardian policy-correctness fix with no plugin
migration.

### Codex 0.153–0.155 notes

Codex 0.153 gives the plugin CLI remote-marketplace `list`, `install`, and `remove` — the same
install path the commands above use. It also adds `tui.auto_recap`, Vim undo/redo, TUI
reconnection after an app-server drop, and a disabled-by-default
`features.context_management.experimental_mode`. All host-side; no manifest migration.

Codex 0.154 matters most here for one line: **existing sessions now pick up newly installed
plugin tools and refresh skills *and hooks* after an out-of-process plugin upgrade or
rollback.** Because Codex records hook trust against a content hash, a refresh that changes a
hook's content resets that hook to needing review — so the untrusted-by-default gate described
under [Verify](#verify) applies *after* an update, not only at first install. Re-check hook
trust after `codex plugin add` picks up a new version. Codex 0.154 also removes the deprecated
`codex mcp-server` entry point, which this repo never referenced (MCP is declared through the
plugin manifest's `mcpServers` field), and adds experimental worktree support via `--worktree`
and `/worktree`.

Codex 0.155 extends that with worktree ownership detail and confirmed deletion of clean managed
worktrees, plus task hiding/archiving/deletion in the agents overview. **This repo's
`worktree isolation` row stays `emulated` regardless**: the skill runs `git worktree` itself,
and the native feature is experimental and lives outside the plugin manifest — adopting it
would be a Codex-specific surface, not a change to the shared hook bundle. Codex 0.155 also
adds Touch ID user verification for MCP requests in local TUI sessions on supported Macs, and
makes MCP servers report expired OAuth credentials accurately with reconnect guidance; both are
host capabilities needing no config here. Its daemon work — configurable update schedules,
`codex app-server daemon update`, and saved-thread/active-goal recovery across daemon restarts
— is likewise host-side.

Approval and sandbox hardening across 0.154–0.155: startup no longer runs workspace-controlled
`PATH` helpers before trust is established, the macOS sandbox blocks terminal input injection,
Windows process escapes from restricted WSL sandboxes are blocked, and brokered shell snapshots
are hardened against credential exposure.

Codex 0.155.1 is a single bug fix: new local TUI sessions leave reasoning summaries disabled by
default again, fixing request rejection by providers that do not support them. Explicit
reasoning-summary settings are still respected. If you point Codex at such a provider, this is
the release you want.

These notes are derived from the official OpenAI release notes for `rust-v0.153.0`,
`rust-v0.154.0`, `rust-v0.155.0`, and `rust-v0.155.1`. Those four were reviewed from release
notes only. A live `codex` **0.156.0** run has since been performed — see the validation note
at the top of this page — so direct CLI validation is no longer 0.146.0.

## Verify

```bash
jq -e '.extensions["com.openai"].hooks' plugin.json   # root manifest: hooks -> ./platforms/codex/hooks.json
jq -e '.hooks' .codex-plugin/plugin.json               # fallback overlay: same pointer
jq -e 'has("modules") | not' platforms/codex/hooks.json  # the generated file has no modules key
jq empty .agents/plugins/marketplace.json
jq -e '.mcpServers.github' mcp.json                     # MCP on the Agent Plugins route
bash scripts/build-manifests.sh . --check               # every manifest matches its sources
bash scripts/build-codex-hooks.sh . --check             # the Codex hooks file matches hooks/hooks.json
bash scripts/doctor.sh .
```

In a Codex session, invoke a skill by name — *"use the repo-standards skill"* — and confirm
it loads. Codex's slash-command surface has not been verified against these skills, so
naming is the reliable form.

**Hooks ship untrusted by default — a clean install does not mean hooks are live.** A
non-managed hook (which includes every hook a plugin bundles) is skipped until a human
reviews and trusts its exact current definition; installing or enabling this plugin does not
trust its hooks automatically. When any hook needs review, Codex shows a startup consent
prompt with the choice to review the hooks, trust all and continue, or continue without
trusting — so this isn't something you have to know to go look for. Trust is recorded per
hook against its content hash (see `trusted_hash` under Machine-level setup, below); editing
a hook resets it to needing review. Confirm current state through that same hooks review
surface, which lists each hook with its trust/enabled state — note trusted and enabled are
separate: a hook can be trusted and still disabled. Codex's own docs also describe a `/hooks`
command for this; take that spelling from the docs rather than as independently verified here.
Do not treat a clean `bash scripts/doctor.sh .` run above as proof hooks are live — it
validates the manifest, not hook trust state. (Not verified against a live `codex` run —
based on Codex's docs and source.)

## Hooks on Codex

**Codex loads hooks from the generated `platforms/codex/hooks.json`, not from
`hooks/hooks.json`.** Codex's hooks-file parser accepts exactly two top-level keys,
`description` and `hooks`, and rejects a file with any other — and the Claude file has
carried a top-level `modules` key (the mod loader) since plugin 4.10.0. That is a
source-read finding, not a live run, but either way a Codex manifest pointing at the
Claude file loads **no** hooks. So both Codex manifests point `hooks` at a copy that
`scripts/build-codex-hooks.sh` generates from the Claude file, which **replaces** Codex's
default discovery rather than adding to it. Three things are removed on the way:

| Removed | Why |
|---|---|
| the `modules` key | Codex rejects it and runs no mod |
| `Notification`, `DirectoryAdded`, `WorktreeCreate`, `WorktreeRemove`, `StopFailure` | no Codex equivalent — the file declares only hooks that can fire, so a `/hooks` review shows only real ones |
| `onFailure` on every hook | Claude's key; Codex's command hook has no such field |

**The guards are fail-open on Codex.** On Claude Code, `onFailure: "block"` makes
`enforce-worktree-edits.sh`, `guard-sensitive-files.sh`, `protect-other-branches.sh`
and `docker-guard.py` deny the action when the guard itself crashes or times out. Codex
cannot express that, so on Codex a guard that fails lets the action through. A guard
that *runs* still blocks with exit 2 exactly as on Claude; what you lose is the
failure-of-the-guard case. The same rules are enforced again in CI.

**Re-trust after every update.** Codex records hook trust against each hook's content
hash and skips any hook whose definition changed until a human trusts it again. Every
plugin update that touches a hook — or the generated file — therefore silently disables
that hook on Codex until you open `/hooks` and trust it. Make `/hooks` part of the update
step below, not something you remember after a guard fails to fire.

## Update

```bash
codex plugin marketplace update tamirs-superpowers
codex plugin add tamirs-superpowers@tamirs-superpowers
```

Then, in a Codex session, run `/hooks` and re-trust any hook the update changed — see
[Hooks on Codex](#hooks-on-codex). Until you do, that hook does not run.

Check what you have:

```bash
jq -r .version .codex-plugin/plugin.json
```

## Uninstall

```bash
codex plugin remove tamirs-superpowers
codex plugin marketplace remove tamirs-superpowers
```

`.codex/config.toml` is a file in your repo holding Codex runtime settings — it declares no
MCP servers, so there is nothing to remove there. MCP comes from the plugin manifest's
`mcpServers` field pointing at [`.mcp.json`](../../../.mcp.json), which leaves with the plugin.

---

## Machine-level setup

Installing the plugin makes *this repository* usable from Codex. Carrying your global rules
into `~/.codex` is a separate, optional step:

```bash
bash scripts/setup.sh plan  --targets codex     # writes nothing
bash scripts/setup.sh apply --targets codex
bash scripts/setup.sh remove --targets codex
```

| Module | Writes | What it does |
|---|---|---|
| `agents-md` | `~/.codex/AGENTS.md` | Renders `core/global-rules.md` inside `>>> tamirs-superpowers >>>` markers; everything outside them is yours |
| `config` | `~/.codex/config.toml` | Appends a **comments-only** marker block |

Codex loads `~/.codex/AGENTS.md` on its own, so no config key is needed to enable the rules.
Two reasons the block is comments only: under TOML v1.0.0 a bare `key = value` appended at
the end of a file binds to the last `[table]` header rather than the document root, and —
the important one — **the Codex renderer never reads or writes hook entries.**
`config.toml` stores a per-hook `trusted_hash` under `[hooks.state."..."]` that Codex
invalidates whenever a hook's content or path changes; rewriting, reordering, or even
reindenting that table would silently break wiring this installer does not own. Your model,
approval policy, and sandbox settings stay yours.

`plan` writes nothing and is the default when there is no terminal, so a hook or CI run can
never adopt anything silently. `apply` shows a diff and asks per change, defaulting to
**No**. Re-running is a no-op — idempotence is a content comparison. Full reference:
[setup](../setup.md) · [platform setup](../platform-setup.md).

## Capabilities and limitations

| Capability | Status | Notes |
|---|---|---|
| skills | native | since 0.40.0 |
| subagents | unknown | Codex has a native subagents feature, but it is standalone `.toml` files under `$CODEX_HOME/agents/` or `.codex/agents/`, deliberately outside the plugin manifest (bundling one is an open upstream feature request); this repo ships no Codex agent mirror. Demoted from "native" 2026-09-08 — see registry |
| hooks | native | via the **manifest `hooks` field** — root `plugin.json` `extensions.com.openai.hooks` and `.codex-plugin/plugin.json` `hooks` both point at the generated `platforms/codex/hooks.json`: the Claude file minus its `modules` key, five events and `onFailure` (see note below). Guards fail-open; re-trust in `/hooks` after every update |
| MCP | native | via the manifest: root `mcp.json` on the Agent Plugins route, `./.mcp.json` on the overlay route — not `.codex/config.toml`, which is Codex runtime settings only. Neither file can carry the github token; see [the github MCP server on Codex](#the-github-mcp-server-on-codex) |
| plugin marketplace | native | |
| shell · git · GitHub CLI | native | |
| worktree isolation | emulated | The skill runs `git worktree` itself |
| auto-invocation · slash commands | unknown | Not measured — **name the skill explicitly** |
| parallel subagents · agent teams · background tasks · structured questions · session transcripts | unknown | Treated as unavailable; stated fallbacks apply |
| statusline · artifacts · extension install | unsupported | |

With `parallel_subagents` unmeasured, orchestration here runs **serialized or sequential** —
same task graph, same single PR.

**Hooks do port, through a generated copy, with partial coverage.** Codex consumes a
hooks file of the same shape as Claude's (its engine sets `CLAUDE_PLUGIN_ROOT` and ships
Claude tool-name matcher aliases on purpose, and exit-2 blocking semantics match), but its
top-level parser is strict and the Claude file's `modules` key fails it. So both Codex
manifests point `hooks` at `platforms/codex/hooks.json`, generated by
`scripts/build-codex-hooks.sh` with that key removed. Coverage is partial: `WorktreeCreate`,
`WorktreeRemove`, `DirectoryAdded`, `Notification` and `StopFailure` — five of this repo's
wired events — have no Codex equivalent and are left out of the generated file; and with
`onFailure` gone, the guards are fail-open. (Source-derived from `openai/codex` main — not
verified against a live `codex` run.)

Source of truth: [`core/capabilities/platforms.json`](../../../core/capabilities/platforms.json).
Comparison: [platform differences](../platform-differences.md).
