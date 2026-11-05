# Maintaining the catalog

This repository is a plugin marketplace. One catalog, three manifests, because each
platform that has a marketplace reads its own file. Keep the three in step; `make validate`
fails when a plugin is listed for Cursor or Codex but missing from the Claude catalog.

| Platform | Manifest | Who reads it |
|---|---|---|
| Claude Code / Claude Desktop | `.claude-plugin/marketplace.json` | `/plugin marketplace add TamirCohen28/scaffold-marketplace-gold` |
| Cursor | `.cursor-plugin/marketplace.json` | Cursor's marketplace import and the submission review |
| Codex | `.agents/plugins/marketplace.json` | `codex plugin marketplace add TamirCohen28/scaffold-marketplace-gold` (also reads the Claude file as legacy-compatible) |
| OpenCode | none | OpenCode has no marketplace; plugins are npm packages named in `opencode.json` |

## Add a plugin that lives in this repository

1. Create `plugins/<name>/` with `.claude-plugin/plugin.json` (`name` must equal the catalog
   entry name), and `.cursor-plugin/plugin.json` / `.codex-plugin/plugin.json` when the plugin
   targets those platforms.
2. Add an entry to each manifest:

   ```jsonc
   // .claude-plugin/marketplace.json  — source is a "./" relative path
   { "name": "<name>", "source": "./plugins/<name>", "description": "…", "version": "0.1.0" }
   // .cursor-plugin/marketplace.json  — source is a path (no "./" needed)
   { "name": "<name>", "source": "plugins/<name>", "description": "…", "version": "0.1.0" }
   // .agents/plugins/marketplace.json — local source object + policy + category
   { "name": "<name>", "source": { "source": "local", "path": "./plugins/<name>" },
     "policy": { "installation": "AVAILABLE", "authentication": "ON_INSTALL" }, "category": "Developer Tools" }
   ```

3. Add a row to the README catalog table.
4. `make validate`.

## Add a plugin hosted elsewhere

Only Claude Code and Codex document remote sources. Cursor documents path sources only, so a
remote plugin is listed for Claude and Codex and left out of the Cursor manifest (that is a
warning, not an error).

| Where it lives | Claude entry `source` | Codex entry `source` |
|---|---|---|
| A GitHub repo | `{ "source": "github", "repo": "owner/repo", "ref": "main" }` | `{ "source": "git-subdir", "url": "https://github.com/owner/repo.git", "path": ".", "ref": "main" }` |
| A directory in a git repo | `{ "source": "git-subdir", "url": "owner/repo", "path": "plugins/x", "ref": "main" }` | same shape with a full URL |
| An npm package | `{ "source": "npm", "package": "@scope/pkg", "version": "1.2.3" }` | `{ "source": "npm", "package": "@scope/pkg", "version": "1.2.3" }` |

Pin with `sha` (a full 40-character SHA) when reproducibility matters more than tracking a
branch; when both `ref` and `sha` are set, `sha` wins.

## Versioning

- A plugin's version lives in its own `plugin.json`; the catalog entry's `version` is for
  display, and at install time `plugin.json` wins (Claude Code warns on a mismatch).
- Bump `metadata.version` in the Claude and Cursor manifests when the catalog itself
  changes shape (a plugin added, removed or renamed), and record it in `docs/CHANGELOG.md`.
- Removing a plugin from the Claude manifest does not uninstall it for users unless
  `forceRemoveDeletedPlugins` is `true`; use `renames` to map a former name to its
  replacement (or `null` for a retired plugin).

## Validate

```bash
make validate                 # jq checks on all three manifests, cross-checked
claude plugin validate .      # the platform validator, when Claude Code is installed
```

Cursor and Codex document no validator; the jq checks in `scripts/validate-marketplace.sh`
cover their documented rules (kebab-case names, path sources resolving, the 10 MB cap,
`policy.installation` values, `category` present).

## Sources

Read 2026-11-05; recorded in the scaffolding plugin's
`docs/engineering/research/marketplace-standards.md`:

- <https://code.claude.com/docs/en/plugins/marketplace-reference>
- <https://cursor.com/docs/reference/plugins#marketplace-manifest-format>
- <https://developers.openai.com/plugins/build/plugins>
- <https://opencode.ai/docs/plugins/>
