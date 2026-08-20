# Feature equivalence matrix

Canonical machine spec: [`../feature-equivalence.json`](../feature-equivalence.json).

**Model:** capability parity — same outcomes via each surface's native mechanism. Not literal file parity (Cursor IDE has no `hooks.json`).

## Where platform truth lives

There is exactly one answer to "what can this harness do": **`core/capabilities/platforms.json`**, validated against `core/capabilities/schema.json`.

The registry is rooted at the **platform** (five: `claude`, `codex`, `cursor`, `gemini`, `opencode`) with that platform's runtime **surfaces** underneath, keyed by surface id. Capability rows hang off a **supported surface**, not off a platform — six supported surfaces, each carrying an explicit status for all 19 capability keys (`native`, `native-experimental`, `partial`, `emulated`, `adapter`, `unsupported`, `unknown`), with a validation command behind every native claim.

Look a surface up under either the platform-rooted shape or an older flat `schema_version` 1 registry:

```bash
jq -r --arg p codex '(first(.platforms[]?.surfaces[$p]? | select(. != null)) // .platforms[$p]?)
     | .capabilities | to_entries[] | "\(.key): \(.value.status)"' core/capabilities/platforms.json
```

`scripts/lib/registry.sh` performs that walk once and returns a flat, one-entry-per-supported-surface view keyed by surface id; `check-feature-equivalence.sh`, `check-platform-targets.sh` and `check-doc-claims.sh` all read that view rather than re-deriving the path.

The four **unverified** surfaces — `codex_ide`, `cursor_cli`, `gemini_code_assist`, `opencode_desktop` — carry no `capabilities` block at all and are omitted from the flat view. They demand no artifact, appear in no map below, and are never counted as targets.

`feature-equivalence.json` does **not** restate any of that. It carries only the repo-contract delta: *which artifact a repo must ship so a platform can reach a capability the registry says it has.* `platform-targets.json` carries only the version/provenance view, and its per-target `capabilities` / `capability_gaps` fields are regenerated from the registry (`bash scripts/check-platform-targets.sh . --sync-capabilities`, wired as `make platform-targets-sync-capabilities`), never hand-edited.

`scripts/check-feature-equivalence.sh` fails the build when these views disagree in any direction:

| Disagreement | Result |
|---|---|
| `feature-equivalence.json` names a platform the registry does not have | E-layer error |
| Registry says a platform provides a capability, contract names no artifact for it | E-layer error |
| Contract demands an artifact for a capability the registry marks `unsupported` | E-layer error |
| `platform-targets.json` `supported_targets` ≠ registry supported surfaces (minus those carrying `runtime_surface_of`) | E-layer error |
| `platform-targets.json` `capabilities`/`capability_gaps` ≠ registry-derived values | V-layer error |

A **surface** with `runtime_surface_of` set (Claude Desktop → Claude Code) consumes another surface's artifacts. It is a fully supported surface with its own measured capability rows, but it is deliberately absent from `supported_targets` and from every artifact map: giving it a duplicate artifact set is the drift this design removes.

## Targets — the six supported surfaces

| Platform | Surface id | Display | Distribution |
|---|---|---|---|
| `claude` | `claude_code` | Claude Code | plugin marketplace |
| `claude` | `claude_desktop` | Claude Desktop | `runtime_surface_of: claude_code` — no separate format |
| `codex` | `codex` | Codex CLI | `.codex-plugin/plugin.json` + `AGENTS.md` |
| `cursor` | `cursor` | Cursor IDE | `.cursor-plugin/plugin.json` + `.mdc` rules |
| `gemini` | `gemini_cli` | Gemini CLI | `gemini-extension.json`, installed from a git URL |
| `opencode` | `opencode` | OpenCode CLI | `opencode.json` `skills.paths`; agents via generated adapter |

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
| E6-01 | `core/capabilities/platforms.json` missing in a multi-platform repo |
| E6-02 | Registry and `platform-targets.json` name different surface sets |

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

## Agent-kit adapter outputs

`repo-scaffold --type plugin` generates one adapter per target from `canonical/`. Hand-editing any of them is drift; `npm run validate` (PK1-12…PK1-17) fails when one is missing.

| Surface | Generated artifact |
|---|---|
| Claude Code / Claude Desktop | `plugins/<name>/skills/` + `.claude-plugin/marketplace.json` |
| Codex CLI | `dist/codex/AGENTS.md`, `dist/codex/.codex/config.toml` |
| Cursor IDE | `dist/cursor/.cursor/rules/000-core.mdc` |
| Gemini CLI | `dist/gemini/gemini-extension.json`, `dist/gemini/GEMINI.md` |
| OpenCode CLI | `dist/opencode/opencode.json` |

## Cursor hook substitute

When Claude ships `hooks/hooks.json`, document in [`docs/agent-guidelines/platform-equivalence.md`](../../../../docs/agent-guidelines/platform-equivalence.md):

- Which hook events run on Claude/Codex
- Cursor IDE equivalent (scoped `.mdc` rules, manual reminders, or "no equivalent")
- Link to live platform docs

Validated by `make agent:check` (agents — not user-facing bash).
