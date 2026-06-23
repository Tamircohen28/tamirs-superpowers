<div align="center">

# scaffold-plugin-gold

<p>Contract gold fixture — agent-kit plugin repo matching plugin-gold profile.</p>

[![CI](https://github.com/TamirCohen28/scaffold-plugin-gold/actions/workflows/ci.yml/badge.svg)](https://github.com/TamirCohen28/scaffold-plugin-gold/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

</div>

---

## Prerequisites

- Node.js 22 (see `.nvmrc`)
- npm 10+

## Quick Start

```bash
npm ci
npm run build
npm run validate
```

## Install as Claude Code plugin

```
/plugin marketplace add TamirCohen28/scaffold-plugin-gold
/plugin install scaffold-plugin-gold@scaffold-plugin-tools
```

## Build adapters

```bash
npm run build   # regenerate dist/ and plugin skills from canonical/
npm run validate
```

## Documentation

See [docs/README.md](docs/README.md) and [docs/engineering/agent-kit-architecture.md](docs/engineering/agent-kit-architecture.md).

## Contributing

See [docs/CONTRIBUTING.md](docs/CONTRIBUTING.md).

## License

MIT — see [LICENSE](LICENSE).
