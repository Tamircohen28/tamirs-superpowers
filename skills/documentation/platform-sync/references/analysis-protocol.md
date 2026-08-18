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

## Step A — Fetch sources

From `references/platforms/<id>.md`, fetch every **P0** URL. Then fetch the **P1** URLs
whose "fetch when" condition matches the local config found in step B (fetch P1 lazily,
after B, if that ordering is cheaper). P2 only on explicit user request.

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

## Output rules

- Every step carries a concrete snippet. "Consider using X" is not a step.
- Every step carries a source URL that was fetched, not inferred.
- Never recommend a capability the registry marks `unsupported` or `unknown`.
- Never emit a separate section for a runtime surface.
- Report fetch errors; never paper over them.
