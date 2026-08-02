---
name: reference-release-tag-alignment
description: After merging a manifest bump, cut the release with release.yml — master CI now warns ("Release pending") instead of going red
metadata:
  type: reference
---

The push-to-master CI job **Manifest/tag version alignment** (`skills/repo/_contract/scripts/check-manifest-version-alignment.sh`) compares `latest v* release tag` to `plugin.json version`. Behaviour depends on the event:

| Event | Flag | Manifest ahead of tag | Manifest behind tag |
|---|---|---|---|
| `pull_request` | `--manifests-only` | not checked | not checked |
| `push` (master) | `--allow-pending-release` | `::warning::` Release pending — **passes** | **fails** |
| manual / local | none (strict) | fails | fails |

**Why it warns rather than fails:** the repo bumps manifests inside feature PRs, but the tag is created afterwards by `release.yml`. At the instant a bump merges, the matching tag *provably cannot exist* — so failing there was a race, not drift. Observed live on PR #72: the alignment job ran at `12:06:00` and read `v1.8.2`; `v1.9.0` published at `12:06:14`. Fourteen seconds. Previously this reddened master on every version-bumping merge (it did so across 1.7.0 → 1.8.0 → 1.8.1).

Manifest *behind* the latest tag is still a hard error under every flag — nothing legitimate moves a manifest backwards past a cut release.

**How to apply:** after merging any manifest-bumping PR, still cut the release — the warning is the reminder, and skipping it strands installed users on the cached copy:

```bash
gh workflow run release.yml -f version=<new-manifest-version>
```

It is idempotent on the bump (skips the commit when manifests already match), then creates + pushes `v<version>` and a GitHub Release marked `--latest`.

Caveat: once `release.yml` has pushed the tag, **do not re-run the whole workflow** — its "Check tag does not already exist" step hard-fails on the existing `v<version>`. Only rerun the failed CI job (`gh run rerun <run-id> --failed`).

Because master no longer reds on a pending release, a docs-only PR that bumps the manifest is no longer *destructive* — but it is still wrong, since it burns a version with no shipped change. See [[feedback-json-manifest-edits]] for the safe way to edit a manifest version, and [[project-admin-merge-personal-repo]] for the merge path.
