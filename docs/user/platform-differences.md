# Platform differences

Six supported platforms, and they do not agree about much. This page is the honest picture:
every cell comes from [`core/capabilities/platforms.json`](../../core/capabilities/platforms.json),
the registry the skills themselves read at runtime.

**`unknown` means this repo has not measured it** — not that it is broken, and not that it
works. It is treated as unavailable until someone records evidence. Nothing here is upgraded
to a checkmark on optimism.

Registry last reviewed: 2026-08-19.

---

## Platform identity

Platform ids are **snake_case** and identical in
[`core/capabilities/platforms.json`](../../core/capabilities/platforms.json) and
[`platform-targets.json`](../engineering/build-and-release/platform-targets.json). Use the id
in configuration and tooling; use the display name in prose. The aliases column lists the
spellings the registry also accepts — no third spelling exists.

| Registry id | Display name | Aliases accepted | Install guide |
|---|---|---|---|
| `claude_code` | Claude Code | `claude-code`, `claude` | [claude-code.md](install/claude-code.md) |
| `claude_desktop` | Claude Desktop | `claude-desktop`, `desktop` | [claude-desktop.md](install/claude-desktop.md) |
| `codex` | Codex CLI | `codex-cli`, `openai-codex` | [codex.md](install/codex.md) |
| `cursor` | Cursor | `cursor-cli` | [cursor.md](install/cursor.md) |
| `gemini_cli` | Gemini CLI | `gemini-cli`, `gemini` | [gemini.md](install/gemini.md) |
| `opencode` | OpenCode | `open-code` | [opencode.md](install/opencode.md) |

Claude Desktop carries `runtime_surface_of: claude_code`: it is the same adapter and the same
plugin, running somewhere else.

## Status vocabulary

| Status | Meaning |
|---|---|
| `native` | The platform reads this repo's canonical files directly |
| `native (experimental)` | Provided, but documented as evolving — skills must not require it |
| `adapter` | **The canonical form does not load; a generated form does.** This repo builds and drift-checks the generated artifact, which the platform then consumes natively. Not "broken", and not "works as shipped" — works *through the adapter* |
| `emulated` | Built by the skill out of lower-level primitives (shell + git) |
| `partial` | Works on some surfaces or configurations, not all |
| `unknown` | **Not measured here.** Treated as unavailable, but this is not a claim that it fails — nobody checked |
| `unsupported` | A measured, confirmed absence; a stated fallback applies |

Two of these are routinely misread, and the distinction matters more than the word:

- **`adapter` is not a demerit.** It means you get the capability, via a file this repo
  generates. It is only a warning against hand-editing the generated copy.
- **`unknown` is not `unsupported`.** "We did not build or verify it" and "it does not work"
  are different facts, and collapsing them is exactly what the registry exists to prevent.

## Capability matrix

| Capability | Claude Code | Claude Desktop | Codex CLI | Cursor | Gemini CLI | OpenCode |
| --- | --- | --- | --- | --- | --- | --- |
| `skills` | native | native | native | native | adapter | native |
| `skill_auto_invocation` | native | native | unknown | partial | unknown | unknown |
| `subagents` | native | unknown | native | native | adapter | adapter |
| `parallel_subagents` | native | unknown | unknown | unknown | unknown | unknown |
| `agent_teams` | native (experimental) | unknown | unknown | unknown | unknown | unknown |
| `hooks` | native | unknown | native | partial | unknown | unsupported |
| `mcp` | native | native | native | native | native | native |
| `statusline` | native | unsupported | unsupported | unsupported | unsupported | unsupported |
| `shell` | native | partial | native | native | native | native |
| `git` | native | partial | native | native | native | native |
| `github_cli` | native | unknown | native | native | native | native |
| `background_tasks` | native | unknown | unknown | unknown | unknown | unknown |
| `worktree_isolation` | native | unknown | emulated | emulated | emulated | emulated |
| `plugin_marketplace` | native | native | native | native | unsupported | unsupported |
| `extension_install` | unsupported | unsupported | unsupported | unsupported | native | unsupported |
| `slash_commands` | native | native | unknown | native | unknown | unknown |
| `ask_user_question` | native | unknown | unknown | unknown | unknown | unknown |
| `artifacts` | partial | partial | unsupported | unsupported | unsupported | unsupported |
| `session_transcripts` | native | unknown | unknown | unknown | unknown | unknown |

Regenerate this table from the registry:

