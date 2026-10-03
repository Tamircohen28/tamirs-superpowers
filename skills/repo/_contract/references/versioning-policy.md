# Versioning and release tagging

Canonical policy for Tamir Cohen repos. Document this file at
`docs/engineering/build-and-release/versioning.md` (copy or adapt — do not symlink).

## Required artifacts

| Artifact | Location | Purpose |
|----------|----------|---------|
| Changelog | `docs/CHANGELOG.md` + root `CHANGELOG.md` (mirror or Keep-a-Changelog copy) | User-facing release notes |
| Version source | `package.json`, plugin manifest(s), or `VERSION` file | Single declared version |
| Policy doc | `docs/engineering/build-and-release/versioning.md` | When to bump, how to tag |
| `AGENTS.md` | Repo root | Agent contributors read release rules here |

## Semver rules

Follow [Semantic Versioning 2.0.0](https://semver.org/):

| Bump | When | Examples |
|------|------|----------|
| **PATCH** (`x.y.Z`) | Bug fixes, doc-only, hook/script fixes with no behavior change for consumers | `fix(hooks): handle missing cwd` |
| **MINOR** (`x.Y.0`) | New backward-compatible features — new skills, new optional hooks, new docs sections | `feat(skills): add platform-sync` |
| **MAJOR** (`X.0.0`) | Breaking changes — removed skills, renamed slash commands, hook behavior that breaks existing workflows, manifest schema migrations | Remove a public skill; change hook matcher defaults |

**Pre-1.0:** `0.y.z` — minor bumps may include breaking changes; document in changelog.

## Multi-manifest sync (plugin repos)

When a repo ships `.claude-plugin/`, `.cursor-plugin/`, and/or `.codex-plugin/`:

- All manifest `version` fields **must match** in the same release commit.
- Bump every manifest in one commit before tagging.
- CI / `make validate` should fail on version drift (when enforced).

## Tagging

1. Finish changelog: move `[Unreleased]` entries under `[X.Y.Z] - YYYY-MM-DD`.
2. Commit: `chore(release): vX.Y.Z`
3. Tag: `git tag -a vX.Y.Z -m "vX.Y.Z"`
4. Push branch and tag: `git push && git push origin vX.Y.Z`
5. GitHub Release (optional): attach notes from changelog section.

**Validate tags:**

```bash
# Latest tag matches plugin manifest (example)
VER=$(jq -r .version .claude-plugin/plugin.json)
git tag -l "v${VER}" | grep -q . || echo "missing tag v${VER}"
```

## Enforcement checklist (repo-standards)

IDs below match `standards-rubric.md` and `score-standards-gaps.sh` exactly —
keep all three in sync when adding/renumbering a check.

| ID | Check | Severity |
|----|-------|----------|
| S10-01 | `docs/CHANGELOG.md` exists with `[Unreleased]` section | P2 |
| S10-02 | `docs/engineering/build-and-release/versioning.md` documents bump rules | P2 |
| S10-03 | `AGENTS.md` references versioning policy | P3 |
| S10-04 | Multi-manifest repos: all `plugin.json` versions equal | P1 |
| S10-05 | Declared `plugin.json` version has a matching release tag (no unreleased manifest bumps on `main`) — scripted in `standards-inventory.sh` (`versioning.manifest_version_tag_match`) + `score-standards-gaps.sh` | P1 |

S10-05 is skipped (never flagged) for a repo with zero release tags yet — there's
nothing to have drifted from before the first release.

## CI enforcement (required, not just repo-standards audit)

Manifest/tag drift must be a **hard CI gate**, not just an advisory finding in a
periodic `/repo-standards` review — the drift that motivated S10-05 sat silently
on `main` for weeks (manifest bumped ahead of the last cut release) before anyone
re-ran the audit.

Every plugin repo (any repo with `.claude-plugin/`, `.cursor-plugin/`, and/or
`.codex-plugin/plugin.json`) should vendor
`skills/repo/_contract/scripts/check-manifest-version-alignment.sh` and wire it
into CI as a required job on every `pull_request` and `push` to the default
branch (see `multi-agent-repo`'s drift-check pattern for how other repos vendor
shared scripts from this repo). The script fails when:

- present manifests disagree with each other, or
- the manifest version has no matching `vX.Y.Z` git tag, given the repo already
  has at least one release tag.

## Dependabot

Block automatic **major** version PRs (`ignore: version-update:semver-major`). Review major bumps manually against this policy.
