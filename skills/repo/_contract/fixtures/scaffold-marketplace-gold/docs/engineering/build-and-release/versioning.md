# Versioning and release

A marketplace repo carries two kinds of version:

- **Each plugin's own** `plugin.json` `version` — bumped by the plugin, and what wins at
  install time (the catalog entry's `version` is display only).
- **The catalog's** `metadata.version` in `.claude-plugin/marketplace.json` and
  `.cursor-plugin/marketplace.json` — bumped when the catalog changes shape (a plugin
  added, removed or renamed).

## Release checklist

1. `docs/CHANGELOG.md` + root `CHANGELOG.md`
2. Bump `metadata.version` in both catalogs that carry one
3. `make validate`
4. Tag `vX.Y.Z` and push