```bash
jq -r '.platforms as $p | .capability_definitions | keys_unsorted[]' core/capabilities/platforms.json
jq -r '.platforms["claude_code"].capabilities | to_entries[] | "\(.key): \(.value.status)"' core/capabilities/platforms.json
```

Every non-`native` entry in the registry carries a `fallback` or `notes` field explaining
what happens instead. Read the entry, not just the cell.

---

## What this means in practice

### Claude Code

The reference target: the only one where the shipped `hooks/hooks.json` bundle runs as
written, the only one with a verified statusline, and the only one where
`parallel_subagents` is `native` — so it is the only platform that runs orchestration
**concurrently**. Session transcripts are readable, so `/session-report` works here and
nowhere else.

### Claude Desktop

**A runtime surface of the Claude adapter, not a separate plugin format.** There is no
Desktop manifest, and none should be created — Desktop consumes the same
`.claude-plugin/plugin.json` from the same marketplace listing. Skills, slash commands, and
MCP work. Shell and git are `partial` (available in coding sessions, absent from plain
chat), and subagents, hooks, and background tasks are `unknown` because this repo has not
exercised them there. Treat Desktop as a place to *use* skills, and do heavy orchestration
in the CLI.

### Codex CLI

Skills, subagents, MCP (via `.codex/config.toml`), and manifest-level hooks are native. The
hook shape is **not** Claude's — the Claude bundle does not port. Slash commands and
auto-invocation are unmeasured, so name skills explicitly. Worktree isolation is `emulated`:
the skill creates and removes worktrees itself instead of relying on hook automation.

### Cursor

Skills, subagents, slash commands, and MCP are native. Hooks are `partial` and this is the
sharpest correction on the page: **Claude-shaped plugin hooks do not run under a Cursor
plugin install.** Cursor runs project-level `.cursor/hooks.json` guards, and third-party
Claude hooks are an opt-in setting. Treat guards as advisory there and let CI enforce.
Auto-invocation is `partial` — sticky skills are documented for the CLI, broader selection
is unverified.

### Gemini CLI

Installed as a **git-URL extension** (`gemini extensions install <url>`, or
`gemini extensions link .` for local development) — the only target where `extension_install`
is the primary path, and where there is no marketplace to publish to.

**Skills and agents work here through a generated adapter, not the canonical files.** Both
rows read `adapter`, and the distinction is worth stating plainly:

- **Agents.** The canonical `agents/*.md` are rejected — Gemini reads them from the extension
  root and fails with `tools.0: Invalid tool name`, because Claude's `tools:` is a
  comma-separated string where Gemini wants a YAML array of its own tool names.
  `scripts/build-gemini-extension.sh` generates `.gemini/agents/*.md` with real Gemini names
  (`read_file`, `search_file_content`, `glob`, `run_shell_command`), verified against the
  loader rather than guessed, and omits `model:` entirely — a Claude alias like `sonnet`
  passes validation and then fails at invocation. On 0.55.1 all ten agents load clean.
- **Skills.** Gemini discovers skills exactly **one level** below a skills root, so the
  canonical two-level `skills/<domain>/<name>/` tree resolves to **zero** skills. The
  generator emits a flat symlink mirror at `.gemini/skills/` — one symlink per skill, so the
  repo still holds exactly one copy — which Gemini then reads natively, in-workspace with no
  install, or via `gemini skills install --path .gemini/skills`.

So: *you get the skills and the agents; what you do not get is Gemini reading this repo's
Claude-shaped files directly.* Regenerate with `make gemini-extension`; never hand-edit
`.gemini/`; `make gemini-extension-check` and `make check-gemini-adapter` fail on drift.

Two failure modes to recognize, because both look like nothing happening:

- **An untrusted workspace folder silently skips the mirror.** Gemini logs "Skipping project
  agents due to untrusted folder" and you see zero skills — identical to a broken mirror.
  Trust the folder before concluding the adapter is at fault.
- **`gemini extensions validate` only parses the manifest.** It reports success on an
  extension whose context file does not even exist, so it is not evidence that anything
  loads. Use `make check-gemini-adapter` and an actual session.

Installing the extension also emits a harmless load error for the canonical `agents/` sitting
at the extension root. It is noise, not failure, and it is unfixable from this side — Gemini
offers no subdirectory flag or manifest field to relocate them.

