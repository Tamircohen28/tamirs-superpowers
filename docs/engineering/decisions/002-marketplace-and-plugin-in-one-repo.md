# ADR 002 — Marketplace and plugin colocated in one repo

**Status:** Accepted

## Context

A Claude Code plugin marketplace is a GitHub repo with a `marketplace.json` at the root. A plugin is a directory with a `.claude-plugin/plugin.json`. These can be separate repos (marketplace repo + plugin repo) or colocated in one repo.

With a single plugin to publish, maintaining two repos adds overhead with no benefit: two sets of CI, two release workflows, two git histories.

## Decision

Use a single GitHub repo (`Tamircohen28/tamirs-superpowers`) that serves as both the marketplace and the plugin source. `marketplace.json` sits at the repo root with `"source": "."`, pointing the marketplace at the root of the same repo as the plugin location.

## Consequences

**Easier:**
- One repo to clone, one CI pipeline, one release workflow
- `marketplace.json` and `.claude-plugin/plugin.json` are always in sync — same commit, same version
- The `tamirs-superpowers--v<version>` git tag used for version resolution is created in the same repo where the plugin source lives

**Harder:**
- If a second plugin is added later, the repo structure needs a refactor: the current plugin would need to move into a subdirectory (e.g. `tamirs-superpowers/`) and `marketplace.json` would need `"source": "./tamirs-superpowers"`. This is a one-time migration.
- The repo root is slightly unconventional — it contains both marketplace config and plugin config at the same level.
