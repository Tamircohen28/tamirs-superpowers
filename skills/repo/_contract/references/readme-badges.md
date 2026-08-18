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

Show each supported target and its **platform tool version** from `docs/engineering/build-and-release/platform-targets.json` (`validated_against`):

One badge per key in `supported_targets`, in that order. Badge label and colour per target:

| Target key | Badge label | Colour |
|---|---|---|
| `claude_code` | `Claude%20Code` | `blueviolet` |
| `cursor` | `Cursor` | `000000` |
| `codex` | `Codex` | `412991` |
| `gemini_cli` | `Gemini%20CLI` | `4285F4` |
| `opencode` | `OpenCode` | `fab283` |

```markdown
[![Claude Code](https://img.shields.io/badge/Claude%20Code-2.0.0-blueviolet)](...)
[![Cursor](https://img.shields.io/badge/Cursor-0.45.0-000000)](...)
[![Codex](https://img.shields.io/badge/Codex-0.40.0-412991)](...)
[![Gemini CLI](https://img.shields.io/badge/Gemini%20CLI-0.55.1-4285F4)](...)
[![OpenCode](https://img.shields.io/badge/OpenCode-1.18.11-fab283)](...)
```

Or a single line under badges:

`AI targets: Claude Code 2.0.0 · Cursor 0.45.0 · Codex 0.40.0 · Gemini CLI 0.55.1 · OpenCode 1.18.11`

`claude_desktop` gets **no badge**: it is a runtime surface of `claude_code`, consumes the
same plugin, and is absent from `supported_targets` by design.

A target still carrying `"validated_against": "unknown"` is declared but not yet validated
— give it no badge rather than a fabricated version. `scripts/check-platform-targets.sh`
warns in that state and hard-fails the moment a real version is recorded.

**Do not** reuse plugin manifest semver on Row 3 — that belongs on Row 1 only.

When repo skills adopt new platform APIs, bump `platform-targets.json`, this row, and `platform-targets.md` in the same PR. Agents run `make platform-targets-sync` (users use `/repo-standards polish`).

## Multi-target install docs

When a repo supports **more than one** AI target:

- README **Quick Start** must have a subsection per target in `supported_targets`
  (Claude Code, Cursor, Codex CLI, Gemini CLI, OpenCode). Claude Desktop is covered by the
  Claude Code subsection — it installs the same plugin.
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
