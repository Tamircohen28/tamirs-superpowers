# Install — Codex CLI

**Platform:** Codex. **Surface:** Codex CLI — registry id `codex`. Everything on this page,
install commands and capability table alike, was measured on the CLI. Codex's other surface,
the **Codex IDE extension**, is **unverified**: this repo has never installed the plugin or
invoked a skill there, so it has no install guide and no capability claims in either
direction. See [platform differences](../platform-differences.md#unverified-surfaces).

Skills require Codex **0.40+**; the manifest `hooks` field requires **0.147.0+**. Direct CLI
validation remains **0.146.0**; the official release delta has been reviewed through
**0.155.1**, which is the version tracked by `.codex-version`.

---

## Install

```bash
codex plugin marketplace add Tamircohen28/tamirs-superpowers
codex plugin add tamirs-superpowers@tamirs-superpowers
```

Codex resolves [`.agents/plugins/marketplace.json`](../../../.agents/plugins/marketplace.json)
and [`.codex-plugin/plugin.json`](../../../.codex-plugin/plugin.json), and loads the
canonical `skills/` tree. MCP servers are configured through
[`.codex/config.toml`](../../../.codex/config.toml), not `.mcp.json`.

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
`rust-v0.154.0`, `rust-v0.155.0`, and `rust-v0.155.1`. **No live `codex` binary was run** —
direct CLI validation is still 0.146.0, as stated at the top of this page.

## Verify

```bash
jq empty .codex-plugin/plugin.json
jq -e '.hooks' .codex-plugin/plugin.json     # manifest hooks field present
jq empty .agents/plugins/marketplace.json
test -f .codex/config.toml && echo "MCP config present"
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

## Update

```bash
codex plugin marketplace update tamirs-superpowers
codex plugin add tamirs-superpowers@tamirs-superpowers
```

Check what you have:

```bash
jq -r .version .codex-plugin/plugin.json
```

## Uninstall

```bash
codex plugin remove tamirs-superpowers
codex plugin marketplace remove tamirs-superpowers
```

`.codex/config.toml` is a file in your repo — remove the MCP entries by hand if you no
longer want them.

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
| hooks | native | via the **manifest `hooks` field**, which points at this repo's own `hooks/hooks.json` — the same file, not a different shape (see note below) |
| MCP | native | via the plugin manifest's `mcpServers` field, which points at `./.mcp.json` — not `.codex/config.toml`, which is Codex runtime settings only |
| plugin marketplace | native | |
| shell · git · GitHub CLI | native | |
| worktree isolation | emulated | The skill runs `git worktree` itself |
| auto-invocation · slash commands | unknown | Not measured — **name the skill explicitly** |
| parallel subagents · agent teams · background tasks · structured questions · session transcripts | unknown | Treated as unavailable; stated fallbacks apply |
| statusline · artifacts · extension install | unsupported | |

With `parallel_subagents` unmeasured, orchestration here runs **serialized or sequential** —
same task graph, same single PR.

**Hooks do port, with partial coverage.** `.codex-plugin/plugin.json` points its `hooks`
field directly at `./hooks/hooks.json`; Codex's manifest schema accepts that file through the
same `HooksFile` type its own engine consumes (internally named `ClaudeHooksEngine`, which
sets `CLAUDE_PLUGIN_ROOT` and ships Claude tool-name matcher aliases on purpose), and exit-2
blocking semantics match — it is the same file shape, not a different one that fails to
port. Coverage is partial: `WorktreeCreate`, `WorktreeRemove`, `DirectoryAdded`, and
`Notification` — four of this repo's wired events — have no Codex equivalent and never fire
there. (Source-derived from `openai/codex` main — not verified against a live `codex` run.)

Source of truth: [`core/capabilities/platforms.json`](../../../core/capabilities/platforms.json).
Comparison: [platform differences](../platform-differences.md).
