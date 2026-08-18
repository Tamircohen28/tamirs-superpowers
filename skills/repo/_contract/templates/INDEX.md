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
| [`check-feature-equivalence.sh.tmpl`](check-feature-equivalence.sh.tmpl) | E-layer parity + capability-registry agreement, copied to target `scripts/` |
| [`check-platform-targets.sh.tmpl`](check-platform-targets.sh.tmpl) | V-layer version/badge checks + `--sync-capabilities`, copied to target `scripts/` |
| [`core/capabilities/schema.json.tmpl`](core/capabilities/schema.json.tmpl) | Capability registry JSON Schema |
| [`core/capabilities/platforms.json.tmpl`](core/capabilities/platforms.json.tmpl) | Capability registry instance — the ONE statement of what each target can do |
| [`makefile-agent-targets.mk.tmpl`](makefile-agent-targets.mk.tmpl) | `make agent:check`, `make agent-polish-gate`, platform-targets-* targets — agents only |
| [`check-manifest-version-alignment.sh.tmpl`](check-manifest-version-alignment.sh.tmpl) | Plugin repos only: manifest-vs-manifest and manifest-vs-tag version drift, copied to target `scripts/`, wired as a required CI job (see `plugin/ci-plugin.yml.tmpl`) |
| [`../fixtures/scaffold-gold/`](../fixtures/scaffold-gold/) | Gold reference tree — must pass `assert-contract.sh` |
| [`scaffold-requirements-plugin.md`](scaffold-requirements-plugin.md) | Agent-kit / `--type plugin` layout |
| [`plugin/`](plugin/) | Canonical rules, build stubs, marketplace, plugin manifest templates |

## Canonical paths (app-gold)

- `docs/CONTRIBUTING.md`, `docs/CHANGELOG.md` (not repo root)
- README: Prerequisites + Quick Start + CI/license badges
- `AGENTS.md` + `CLAUDE.md` (`@AGENTS.md` line 1) + `.cursor/rules/000-project.mdc`
- `docs/agent-guidelines/`, `scripts/check-agent-drift.sh`, `make agent:check`
- `core/capabilities/{schema.json,platforms.json}` when the repo targets ≥2 harnesses

## One source of truth

`core/capabilities/platforms.json` states the platform set and every capability status.
`feature-equivalence.json` adds only the artifact delta; `platform-targets.json` adds only
versions plus a **derived** capability mirror (`--sync-capabilities`). Never restate a
platform's support in prose or in a second JSON file — `check-feature-equivalence.sh`
fails when any two views disagree.

Do not invent formats — render from these templates.
