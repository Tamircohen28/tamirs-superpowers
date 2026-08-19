<p align="center">
  <img src="assets/banner.svg" alt="scaffold-plugin-gold" width="600" />
</p>

<p align="center">
  <a href="https://github.com/Tamircohen28"><img src="https://img.shields.io/badge/author-Tamir%20Cohen-181717?logo=github" alt="Author" /></a>
  <a href="https://github.com/TamirCohen28/scaffold-plugin-gold/actions/workflows/ci.yml"><img src="https://img.shields.io/badge/CI-passing-brightgreen" alt="CI" /></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License" /></a>
  <a href="package.json"><img src="https://img.shields.io/badge/version-0.1.0-blue" alt="Version" /></a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/npm-0.1.0-red" alt="npm" />
  <img src="https://img.shields.io/badge/Node.js-22-green" alt="Node 22" />
</p>

<p align="center">
  <a href="docs/engineering/build-and-release/platform-targets.json"><img src="https://img.shields.io/badge/Claude%20Code-2.0.0-blueviolet" alt="Claude Code" /></a>
  <a href="docs/engineering/build-and-release/platform-targets.json"><img src="https://img.shields.io/badge/Cursor-0.45.0-000000" alt="Cursor" /></a>
  <a href="docs/engineering/build-and-release/platform-targets.json"><img src="https://img.shields.io/badge/Codex-0.40.0-412991" alt="Codex" /></a>
  <a href="docs/engineering/build-and-release/platform-targets.json"><img src="https://img.shields.io/badge/Gemini%20CLI-0.30.0-4285F4" alt="Gemini CLI" /></a>
  <a href="docs/engineering/build-and-release/platform-targets.json"><img src="https://img.shields.io/badge/OpenCode-1.18.11-fab283" alt="OpenCode" /></a>
</p>

# scaffold-plugin-gold

Contract gold fixture — agent-kit plugin repo matching plugin-gold profile.

## Prerequisites

- Node.js 22 (see `.nvmrc`)
- npm 10+

## Quick Start

```bash
make install
make validate
```

### Claude Code

```
/plugin marketplace add TamirCohen28/scaffold-plugin-gold
/plugin install scaffold-plugin-gold@scaffold-plugin-tools
```

### Cursor / Codex

After `make install`, adapters are under `dist/cursor/` and `dist/codex/`.

## Documentation

See [docs/README.md](docs/README.md).

## Contributing

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md).

## License

MIT © [Tamir Cohen](https://github.com/Tamircohen28) — see [LICENSE](LICENSE).
