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
