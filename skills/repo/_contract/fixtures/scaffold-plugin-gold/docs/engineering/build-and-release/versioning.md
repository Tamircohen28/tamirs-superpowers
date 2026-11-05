# Versioning and release

Agent-kit repos bump **all** plugin manifest versions together. Policy:
`skills/repo/_contract/references/versioning-policy.md`.

## Release checklist

1. `docs/CHANGELOG.md` + root `CHANGELOG.md`
2. Bump `package.json` and every `plugins/*/plugin.json` / dist manifests
3. `npm run build && npm run validate`
4. Tag `vX.Y.Z` and push

---

<p align="center"><a href="https://github.com/Tamircohen28">Have a Question?</a>&nbsp;·&nbsp;<a href="https://github.com/Tamircohen28/scaffold-plugin-gold/issues/new/choose">Open an Issue</a></p>
