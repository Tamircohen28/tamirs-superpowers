# Versioning and release

Tamir Cohen repos follow [Semantic Versioning](https://semver.org/). Full policy:
[`skills/repo/_contract/references/versioning-policy.md`](../../skills/repo/_contract/references/versioning-policy.md).

## This plugin (`tamirs-superpowers`)

| Artifact | Version source |
|----------|----------------|
| Claude Code | `.claude-plugin/plugin.json` |
| Cursor | `.cursor-plugin/plugin.json` |
| Codex | `.codex-plugin/plugin.json` |

All three manifests **must match** before tagging a release.

## Bump rules (summary)

| Bump | When |
|------|------|
| **PATCH** | Hook/skill bug fixes, docs-only, non-breaking config tweaks |
| **MINOR** | New skills, new optional hooks, backward-compatible features |
| **MAJOR** | Removed skills, breaking hook behavior, renamed slash commands |

## Release checklist

1. Move `[Unreleased]` entries in `CHANGELOG.md` and `docs/CHANGELOG.md` under `[X.Y.Z] - date`
2. Bump all plugin manifest `version` fields to `X.Y.Z` (+ `README.md` badges)
3. Run `make validate` (manifest/tag alignment fails until the tag exists — use `make validate` with manifests at current tag, or run `check-manifest-version-alignment.sh . --manifests-only` mid-release)
4. Commit and merge the release PR
5. Run the [Release workflow](.github/workflows/release.yml) with `X.Y.Z` to create `vX.Y.Z` if not already tagged
6. Publish through `Tamircohen28/tamirs-marketplace` marketplace catalog (separate repo — no version field there; users pull via `plugin.json` version)

## Claude Code update behavior

This plugin sets an explicit `version` in `.claude-plugin/plugin.json`. Claude Code uses that string as the **cache key** for `/plugin update` ([official docs](https://code.claude.com/docs/en/plugins-reference#version-management)):

| Situation | What users see |
|-----------|----------------|
| New commits, **same** `version` | `/plugin update` → "already at the latest version"; cached copy unchanged |
| `version` bumped + tag pushed | Update downloads new cache directory; users should `/reload-plugins` |
| Local dev, no release yet | Edit `~/.claude/plugins/cache/tamirs-marketplace/tamirs-superpowers/<version>/` or symlink dev clone |

Agent contributors: see [`rules/dev/plugin-version-bump.md`](../../../rules/dev/plugin-version-bump.md).

## Validate tag matches manifest

```bash
VER=$(jq -r .version .claude-plugin/plugin.json)
git tag -l "v${VER}" | grep -q . || echo "missing tag v${VER}"
```

## Dependabot

Major-version PRs are blocked in `.github/dependabot.yml`. Review minors manually after reading upstream changelogs.
