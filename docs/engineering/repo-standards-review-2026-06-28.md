# Repo standards review — tamirs-superpowers

**Date:** 2026-06-28
**Target:** `/Users/tamircohen/Projects/tamirs-superpowers`
**Profile:** `app-gold`

## Executive summary

tamirs-superpowers is a mature Claude Code plugin repo with excellent README quality, a rich docs tree, full GitHub infra (CI, secret scan, PR template, Dependabot), branch protection, and a working statusline. Only **1 P1 gap** exists: `CLAUDE.md` does not cross-reference `AGENTS.md`, leaving contributor agents without a pointer to the canonical rules file. Four P2 gaps remain: `docs/CHANGELOG.md` missing (a root `CHANGELOG.md` exists but the contract expects it under `docs/`), no `docs/agent-guidelines/`, no dedicated drift-check script (Makefile enforcement exists), and `CODEOWNERS` at `.github/CODEOWNERS` rather than root (a script false positive — canonical GitHub location is accepted). IP scan returned false positives only. No P3 gaps.

## Severity summary

| Severity | Count |
|----------|-------|
| P1 | 1 |
| P2 | 3 (+ 1 false positive) |
| P3 | 0 |

## Standards gaps (S1–S7 + Multi-agent)

### S1 README — PASS

All S1 checks pass. README has: banner (`assets/banner.png`), CI + license + plugin badges, Prerequisites, Quick Start, Features, docs link. Content is specific and placeholder-free.

### S2 docs/ — 1 gap

| ID | Severity | Finding |
|----|----------|---------|
| S2-03 | P2 | `docs/CHANGELOG.md` missing. A `CHANGELOG.md` exists at repo root — contract expects the canonical copy at `docs/CHANGELOG.md`. Either symlink or move it. |

S2-01 (docs/user/), S2-02 (docs/engineering/), S2-04 (docs/CONTRIBUTING.md) — all pass.

### S3 GitHub infra — PASS

CI workflow, secret-scan job, PR template, and Dependabot all present. No self-hosted runners in any workflow.

### S4 Branch governance — NOTE

| ID | Severity | Finding |
|----|----------|---------|
| S4-01 | ~~P2~~ | **False positive** — `CODEOWNERS` at `.github/CODEOWNERS` with `* @TamirCohen28`. Inventory script checks only root; `.github/` is the canonical GitHub location. No action needed. |

Branch protection enabled with ≥1 required review.

### S5 Root legal/ops — PASS

LICENSE and .gitignore both present.

### S6 Repo hygiene — PASS

No stray docs at docs root, no ticket-named files outside engineering. Two empty directories detected (non-blocking).

### S7 Employer IP — PASS (false positives only)

IP scan returned 4 hits — all false positives:
- `MY_SERVICE_TOKEN: "your-token-here"` in `skills/mcp/mcp-builder/references/quick-reference.md:130` — explicit placeholder documentation value, not a real token.
- `runs-on: [self-hosted]` in `skills/repo/repo-standards/SKILL.md`, `AGENTS.md`, `CLAUDE.md` — all inside "Never do this" rule statements, not actual CI config.

**Result: CLEAN — no genuine IP leakage detected.**

### S8 Multi-agent — 2 gaps

| ID | Severity | Finding |
|----|----------|---------|
| L2-02 | **P1** | `CLAUDE.md` does not reference `AGENTS.md`. Contributors loading `CLAUDE.md` have no pointer to `AGENTS.md` and its working agreements. Fix: add an `## Agent contributors` section to `CLAUDE.md` pointing to `AGENTS.md`. |
| L5-01 | P2 | `docs/agent-guidelines/` directory missing. Agents entering this repo have no structured onboarding docs separate from `AGENTS.md`. Consider adding a lightweight `docs/agent-guidelines/overview.md`. |
| L7-01 | P2 | No dedicated `scripts/check-agent-drift.sh` at repo root. Note: Makefile has `validate-skill-frontmatter` which provides equivalent drift enforcement for this plugin repo type. Gap is real but low-impact given existing CI gate. |

## Plugin / agent-kit appendix

Not applicable — profile is `app-gold` (claude-plugin sub-type, not agent-kit).

Qualitative note: repo correctly identifies as `claude-plugin` type with `manifests.claude_plugin`, `manifests.cursor_plugin`, `manifests.codex_plugin` all present. 26 plugin skills detected, 1 Claude project skill.

## Employer IP scan

