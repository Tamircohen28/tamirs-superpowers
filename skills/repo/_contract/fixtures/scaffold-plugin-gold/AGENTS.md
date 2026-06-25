# scaffold-plugin-gold — AGENTS.md

Contributor rules for this **agent-kit distribution repo**.

## Overview

Edit `canonical/` only. Run `npm run build` to regenerate `dist/` and plugin skills. Never edit generated files by hand.

## Commands

| Command | Purpose |
|---------|---------|
| `npm ci` | Install dependencies |
| `npm run build` | Regenerate dist/ and plugins/*/skills/ |
| `npm run validate` | Layout + GENERATED marker checks |
| `make agent:check` | validate + drift script |

## Constraints

- Never commit secrets or `.env` files
- CI uses `ubuntu-latest` only
- Treat hooks/ and install scripts as supply-chain surface

## Architecture

See [docs/engineering/agent-kit-architecture.md](docs/engineering/agent-kit-architecture.md).

## Dependency management

- Configure `.github/dependabot.yml` with only the ecosystems present in this repo.
- Weekly cadence for npm/pip, monthly for GitHub Actions. Never daily.
- Group minor and patch updates into one PR per ecosystem (`groups`).
- Block automatic major-version PRs (`ignore: version-update:semver-major`). Handle major bumps manually after reading the changelog.
- Set `open-pull-requests-limit: 3` or lower. Never let Dependabot open one PR per dependency.
- Do not blindly merge Dependabot PRs — require CI (build + tests + lint) to pass first.
- Prefer security updates over routine version churn. To get security fixes only, disable version updates and enable Dependabot security alerts via repo Settings → Code security.
