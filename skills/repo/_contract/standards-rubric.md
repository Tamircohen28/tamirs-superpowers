# Standards rubric — repo-standards

Auto-scored IDs map to `score-standards-gaps.sh`. Manual follow-up required for content quality.

Canonical references:
- Badge layout: [`references/readme-badges.md`](references/readme-badges.md)
- Versioning policy: [`references/versioning-policy.md`](references/versioning-policy.md)

## S1 README

| ID | Check | Severity |
|----|-------|----------|
| S1-01 | README.md exists | P1 |
| S1-02 | CI + license badges (row 1) | P2 |
| S1-03 | Prerequisites section | P2 |
| S1-04 | Quick Start section | P2 |
| S1-05 | Hero banner (`assets/banner.*` referenced in README) | P2 |
| S1-06 | Author badge linking to GitHub profile | P2 |
| S1-07 | Version badge (package.json or plugin manifest version) | P2 |
| S1-08 | `Makefile` exposes `install`, `update`, `uninstall` targets | P2 |
| S1-09 | AI-target badges row when repo supports ≥2 platforms | P2 |
| S1-10 | Per-target Quick Start subsections when multi-platform | P2 |

Manual: features bullets, docs link, Quick Start uses `make install` as primary path.

## S2 docs/

## S2 docs/

| ID | Check | Severity |
|----|-------|----------|
| S2-01 | docs/user/ | P2 |
| S2-02 | docs/engineering/ | P2 |
| S2-03 | docs/CHANGELOG.md | P2 |
| S2-04 | docs/CONTRIBUTING.md | P2 |

Manual: doc map READMEs, ADR index, project-specific content.

## S3 GitHub infra

| ID | Check | Severity |
|----|-------|----------|
| S3-01 | CI workflow | P1 |
| S3-02 | Secret-scan in CI | P2 |
| S3-03 | PR template | P2 |
| S3-04 | dependabot.yml | P3 |

Manual: issue templates, release workflow, no self-hosted runners.

## S4 Branch governance

| ID | Check | Severity |
|----|-------|----------|
| S4-01 | CODEOWNERS | P2 |
| S4-02 | Branch protection enabled | P2 |
| S4-03 | ≥1 required approving review | P2 |
| S4-04 | `allow_auto_merge` enabled | P2 |
| S4-05 | `delete_branch_on_merge` enabled | P3 |
| S4-06 | Required `CI` status check on default branch | P2 |

## S5 Root legal/ops

| ID | Check | Severity |
|----|-------|----------|
| S5-01 | LICENSE | P1 |
| S5-02 | .gitignore | P2 |
| S5-03 | Root `CHANGELOG.md` (mirror or primary) | P2 |
| S5-04 | `AGENTS.md` at repo root | P1 |

## S10 Versioning and release

| ID | Check | Severity |
|----|-------|----------|
| S10-01 | `docs/CHANGELOG.md` with `[Unreleased]` section | P2 |
| S10-02 | `docs/engineering/build-and-release/versioning.md` exists | P2 |
| S10-03 | `AGENTS.md` references versioning policy | P3 |
| S10-04 | Multi-manifest plugin repos: all `plugin.json` versions match | P1 |
| S10-05 | Declared `plugin.json` version has a matching release tag (no unreleased manifest bumps on main) | P1 |

Manual: git tag matches declared version; release workflow; semver bump discipline per `versioning-policy.md`.

## S6 Repo hygiene

| ID | Check | Severity |
|----|-------|----------|
| S6-01 | No stray docs/*.md at docs root | P1 |
| S6-02 | No ticket-named md outside engineering | P2 |
| S6-03 | Excessive empty directories | P3 |
| S6-04 | Self-hosted CI | P1 |
| S6-05 | No `.sh` files at repo root (use `scripts/`) | P2 |

## S7 Employer IP

| ID | Check | Severity |
|----|-------|----------|
| S7-01 | ip-scan.sh clean | P1 |

## S8 Multi-agent

Deterministic L-layer gaps are included in `score-contract-gaps.sh`. Qualitative L1 content review may still delegate to `Skill("multi-agent-repo")` review mode (summary-only appendix).
