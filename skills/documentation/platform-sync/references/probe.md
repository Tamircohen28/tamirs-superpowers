# Probe input — `platform-sync`

A version probe can answer the one question every prior review cycle spent the most effort
re-deriving by hand: *is each platform still on the version this repo's docs say it's on, and
if not, what's the new one?* When that answer is already available, `platform-sync` consumes
it instead of re-deriving the same answer through open-ended WebSearch/WebFetch research.

**This is a documented assumption, not a verified contract.** `scripts/probe-platform-versions.sh`
was being built by a separate, parallel task when this reference was written, and its exact
output shape was not available to check against. The shape below is a reasonable one for a
version probe to emit, matching this skill's own registry surface ids
(`references/registry.md`). If the script that actually ships disagrees with this shape,
reconcile this file with it before relying on the fast path below — do not silently adapt
around a mismatched shape mid-run, and do not block this skill's other steps on that
reconciliation happening first.

## Assumed output shape

One line per registry surface id — `claude_code`, `codex`, `cursor`, `gemini_cli`, `opencode`
(`claude_desktop` is covered by `claude_code`; see `registry.md`'s runtime-surface rule) — to
stdout:

```
<surface_id> pinned=<version> current=<version|unknown> reachable=<true|false>
```

Example:

```
claude_code pinned=2.1.278 current=2.1.281 reachable=true
codex pinned=0.155.1 current=0.155.1 reachable=true
cursor pinned=3.11 current=unknown reachable=false
```

`pinned` is the version this repo's docs currently claim — the same value `registry.md`'s
per-target "Version detection" rule would derive from local config (`.claude-code-version`,
`platform-targets.json`, or a `SKILL.md`/`CLAUDE.md` narrative reference). `current` is what
the probe found live upstream. `reachable: false` means the probe's own fetch failed;
`current` is then `unknown` and must never be treated as "up to date".

## How to consult it

1. Look for the probe script at `scripts/probe-platform-versions.sh`. If it is absent, there
   is no probe input — skip straight to "Fallback: hand research" below for every target.
2. Run it once, capturing stdout. A non-zero exit, empty output, or output that does not match
   the line shape above is treated exactly like "absent" — fall back. Do not half-trust a
   malformed result by parsing the lines that happen to match.
3. Parse one line per target. Keep only lines for targets this run actually detected in
   Step 2; a probe result for an undetected target is discarded, not reported.
4. Thread the parsed `pinned`/`current`/`reachable` triple for each detected target into
   `references/analysis-protocol.md` Step A, which branches on it.

## Fallback: hand research

When probe input is unavailable for a target — script missing, run failed, or that target's
line was absent from otherwise-valid output — `analysis-protocol.md` Step A runs exactly as it
did before this reference existed: fetch every P0 source and derive "current" from what was
fetched, per that target's own "Version detection" rule. This is not a degraded mode to
apologize for. It is the only path available before a probe script exists at all, and it must
keep working forever — including in a checkout of this repo from before the probe shipped, and
for any target the probe does not (yet) cover.

## Reporting

State which path was taken, once, in the output header, next to `SKILL.md`'s "Registry
source" line: `available` (name the pinned/current/reachable line used, per target),
`not available` (script missing), or `stale/malformed` (ran but output unusable — say why).
Never let the reader infer which path ran from the absence of a research trail.
