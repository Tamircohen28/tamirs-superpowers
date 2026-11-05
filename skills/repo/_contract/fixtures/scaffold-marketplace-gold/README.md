<p align="center">
  <img src="assets/banner.svg" alt="scaffold-marketplace-gold" width="600" />
</p>

<p align="center">
  <a href="https://github.com/Tamircohen28"><img src="https://img.shields.io/badge/author-Tamir%20Cohen-181717?logo=github" alt="Author" /></a>
  <a href="https://github.com/TamirCohen28/scaffold-marketplace-gold/actions/workflows/ci.yml"><img src="https://img.shields.io/badge/CI-passing-brightgreen" alt="CI" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License" /></a>
  <a href=".claude-plugin/marketplace.json"><img src="https://img.shields.io/badge/version-0.1.0-blue" alt="Version" /></a>
</p>

<p align="center">
  <a href="docs/engineering/build-and-release/platform-targets.json"><img src="https://img.shields.io/badge/Claude%20Code-2.0.0-blueviolet" alt="Claude Code" /></a>
  <a href="docs/engineering/build-and-release/platform-targets.json"><img src="https://img.shields.io/badge/Cursor-0.45.0-000000" alt="Cursor" /></a>
  <a href="docs/engineering/build-and-release/platform-targets.json"><img src="https://img.shields.io/badge/Codex-0.40.0-412991" alt="Codex" /></a>
  <a href="docs/engineering/build-and-release/platform-targets.json"><img src="https://img.shields.io/badge/Gemini%20CLI-0.30.0-4285F4" alt="Gemini CLI" /></a>
  <a href="docs/engineering/build-and-release/platform-targets.json"><img src="https://img.shields.io/badge/OpenCode-2.2.5-fab283" alt="OpenCode" /></a>
</p>

# scaffold-marketplace-gold

Contract gold fixture for marketplace-gold profile validation.

A **plugin marketplace**: one catalog of plugins, published in the manifest each platform
reads. Users add the marketplace once and install plugins from it by name.

## Catalog

| Plugin | Description | Source | Claude Code | Cursor | Codex | OpenCode |
|---|---|---|---|---|---|---|
| `scaffold-marketplace-gold-starter` | Starter plugin shipped with this marketplace | `./plugins/scaffold-marketplace-gold-starter` | yes | yes | yes | no |

OpenCode has no marketplace concept: a plugin reaches OpenCode only when it is also
published to npm as an OpenCode plugin module and named in a user's `opencode.json`
`plugin` array. The column is honest, not a gap to fix here.

## Prerequisites

- `jq` (manifest checks)
- Claude Code 2.x for `claude plugin validate` (optional; the jq checks run without it)

## Quick Start

### Claude Code

```text
/plugin marketplace add TamirCohen28/scaffold-marketplace-gold
/plugin install scaffold-marketplace-gold-starter@scaffold-marketplace-gold
```

Claude Desktop installs from the same listing.

### Cursor

Cursor reads `.cursor-plugin/marketplace.json` from this repository. Submit the repo at
<https://cursor.com/marketplace/publish>, or install a plugin from a git URL with the
Cursor CLI: `agent plugin marketplace add https://github.com/TamirCohen28/scaffold-marketplace-gold`.

### Codex

```text
codex plugin marketplace add TamirCohen28/scaffold-marketplace-gold
```

Codex reads `.agents/plugins/marketplace.json` (and `.claude-plugin/marketplace.json` as a
legacy-compatible catalog). Install from the ChatGPT desktop app, or
`codex plugin add scaffold-marketplace-gold-starter@scaffold-marketplace-gold` on the CLI.

### OpenCode

No marketplace. See the Catalog column above.

## Maintaining the catalog

```bash
make validate     # every manifest, cross-checked; claude plugin validate when available
```

How to add a plugin (local directory, GitHub repo, npm package) and what each platform
needs from its entry: [docs/user/catalog.md](docs/user/catalog.md).

## Documentation

See [docs/README.md](docs/README.md).

## Contributing

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md).

---

MIT © [Tamir Cohen](https://github.com/Tamircohen28)
