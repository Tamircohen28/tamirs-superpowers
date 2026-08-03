# Platform Sync — URL References

This umbrella skill delegates all URL fetching to its four internal sub-skills.
Each sub-skill has its own `references/urls.md` for permitted source URLs.

| Sub-skill | Platform | URL reference file |
|---|---|---|
| platform-sync-claude | Claude Code | `skills/documentation/platform-sync-claude/references/urls.md` |
| platform-sync-codex | OpenAI Codex CLI | `skills/documentation/platform-sync-codex/references/urls.md` |
| platform-sync-cursor | Cursor | `skills/documentation/platform-sync-cursor/references/urls.md` |
| platform-sync-opencode | OpenCode | `skills/documentation/platform-sync-opencode/references/urls.md` |

The umbrella skill itself does not fetch URLs directly — it reads local config
(`.claude-plugin/`, `.codex-plugin/`, `.cursor-plugin/`, `opencode.json`) and invokes
sub-skills via the Skill tool, which handle all fetching internally.

**Adding a fifth target?** A new target needs all four of: a `platform-sync-<target>`
sub-skill with its own `urls.md`, a detection section in `references/detection.md`, a row
in this table, and an entry under `supported_targets` in `platform-targets.json`. The
`--require-co-change` mode of `scripts/check-platform-targets.sh` enforces the last one;
the rest are caught by review.
