# Machine-level setup for Codex, Cursor, Gemini and OpenCode

Installing this plugin makes *this repository* usable from five agent CLIs. That is
a different thing from making *your machine* carry your global rules. This page is
about the second one: one canonical rules file in the repo, rendered into each
platform's own global config format.

```bash
bash scripts/setup.sh plan                      # show what would change, write nothing
bash scripts/setup.sh apply                     # confirm each change, then write
bash scripts/setup.sh apply --targets codex     # one platform
bash scripts/setup.sh remove                    # undo, scoped to what we wrote
```

`plan` is the default when there is no terminal, so a CI or hook invocation can
never adopt anything silently.

## The canonical source

[`core/global-rules.md`](../../core/global-rules.md) is the one source. Every
machine-level rules file below is rendered from it — never copied by hand, never
edited per platform.

| Target | Rules file | Config file | Merge strategy |
|---|---|---|---|
| Claude Code | `~/.claude/CLAUDE.md` | `~/.claude/settings.json` | whole-file rules; deep-merged settings |
| Codex CLI | `~/.codex/AGENTS.md` | `~/.codex/config.toml` | marker block in both |
| Gemini CLI | `~/.gemini/GEMINI.md` | `~/.gemini/settings.json` | marker block; deep merge |
| Cursor | `~/.cursor/rules/tamirs-superpowers.mdc` | `~/.cursor/cli-config.json` | marker block; deep merge |
| OpenCode | `~/.config/opencode/AGENTS.md` | `~/.config/opencode/opencode.json` | marker block; deep merge |

Editing a rendered file is editing a build artifact — the next `apply` overwrites
the block it owns. Change `core/global-rules.md` and re-run.

Anything **outside** the markers is yours and is preserved:

```
<!-- >>> tamirs-superpowers >>> -->
...rendered rules...
<!-- <<< tamirs-superpowers <<< -->
```

Markdown uses HTML-comment markers so the bookkeeping does not render as a heading
the agent might read as an instruction. TOML uses `#` comments.

## Idempotence

Every module is a renderer, not a writer: given the file as it is, it prints the
file as it should be, and the engine compares content. Running `apply` twice is
therefore a no-op the second time — it reports `Everything is already up to date`
and writes nothing. Nothing rendered contains a timestamp, a hostname, or an
absolute path, because any of those would make every run a diff.

## What is deliberately NOT touched

**Codex hooks — the important one.** `~/.codex/config.toml` stores a per-hook
`trusted_hash` under `[hooks.state."..."]`. Codex invalidates that trust whenever
the hook's content or path changes, and re-trusting is a user action. Rewriting,
reordering or even reindenting that table would silently break hook wiring this
installer does not own. **The Codex renderer never reads or writes hook entries.**
Its block is appended at the end of the file and contains **comments only** — a
second reason for that: under TOML v1.0.0, a bare `key = value` appended at the end
of a file binds to the last `[table]` header, not to the document root, so
appending real settings to a file that already has tables is unsafe by
construction. Codex loads `~/.codex/AGENTS.md` automatically, so no key is needed
to enable the rules. Your model, approval policy and sandbox settings stay yours.

**cmux and gortex wiring.** cmux writes hook wiring into `~/.cursor/hooks.json`,
`~/.codex/hooks.json` and `~/.gemini/settings.json`; gortex writes more. None of it
is removed or rewritten:

- `~/.cursor/hooks.json` — no module touches this file at all.
- `~/.gemini/settings.json` — the fragment asserts `context.fileName` and nothing
  else. `hooks` and MCP entries are untouched, and arrays merge as a union.
- `~/.config/opencode/opencode.json` — the fragment asserts `$schema` and nothing
  else; `plugin` and `mcp` are untouched.

Re-run `cmux hooks setup` after this whenever you like; the two do not collide.

**Security-sensitive keys.** Nothing writes `permissions.deny` (in Cursor, deny
beats allow, so an installer that can widen it can lock you out of your own tool),
`provider`, `permission`, `agent`, or any auth or cache key.

## What each config fragment asserts

The fragments live in `platforms/<target>/templates/` and are documented inline.
Keys beginning with `_` are notes for the next repo reader and are stripped before
the merge — they never reach your machine.

- **Cursor** `permissions.allow`: read-only shell inspection (`ls`, `git status`,
  `git log`, `git diff`) plus the three GitHub domains the shipped skills fetch.
  Deliberately conservative, and deliberately not a mechanical translation of the
  Claude allow-list — Cursor's `Shell()`/`Read()`/`Write()`/`WebFetch()`/`Mcp()`
  syntax does not map one-to-one onto Claude's `Bash()` patterns.
- **Gemini** `context.fileName`: `["GEMINI.md", "AGENTS.md"]`, so a rule written
  once is picked up whichever CLI you reach for.
- **OpenCode** `$schema`: makes your editor validate the file. Nothing else —
  OpenCode loads `~/.config/opencode/AGENTS.md` with no config key.
- **Codex**: nothing. See above.

## Capability honesty

Not every platform can express everything the rules assume. Rather than dropping
those rules quietly, each rendered file ends with a **Platform notes** section
generated from [`core/capabilities/platforms.json`](../../core/capabilities/platforms.json),
naming each non-native capability and what to do instead. Examples as rendered
today:

- **OpenCode** — `hooks: unsupported`. The guard hooks do not run at all; the same
  rules are enforced as explicit in-skill steps and in CI.
- **Cursor** — `hooks: partial`. The Claude-shaped plugin hook bundle does not run
  under a Cursor install; guards are advisory there.
- **Codex, Gemini, Cursor, OpenCode** — `statusline: unsupported`. Cosmetic, and
  nothing depends on it.
- **All four** — `worktree_isolation: emulated`. The worktree lifecycle is driven
  by the skill through `git`, not by hook automation.
- **Several rows are `unknown`** rather than `unsupported`: they have not been
  measured on that platform by this repo, and the registry does not claim a result
  it never observed.

## Undo

`bash scripts/setup.sh remove` strips the marker blocks, deletes a rules file that
held nothing but our block, and un-merges exactly the JSON values that are still
what we wrote. A value you have since changed is yours and stays. One honest
limitation: an array entry that was **both** in your config and in our fragment
(`Shell(ls)` in Cursor, say) is removed on `remove`, because a union merge leaves
no record of who put it there first. The pre-change backup —
`<file>.pre-tamirs-superpowers` — is written before the first change to every file
and is never overwritten, so the original is always recoverable.

## Verify

```bash
bash tests/test-renderers.sh    # hermetic: fake HOME, never touches your real config
bash scripts/doctor.sh .
```
