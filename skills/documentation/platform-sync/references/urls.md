# Source URLs — `platform-sync`

**Source URLs are per-target data, not engine configuration.** Each target's permitted
sources — P0, P1 and P2, with their fetch conditions — live in that target's reference
file:

| Target | Reference file |
|---|---|
| Claude Code (and Claude Desktop as a runtime surface) | `references/platforms/claude-code.md` |
| OpenAI Codex CLI | `references/platforms/codex.md` |
| Cursor | `references/platforms/cursor.md` |
| Gemini CLI | `references/platforms/gemini-cli.md` |
| OpenCode | `references/platforms/opencode.md` |

The engine fetches these itself; there are no per-platform sub-skills doing it any more.
The deprecated `platform-sync-claude`, `platform-sync-codex`, `platform-sync-cursor` and
`platform-sync-opencode` shims delegate here and are scheduled for removal.

## Priority legend

- **P0** — always fetched. A P0 failure aborts that target only, never the run.
- **P1** — fetched when the reference file's "fetch when" condition matches local config.
- **P2** — fetched only on explicit request, or when P1 sources proved insufficient.

## Adding a target

1. Add the platform to `core/capabilities/platforms.json` with a complete capability block.
2. Add `references/platforms/<id>.md` following the shape of the existing files.
3. Add the target to `docs/engineering/build-and-release/platform-targets.json`
   (`scripts/check-platform-targets.sh --require-co-change` enforces this).

**No change to `SKILL.md` is required, and no new skill is created.** That is the point of
the restructure: target count and skill count are now independent. Gemini CLI was added
this way — reference data and a registry entry, no fifth sub-skill.
