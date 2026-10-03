# Per-platform analysis protocol — `platform-sync`

The single analysis loop, run **once per detected target**. It replaced four near-identical
`platform-sync-<target>` skills; everything that used to differ between them now lives in
`references/platforms/<id>.md` as data.

Run targets in parallel where the harness supports it (`parallel_subagents`), sequentially
where it does not. Either way the protocol and the output shape are identical — parallelism
is an optimisation, never a behavioural difference.

**Hard constraint, all steps:** every finding cites a URL that was actually fetched in
step A. No training knowledge. A plausible-sounding feature with no fetched source is a
fabrication, not a finding.

---

## Step A — Determine what to fetch

Before fetching anything, check whether `references/probe.md` produced a parsed
pinned/current/reachable triple for this target (`SKILL.md` Step 3). Three cases:

**Probe says reachable and pinned == current.** This target is already current. Skip B–D
entirely and emit the "no findings" line in Step E. There is nothing to judge — do not fetch
just to double-check a probe result that already answered the question.

**Probe says reachable and pinned != current.** A delta is known to exist; fetch every P0
URL from `references/platforms/<id>.md` as usual — the probe tells you *that* something
changed, not *what* — but read the fetched content scoped to the known range (pinned+1 ..
current), not the platform's whole history. This is the judging-a-known-delta path this
reference exists for: the expensive part of a prior review cycle — "did anything change, and
what version are we even comparing against" — is already answered, so this step's job shrinks
to fetching the already-known range's sources, and Steps C–D become the real work (does this
delta item matter here, and how).

**Probe says unreachable, or gave no line for this target.** Fall back to the pre-probe
behaviour: fetch every P0 URL and derive "current" yourself from what came back, per the
target's own "Version detection" rule. Do not re-attempt a fetch the probe already reported
failing in this same run — same URL, same failure, wasted attempt — report it as
`probe-reported unreachable`, not a fresh fetch error, unless there is a concrete reason to
believe the condition changed since the probe ran.

In every case, then fetch the **P1** URLs whose "fetch when" condition matches the local
config found in step B (fetch P1 lazily, after B, if that ordering is cheaper). P2 only on
explicit user request.

If a P0 fetch fails, **abort this target only** and record:

```
⛔ FETCH ERROR — <platform display name>
URL: <url>
Error: <error message>
Cannot audit <platform>; other platforms are unaffected.
```

Never let one platform's fetch failure abort the run. Never substitute training knowledge
for a failed fetch.

## Step B — Read local config

Read every path in the target's "Local config to read" table, plus every path that
triggered detection. Record what is present, what is absent, and the declared version per
the target's "Version detection" rule.

## Step C — Check capabilities before proposing anything

For each candidate finding, resolve the capability it depends on against the registry
(see `registry.md`). A finding that depends on an `unsupported` or `unknown` capability is
**not** an improvement step — it belongs under "Documented gaps". This check happens before
drafting, not after.

## Step D — Identify unused features

Work the target's "Feature-scan areas" list. For each area, compare what step B found
against what step A fetched. A finding needs all four of:

1. the feature is documented in fetched content;
2. the repo does not already use it;
3. it applies to *this* repo's shape (plugin, app, or hybrid);
4. the capability check in step C passed.

Also record what the repo already does well — an audit that only lists gaps gives the
reader no calibration.

## Step E — Emit the section

One section per target, in exactly this shape. The engine concatenates and re-sorts these;
do not add prose outside it.

```
## <Display name> — v<declared> detected → v<latest> latest
**Signals:** <paths that triggered detection>
**Surfaces:** <runtime surfaces these findings also cover, or omit>
**Probe:** <pinned=X current=Y — verdict | not available | stale/malformed>

### Improvement steps
1. <Feature name> — <one sentence: the benefit or the risk>
   Config:
   ```<lang>
   <concrete, copy-pasteable snippet>
   ```
   Effort: low | medium | high
   Source: <URL fetched in step A>

### Already well-used
- <feature>: <brief note> ✓

### Documented gaps (not improvements)
- <capability>: <unsupported|unverified> on <platform> — <registry fallback, or "not verified">
```

If a target has no findings, emit the header plus:
`No improvements found for <Display name> — config is current.`

A probe-confirmed "already current" target (Step A's first case) always takes this no-findings
form — do not fetch sources just to produce a fuller-looking section.

## Output rules

- Every step carries a concrete snippet. "Consider using X" is not a step.
- Every step carries a source URL that was fetched, not inferred.
- Never recommend a capability the registry marks `unsupported` or `unknown`.
- Never emit a separate section for a runtime surface.
- Report fetch errors; never paper over them.
- Report the probe path (`**Probe:**` line) honestly — a target audited via full hand
  research must say `not available`/`stale/malformed`, never imply a probe confirmed it.
