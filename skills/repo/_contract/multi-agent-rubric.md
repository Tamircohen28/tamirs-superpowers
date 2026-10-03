# Multi-agent rubric excerpt

Auto-scored IDs from `score-inventory-gaps.sh`. Full rubric: [`../multi-agent-repo/references/audit-rubric.md`](../multi-agent-repo/references/audit-rubric.md).

| ID | Check | Severity |
|----|-------|----------|
| L1-01 | AGENTS.md at repo root | P1 |
| L1-04 | AGENTS.md ≤ 32 KiB | P1 |
| L2-01 | CLAUDE.md exists | P1 |
| L2-02 | CLAUDE.md references AGENTS.md | P1 |
| L3-01 | `.cursor/rules/` present | P2 |
| L3-02 | No `.md` files in `.cursor/rules/` | P1 |
| L4-02 | Portable skills dir (`.agents/skills`, `skills`, or `.claude/skills`) | P2 |
| L5-01 | `docs/agent-guidelines/` | P2 |
| L6-03 | `agent:check` in Makefile or package.json | P1 |
| L7-01 | `scripts/check-agent-drift.sh` | P2 |
| E1-01 | `.agents/skills/` or documented bridge (app repos) | P1 |
| E2-01 | Every skills-path manifest present when skills ship (`.claude-plugin`, `.cursor-plugin`, `.codex-plugin`) | P1 |
| V1-01 | `platform-targets.json` when multi-platform | P1 |
| E6-01 | `core/capabilities/platforms.json` when multi-platform | P1 (plugin) / P2 (app) |
| E6-02 | Registry and `platform-targets.json` agree on the platform set | P1 |

Merged with standards S1–S7 via `score-contract-gaps.sh`. E/V via `score-equivalence-gaps.sh` and `score-platform-target-gaps.sh`.
