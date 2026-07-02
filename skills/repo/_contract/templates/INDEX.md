# Contract templates index

Canonical templates for `repo-scaffold` and `repo-standards` polish. Contract version: see [`../standards-contract.json`](../standards-contract.json).

## Layout

| Path | Purpose |
|------|---------|
| [`github/ci.yml.tmpl`](github/ci.yml.tmpl) | `CI` + `secret-scan` jobs, `ubuntu-latest` |
| [`github/dependabot.yml.tmpl`](github/dependabot.yml.tmpl) | Weekly GitHub Actions updates |
| [`github/agent_task.yml.tmpl`](github/agent_task.yml.tmpl) | Agent-task issue template with Resume block for switch-dev |
| [`scaffold-requirements.md`](scaffold-requirements.md) | README sections, docs tree, merge settings, branch protection |
| [`../scripts/enable-repo-merge-settings.sh`](../scripts/enable-repo-merge-settings.sh) | `allow_auto_merge` + `delete_branch_on_merge` |
| [`../scripts/ensure-branch-protection.sh`](../scripts/ensure-branch-protection.sh) | Apply/verify default-branch protection (1 review + CI) |
| [`legacy-scaffold-templates.md`](legacy-scaffold-templates.md) | Full stack-specific bodies (Node, Python, Swift, CLAUDE.md, workflows) |
| [`check-agent-drift.sh.tmpl`](check-agent-drift.sh.tmpl) | Drift script copied to target `scripts/` |
| [`check-manifest-version-alignment.sh.tmpl`](check-manifest-version-alignment.sh.tmpl) | Plugin repos only: manifest-vs-manifest and manifest-vs-tag version drift, copied to target `scripts/`, wired as a required CI job (see `plugin/ci-plugin.yml.tmpl`) |
| [`../fixtures/scaffold-gold/`](../fixtures/scaffold-gold/) | Gold reference tree — must pass `assert-contract.sh` |
| [`scaffold-requirements-plugin.md`](scaffold-requirements-plugin.md) | Agent-kit / `--type plugin` layout |
| [`plugin/`](plugin/) | Canonical rules, build stubs, marketplace, plugin manifest templates |

## Canonical paths (app-gold)

- `docs/CONTRIBUTING.md`, `docs/CHANGELOG.md` (not repo root)
- README: Prerequisites + Quick Start + CI/license badges
- `AGENTS.md` + `CLAUDE.md` (`@AGENTS.md` line 1) + `.cursor/rules/000-project.mdc`
- `docs/agent-guidelines/`, `scripts/check-agent-drift.sh`, `make agent:check`

Do not invent formats — render from these templates.
