# scaffold-gold — AGENTS.md

## Overview

Minimal Node fixture for repo contract validation.

## Commands

| Command | Purpose |
|---------|---------|
| `make install` | Install dependencies |
| `make test` | Run tests |
| `make lint` | Run linter |
| `make agent:check` | Verify thin adapters reference this file |

## Constraints

- Never commit secrets or `.env` files
- CI uses `ubuntu-latest` only

## Dependency management

- Configure `.github/dependabot.yml` with only the ecosystems present in this repo.
- Weekly cadence for npm/pip, monthly for GitHub Actions. Never daily.
- Group minor and patch updates into one PR per ecosystem (`groups`).
- Block automatic major-version PRs (`ignore: version-update:semver-major`). Handle major bumps manually after reading the changelog.
- Set `open-pull-requests-limit: 3` or lower. Never let Dependabot open one PR per dependency.
- Do not blindly merge Dependabot PRs — require CI (build + tests + lint) to pass first.
- Prefer security updates over routine version churn. To get security fixes only, disable version updates and enable Dependabot security alerts via repo Settings → Code security.
