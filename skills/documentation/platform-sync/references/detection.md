# Platform detection — `platform-sync`

Detect which AI coding assistant **targets** a repo uses before running any analysis. A repo
may use zero, one, or many targets. Manifests are the strongest signal but are never
required — an app repo with only `CLAUDE.md` uses Claude Code just as truly as a plugin repo.

## How detection works now

Detection signals are **per-target data**, not a list in this file. For each target
resolved by `registry.md`, read the "Detection signals" table in
`references/platforms/<id>.md` and treat the target as detected when **any** signal matches.

This file holds only the rules that apply across every target.

## Cross-target rules

**Shared signals fire for every target that claims them.** `AGENTS.md` is claimed by Codex
(strong), Gemini CLI (medium) and OpenCode (medium). A repo with `AGENTS.md` and nothing
else legitimately detects three targets. Do not arbitrate; report each with the signal that
triggered it and its strength.

**Record what triggered each target.** Every output section names its signals, e.g.
`CLAUDE.md + skills/`. A finding whose provenance cannot be traced to a signal is not
actionable.

**Weak signals still count, but say so.** A target detected only by weak signals (e.g. a
bare `.mcp.json`) is reported with `(weak signal only)` next to the signal list, so the
reader can judge whether the audit is worth acting on.

**Runtime surfaces are not detected separately.** A registry entry with
`runtime_surface_of` is covered by detecting its underlying target — `claude-desktop` is
covered by Claude Code detection. See `registry.md`.

**Absence of a manifest is not absence of a target.** OpenCode and Gemini CLI have no
Claude-style plugin manifest at all; Claude Code, Codex and Cursor are all usable with no
manifest in an app repo. Never gate detection on a manifest.

## No targets detected

If no signal matches any resolved target, output exactly:

```
No AI coding assistant usage detected in this repo.
platform-sync looks for Claude Code (CLAUDE.md, .claude-plugin/, skills/, hooks/),
Cursor (.cursor/rules/, .cursor-plugin/), Codex (AGENTS.md, .codex-plugin/),
Gemini CLI (.gemini/, GEMINI.md, gemini-extension.json), or
OpenCode (opencode.json, .opencode/).
Add agent config for at least one platform, then re-run /platform-sync.
```

Then stop — do not fetch anything and do not guess.

If the registry resolved a different target set than the one named above, list that set
instead. The message must describe what was actually looked for.
