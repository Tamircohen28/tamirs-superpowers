# Install — Codex CLI

**Platform:** Codex. **Surface:** Codex CLI — registry id `codex`. Everything on this page,
install commands and capability table alike, was measured on the CLI. Codex's other surface,
the **Codex IDE extension**, is **unverified**: this repo has never installed the plugin or
invoked a skill there, so it has no install guide and no capability claims in either
direction. See [platform differences](../platform-differences.md#unverified-surfaces).

Skills require Codex **0.40+**; the manifest `hooks` field requires **0.147.0+**. Direct CLI
validation remains **0.146.0**; the official release delta has been reviewed through
**0.149.1**, which is the version tracked by `.codex-version`.

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

### Codex 0.148–0.149.1 notes

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
the native flag in Codex-specific automation when provenance is useful. The filesystem fixes
are host-side and require no plugin changes.

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
| subagents | native | declared capability |
| hooks | native | since 0.147.0, via the **manifest `hooks` field** — a different shape from Claude's `hooks/hooks.json`, which does not port |
| MCP | native | `.codex/config.toml` |
| plugin marketplace | native | |
| shell · git · GitHub CLI | native | |
| worktree isolation | emulated | The skill runs `git worktree` itself |
| auto-invocation · slash commands | unknown | Not measured — **name the skill explicitly** |
| parallel subagents · agent teams · background tasks · structured questions · session transcripts | unknown | Treated as unavailable; stated fallbacks apply |
| statusline · artifacts · extension install | unsupported | |

With `parallel_subagents` unmeasured, orchestration here runs **serialized or sequential** —
same task graph, same single PR.

Source of truth: [`core/capabilities/platforms.json`](../../../core/capabilities/platforms.json).
Comparison: [platform differences](../platform-differences.md).
