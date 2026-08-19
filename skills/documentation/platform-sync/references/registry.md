# Platform registry resolution — `platform-sync`

`platform-sync` never carries a hardcoded platform list in its instructions. The set of
targets it audits is **data**, resolved at run time. Adding a target must mean adding
registry data plus one `references/platforms/<id>.md` file — never editing the engine.

## Resolution order

Try each source in order and use the **first** one that parses:

1. **`core/capabilities/platforms.json`** — the canonical capability registry instance
   (schema: `core/capabilities/schema.json`). Read `platforms` for the target ids,
   `display_name`, `runtime_surface_of`, and the per-capability status/fallback entries.
   This is the preferred source: it is the same registry every other component checks.
   **Id-to-filename mapping:** the reference file for registry id `<id>` is
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
Registry: core/capabilities/platforms.json not found — platform list resolved from
references/platforms/ (5 targets). Capability gaps not verified.
```

## Per-target reference data

For each resolved target id, read `references/platforms/<id>.md`. That file supplies
detection signals, P0/P1/P2 source URLs, local config paths, feature-scan areas, version
detection, and capability boundaries.

**A target with registry data but no reference file is a gap, not a silent skip.** Report:

```
⚠ <id> is in the registry but has no references/platforms/<id>.md — cannot audit.
```

The reverse (a reference file with no registry entry) is fine: audit it, and note that its
capability gaps were not verified against the registry.

## Runtime surfaces are not separate targets

A registry entry carrying `runtime_surface_of: <other-id>` is a surface of another
adapter, not a distinct format. `claude-desktop` consumes the Claude Code plugin artifact.
Audit the underlying target once and note in that section which surfaces the findings
cover. Never emit a second section, and never double-count a surface in the summary table.

## Capability-gap enforcement

Before emitting any improvement step, check the target's capabilities in the registry:

| Registry status | What the engine may emit |
|---|---|
| `native`, `native-experimental` | A normal improvement step. |
| `partial`, `emulated`, `adapter` | An improvement step that names the limitation and the documented fallback. |
| `unsupported` | **Never** an improvement step. Report under "Documented gaps". |
| `unknown` | Never an improvement step. Report as unverified under "Documented gaps". |

This is the mechanism that stops platform-sync recommending Claude hooks to OpenCode.

## Fallback platform list

Only when every source above is unavailable — a genuinely bare repo — use:
`claude_code`, `claude_desktop`, `codex`, `cursor`, `gemini_cli`, `opencode`.
State in the output that the list was a fallback and that no capability data was consulted.
