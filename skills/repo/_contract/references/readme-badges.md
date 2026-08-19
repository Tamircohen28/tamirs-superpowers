# README badge layout

Required badge rows for Tamir Cohen repos. Apply in **review** and **polish** modes.

Hero banner art direction and its quality bar: [`readme-banner.md`](readme-banner.md).

## Badge markup — one anchor, one line. Always.

```html
<!-- correct -->
<a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License" /></a>

<!-- WRONG — renders a blue underlined gap between badges -->
<a href="LICENSE">
  <img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License" />
</a>
```

**Why, so nobody reformats it back for readability:** the newline and the indentation in the
second form are *inside* the anchor element, so they are link **text**. GitHub renders that
text, underlined, between every pair of badges — the "blue underline between the banners"
defect. The single-line form contains no text node and cannot produce one. Prettier-style
"one attribute per line" reformatting of a badge row reintroduces the bug.

The badge row itself still wraps across lines — one `<a>…</a>` per line inside
`<p align="center">`. It is only the *inside* of an anchor that must not break.

Checked by `skills/repo/_contract/scripts/check-readme-branding.sh` → gap **S1-11**.

## No emoji in the README header

No emoji above the first `## ` heading. That region is the banner, the badge rows, the H1 and
the tagline — the part that gets screenshotted, embedded in listings, and read by people
deciding whether the project is serious. Body prose below the first `## ` heading is
unrestricted; use emoji there if it helps.

This covers the H1 (`# St. Claude 🏠` is the defect), any tagline under it, and any emoji
glyph inside a banner or badge. Checked → gap **S1-12**.

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

**Every version below is a placeholder.** Read the value from
`docs/engineering/build-and-release/platform-targets.json` → `targets.<key>.validated_against`
and substitute it. Do **not** copy a literal number out of this file: the four repos that did
so are advertising harness versions nobody ever validated, which is what
`<VALIDATED_VERSION>` exists to make impossible.

```markdown
[![Claude Code](https://img.shields.io/badge/Claude%20Code-<VALIDATED_VERSION>-blueviolet)](docs/engineering/build-and-release/platform-targets.json)
[![Cursor](https://img.shields.io/badge/Cursor-<VALIDATED_VERSION>-000000)](docs/engineering/build-and-release/platform-targets.json)
[![Codex](https://img.shields.io/badge/Codex-<VALIDATED_VERSION>-412991)](docs/engineering/build-and-release/platform-targets.json)
[![Gemini CLI](https://img.shields.io/badge/Gemini%20CLI-<VALIDATED_VERSION>-4285F4)](docs/engineering/build-and-release/platform-targets.json)
[![OpenCode](https://img.shields.io/badge/OpenCode-<VALIDATED_VERSION>-fab283)](docs/engineering/build-and-release/platform-targets.json)
```

Derive them in one command:

```bash
jq -r '.supported_targets[] as $k | "\($k): \(.targets[$k].validated_against)"' \
  docs/engineering/build-and-release/platform-targets.json
```

Or a single line under the badges, same substitution rule:

`AI targets: Claude Code <VALIDATED_VERSION> · Cursor <VALIDATED_VERSION> · …`

**Two checks enforce this.** `scripts/check-platform-targets.sh` hard-fails a repo that ships
it (`make check-platform-targets`); `check-readme-branding.sh` compares the same badges for
any repo, ships as gap **S1-13**, and skips cleanly when the repo has no
`platform-targets.json`.

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
