# Platform Sync — URL References

This umbrella skill delegates all URL fetching to its three internal sub-skills.
Each sub-skill has its own `references/urls.md` for permitted source URLs.

| Sub-skill | Platform | URL reference file |
|---|---|---|
| platform-sync-claude | Claude Code | `skills/documentation/platform-sync-claude/references/urls.md` |
| platform-sync-codex | OpenAI Codex CLI | `skills/documentation/platform-sync-codex/references/urls.md` |
| platform-sync-cursor | Cursor | `skills/documentation/platform-sync-cursor/references/urls.md` |

The umbrella skill itself does not fetch URLs directly — it reads local manifests
(`.claude-plugin/`, `.codex-plugin/`, `.cursor-plugin/`) and invokes sub-skills via
the Skill tool, which handle all fetching internally.
