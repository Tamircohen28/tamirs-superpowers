# Plugin marketplace repos

Guide to **marketplace repos** — a repository whose purpose is to be a **catalog of
plugins** (your own or third-party) that each platform's plugin system can add and install
from. Scaffold one with `repo-scaffold --type marketplace`.

Use this when you want one place your team adds plugins to and everyone installs from. A
repo that *is* a plugin is `--type plugin` ([agent-kit repos](agent-kit.md)) or a flat
plugin like `tamirs-superpowers`; both can self-host a one-entry listing, but a marketplace
repo lists many and ships nothing to build.

---

## Which platforms have a marketplace

Read from the platform pages on 2026-11-05 and recorded in
[`docs/engineering/research/marketplace-standards.md`](../engineering/research/marketplace-standards.md).
The scaffold writes one manifest per platform that has a marketplace and **none** for a
platform that does not.

| Platform | Marketplace | Manifest the scaffold writes | How users add it |
|---|---|---|---|
| Claude Code / Claude Desktop | yes | `.claude-plugin/marketplace.json` | `/plugin marketplace add <owner>/<repo>` then `/plugin install <plugin>@<marketplace>` |
| Cursor | yes | `.cursor-plugin/marketplace.json` | Cursor reads it from the repo; submit at cursor.com/marketplace/publish, or `agent plugin marketplace add <git-url>` (Cursor CLI) |
| Codex | yes | `.agents/plugins/marketplace.json` (also reads the Claude file as legacy-compatible) | `codex plugin marketplace add <owner>/<repo>` then `codex plugin add <plugin>@<marketplace>` |
| OpenCode | **no** | none | OpenCode plugins are npm packages named in `opencode.json`; the generated README says so |

The four repo shapes and their contract profiles:

| Shape | Example | What it ships | Standards profile |
|-------|---------|---------------|-------------------|
| App / library | Node API, Python service | code, `.agents/skills/` | `app-gold` |
| Flat Claude plugin | `tamirs-superpowers` | one plugin, self-hosted listing | `app-gold` |
| Agent-kit distribution | team engineering kit | one plugin built from `canonical/` | `plugin-gold` |
| **Marketplace** | team plugin catalog | many plugins, three catalogs | `marketplace-gold` |

---

## Create a marketplace repo

### Prerequisites

- Claude Code with `tamirs-superpowers` installed
- `gh` CLI authenticated
- `jq` (the validate script) — Claude Code itself for `claude plugin validate`

### Command

```text
/tamirs-superpowers:repo-scaffold team-plugins -- "The plugins our team ships for Claude Code, Cursor and Codex" --type marketplace
```

| Flag | Default | Meaning |
|------|---------|---------|
| `--type marketplace` | `app` | Catalog layout + `marketplace-gold` contract |
| `--tech node` | forced to `node` | Only for the standard `.gitignore` / `.nvmrc`; nothing runs npm |

### What scaffold produces

```text
team-plugins/
├── .claude-plugin/marketplace.json      # Claude Code + Claude Desktop (the canonical list)
├── .cursor-plugin/marketplace.json      # Cursor
├── .agents/plugins/marketplace.json     # Codex
├── plugins/team-plugins-starter/        # one local plugin to seed the catalog
│   ├── .claude-plugin/plugin.json       #   name == catalog entry name
│   ├── .cursor-plugin/plugin.json
│   ├── .codex-plugin/plugin.json
│   └── skills/<skill>/SKILL.md
├── scripts/validate-marketplace.sh      # every manifest, cross-checked
├── docs/user/catalog.md                 # how to add local, GitHub or npm plugins
├── Makefile                             # install = claude plugin marketplace add .
├── README.md                            # Catalog table + per-platform Quick Start
└── (app-gold baseline: docs tree, CI, AGENTS.md, CLAUDE.md, capability registry, rulesets)
```

The names: the marketplace is named after the repo (both Claude and Codex ask for a
distinctive top-level name), and the seeded plugin is `<repo>-starter`. The scaffold's
final skill-creator pass replaces the starter's placeholder skill with a real one.

---

## Maintain the catalog

One catalog, three spellings. `make validate` runs `scripts/validate-marketplace.sh`,
which checks each manifest against its platform's documented rules and then cross-checks
them: a plugin listed for Cursor or Codex but missing from the Claude catalog is an error;
a Claude-only plugin (hooks, MCP) is a warning. When Claude Code is installed it also runs
`claude plugin validate .`, and it says when it skipped that.

| Where the plugin lives | Claude entry | Cursor entry | Codex entry |
|---|---|---|---|
| `plugins/<name>/` in this repo | `"source": "./plugins/<name>"` | `"source": "plugins/<name>"` | `{ "source": "local", "path": "./plugins/<name>" }` |
| A GitHub repo | `{ "source": "github", "repo": "owner/repo" }` | not documented — omit | `{ "source": "git-subdir", "url": "…", "path": ".", "ref": "main" }` |
| An npm package | `{ "source": "npm", "package": "@scope/pkg" }` | not documented — omit | `{ "source": "npm", "package": "@scope/pkg" }` |

Codex entries always carry `policy.installation`, `policy.authentication` and `category`.
The full per-platform field list, versioning rules and the add-a-plugin walkthrough are in
the generated repo's `docs/user/catalog.md`.

---

## Audit and polish with repo-standards

`repo-standards` auto-detects the profile:

| Detection | Profile |
|-----------|---------|
| `canonical/rules/` exists | `plugin-gold` |
| `.claude-plugin/marketplace.json` exists and no root `.claude-plugin/plugin.json` | `marketplace-gold` |
| Otherwise | `app-gold` |

**Marketplace-gold extras** (MK* gap checks): the three manifests exist and validate,
the README has a `## Catalog` table and says what happens on OpenCode, `docs/user/catalog.md`
exists, CI has a `validate` job, `make validate` exists, every local plugin has a manifest,
and CODEOWNERS covers `plugins/`, `scripts/`, `.claude-plugin/`, `.cursor-plugin/`, `.agents/`.

From `tamirs-superpowers` (offline):

```bash
CONTRACT_OFFLINE=1 bash skills/repo/_contract/scripts/assert-contract.sh \
  /path/to/team-plugins marketplace-gold
```

---

## Security model

A marketplace is a supply chain for everyone who adds it:

- CODEOWNERS on the three manifests, `plugins/` and `scripts/`.
- Pin third-party entries with `sha` (a full 40-character SHA) when reproducibility matters;
  when both `ref` and `sha` are set, `sha` wins.
- Remember `forceRemoveDeletedPlugins`: removing an entry does not uninstall it for Claude
  Code users unless that flag is `true`; use `renames` for a retired or renamed plugin.
- No install scripts run for `npm` sources on Claude Code or Codex; do not rely on them.

---

## Related docs

| Doc | Content |
|-----|---------|
| [Research: marketplace standards](../engineering/research/marketplace-standards.md) | What each platform page says, read 2026-11-05 |
| [Agent-kit repos](agent-kit.md) | The `--type plugin` shape |
| [Contract package](../../skills/repo/_contract/README.md) | `app-gold` / `plugin-gold` / `marketplace-gold` |
| Contract templates | `skills/repo/_contract/templates/marketplace/` |

---

<p align="center"><a href="https://github.com/Tamircohen28">Have a Question?</a>&nbsp;·&nbsp;<a href="https://github.com/Tamircohen28/tamirs-superpowers/issues/new/choose">Open an Issue</a></p>
