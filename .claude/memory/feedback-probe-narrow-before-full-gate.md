---
name: feedback-probe-narrow-before-full-gate
description: "When a gate failure is already localized, re-run that one check script, not the 2-minute make validate"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: a35855d6-d668-42fb-af0b-d574c2b896ae
  modified: 2026-09-23T11:28:23.737Z
---

`make validate` takes 2+ minutes. When it fails and the failure is **already identified**
(a named script, a named file), re-run that script alone to confirm the fix, then run the
full gate **once** at the end.

**Why:** in one session the full gate was re-run 2-3 times per small JSON edit while
iterating on narrow fixes — a `.codex-version` pin mismatch confirmed by
`scripts/check-platform-version-pins.sh` in under a second, and an orphan-hook Makefile
recipe testable directly. Each full re-run bought nothing the narrow check would not have
given immediately. The full gate is the final safety net, not the diagnostic loop.

**How to apply:** read the failing line, run the script it names (`check-platform-version-pins.sh`,
`check-opencode-permission-keys.sh . --refresh`, `build-*-commands.sh . --check`,
`sync-contract-scripts.sh`), fix, re-run that script, and only then spend the 2 minutes.
Mind each script's argument contract — several take the repo root as `$1`, so a bare
`--refresh` is read as a path. See [[feedback-background-task-exit-codes]] for reading the
gate's result once it does run, and [[feedback-sweep-before-full-validate]] for gathering
every instance before starting it.
