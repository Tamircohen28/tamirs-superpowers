# Repo standards remediation plan — tamirs-superpowers

**Date:** 2026-06-28
**Target:** `/Users/tamircohen/Projects/tamirs-superpowers`
**Based on:** `docs/engineering/repo-standards-review-2026-06-28.md`

## Goal

Close 1 P1 and 3 P2 gaps; fix a stale CLAUDE.md key-files reference. All other standards pass.

## Phases

### Phase 0 — Employer IP

| Action | Files | Approach |
|--------|-------|----------|
| Confirmed CLEAN | all tracked | ip-scan.sh — all hits were false positives (doc placeholders, rule text) |

No changes needed.

---

### Phase 1 — CLAUDE.md: add AGENTS.md cross-reference + fix stale entry

| Action | Files | Approach |
|--------|-------|----------|
| Add `## Agent contributors` section referencing `AGENTS.md` | CLAUDE.md | direct edit — closes **L2-02 P1** |
| Remove stale `marketplace.json` entry from key files table | CLAUDE.md | direct edit — cleanup |

---

### Phase 2 — docs/ tree gaps

| Action | Files | Approach |
|--------|-------|----------|
| Create `docs/CHANGELOG.md` pointing to root CHANGELOG.md | docs/CHANGELOG.md | new file — closes **S2-03 P2** |
| Create `docs/agent-guidelines/overview.md` | docs/agent-guidelines/overview.md | new file — closes **L5-01 P2** |

---

### Phase 3 — GitHub infra

No gaps. SKIP.

---

### Phase 4 — Branch governance

No gaps. CODEOWNERS at `.github/CODEOWNERS` is canonical GitHub location (script false positive). SKIP.

---

### Phase 5 — Drift enforcement

| Action | Files | Approach |
|--------|-------|----------|
| Create `scripts/check-agent-drift.sh` wrapping validate-skill-frontmatter.py | scripts/check-agent-drift.sh | new file — closes **L7-01 P2** |

AGENTS.md already exists and is comprehensive. Skip Skill("multi-agent-repo") delegation.

---

### Phase 6 — Quality audits

| Action | Delegate |
|--------|---------|
| Run `Skill("docs-review")` on README + docs/** | docs-review |
| Run `Skill("changelog-review")` (plugin repo) | changelog-review |

---

### Phase 7 — Validate

| Command | Expected |
|---------|----------|
| `bash assert-contract.sh "$TARGET_ROOT" app-gold` | P1 gaps = 0 |

---

## Risk notes

- `docs/CHANGELOG.md`: Creating as a pointer doc (links to root CHANGELOG.md). This avoids content duplication while satisfying the contract check.
- `scripts/check-agent-drift.sh`: A thin wrapper. The real validation is already in Makefile via `validate-skill-frontmatter`.
- S4-01 false positive: `.github/CODEOWNERS` exists and is correct; do NOT add a root CODEOWNERS (redundant and potentially confusing).

## Next step

`/repo-standards polish` on branch `wt/tamirs-superpowers-repo-standards-review`.
