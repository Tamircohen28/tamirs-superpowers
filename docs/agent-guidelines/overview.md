# Agent guidelines — tamirs-superpowers

Quick reference for AI agents contributing to this plugin repo.

## Start here

Read [`../../AGENTS.md`](../../AGENTS.md) at the repo root for full working agreements, allowed/forbidden commands, and CI expectations.

## Repo type

This is a **Claude Code plugin** — no build step, no package.json, no compiled output. All content is Markdown, JSON, and Bash.

## Key commands

```bash
make validate    # shellcheck + JSON lint + frontmatter + contract test (run after every change)
make lint        # shellcheck only
```

## What agents can touch

| Area | Guidance |
|------|----------|
| `skills/<domain>/<name>/SKILL.md` | Use `skill-creator` skill; never hand-write frontmatter |
| `hooks/*.sh` | Run shellcheck; do not modify `hooks/lib/worktree-common.sh` without testing both hook scripts |
| `.claude-plugin/plugin.json` | Bump version in all three manifests + `README.md` badges after shipped changes — see `rules/dev/plugin-version-bump.md` |
| `docs/**` | Edit freely; run `make validate` after |
| `.github/workflows/` | Never add `runs-on: [self-hosted]`; use `ubuntu-latest` |

## Off-limits for agents

- Never commit secrets — `.mcp.json` uses `${ENV_VAR}` placeholders only
- Never add employer-internal references (internal hostnames, registries, scoped packages)
- Never add `runs-on: [self-hosted]` to any CI workflow
- Never create a root `marketplace.json` — this repo is published through the `Tamircohen28/tamirs-marketplace` catalog

## Validation before PR

```bash
make validate
make test-repo-contract
bash skills/repo/repo-standards/scripts/assert-contract.sh . app-gold
```
