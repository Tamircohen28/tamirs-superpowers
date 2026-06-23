# Standards rubric — repo-standards

Auto-scored IDs map to `score-standards-gaps.sh`. Manual follow-up required for content quality.

## S1 README

| ID | Check | Severity |
|----|-------|----------|
| S1-01 | README.md exists | P1 |
| S1-02 | CI + license badges | P2 |
| S1-03 | Prerequisites section | P2 |
| S1-04 | Quick Start section | P2 |

Manual: hero banner, features bullets, docs link, no placeholder prose.

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

## S5 Root legal/ops

| ID | Check | Severity |
|----|-------|----------|
| S5-01 | LICENSE | P1 |
| S5-02 | .gitignore | P2 |

## S6 Repo hygiene

| ID | Check | Severity |
|----|-------|----------|
| S6-01 | No stray docs/*.md at docs root | P1 |
| S6-02 | No ticket-named md outside engineering | P2 |
| S6-03 | Excessive empty directories | P3 |
| S6-04 | Self-hosted CI | P1 |

## S7 Employer IP

| ID | Check | Severity |
|----|-------|----------|
| S7-01 | ip-scan.sh clean | P1 |

## S8 Multi-agent

Deterministic L-layer gaps are included in `score-contract-gaps.sh`. Qualitative L1 content review may still delegate to `Skill("multi-agent-repo")` review mode (summary-only appendix).
