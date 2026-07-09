# Feature equivalence matrix

Canonical machine spec: [`../feature-equivalence.json`](../feature-equivalence.json).

**Model:** capability parity — same outcomes via each platform's native mechanism. Not literal file parity (Cursor has no `hooks.json`).

## Repo types

| Type | Signals | Skills canonical path |
|------|---------|----------------------|
| `app` | package manifest, no plugin | `.agents/skills/` |
| `claude-plugin` | `.claude-plugin/plugin.json` + `skills/` | `skills/` via manifests |
| `agent-kit` | `canonical/rules/` | `canonical/skills/` → generated |
| `hybrid` | plugin + app artifacts | union of app + plugin rules |

## E-layer rubric (auto-scored)

| ID | Check |
|----|-------|
| E1-01 | App: `.agents/skills/` missing with no documented bridge |
| E1-02 | App: `.agents/skills` and `.claude/skills` skill sets differ |
| E2-01 | Plugin: skills exist but missing cursor/codex manifest |
| E2-02 | Plugin: manifest `skills` paths disagree |
| E3-01 | `.mcp.json` not referenced in all plugin manifests |
| E3-02 | MCP documented but no `.codex/config.toml` stub |
| E4-01 | Claude hooks without Codex hooks or Cursor substitute doc |
| E5-01 | `platform-equivalence.md` missing when hooks or MCP present |

## V-layer rubric (platform tool versions)

| ID | Check |
|----|-------|
| V1-01 | Multi-platform repo missing `platform-targets.json` |
| V1-02 | README AI badges ≠ `validated_against` in JSON |
| V1-03 | `platform-targets.md` missing or stale |
| V1-04 | `validated_against < latest_known` |
| V1-05 | `last_reviewed` older than 90 days |
| V1-06 | `supported_min` incompatible with `features_adopted` |

Plugin **semver** (manifest `version`) is separate — see S10-04. Row 3 README badges show **platform tool** versions from `platform-targets.json`.

## Cursor hook substitute

When Claude ships `hooks/hooks.json`, document in [`docs/agent-guidelines/platform-equivalence.md`](../../../docs/agent-guidelines/platform-equivalence.md):

- Which hook events run on Claude/Codex
- Cursor equivalent (scoped `.mdc` rules, manual reminders, or "no equivalent")
- Link to live platform docs

Validated by `make agent:check` (agents — not user-facing bash).
