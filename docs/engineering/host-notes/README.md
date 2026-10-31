# Host notes

Per-host release notes the maintainers reviewed against this plugin: what each host release changed, what this repo adopted because of it, and what was reviewed and found not applicable — recorded so nobody re-reviews it. One file per platform, organised by release number ascending.

| Host | File | Status |
|---|---|---|
| Claude Code (and Claude Desktop, the same distribution) | [`claude-code.md`](claude-code.md) | 2.1.234 through 2.1.312 |
| Codex CLI, Cursor, Gemini CLI, OpenCode | — | not yet split out; their per-cycle review text still lives in `platform-targets.json`'s `verification_method` fields |

**What is and is not authoritative.** These files are narrative. The **evidence-bearing record** stays [`platform-targets.json`](../build-and-release/platform-targets.json): per target, `validated_against` (last live run), `reviewed_through` / `latest_known` (changelog read), `verified_on`, and the dated `verification_method` text; the root `.claude-code-version`, `.codex-version` and `.cursor-version` pins mirror it and `scripts/check-platform-version-pins.sh` holds them to it. When a note here and that record disagree, the record wins and the note is corrected. Capability facts belong in [`core/capabilities/platforms.json`](../../../core/capabilities/platforms.json), not here.

**Why not `CLAUDE.md`.** Until plugin 5.0.0 the Claude Code notes lived inline in the root `CLAUDE.md`. A `CLAUDE.md` at a plugin root is never loaded by Claude Code (`claude plugin validate` warns about it), and the plugin directory's scanner reads prose about what the plugin *used* to do as what it does — so a 50 KB history there was read by no host and misread by the one scanner that did. `CLAUDE.md` is now a short, current contributor page and links here once.

**Adding a note.** The nightly `platform-sync` review appends under a new `### <version>` heading in the host's file, one bold-led item per sub-topic, each marked **adopted** (with the plugin release), **reviewed, not applicable** (with the reason) or **open** (for Tamir's judgment). Never a model name; never a claim that is not in the host's changelog or in a live run recorded in `platform-targets.json`.
