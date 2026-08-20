# Platform registry resolution — `platform-sync`

`platform-sync` never carries a hardcoded platform list in its instructions. The set of
targets it audits is **data**, resolved at run time. Adding a target must mean adding
registry data plus one `references/platforms/<id>.md` file — never editing the engine.

## Resolution order

Try each source in order and use the **first** one that parses:

1. **`core/capabilities/platforms.json`** — the canonical capability registry instance
   (schema: `core/capabilities/schema.json`). This is the preferred source: it is the same
   registry every other component checks.

   The registry is rooted at the **platform** — `claude`, `codex`, `cursor`, `gemini`,
   `opencode` — and lists that platform's runtime **surfaces** underneath, keyed by surface
   id. A target is a **surface**, not a platform: `display_name`, `kind`, `support`,
   `install`, `runtime_surface_of` and the per-capability status/fallback entries all live
   on the surface. Read the supported surfaces:

   ```bash
   jq -r '.platforms | to_entries[] | .key as $pl | .value.surfaces | to_entries[]
          | select(.value.support == "supported")
          | "\(.key)\t\(.value.display_name)\t(platform: \($pl))"' core/capabilities/platforms.json
   ```

   To look one surface up by id under either the platform-rooted shape or an older flat
   schema\_version 1 registry:

   ```bash
   jq --arg p cursor '(first(.platforms[]?.surfaces[$p]? | select(. != null)) // .platforms[$p]?)' \
      core/capabilities/platforms.json
   ```

   `scripts/lib/registry.sh` performs exactly that walk once and returns a flat,
   one-entry-per-supported-surface view keyed by surface id — every checker in this repo
   reads it, and so should any script this skill writes.

   A surface whose `support` is `"unverified"` carries **no capabilities block at all** and
   is **not a target**: never audit it, never emit an improvement step for it, and never
   count it among the supported targets. `registry_flat` omits it for that reason.

   **Id-to-filename mapping:** the reference file for surface id `<id>` is
   `references/platforms/<id-with-underscores-as-hyphens>.md` — `claude_code` →
   `claude-code.md`, `gemini_cli` → `gemini-cli.md`. Note that a skill's `compatibility`
   frontmatter block uses a slightly different, shorter key set (`gemini`, not `gemini_cli`);
   these are two id spaces and each must be spelled correctly in its own place.

2. **`docs/engineering/build-and-release/platform-targets.json`** — read `targets` (or
   `supported_targets`) for ids, `validated_against` versions, and `capability_gaps`.
3. **The `references/platforms/` directory itself** — every `*.md` file there is a target,
   named by its filename stem.

If sources 1 and 2 are both absent (auditing a foreign repo, or running before the
registry lands), say so in the output header rather than silently falling back:

```
Registry: core/capabilities/platforms.json not found — surface list resolved from
references/platforms/ (5 targets). Capability gaps not verified.
```

## Per-target reference data

For each resolved target id, read `references/platforms/<id>.md`. That file supplies
detection signals, P0/P1/P2 source URLs, local config paths, feature-scan areas, version
detection, and capability boundaries.

**A target with registry data but no reference file is a gap, not a silent skip** — except
a surface with `runtime_surface_of` set, which is covered by its underlying surface's file
(`claude_desktop` by `claude-code.md`; see below). Report:

```
⚠ <id> is in the registry but has no references/platforms/<id>.md — cannot audit.
```

The reverse (a reference file with no registry entry) is fine: audit it, and note that its
capability gaps were not verified against the registry.

## Surfaces that consume another surface's artifacts

A surface carrying `runtime_surface_of: <other-surface-id>` ships no distribution format of
its own. `claude_desktop` is `runtime_surface_of: claude_code` — it is a supported surface
with its own measured capability rows, but it consumes the Claude Code plugin artifact.
Audit the underlying artifact once, and note in that section which surfaces the findings
cover. Never emit a second section, and never double-count a surface in the summary table.

This is a statement about *artifacts*, not about support: every one of the six supported
surfaces is real and audited. What varies is whether the surface has a format to audit.

## Capability-gap enforcement

Before emitting any improvement step, check the target's capabilities in the registry:

| Registry status | What the engine may emit |
|---|---|
| `native`, `native-experimental` | A normal improvement step. |
| `partial`, `emulated`, `adapter` | An improvement step that names the limitation and the documented fallback. |
| `unsupported` | **Never** an improvement step. Report under "Documented gaps". |
| `unknown` | Never an improvement step. Report as unverified under "Documented gaps". |

This is the mechanism that stops platform-sync recommending Claude hooks to OpenCode.

## Fallback surface list

Only when every source above is unavailable — a genuinely bare repo — use the six supported
surface ids: `claude_code`, `claude_desktop`, `codex`, `cursor`, `gemini_cli`, `opencode`
(Claude Code, Claude Desktop, Codex CLI, Cursor IDE, Gemini CLI, OpenCode CLI).
State in the output that the list was a fallback and that no capability data was consulted.
