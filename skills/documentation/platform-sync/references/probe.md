# Probe input — `platform-sync`

A version probe can answer the one question every prior review cycle spent the most effort
re-deriving by hand: *is each platform still on the version this repo's docs say it's on, and
if not, what's the new one?* When that answer is already available, `platform-sync` consumes
it instead of re-deriving the same answer through open-ended WebSearch/WebFetch research.

**Reconciled against the real script.** `scripts/probe-platform-versions.sh` (task-001,
merged the same objective cycle as this file) was written in parallel without this file's exact
assumed shape available, and its real output differs from what was first assumed here —
reconciled by the integrator against the actual script source, not re-guessed. The shape below
is `probe-platform-versions.sh`'s real output, verified by running it.

## Real output shape

One line per registry surface id — `claude_code`, `codex`, `cursor`, `gemini_cli`, `opencode`
(`claude_desktop` is covered by `claude_code`; see `registry.md`'s runtime-surface rule) — to
stdout, followed by a blank line and a summary line:

```
<surface_id>: pinned=<version> current=<version|n/a|unreachable> — <verdict text>

Summary: <N> drifted, <M> unreachable
```

Real example (verbatim from a live run):

```
claude_code: pinned=2.1.278 current=n/a — no automated upstream source; advance via changelog review
cursor: pinned=3.21.13 current=3.21.16 — DRIFT
codex: pinned=0.155.1 current=0.155.1 — no drift
gemini_cli: pinned=0.60.0 current=0.60.0 — no drift
opencode: pinned=1.18.31 current=1.18.31 — no drift

Summary: 1 drifted, 0 unreachable
```

`pinned` is the version this repo's docs currently claim — the same value `registry.md`'s
per-target "Version detection" rule would derive from local config (`.claude-code-version`,
`platform-targets.json`, or a `SKILL.md`/`CLAUDE.md` narrative reference). `current` is one of
three things, and they are NOT the same case:

- **an actual version** — the probe reached the endpoint and got a real answer. Compare
  against `pinned` for drift.
- **`unreachable`** — a transient fetch failure (network, endpoint down, rate limit). No
  current value exists this run; treat exactly like `n/a` for this run's analysis, but it may
  succeed on a later run — don't record this as a permanent property of the target.
- **`n/a`** — `claude_code` only, always, by design: no public version-check API exists for
  it at all. This is not a failure and will not resolve on a later run; advancing this target's
  version stays a changelog-review decision forever, per the script's own header comment.

There is no literal `reachable=true|false` field in the real output — reachability is implied
by which of the three `current` states above appears. Treat `unreachable` and `n/a` the same
way for branching purposes (no live current value this run → fall back to hand research for
that target); the distinction between them only matters for phrasing why, not for what to do.

## How to consult it

1. Look for the probe script at `scripts/probe-platform-versions.sh`. If it is absent, there
   is no probe input — skip straight to "Fallback: hand research" below for every target.
2. Run it once, capturing stdout. Its exit code alone is NOT a validity signal — it exits
   non-zero whenever at least one target drifted, which is a normal, expected, USABLE result,
   not a failure. Only empty output, or output that does not match the line shape above, means
   "absent" — fall back for every target in that case. Do not half-trust a malformed result by
   parsing the lines that happen to match.
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
