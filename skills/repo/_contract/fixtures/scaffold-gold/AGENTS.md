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
