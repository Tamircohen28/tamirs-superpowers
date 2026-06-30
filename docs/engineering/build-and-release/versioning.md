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
2. Bump all plugin manifest `version` fields to `X.Y.Z`
3. Run `make validate`
4. Commit `chore(release): vX.Y.Z`
5. `git tag -a vX.Y.Z -m "vX.Y.Z"` and `git push origin vX.Y.Z`
6. Publish through `Tamircohen28/plugins` marketplace catalog (separate repo)

## Validate tag matches manifest

```bash
VER=$(jq -r .version .claude-plugin/plugin.json)
git tag -l "v${VER}" | grep -q . || echo "missing tag v${VER}"
```

## Dependabot

Major-version PRs are blocked in `.github/dependabot.yml`. Review minors manually after reading upstream changelogs.
