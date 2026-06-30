# Plugin / agent-kit review — manual axes

Use when `$CONTRACT_PROFILE` is `plugin-gold` or `inventory-agent-setup.sh` reports `repo_type: agent-kit`.

## Repo classification

| Type | Signals |
|------|---------|
| **app** | No `.claude-plugin/plugin.json`, no `canonical/rules/` |
| **claude-plugin** | Root `.claude-plugin/plugin.json` + `skills/` (flat plugin, e.g. tamirs-superpowers) |
| **agent-kit** | `canonical/rules/` + `plugins/<name>/` + `.claude-plugin/marketplace.json` |
| **hybrid** | App artifacts + plugin manifest |

## Auto-scored (PK* gaps)

Deterministic checks via `score-plugin-gaps.sh`: canonical layout, marketplace manifest, plugin wrapper, `package-lock.json` (for `npm ci`), dist/ GENERATED markers, validate CI job, CODEOWNERS paths.

## Manual review axes (v1)

Walk these in review mode; record pass/gap in the plugin appendix.

| ID | Check | Severity |
|----|-------|----------|
| PR1-01 | `canonical/rules/*.md` are tool-neutral (no `$CLAUDE_*`, no `!` blocks, no YAML frontmatter) | P1 |
| PR1-02 | Skills authored in `canonical/skills/` — not duplicated ad hoc in `plugins/*/skills/` | P1 |
| PR1-03 | `dist/` and generated adapter files have GENERATED header; contributors warned not to hand-edit | P1 |
| PR2-01 | Plugin version strategy documented — `docs/engineering/build-and-release/versioning.md` | P2 |
| PR2-02 | `hooks/` and install scripts have CODEOWNERS + no hidden postinstall/network fetch | P2 |
| PR2-03 | README documents **all** supported targets + `make install` / `make update` / `make uninstall` | P2 |
| PR2-04 | README badge rows: author, CI, license, version, AI targets (see `readme-badges.md`) | P2 |
| PR2-05 | Security model section covers supply-chain (skills/hooks as executable surface) | P2 |
| PR3-01 | `agent:update` / sync-to-repo documented or stubbed with clear follow-up | P3 |

## Polish notes

- Phase 5: invoke `multi-agent-repo` with plugin constraints (see `delegation.md`).
- Phase 6: always run `changelog-review` on agent-kit and Claude plugin repos.
- Phase 7: exit gate uses `plugin-gold`, not `app-gold`.
- After canonical edits, run `npm run build` before assert-contract.

## Flat plugin repos (no canonical/)

Repos like tamirs-superpowers stay on `app-gold` until migrated. Review using `multi-agent-repo` target-layouts **claude-plugin** section + `changelog-review` only.
