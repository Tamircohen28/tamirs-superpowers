# Marketplace scaffold requirements (marketplace-gold)

Extends [scaffold-requirements.md](scaffold-requirements.md) for `--type marketplace`:
a repository whose purpose is to be a **catalog of plugins** (own or third-party) that each
platform's plugin system can add and install from. It is not a plugin itself (that is
`--type plugin` / `plugin-gold`) and ships no `canonical/` build layout.

Everything here is doc-cited from the platform pages read on 2026-11-05 —
[docs/engineering/research/marketplace-standards.md](../../../../docs/engineering/research/marketplace-standards.md).
A platform with no marketplace concept gets **no manifest**; the scaffold says so instead.

## Manifests — one per platform that has a marketplace

| Platform | Path | Template | Required fields (doc-cited) |
|---|---|---|---|
| Claude Code / Claude Desktop | `.claude-plugin/marketplace.json` | `marketplace/claude/marketplace.json.tmpl` | `name`, `owner.name`, `plugins[].{name,source}` |
| Cursor | `.cursor-plugin/marketplace.json` | `marketplace/cursor/marketplace.json.tmpl` | `name` (kebab-case), `owner.name`, `plugins[].name`; `source` is a path |
| Codex | `.agents/plugins/marketplace.json` | `marketplace/codex/marketplace.json.tmpl` | `name`, `plugins[].{name,source,policy.installation,policy.authentication,category}` |
| OpenCode | **none** | — | OpenCode defines no marketplace; plugins are npm packages named in `opencode.json`. The README's catalog column says `no`. |

Claude Desktop installs from the Claude Code listing — no separate manifest. Codex also
reads `.claude-plugin/marketplace.json` as a "legacy-compatible marketplace"; the native
file is still written because the page says new catalogs should use it.

Substitutions: `MARKETPLACE_NAME` = `REPO_NAME` (both Claude and Codex ask for a
distinctive top-level name; the repo name is it), `MARKETPLACE_DISPLAY_NAME` = the repo
name in Title Case, `PLUGIN_NAME` = `<REPO_NAME>-starter` (the seeded local plugin).

## Required tree

```
.claude-plugin/marketplace.json
.cursor-plugin/marketplace.json
.agents/plugins/marketplace.json
plugins/<REPO_NAME>-starter/.claude-plugin/plugin.json   # name == catalog entry name
plugins/<REPO_NAME>-starter/.cursor-plugin/plugin.json
plugins/<REPO_NAME>-starter/.codex-plugin/plugin.json
plugins/<REPO_NAME>-starter/skills/example-skill/SKILL.md
scripts/validate-marketplace.sh      # from marketplace/scripts/validate-marketplace.sh.tmpl, byte-identical
docs/user/catalog.md                 # how to add local / github / npm plugins per platform
Makefile                             # install = claude plugin marketplace add .; validate = the script
core/capabilities/schema.json        # capability registry (multi-platform repo)
core/capabilities/platforms.json
```

No `canonical/`, no `dist/`, no `package.json`: a marketplace has nothing to build. `TECH`
defaults to `node` only so the standard Node `.gitignore`/`.nvmrc` apply; nothing runs npm.

## README (in addition to app-gold)

- A **Catalog** table: Plugin | Description | Source | Claude Code | Cursor | Codex | OpenCode.
  The OpenCode column is `no` unless the plugin is also an npm OpenCode plugin module.
- Per-platform **Quick Start** subsections with the documented add commands only:
  Claude `/plugin marketplace add <owner>/<repo>` + `/plugin install <plugin>@<marketplace>`;
  Codex `codex plugin marketplace add <owner>/<repo>`; Cursor reads the manifest from the
  repo (submission at cursor.com/marketplace/publish; CLI `agent plugin marketplace add <git-url>`);
  OpenCode: "No marketplace."
- Version badge links to `.claude-plugin/marketplace.json` (`metadata.version`).
- AI-target badges derived from `platform-targets.json` as for every multi-platform repo.

## Validation

`scripts/validate-marketplace.sh .` checks every manifest (syntax, required fields, name
rules, source shapes, `..` escapes, local directories exist, entry name == plugin manifest
name, duplicates) and cross-checks the three catalogs; it runs `claude plugin validate .`
when the CLI is on PATH and says when it skipped it. Cursor and Codex document no
validator, so the jq checks are the whole gate there.

## CI

Jobs: `CI` (manifests parse, every local plugin has a manifest), `validate` (the script),
`secret-scan`, `action-pinning`. Template: `marketplace/ci-marketplace.yml.tmpl`.
No `manifest-version-alignment` job: there is no root `plugin.json` to align.

## CODEOWNERS

Must include paths: `plugins/`, `scripts/`, `.claude-plugin/`, `.cursor-plugin/`, `.agents/`.

## Contract profile

Exit gate: `assert-contract.sh <root> marketplace-gold` (P1=P2=P3=0 offline; every
GitHub-API check — S4-02, S4-04…S4-14 — is skipped by id). Detected by
`detect-contract-profile.sh` when `.claude-plugin/marketplace.json` exists without a root
`.claude-plugin/plugin.json` and without `canonical/rules/`.

Apply `enable-repo-merge-settings.sh`, then `scripts/github-policy.sh apply --repo <owner/name>`,
in polish phase 4 (same as app-gold).

## Templates

See [`marketplace/`](marketplace/) for the manifests, the starter plugin, the validate
script, CI, Makefile, README and catalog doc.
