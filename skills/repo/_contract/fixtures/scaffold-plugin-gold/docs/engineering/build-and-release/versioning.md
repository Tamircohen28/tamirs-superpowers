# Versioning and release

Agent-kit repos bump **all** plugin manifest versions together. Policy:
`skills/repo/_contract/references/versioning-policy.md`.

## Release checklist

1. `docs/CHANGELOG.md` + root `CHANGELOG.md`
2. Bump `package.json` and every `plugins/*/plugin.json` / dist manifests
3. `npm run build && npm run validate`
4. Tag `vX.Y.Z` and push
