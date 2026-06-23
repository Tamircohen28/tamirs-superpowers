# Contract templates index

Canonical templates for `repo-scaffold` and `repo-standards` polish. Contract version: see [`../standards-contract.json`](../standards-contract.json).

## Layout

| Path | Purpose |
|------|---------|
| [`github/ci.yml.tmpl`](github/ci.yml.tmpl) | `CI` + `secret-scan` jobs, `ubuntu-latest` |
| [`github/dependabot.yml.tmpl`](github/dependabot.yml.tmpl) | Weekly GitHub Actions updates |
| [`scaffold-requirements.md`](scaffold-requirements.md) | README sections, docs tree, branch protection |
| [`legacy-scaffold-templates.md`](legacy-scaffold-templates.md) | Full stack-specific bodies (Node, Python, Swift, CLAUDE.md, workflows) |
| [`check-agent-drift.sh.tmpl`](check-agent-drift.sh.tmpl) | Drift script copied to target `scripts/` |
| [`../fixtures/scaffold-gold/`](../fixtures/scaffold-gold/) | Gold reference tree — must pass `assert-contract.sh` |
| [`scaffold-requirements-plugin.md`](scaffold-requirements-plugin.md) | Agent-kit / `--type plugin` layout |
| [`plugin/`](plugin/) | Canonical rules, build stubs, marketplace, plugin manifest templates |

## Canonical paths (app-gold)

- `docs/CONTRIBUTING.md`, `docs/CHANGELOG.md` (not repo root)
- README: Prerequisites + Quick Start + CI/license badges
- `AGENTS.md` + `CLAUDE.md` (`@AGENTS.md` line 1) + `.cursor/rules/000-project.mdc`
- `docs/agent-guidelines/`, `scripts/check-agent-drift.sh`, `make agent:check`

Do not invent formats — render from these templates.
