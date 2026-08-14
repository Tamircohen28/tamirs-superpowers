---
alwaysApply: true
---

# Plugin version bump (four supported targets)

Applies when you change **shipped plugin content** in this repo: `skills/`, `hooks/`, `agents/`, plugin manifests, `scripts/`, `opencode.json`, or `.mcp.json`.

## Why this matters

`tamirs-superpowers` sets an explicit `"version"` in each plugin manifest. Claude Code uses that string as the **cache key** for updates ([plugins reference — Version management](https://code.claude.com/docs/en/plugins-reference#version-management)):

- Pushing new commits **without** bumping `version` does **not** deliver changes to installed users.
- `/plugin update` reports **"already at the latest version"** and keeps the cached copy.
- `/reload-plugins` reloads from the **local cache** only — it does not fetch from GitHub.

Published through [`Tamircohen28/tamirs-marketplace`](https://github.com/Tamircohen28/tamirs-marketplace) (`tamirs-superpowers@tamirs-marketplace`).

## What a bump has to touch

The repo ships to **four targets**, but only three carry a version string. Bump all three in the **same commit**:

| File | Field | Target |
|------|-------|--------|
| `.claude-plugin/plugin.json` | `version` | Claude Code |
| `.cursor-plugin/plugin.json` | `version` | Cursor |
| `.codex-plugin/plugin.json` | `version` | Codex |

`opencode.json` has **no version field** — OpenCode installs by path, not through a marketplace, so there is no cache to invalidate. Do not add one for symmetry; the asymmetry is real and recorded in `platform-targets.json` under `targets.opencode.capability_gaps`.

The same commit must also carry whatever the bump falsified:

| Artifact | Why it drifts otherwise |
|----------|------------------------|
| `README.md` version badge | Users read the badge, not the manifest |
| `CHANGELOG.md` — promote `[Unreleased]` → `[X.Y.Z] - YYYY-MM-DD` | Release notes are generated from it |
| `docs/CHANGELOG.md` summary entry | Mirror; diverges silently |
| `docs/engineering/build-and-release/platform-targets.json` | `last_reviewed` and per-target `validated_against` pin what was actually checked |
| Documented **skill count** (README, CLAUDE.md, AGENTS.md, all four install guides) | Adding or removing a skill falsifies every one — `make check-doc-claims` fails the build |
| `docs/user/install/<target>.md` | Anything a user copy-pastes, per target |

| Change type | Semver bump |
|-------------|-------------|
| New or removed skills, new hooks, backward-compatible features | **MINOR** (`1.5.1` → `1.6.0`) |
| Bug fixes, docs-only in shipped paths, non-breaking hook tweaks | **PATCH** (`1.5.1` → `1.5.2`) |
| Removed skills, breaking hook behavior, renamed slash commands | **MAJOR** |

Full policy: [`docs/engineering/build-and-release/versioning.md`](../../docs/engineering/build-and-release/versioning.md).

## Adding or changing a supported target

A target is not "supported" until **all five** exist. `make validate` enforces items 2–4:

1. Manifest or config for the target (`.<target>-plugin/plugin.json`, or an `opencode.json`-style config)
2. `docs/user/install/<target>.md`, linked from `docs/user/install/README.md`
3. An entry in `platform-targets.json` → `supported_targets` **and** `targets.<key>`, with `validated_against`, `verified_on`, `verification_method`, `install_doc`, and any `capability_gaps`
4. `skills/documentation/platform-sync-<target>/` with its own `references/urls.md` — without it, `/platform-sync` silently skips the target and reports success
5. The target named in `README.md` and `AGENTS.md`

Never record a `validated_against` you did not observe. Run the target's own `--version` on the machine and write how you got it into `verification_method`. A guessed floor is worse than an absent one — it converts "unknown" into a false promise.

Marketplace declarations are per-target and not interchangeable. Claude Code's `extraKnownMarketplaces` is a **record keyed by marketplace name** — an array is dropped silently, with no error and no warning. (Since Claude Code 2.1.232 the setting is also accepted under the alias `additionalMarketplaces`; identical record shape and the same silent array drop — prefer `extraKnownMarketplaces` where older versions must read the file.) Cursor and Codex read their own manifests; OpenCode has no marketplace at all. `make check-marketplace-schema` guards the shape in both real settings files and the scaffold templates.

## Agent checklist (after plugin content changes)

1. Run `make validate` — includes `check-marketplace-schema` and `check-doc-claims`
2. When changing `skills/repo/**` or platform specs, run `make platform-targets-sync`, then update `platform-targets.json` + README badges
3. Promote `[Unreleased]` entries in `CHANGELOG.md` under `[X.Y.Z] - YYYY-MM-DD`; mirror in `docs/CHANGELOG.md`
4. Bump the three `plugin.json` manifests + `README.md` badge to the same `X.Y.Z`
5. Open a PR — **never** push manifest bumps directly to `master`
6. After merge, run the [Release workflow](.github/workflows/release.yml) with `X.Y.Z` to create the `vX.Y.Z` tag
7. **Verify the tag actually contains the change** (below) before telling anyone it shipped
8. Tell users to refresh:

   ```text
   /plugin marketplace update tamirs-marketplace
   /plugin update tamirs-superpowers@tamirs-marketplace
   /reload-plugins
   ```

## Verify the release before announcing it

A tag can be cut from the wrong ref and still look right in the GitHub UI. Diff the tag against what it claims to ship:

```bash
git fetch --tags
git diff "vX.Y.Z" origin/master -- skills/ hooks/ scripts/ agents/   # expect empty
git show "vX.Y.Z:.claude-plugin/plugin.json" | jq -r .version        # expect X.Y.Z
```

A local install that "has" the feature proves nothing — the cache may have been hand-patched (below). Only the tag is evidence. If either check surprises you, do not announce the release; cut a new patch version. Never move a published tag.

## Local development without a release

Point the cache at your working tree — **do not edit the cache in place**:

```bash
# Find the installed version directory
ls ~/.claude/plugins/cache/tamirs-marketplace/tamirs-superpowers/

# Replace it with a symlink to your clone
mv ~/.claude/plugins/cache/tamirs-marketplace/tamirs-superpowers/X.Y.Z{,.bak}
ln -s /path/to/your/clone ~/.claude/plugins/cache/tamirs-marketplace/tamirs-superpowers/X.Y.Z
```

Then `/reload-plugins`.

> **Never hand-edit files under `~/.claude/plugins/cache/`.** Two mechanisms destroy those edits without warning:
>
> - **`autoUpdate`** replaces the version directory wholesale, mid-session. A patch applied at the start of a session can be gone by the end of it.
> - **Version-glob resolution.** The statusline command and several skills resolve their own path with `ls .../tamirs-superpowers/*/... | sort -rV | head -1` — *newest version wins*. When an auto-update installs `1.10.0` alongside your patched `1.9.0`, the glob moves to the unpatched copy and the change appears "not to have worked". The symptom looks like a bug in the feature; the cause is resolution order.
>
> A symlink survives both, because the directory it points at is yours. If you must patch a real cache directory to reproduce something, back it up first and treat the result as disposable — never as evidence that a release is correct.

Do **not** assume `/plugin update` or `/reload-plugins` will pull from your local working tree or unpushed commits.

## Prune stale cache versions

Old versions accumulate, and every one is a candidate for a version glob to land on. After confirming an update installed:

```bash
ls ~/.claude/plugins/cache/tamirs-marketplace/tamirs-superpowers/   # keep only the current version
```

## CI enforcement

`make validate` and the CI job `Manifest/tag version alignment` fail when:

- the three manifests disagree, or
- a documented skill count or supported target does not match the tree (`check-doc-claims`), or
- `extraKnownMarketplaces` appears as an array anywhere (`check-marketplace-schema`), or
- manifest `version` moves **backwards** relative to the latest `vX.Y.Z` tag

The tag is created **post-merge**, so a proposed bump has no tag yet. CI accounts for this: pull requests run `--manifests-only` (tag comparison skipped entirely), and pushes to `master` run `--allow-pending-release`, which downgrades "manifest ahead of latest tag" to a warning. Neither fails the bump PR — if the alignment job does fail, the cause is real drift, not the pending release.