```
=== Employer IP Scan: /Users/tamircohen/Projects/tamirs-superpowers ===
Scanned at: 2026-06-28

Pattern: SECRET|TOKEN|PASSWORD|API_KEY|ACCESS_KEY — 1 hit
  skills/mcp/mcp-builder/references/quick-reference.md:130: "MY_SERVICE_TOKEN": "your-token-here"
  → FALSE POSITIVE: explicit documentation placeholder

Pattern: runs-on: [self-hosted] — 3 hits
  skills/repo/repo-standards/SKILL.md:190, AGENTS.md:17, CLAUDE.md:47
  → FALSE POSITIVE: all in "never do this" rule text, no actual workflow config

RESULT: CLEAN — no genuine employer IP detected
```

## Multi-agent appendix

Multi-agent inventory (summary):
- `repo_type`: `claude-plugin`
- `agents_md.exists`: true (3506 bytes, within Codex limit)
- `claude_md.imports_agents`: **false** ← L2-02 gap
- `cursor_rules.count`: 8 (2 always-apply, no legacy .cursorrules)
- `skills.plugin_skill_count`: 26
- `manifests`: claude-plugin ✓, cursor-plugin ✓, codex-plugin ✓
- `docs.agent_guidelines_dir`: **false** ← L5-01 gap
- `enforcement.drift_script`: false ← L7-01 gap
- `enforcement.has_agent_check`: **true** (Makefile `validate-skill-frontmatter`)
- `enforcement.has_ci`: true

## Docs read-only notes

- **docs/user/**: Comprehensive — concepts, quick-start, reference, agent-kit, troubleshooting. All look project-specific and current.
- **docs/engineering/**: Well-structured — architecture overview, statusline, build-and-release, CI workflow, ADR index. README.md index table is accurate.
- **docs/README.md** and **docs/CONTRIBUTING.md**: Present.
- **CLAUDE.md**: Key files table still lists `marketplace.json` but README says the repo no longer ships `marketplace.json`. Minor stale reference — not a standards gap but worth cleaning up.
- No placeholder prose, no stray top-level docs, no ticket-named files.

## Inventory appendix

```json
{
  "root": "/Users/tamircohen/Projects/tamirs-superpowers",
  "readme": {"exists": true, "has_badges": true, "has_prerequisites": true, "has_quick_start": true, "has_license_line": true, "has_banner": true},
  "docs": {"readme": true, "changelog": false, "contributing": true, "user_dir": true, "engineering_dir": true},
  "github": {"ci_workflow": true, "secret_scan_job": true, "pr_template": true, "dependabot": true},
  "root_files": {"license": true, "codeowners": false, "gitignore": true, "claude_md": true, "agents_md": true},
  "branch_governance": {"protection_enabled": true, "required_approving_reviews": 1},
  "hygiene": {"misplaced_top_level_docs": 0, "ticket_named_outside_engineering": 0, "empty_dirs": 2, "self_hosted_ci": false},
  "gap_scoring": {
    "profile": "app-gold",
    "gaps": [
      {"id": "S2-03", "severity": "P2", "message": "docs/CHANGELOG.md missing", "phase": 2},
      {"id": "S4-01", "severity": "P2", "message": "CODEOWNERS missing (FALSE POSITIVE — .github/CODEOWNERS exists)", "phase": 4},
      {"id": "L2-02", "severity": "P1", "message": "CLAUDE.md does not reference AGENTS.md", "phase": 1},
      {"id": "L5-01", "severity": "P2", "message": "docs/agent-guidelines/ missing", "phase": 2},
      {"id": "L7-01", "severity": "P2", "message": "No check-agent-drift script (has_agent_check=true via Makefile)", "phase": 4}
    ],
    "counts_after_false_positives": {"p1": 1, "p2": 3, "p3": 0}
  }
}
```

## Next steps

- `/repo-standards plan` — generate phased remediation plan from this review
- `/repo-standards polish` — implement on `feat/repo-standards-setup` and open PR

**Top priority actions:**
1. **(P1)** Add `## Agent contributors` or equivalent section to `CLAUDE.md` linking to `AGENTS.md`
2. **(P2)** Move or symlink `CHANGELOG.md` → `docs/CHANGELOG.md`
3. **(P2)** Create `docs/agent-guidelines/overview.md` with agent onboarding summary
4. **(P2)** Add `scripts/check-agent-drift.sh` (can wrap existing `scripts/validate-skill-frontmatter.py`)
5. **(cleanup)** Remove stale `marketplace.json` entry from `CLAUDE.md` key files table
