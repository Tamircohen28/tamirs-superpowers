---
name: reference-release-tag-alignment
description: Master CI "Manifest/tag version alignment" goes red until a release tag matches the manifest — cut it with release.yml
metadata:
  type: reference
---

The push-to-master CI job **Manifest/tag version alignment** (`skills/repo/_contract/scripts/check-manifest-version-alignment.sh`) enforces `latest v* release tag == plugin.json version`. On PRs it runs with `--manifests-only` (only checks the three manifests agree), so a version-bumping PR is green — but the moment it merges, **master CI goes red** until a matching release tag exists.

**Why:** the repo bumps manifests inside feature PRs (per the "version bump required for marketplace delivery" constraint), but the tag/release is created separately by `release.yml`. If that step is skipped, `manifest (e.g. 1.8.1) != latest tag (e.g. v1.6.1)` and master stays red. This recurred across 1.7.0 → 1.8.0 → 1.8.1.

**How to apply:** after merging any manifest-bumping PR, run the release workflow:

```bash
gh workflow run release.yml -f version=<new-manifest-version>
```

It is idempotent on the bump (skips the commit when manifests already match), then creates + pushes `v<version>` and a GitHub Release marked `--latest`. To confirm the fix on an already-red master run, `gh run rerun <run-id> --failed` — the re-checkout (fetch-depth 0) picks up the new tag.

Corollary: a **docs/memory-only PR must NOT bump the manifest** — bumping without a release would re-red master. See [[feedback-json-manifest-edits]] for the safe way to edit a manifest version, and [[project-admin-merge-personal-repo]] for the merge path.
