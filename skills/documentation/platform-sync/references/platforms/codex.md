# Platform reference data — `codex`

Data consumed by the `platform-sync` engine (`references/analysis-protocol.md`).

- **Display name:** OpenAI Codex CLI
- **Registry id:** `codex` (same in the registry, in `platform-targets.json`, and in a skill's `compatibility` block)

## Detection signals

| Signal | Path / pattern | Strength |
|--------|----------------|----------|
| Plugin manifest | `.codex-plugin/plugin.json` | strong |
| Agents file | `AGENTS.md` at repo root | strong |
| Codex config | `.codex/` or `codex.config.*` | medium |

`AGENTS.md` is a shared signal — Codex, Gemini CLI and OpenCode all read it. Its presence
alone triggers every platform that claims it; do not treat it as Codex-exclusive.

## Sources — P0 (fetch always; failure aborts this platform only)

| Topic | URL |
|---|---|
| GitHub releases (latest version tag) | https://github.com/openai/codex/releases |
| Raw README (canonical feature list) | https://raw.githubusercontent.com/openai/codex/main/README.md |

## Sources — P1

| Fetch when | URL |
|---|---|
| `AGENTS.md` present or proposed | https://github.com/openai/codex/blob/main/AGENTS.md |
| Rendered repo context needed | https://github.com/openai/codex |
| Hooks wired (`platforms/codex/hooks.json` exists) | https://learn.chatgpt.com/docs/hooks |
| Hook-loading source of truth for a plugin manifest | https://raw.githubusercontent.com/openai/codex/main/codex-rs/core-plugins/src/loader.rs |

## Sources — P2

| Topic | URL |
|---|---|
| Contributing / architecture | https://github.com/openai/codex/blob/main/CONTRIBUTING.md |

Codex CLI is open source and has no separate hosted docs site — the repository is the
documentation. A 404 means the file does not exist yet; report it, never guess around it.

## Local config to read

| Path | What to note |
|------|--------------|
| `.codex-plugin/plugin.json` | `version`, `skills`, `hooks`, `mcpServers` |
| `AGENTS.md` | Size (≤32 KiB), commands, working agreements |
| `.codex/`, `codex.config.*` | CLI config overrides |
| `Makefile` | Install/update commands agents should use |

App repos with only `AGENTS.md`: report the declared version as `project-only` and compare
against current AGENTS.md guidance in the fetched README.

## Feature-scan areas

- **AGENTS.md** — missing at root is a high-priority finding; oversized (>32 KiB) is a
  correctness finding, not a style one.
- **Plugin schema** — manifest fields in the fetched README absent from local config.
- **Skills** — does `.codex-plugin/plugin.json` enumerate the same skill paths the Claude
  manifest does? A domain present for one target and absent for another is silent
  capability loss.
- **MCP servers** — documented support with nothing wired locally.
- **Hooks** — only if the fetched README documents lifecycle hooks. Do not port Claude
  hook events on the assumption they exist. When the hooks page is fetched, diff its
  contract against `tests/hooks/test-codex-contract.sh` (the twelve event names, the
  stdin fields, the PreToolUse output keys Codex rejects, the Stop-family JSON rule) and
  against `loader.rs`'s manifest-format gate: at `rust-v0.163.0` a plugin with a root
  Agent Plugins `plugin.json` loads no hooks at all. A change on either side is a
  correctness finding, not a style one.

## Version detection

Declared: `.codex-plugin/plugin.json` → `version`, else `project-only`.
Latest: newest tag on the releases feed.

## Capability boundaries

Verify against the capability registry before recommending anything ported from another
target. Codex has no plugin marketplace and no plugin-declared statusline; never emit an
improvement step that assumes one.
