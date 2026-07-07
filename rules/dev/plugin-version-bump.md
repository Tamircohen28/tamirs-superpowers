---
alwaysApply: true
---

# Plugin version bump (Claude Code marketplace)

Applies when you change **shipped plugin content** in this repo: `skills/`, `hooks/`, `agents/`, plugin manifests, `scripts/`, or `.mcp.json`.

## Why this matters

`tamirs-superpowers` sets an explicit `"version"` in `.claude-plugin/plugin.json`. Claude Code uses that string as the **cache key** for updates ([plugins reference — Version management](https://code.claude.com/docs/en/plugins-reference#version-management)):

- Pushing new commits **without** bumping `version` does **not** deliver changes to installed users.
- `/plugin update` reports **"already at the latest version"** and keeps the cached copy.
- `/reload-plugins` reloads from the **local cache** only — it does not fetch from GitHub.

Published through [`Tamircohen28/plugins`](https://github.com/Tamircohen28/plugins) (`tamirs-superpowers@tamirs-plugins`).

## When agents must bump the version

Bump **all three** manifests in the **same commit** before opening a release PR:

| File | Field |
|------|-------|
| `.claude-plugin/plugin.json` | `version` |
| `.cursor-plugin/plugin.json` | `version` |
| `.codex-plugin/plugin.json` | `version` |

Also update `README.md` version badges when bumping.

| Change type | Semver bump |
|-------------|-------------|
| New or removed skills, new hooks, backward-compatible features | **MINOR** (`1.5.1` → `1.6.0`) |
| Bug fixes, docs-only in shipped paths, non-breaking hook tweaks | **PATCH** (`1.5.1` → `1.5.2`) |
| Removed skills, breaking hook behavior, renamed slash commands | **MAJOR** |

Full policy: [`docs/engineering/build-and-release/versioning.md`](../../docs/engineering/build-and-release/versioning.md).

## Agent checklist (after plugin content changes)

1. Run `make validate`
2. Move `[Unreleased]` entries in `CHANGELOG.md` under `[X.Y.Z] - YYYY-MM-DD`
3. Bump all three `plugin.json` manifests + `README.md` badges to the same `X.Y.Z`
4. Open a PR — **never** push manifest bumps directly to `master` without a PR
5. After merge, run the [Release workflow](.github/workflows/release.yml) with `X.Y.Z` to create the `vX.Y.Z` git tag (required for CI manifest/tag alignment)
6. Tell users to refresh:

   ```text
   /plugin marketplace update tamirs-plugins
   /plugin update tamirs-superpowers@tamirs-plugins
   /reload-plugins
   ```

## Local development without a release

To test unpublished changes in Claude Code **before** bumping version:

1. Find the cache path: `ls ~/.claude/plugins/cache/tamirs-plugins/tamirs-superpowers/`
2. Edit files there, **or** symlink your dev clone to that path
3. Run `/reload-plugins`

Do **not** assume `/plugin update` or `/reload-plugins` will pull from your local working tree or unpushed commits.

## CI enforcement

`make validate` and CI job `Manifest/tag version alignment` fail when:

- the three manifests disagree, or
- manifest `version` has no matching `vX.Y.Z` git tag (once the repo has at least one release tag)

After bumping manifests in a PR, the tag is created **post-merge** via the Release workflow — expect the alignment CI job to fail on the PR until `vX.Y.Z` exists on `master`.
