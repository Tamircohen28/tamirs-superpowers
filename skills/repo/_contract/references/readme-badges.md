# README badge layout

Required badge rows for Tamir Cohen repos. Apply in **review** and **polish** modes.

## Row 1 — always (centered `<p align="center">`)

| Badge | Example | Notes |
|-------|---------|-------|
| Author | `[![Tamir Cohen](https://img.shields.io/badge/author-Tamir%20Cohen-181717?logo=github)](https://github.com/Tamircohen28)` | Link to GitHub profile |
| CI | GitHub Actions workflow badge | Match actual workflow file |
| License | `img.shields.io/badge/license-MIT-blue` | Match LICENSE file |
| Version | `img.shields.io/badge/version-X.Y.Z-blue` | From package.json or primary plugin manifest |

## Row 2 — optional (only when applicable)

| Badge | When |
|-------|------|
| npm / PyPI / crates.io | Published package — link to registry |
| Live site | Vercel/Netlify/custom deploy — link to production URL |
| Framework | e.g. `Next.js 16`, `Node 22` — from package.json engines or docs |

Omit the entire row if none apply.

## Row 3 — AI targets (when repo supports ≥1 platform)

Show each supported target and its configured version:

```markdown
[![Claude Code](https://img.shields.io/badge/Claude%20Code-1.5.1-blueviolet)](...)
[![Cursor](https://img.shields.io/badge/Cursor-1.5.1-000000)](...)
[![Codex](https://img.shields.io/badge/Codex-1.5.1-412991)](...)
```

Or a single line under badges:

`AI targets: Claude Code 1.5.1 · Cursor 1.5.1 · Codex 1.5.1`

Derive versions from `.claude-plugin/plugin.json`, `.cursor-plugin/plugin.json`,
`.codex-plugin/plugin.json`, or `AGENTS.md` install section — they must match in
multi-target plugin repos.

## Multi-target install docs

When a repo supports **more than one** AI target:

- README **Quick Start** must have a subsection per target (Claude Code, Cursor, Codex).
- Prefer **one-liner `make` commands** (`make install`, `make update`, `make uninstall`).
- Bash blocks are allowed as *alternatives* only — label them "Alternative (manual)".
- User docs (`docs/user/quick-start.md`) mirror the same per-target structure.

## Makefile lifecycle targets

Every repo with installable artifacts must expose:

| Target | Purpose |
|--------|---------|
| `make install` | First-time setup (deps, bootstrap, plugin enable) |
| `make update` | Refresh to latest (deps, plugin, generated dist) |
| `make uninstall` | Reverse install-side effects where safe |

App repos: `install` → `npm ci`; `update` → `npm update` or documented upgrade;
`uninstall` → remove `node_modules` / venv.

Plugin repos: lifecycle scripts live under `scripts/` (`install.sh`, `update.sh`,
`uninstall.sh`, `statusline.sh`); **never** loose `.sh` files at repo root. Makefile
targets call `bash scripts/<name>.sh`. Never require a multi-step bash block as the only
documented path.
