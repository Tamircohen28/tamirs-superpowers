# Polish phases — implementation order

Polish mode implements phases 0–7 sequentially. Do not skip IP acknowledgment (phase 0).

| Phase | Actions | Delegate |
|-------|---------|----------|
| 0 | Run `ip-scan.sh`; fix hits; re-scan until clean | local |
| 1 | README, LICENSE, .gitignore, Makefile | `scaffold-templates.md` |
| 2 | docs/ tree stubs with real content | local |
| 3 | `.github/workflows`, PR template, dependabot | `scaffold-templates.md` |
| 4 | CODEOWNERS + `gh api` branch protection | `scaffold-templates.md` |
| 5 | Multi-agent setup | `Skill("multi-agent-repo")` dev |
| 6 | Doc + plugin audits | `Skill("docs-review")`, `Skill("changelog-review")` if plugin |
| 7 | Re-inventory + gap score; confirm P1 = 0 | local scripts |

Commit in logical chunks. Push branch. `gh pr create` — stop.
