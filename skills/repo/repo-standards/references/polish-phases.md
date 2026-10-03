# Polish phases — implementation order

Polish mode implements phases 0–7 sequentially. Do not skip IP acknowledgment (phase 0).

| Phase | Actions | Delegate |
|-------|---------|----------|
| 0 | Run `ip-scan.sh`; fix hits; re-scan until clean | local |
| 1 | README, LICENSE, .gitignore, Makefile | `scaffold-templates.md` |
| 2 | docs/ tree stubs with real content | local |
| 3 | `.github/workflows`, PR template, dependabot; if plugin-gold: copy `check-manifest-version-alignment.sh.tmpl` → `scripts/`, wire as required CI job | `scaffold-templates.md` |
| 4 | CODEOWNERS + merge settings + branch governance (`enable-repo-merge-settings.sh`, then `scripts/github-policy.sh apply --repo <owner/name>` — rulesets, from `config/github/repository-policy.json`) | `scaffold-requirements.md` |
| 5 | Multi-agent setup | `Skill("multi-agent-repo")` dev — add plugin constraints when profile is `plugin-gold` |
| 6 | Doc + plugin audits | `Skill("docs-review")`, `Skill("changelog-review")` if plugin or agent-kit |
| 7 | Re-inventory + gap score; confirm P1 = 0 | `assert-contract.sh` with detected profile (`app-gold` or `plugin-gold`) |

Commit in logical chunks. Push branch. `gh pr create` — stop.
