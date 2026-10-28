# Install — Codex CLI

**Platform:** Codex. **Surface:** Codex CLI — registry id `codex`. Everything on this page,
install commands and capability table alike, was measured on the CLI. Codex's other surface,
the **Codex IDE extension**, is **unverified**: this repo has never installed the plugin or
invoked a skill there, so it has no install guide and no capability claims in either
direction. See [platform differences](../platform-differences.md#unverified-surfaces).

Skills require Codex **0.40+**; the manifest `hooks` field requires **0.147.0+**. Direct CLI
validation is **0.163.0** — a live `codex` run on 2026-10-17 installed this plugin through a
local marketplace, fired every hook in the generated `platforms/codex/hooks.json` on its event
and captured the payloads into `tests/fixtures/codex/` (see [Hooks on Codex](#hooks-on-codex)).
An earlier live run on 0.156.0 (2026-09-23) confirmed the install preserves the plugin's
executable `.sh` files, hooks file, agent definitions and every `SKILL.md`. The official
release delta is reviewed through **0.165.0** (2026-10-27; changelog only), which is the version tracked by
`.codex-version`.

---

## Install

```bash
codex plugin marketplace add Tamircohen28/tamirs-superpowers
codex plugin add tamirs-superpowers@tamirs-superpowers
```

Codex resolves [`.agents/plugins/marketplace.json`](../../../.agents/plugins/marketplace.json)
and then the Codex manifest
[`.codex-plugin/plugin.json`](../../../.codex-plugin/plugin.json), generated from one
source by `scripts/build-manifests.sh` ([manifests](../../engineering/build-and-release/manifests.md)).
Codex **0.147+** would also read an Agent Plugins `plugin.json` at the repository root —
but, measured on 0.163.0, a plugin that carries one has every hook source emptied before
any hooks path is read (see [Measurement status](#measurement-status)), so this repository
deliberately has **no root `plugin.json`**: the Agent Plugins manifest lives under
`platforms/agent-plugins/` and ships only at the root of the `agent-plugins` release
tarball. Skills come from the canonical `skills/` tree, listed as seven roots in the
manifest. Hooks come from the **generated**
[`platforms/codex/hooks.json`](../../../platforms/codex/hooks.json), not from
`hooks/hooks.json` — see [Hooks on Codex](#hooks-on-codex). MCP servers are declared by
the manifest's `mcpServers` pointing at [`.mcp.json`](../../../.mcp.json) — never
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

### Codex 0.165.0 notes (reviewed, not directly validated)

Codex adds a native Google Cloud Vertex AI provider, GPT-6.1 Terra to the model catalog, repository filtering in the session picker, directory grouping for agents, in-conversation reasoning-effort changes, and memory v2 defaults for new profiles. Experimental attached app-server thread forks are not used by this CLI plugin. MCP requests now cancel when their callers disappear; queued messages cannot restart work after an interrupt or Plan-mode switch; approval reviewer defaults and Git marketplace URL validation are hardened. No change is needed to the generated Codex hooks, local stdio MCP server, marketplace URL or manifest. Prefer native Codex features over custom equivalents. This was a release-note review, not a new live plugin test; validated against **0.163.0**.

### Codex 0.164.0 notes (reviewed, not directly validated)

Codex 0.164.0 adds reusable `/presets`, inline `/model` and `/permissions` arguments, enterprise MCP OAuth/account-grant sign-in and credential masking for remote commands. It also improves compaction/resume recovery, Windows proxy authentication, macOS sandbox path checks and daemon cleanup. This plugin's generated Codex hook overlay and local stdio MCP server do not need a migration. Prefer Codex-native authentication, permission profiles and recovery over plugin-side wrappers where applicable; no untested configuration is added. The latest direct hook/installation test remains 0.163.0 (2026-10-17).

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

## Hook contract on Codex

What Codex demands of a hook that Claude Code does not, how each hook this plugin wires
meets it, and what has been measured. The checkable half lives in
[`tests/hooks/test-codex-contract.sh`](../../../tests/hooks/test-codex-contract.sh), which runs
every command in the generated file against Codex-shaped payloads
([`tests/fixtures/codex/`](../../../tests/fixtures/codex/README.md)) with `PLUGIN_ROOT` and
`PLUGIN_DATA` exported the way Codex exports them — no Codex binary needed, so it runs in
`make test-hooks` and CI.

**The generated file.** Codex loads [`platforms/codex/hooks.json`](../../../platforms/codex/hooks.json),
which `scripts/build-codex-hooks.sh` derives from `hooks/hooks.json`, and only that: Codex's
parser accepts exactly `description` and `hooks` at the top level. **Measured on codex-cli
0.163.0 (2026-10-17):** a plugin whose hooks file carries a `modules` key gets the error item
`failed to parse plugin hooks config …/hooks/hooks.json: unknown field `modules`, expected
`description` or `hooks`` and **none of that file's hooks run**; the session itself continues.
The generated file wires `PreToolUse`, `PostToolUse`, `SessionStart`, `SessionEnd`,
`UserPromptSubmit`, `Stop`, `SubagentStop` and `PreCompact`. `Notification`, `DirectoryAdded`,
`WorktreeCreate`, `WorktreeRemove` and `StopFailure` have no Codex event; `SubagentStart`,
`PermissionRequest`, `PostCompact` and `Interrupt` exist on Codex but this plugin has no hook
for them, so the generator adds nothing there.

**Guards fail open.** There is no `onFailure` on Codex, so a guard that crashes or times out
lets the action through. A guard that *runs* still blocks: Codex honours
`hookSpecificOutput.permissionDecision: "deny"` with a non-empty `permissionDecisionReason`,
which is what `enforce-worktree-edits.sh`, `guard-sensitive-files.sh`,
`protect-other-branches.sh` and `docker-guard.py` emit, and `exit 2` with the reason on stderr.
Codex *rejects* a `PreToolUse` answer of `permissionDecision: "ask"`, legacy
`decision: "approve"`, `continue: false`, `stopReason`, `suppressOutput`, or `allow` without
`updatedInput` — a rejected answer is reported as a hook failure and **the tool call proceeds**,
so a guard answering in one of those shapes would look installed and guard nothing. The test
asserts that no wired guard answers in any of them, and that the guards still deny an
`apply_patch` write to a lockfile while allowing an ordinary one. `apply_patch` is Codex's edit
tool; it matches the `Edit|Write|…` groups by Codex's own alias rule and its payload is
`tool_input.command` holding the patch envelope, which
[`hooks/lib/write-targets.py`](../../../hooks/lib/write-targets.py) parses. One gap: the
`PostToolUse` hooks keyed on `tool_input.file_path` (`plugin-reload-reminder.sh`,
`validate-report-links.sh`) never see an `apply_patch` target and are silent on Codex.

**Stop hooks print JSON.** A `Stop` or `SubagentStop` hook that exits 0 "must print JSON;
plain text is invalid". `check-done.sh` and `subagent-handoff-check.sh` therefore answer
`{}` through `hook_stop_ok` on every exit-0 path (the reminder stays on stderr); on Claude Code
`{}` means "no decision", exactly what the old bare exit meant. The test pins both the busy and
the silent paths.

**Dialect detection.** `hooks/lib/hook-output.sh`'s `hook_detect_platform` sets
`HOOK_PLATFORM=codex` when `PLUGIN_ROOT` or `PLUGIN_DATA` is exported — Codex's documented,
Codex-specific extension, beside the `CLAUDE_PLUGIN_ROOT`/`CLAUDE_PLUGIN_DATA` it also sets for
compatibility; Claude Code exports only the latter pair and Cursor expands neither — falling back
to a `turn_id` key in the payload. Measured on 0.163.0: a plugin hook's environment carried
`PLUGIN_ROOT`, `PLUGIN_DATA`, `CLAUDE_PLUGIN_ROOT`, `CLAUDE_PLUGIN_DATA` and `CODEX_HOME`, and
its working directory was the session `cwd`.

**Trust is bound to a hash.** Codex records trust per hook against its content hash; every
plugin update that changes a hook, or the generated file, silently disables that hook until
`/hooks` re-trusts it. Enabling the plugin does not trust its hooks. `codex exec
--dangerously-bypass-hook-trust` runs them without trust for one invocation (the flag exists on
0.163.0 — see below). Codex also clamps `SessionEnd` and `Interrupt` timeouts to 3 s and reports
the clamp as an error item; the three `SessionEnd` hooks here declare 10–30 s, so on Codex they
get 3 s (the test warns about it; the generator is deliberately left as is until that trade-off
is decided).

### Measurement status

**Measured on codex-cli 0.163.0, 2026-10-17**, from `npm install -g @openai/codex` into a
throwaway prefix, `CODEX_HOME` pointed at a scratch directory, no credential stored and no login:

- `codex --version` → `codex-cli 0.163.0`. `codex plugin marketplace add ./` on this checkout
  (`{"marketplaceName":"tamirs-superpowers","alreadyAdded":false}`), `codex plugin list
  --available --json` listing `tamirs-superpowers@tamirs-superpowers` at the manifest version,
  and `codex plugin add tamirs-superpowers@tamirs-superpowers` all work offline; the install is a
  full copy of the tree under `$CODEX_HOME/plugins/cache/<marketplace>/<plugin>/<version>/`,
  `platforms/codex/hooks.json` included. There is no `codex plugin validate` or `codex hooks`
  subcommand; `codex features list` reports `hooks … stable true`.
- `codex exec --skip-git-repo-check --ephemeral --dangerously-bypass-hook-trust --json` against
  a dead local provider (`model_providers.<x>.base_url = http://127.0.0.1:9/v1`) starts the
  session and fires `SessionStart` and `UserPromptSubmit` before the model call fails. That is how
  the payloads, the environment and the `modules` rejection above were recorded, with a probe
  plugin carrying one recording hook.
- **The root `plugin.json` disables every hook.** With a probe plugin that is this repo's tree
  renamed, the hooks fired only after the root Agent Plugins `plugin.json` was removed; a root
  manifest without `extensions`, one with `extensions.com.openai.hooks`, and one with both that
  and the overlay's `hooks` all loaded **no hook**. The reason is in `openai/codex`
  `core-plugins/src/loader.rs` at `rust-v0.163.0` (and still on `main`): when the manifest format
  is `AgentPlugin`, hook sources are set to an empty list before `load_plugin_hooks` is ever
  called. Hooks load only for a legacy-format plugin, i.e. one with no root `plugin.json`. So as
  shipped, with the root manifest present, **Codex 0.163.0 runs none of this plugin's hooks**,
  whatever the two Codex manifests point at. **Resolved in 5.0.0:** the repository ships no
  root `plugin.json` (the Agent Plugins manifest is generated under `platforms/agent-plugins/`
  and placed at the root of the `agent-plugins` tarball only), `scripts/check-dist.sh --target
  codex` refuses one, and the Codex route is `.codex-plugin/plugin.json` alone.

**Not measurable offline** (needs a session that completes a turn): `PreToolUse`/`PostToolUse`
firing on a real `apply_patch` call, `Stop`/`SubagentStop` output handling, the `/hooks` review
surface and its hash-bound re-trust, and whether the ten generated `.codex/agents/*.toml` load.

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
| hooks | native | via the **manifest `hooks` field** — `.codex-plugin/plugin.json` `hooks` points at the generated `platforms/codex/hooks.json`: the Claude file minus its `modules` key, five events and `onFailure` (see note below). Guards fail-open; re-trust in `/hooks` after every update |
| MCP | native | via the manifest: `.codex-plugin/plugin.json` `mcpServers` → `./.mcp.json` — not `.codex/config.toml`, which is Codex runtime settings only. Neither file can carry the github token; see [the github MCP server on Codex](#the-github-mcp-server-on-codex) |
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
