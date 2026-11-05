# scaffold-marketplace-gold — AGENTS.md

Contributor rules for this **plugin marketplace repo**: a catalog of plugins, published in
the manifest each platform reads.

## Overview

One catalog, three manifests. `.claude-plugin/marketplace.json` is the canonical list;
`.cursor-plugin/marketplace.json` and `.agents/plugins/marketplace.json` must agree with it.
OpenCode has no marketplace and gets no manifest. Plugins that live here sit under
`plugins/<name>/`; plugins hosted elsewhere are listed by `github`, `git-subdir` or `npm`
source. How to add one: [docs/user/catalog.md](docs/user/catalog.md).

## Commands

| Command | Purpose |
|---------|---------|
| `make validate` | Every manifest checked and cross-checked (`scripts/validate-marketplace.sh`) |
| `make agent:check` | validate + drift, equivalence, platform-target and action-pinning checks |
| `make install` | `claude plugin marketplace add .` — register this checkout locally |

## Constraints

- A plugin listed for Cursor or Codex must also be in the Claude catalog.
- A local plugin's `plugin.json` `name` equals its catalog entry name.
- Relative sources start with `./` and never contain `..`.
- Never commit secrets or `.env` files; CI uses `ubuntu-latest` only.
- Treat `plugins/` and `scripts/` as supply-chain surface (CODEOWNERS).

## Versioning

A plugin's version lives in its own `plugin.json`. The catalog's `metadata.version` bumps
when the catalog changes shape; see
[docs/engineering/build-and-release/versioning.md](docs/engineering/build-and-release/versioning.md)
and record it in [docs/CHANGELOG.md](docs/CHANGELOG.md).

## Dependency management

- Configure `.github/dependabot.yml` with only the ecosystems present in this repo.
- Monthly cadence for GitHub Actions. Never daily.
- Group updates into one PR per ecosystem (`groups`).
- Set `open-pull-requests-limit: 3` or lower. Never let Dependabot open one PR per dependency.
- Do not blindly merge Dependabot PRs — require CI to pass first.