**`hooks` is `unknown`, and deliberately so.** Gemini accepts the outer `{"hooks": {…}}`
shape of the Claude schema without complaining, but it has its own event vocabulary, and
whether Claude's event names ever *fire* was never checked — so no claim is made in either
direction. Separately, and this is a different fact: **this adapter ships no hooks at all, by
design.** Guards live in the skills as explicit steps and in CI. If you want to try them
yourself, `gemini hooks migrate --from-claude` translates them into your personal settings.

MCP works natively; the bundled `github` server reads `gh auth token` at startup, so
`gh auth login` is a prerequisite for its first call. There is no extension-declared
statusline (measured, not assumed).

### OpenCode

Install is by path: point `opencode.json` `skills.paths` at a checkout. There is no
marketplace and no extension install.

**Do not port Gemini's mirror strategy here.** Gemini follows symlinks during skill
discovery; **OpenCode does not, at any level.** OpenCode reads the canonical two-level tree
directly through `skills.paths`, which is why it needs no mirror — and why a symlinked one
would silently find nothing. Subagents come from an `adapter` —
`.opencode/agent/` is generated from `agents/` because the frontmatter genuinely differs,
and drift fails CI. Hooks do not port at all: OpenCode's only lifecycle mechanism is a JS/TS
plugin API, and this repo ships no plugin module by design (it would add a Node runtime
dependency for nothing else).

---

## Consequences you will actually notice

| If your platform… | Then |
|---|---|
| lacks `parallel_subagents` | orchestration runs **serialized or sequential** — same task graph, same one PR, more wall-clock time |
| lacks `subagents` | roles run inline in your main session, one at a time |
| lacks `hooks` | worktree creation and edit guards become explicit steps in the skill, plus CI checks |
| shows `adapter` | you have the capability, through a generated file — regenerate it, never hand-edit it |
| shows `unknown` | nobody measured it. Skills treat it as unavailable and say so; it is not a claim of failure |
| lacks `slash_commands` | invoke skills by name: *"use the orchestrate-dev skill"* |
| lacks `skill_auto_invocation` | the agent will not pick a skill from your phrasing — name it |
| lacks `statusline` | nothing; it is cosmetic and nothing depends on it |
| lacks `session_transcripts` | `/session-report` refuses rather than reporting zeros |
| lacks `github_cli` | delivery ends at a pushed branch, and says so — never a fake PR claim |
| lacks `ask_user_question` | choices are asked in prose and wait for a free-text reply |

## Authoritative platform documentation

Curated per-platform reference links, taken from the registry's `doc_urls`. These are the
stable references; `platform-targets.json` carries the fuller list, including blog and
changelog entries used for version tracking.

| Platform | Authoritative documentation |
|---|---|
| Claude Code (`claude_code`) | [plugins-reference](https://code.claude.com/docs/en/plugins-reference) · [plugin-marketplaces](https://code.claude.com/docs/en/plugin-marketplaces) · [skills](https://code.claude.com/docs/en/skills) |
| Claude Desktop (`claude_desktop`) | [plugins-reference](https://code.claude.com/docs/en/plugins-reference) · [skills](https://code.claude.com/docs/en/skills) |
| Codex CLI (`codex`) | [agents-md](https://developers.openai.com/codex/guides/agents-md) · [config-basic](https://developers.openai.com/codex/config-basic) |
| Cursor (`cursor`) | [plugins](https://cursor.com/docs/plugins) · [rules](https://cursor.com/docs/context/rules) · [hooks](https://cursor.com/docs/hooks) · [third-party-hooks](https://cursor.com/docs/reference/third-party-hooks) |
| Gemini CLI (`gemini_cli`) | [reference](https://github.com/google-gemini/gemini-cli/blob/main/docs/extensions/reference.md) · [skills](https://github.com/google-gemini/gemini-cli/blob/main/docs/cli/skills.md) · [subagents](https://github.com/google-gemini/gemini-cli/blob/main/docs/core/subagents.md) |
| OpenCode (`opencode`) | [skills](https://opencode.ai/docs/skills/) · [agents](https://opencode.ai/docs/agents/) · [plugins](https://opencode.ai/docs/plugins/) · [config.json](https://opencode.ai/config.json) |

## Keeping this page honest

- The registry is the source; this page is a rendering of it.
- `scripts/check-capability-registry.sh` validates the registry against its schema.
- `scripts/check-doc-claims.sh` asserts that every supported target is named here and in the
  README, and that each declares an install guide that exists.
- Adding a platform, or changing a status, is a registry edit first — never a docs edit.
  Procedure: [engineering/architecture/adding-a-platform.md](../engineering/architecture/adding-a-platform.md).
