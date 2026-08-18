# Per-platform extension validation

Portable validity is necessary, not sufficient. A skill can satisfy
`core/schemas/skill-frontmatter.json` and still be undiscoverable, or subtly wrong, on a
specific target. Check the extensions against every platform the skill claims in its
`compatibility` block — and against nothing else, since a claim you do not make is a claim
you do not have to defend.

Verify platform facts against the live docs, not from memory: the source URLs per target
live in `skills/documentation/platform-sync/references/platforms/<id>.md`.

Portable validity is necessary, not sufficient. Check the extensions against each target the
skill claims in `compatibility`:

| Target | What to check |
|---|---|
| **Claude Code / Desktop** | Field pairings (`context`/`agent`, invocation tier); `allowed-tools` names are real; referenced `references/` and `scripts/` paths exist; `description` + `when_to_use` within the 1536-char listing cap |
| **OpenCode** | Recognises a smaller frontmatter set and ignores the rest — so the skill must be usable from `description` alone. Its domain directory must appear in `opencode.json` → `skills.paths`, or the skill is undiscoverable no matter how correct the file is |
| **Gemini CLI** | Follows the Agent Skills model; verify against the live docs (`skills/documentation/platform-sync/references/platforms/gemini.md`) rather than from memory, and do not claim skill discovery the fetched docs do not describe |
| **Cursor** | Consumes rules and skills; a skill that duplicates canonical `AGENTS.md` policy rather than pointing at it is drift |
| **Codex CLI** | Reads `AGENTS.md` plus the manifest's declared skill paths; confirm the new skill's path is declared |

The general rule: **a Claude-only field may stay in the canonical skill only if the other
harnesses safely ignore it and portability is unaffected.** If it would change behaviour
elsewhere, generate a Claude adapter representation instead of putting it in the canonical
file.


## The deciding rule

A Claude-only field may stay in the canonical `SKILL.md` **only if** both hold:

1. every other supported harness safely ignores it, and
2. validation confirms portability is unaffected.

If neither holds — if the field would change behaviour on another target — generate a Claude
adapter representation instead of putting it in the canonical file. Do not force meaningless
Claude fields onto a skill to satisfy a validator; that requirement no longer exists.

## What "supported" costs

Declaring `compatibility: {opencode: supported}` is an evidence claim, not an intention. It
means the skill has been validated for that target — at minimum that its portable core is
complete, its domain is discoverable there, and every capability in
`metadata.tamirs.capabilities.required` is available on it per
`core/capabilities/platforms.json`. If you have not checked, use `partial` with a note, or
leave the row out and say the target is unverified. An unverified `supported` is the failure
mode this whole contract exists to prevent.
