# Architecture Decision Records

This directory tracks significant design decisions. Each ADR documents what was decided, why, and what alternatives were considered.

## Index

| ADR | Title | Status |
|-----|-------|--------|
| [001](001-plugin-over-dotfiles.md) | Plugin over dotfiles for Claude config distribution | Accepted |
| [002](002-marketplace-and-plugin-in-one-repo.md) | Marketplace and plugin colocated in one repo | Accepted |
| [003](003-hook-tiers-as-options.md) | Hook tiers as plugin options, not separate plugins | Accepted |
| [004](004-permission-levels.md) | Permission levels: presets, config, overrides and enforcement per platform | Superseded by [006](006-remove-permission-levels.md) |
| [006](006-remove-permission-levels.md) | Remove the permission levels | Accepted |

## Format

Each ADR uses the lightweight format:
- **Status** — Proposed / Accepted / Deprecated / Superseded
- **Context** — What situation led to this decision
- **Decision** — What was decided
- **Consequences** — What becomes easier and harder as a result

---

<p align="center"><a href="https://github.com/Tamircohen28">Have a Question?</a>&nbsp;·&nbsp;<a href="https://github.com/Tamircohen28/tamirs-superpowers/issues/new/choose">Open an Issue</a></p>
