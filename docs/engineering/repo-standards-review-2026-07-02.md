# Repo standards review — tamirs-superpowers

**Date:** 2026-07-02
**Target:** `/Users/tamircohen/Projects/tamirs-superpowers`
**Profile:** `app-gold`

## Executive summary

tamirs-superpowers now passes the full app-gold standards contract with **zero P1/P2/P3 gaps**. All gaps flagged in the 2026-06-28 review (CLAUDE.md → AGENTS.md cross-reference, `docs/CHANGELOG.md`, `docs/agent-guidelines/`) were closed by PRs #46–#48. README has banner, badges, prerequisites, quick start, and license line; the docs tree, GitHub CI/CD infra, branch protection, and multi-agent files (`AGENTS.md`, `CLAUDE.md`) are all present. The employer-IP scan is clean — every hit is a false positive (see below). No remediation is required.

## Severity summary

| Severity | Count |
|----------|-------|
| P1 | 0 |
| P2 | 0 |
| P3 | 0 |

## Standards gaps (S1–S7 + Multi-agent S8)

No gaps. Machine gap-scoring (`score-contract-gaps.sh`) returned `{"p1":0,"p2":0,"p3":0}` across standards, multi-agent, and plugin sources.

| Standard | Status |
|----------|--------|
| S1 README (banner, badges, prerequisites, quick start, license) | PASS |
| S2 docs/ (README, CHANGELOG, CONTRIBUTING, user/, engineering/) | PASS |
| S3 GitHub CI/CD (ci workflow, secret-scan job, PR template, Dependabot) | PASS |
| S4 root files (LICENSE, CODEOWNERS, .gitignore, CLAUDE.md, AGENTS.md) | PASS |
| S5 branch governance (protection enabled, 1 required approving review) | PASS |
| S6 hygiene (no misplaced docs, no ticket-named files, no self-hosted CI) | PASS |
| S7 employer-IP clean | PASS (false positives only) |

## Employer IP scan

`ip-scan.sh` reported 10 raw hits; all are false positives:

- **`MY_SERVICE_TOKEN: "your-token-here"`** (`skills/mcp/mcp-builder/references/quick-reference.md:130`) — explicit placeholder documentation value, not a real secret.
- **`runs-on: [self-hosted]`** (7 hits) — all occur inside *rule statements* forbidding self-hosted runners (`AGENTS.md`, `CLAUDE.md`, `SKILL.md`, `docs/agent-guidelines/overview.md`) or in the prior review doc. No actual CI config uses self-hosted; all 8 workflow jobs run on `ubuntu-latest`.
- Prior-review-doc echoes of the above.

**No Wix IP present.** All `wix`-string matches are intentional guardrails: the `hooks/wix-ip-guard.sh` detector, the `run-tamirs-superpowers` smoke-test check, CHANGELOG entries documenting past scrubbing, and "never add Wix references" rules in AGENTS.md/CLAUDE.md/CONTRIBUTING.md. These are defensive and must stay.

## CI hosting note

CI is **GitHub-hosted (`ubuntu-latest`)**, not a Mac self-hosted runner. No self-hosted runner label appears in any workflow YAML, so no runner-specific CI configuration is needed.

## Multi-agent appendix

`AGENTS.md` and `CLAUDE.md` are present and cross-referenced. Detailed multi-agent audit is delegated to the `multi-agent-repo` skill (run separately).

## Inventory appendix (JSON)

```json
{"readme":{"exists":true,"has_badges":true,"has_prerequisites":true,"has_quick_start":true,"has_license_line":true,"has_banner":true},"docs":{"readme":true,"changelog":true,"contributing":true,"user_dir":true,"engineering_dir":true},"github":{"ci_workflow":true,"secret_scan_job":true,"pr_template":true,"dependabot":true},"root_files":{"license":true,"codeowners":true,"gitignore":true,"claude_md":true,"agents_md":true},"branch_governance":{"protection_enabled":true,"required_approving_reviews":1},"hygiene":{"misplaced_top_level_docs":0,"ticket_named_outside_engineering":0,"empty_dirs":2,"self_hosted_ci":false}}
```

## Next steps

- No standards remediation required; polish phase would produce no material change.
- Minor hygiene: 2 empty directories detected (non-blocking) — can be swept by the `cleanup` skill.
- Proceed to `multi-agent-repo` audit and open-PR (`pr-dev`) workflow.
