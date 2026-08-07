# ADR 002 — Marketplace and plugin colocated in one repo

**Status:** Accepted — amended 2026-08-03

## Context

A Claude Code plugin marketplace is a GitHub repo carrying `.claude-plugin/marketplace.json`. A plugin is a directory with a `.claude-plugin/plugin.json`. These can be separate repos (marketplace repo + plugin repo) or colocated in one repo.

With a single plugin to publish, maintaining two repos adds overhead with no benefit: two sets of CI, two release workflows, two git histories.

Since this ADR was first written the repo also became publishable through the [`tamirs-marketplace`](https://github.com/Tamircohen28/tamirs-marketplace) catalog, and the target list grew from one platform to four. Colocation still holds — but the details recorded in the original decision had drifted from what the repo actually contains.

## Decision

Use a single GitHub repo (`Tamircohen28/tamirs-superpowers`) that is simultaneously a plugin source and a standalone marketplace for **every** supported target:

| Target | Marketplace manifest | Plugin manifest |
|--------|---------------------|-----------------|
| Claude Code | `.claude-plugin/marketplace.json` (`"source": "./"`) | `.claude-plugin/plugin.json` |
| Cursor | the plugin manifest is imported directly | `.cursor-plugin/plugin.json` |
| Codex | `.agents/plugins/marketplace.json` | `.codex-plugin/plugin.json` |
| OpenCode | none — no marketplace concept | none — `opencode.json` + `.opencode/agent/` |

The catalog remains the recommended install path on Claude Code and Cursor; the in-repo marketplaces make the repo installable on its own.

## Amendments (2026-08-03)

Two claims in the original decision were wrong, and both had real consequences:

- **The manifest path.** The ADR said `marketplace.json` sits "at the repo root". Claude Code reads `.claude-plugin/marketplace.json`, and no such file existed — `claude plugin marketplace add <repo>` failed with `Marketplace file not found`. Standalone Claude Code install did not work. The file now exists and the add succeeds.
- **Version resolution by tag.** The ADR claimed the `v<version>` git tag is used for version resolution. The catalog entry pins `"ref": "master"`, so releases are resolved by branch, not tag. Tags remain useful as release markers; they are not what installers follow.

Codex's marketplace manifest lives at `.agents/plugins/marketplace.json` — *not* `.codex-plugin/marketplace.json`. That file was likewise missing from version control until 1.12.0, which broke standalone Codex install the same way.

## Consequences

**Easier:**
- One repo to clone, one CI pipeline, one release workflow
- Marketplace and plugin manifests are always in sync — same commit, same version
- Every target can install from this repo alone, with no catalog dependency

**Harder:**
- Four manifests must move together on a version bump (`.claude-plugin`, `.cursor-plugin`, `.codex-plugin`, plus the Codex marketplace file). CI's manifest alignment check covers the three plugin manifests.
- If a second plugin is added later, the repo needs a refactor: the current plugin moves into a subdirectory and each marketplace's `source` is repointed. This is a one-time migration.
- The repo root is unconventional — it carries marketplace and plugin config for three different platforms side by side.
