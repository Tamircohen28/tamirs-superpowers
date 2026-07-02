# Plugin scaffold requirements (plugin-gold)

Extends [scaffold-requirements.md](../scaffold-requirements.md) for `--type plugin` agent-kit repos.

## README sections (in addition to app-gold)

- **Install as Claude Code plugin** — marketplace add + plugin install commands
- **Install to a target repo** — pointer to future `agent:update` / sync script
- **Build adapters** — `npm run build` + `npm run validate`
- **Security model** — CODEOWNERS on canonical/, plugins/, scripts/, hooks/

## Required tree

```
agent-kit.config.json
canonical/rules/{core,testing,security,frontend,backend}.md
canonical/skills/<name>/SKILL.md
canonical/templates/*.hbs          # future Handlebars pipeline
scripts/build.mjs
scripts/validate.mjs
dist/codex/AGENTS.md               # GENERATED
dist/cursor/.cursor/rules/000-core.mdc
plugins/<name>/.claude-plugin/plugin.json
plugins/<name>/skills/
plugins/<name>/hooks/hooks.json    # optional empty stub
.claude-plugin/marketplace.json
package.json                       # build, validate, agent:check scripts
package-lock.json                  # required for npm ci in CI/Makefile
```

## CI

- Jobs: `CI`, `validate`, `secret-scan`, `manifest-version-alignment`
- `validate` job runs `npm run build` then `npm run validate`
- `manifest-version-alignment` runs `scripts/check-manifest-version-alignment.sh .`
  (copied from `check-manifest-version-alignment.sh.tmpl`) with `fetch-depth: 0` so
  tags are visible — required for any repo with `.claude-plugin/`,
  `.cursor-plugin/`, and/or `.codex-plugin/plugin.json` (S10-04/S10-05)

## CODEOWNERS

Must include paths: `canonical/`, `plugins/`, `scripts/`, `hooks/`

## Contract profile

Exit gate: `assert-contract.sh <root> plugin-gold` (P1=P2=P3=0 offline except branch protection and merge settings).

Apply `enable-repo-merge-settings.sh` and `ensure-branch-protection.sh` in polish phase 4 (same as app-gold).

## Templates

See [`plugin/`](plugin/) for canonical bodies, build/validate stubs, manifests, and CI.
