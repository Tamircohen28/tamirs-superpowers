# `docs/engineering/refactor/` — Phase 0 artifacts

This directory holds the **Phase 0 (freeze and inventory)** deliverable of the
portable-orchestration refactor, as required by §25 and §26 of
`session-files/REFACTOR-SPEC.md`.

| File | What it is |
|------|-----------|
| [`file-inventory.csv`](file-inventory.csv) | One row per tracked file — the machine-readable audit |
| [`file-inventory.md`](file-inventory.md) | Human-readable summary: counts, the unvalidated-file list, duplication clusters, version drift, risks |

## Provenance

- **Generated:** 2026-08-19
- **Baseline commit:** `c9399aa` (`docs(targets): last_reviewed trailed the newest verification (#89)`)
- **Scope:** all 451 files in `git ls-files` at that commit — no exemptions, fixtures included
- **Method:** §26's nine questions answered per file, from reading the manifests,
  `Makefile`, `.github/workflows/ci.yml`, the validation scripts, and the files
  themselves; duplicate detection used git blob object ids (byte-exact) plus manual
  diffing of the near-duplicate clusters.

## This is a point-in-time artifact

It describes the repository **as it was before the refactor**, not as it will be
after. Every `migration_action` is a *proposal* recorded at freeze time and every
`validated_by` is the validator that existed at baseline. Once the refactor lands,
this inventory is history: it is the evidence for what was decided and why, and it
should **not** be edited to track the new tree. If a later phase needs a fresh
inventory, generate a new dated one alongside this file.

`validated_by = NONE` in the CSV is a **finding, not a failure** — it records a
file that nothing in `make validate` or CI proves correct today, which is exactly
what Phase 1 and Phase 6 (validation tiers) exist to close.
