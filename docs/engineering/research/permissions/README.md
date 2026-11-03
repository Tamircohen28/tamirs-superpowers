# Configurable permission levels — cross-platform research synthesis

Research input to ADR 004 (permission levels). Date 2026-11-03. Evidence tags: doc-cited / source-cited / measured / unverified.

> **Pre-spike synthesis.** Written before the live checks in [`spikes/`](spikes/) and before
> [ADR 004](../../decisions/004-permission-levels.md). Where they differ, the spikes and the ADR win. Known
> superseded rows: Gemini headless hook `ask` **hangs** rather than becoming deny (spike G1); OpenCode `--auto`
> auto-approves a plugin `ask`, so OpenCode has no host-enforced ask (spike O1); the "in-chat confirmation" route for
> Codex and Cursor was removed (ADR D5); the open questions on Gemini hang-or-deny and OpenCode hook-vs-`--auto` are
> answered in the spikes.

Date: 2026-11-03. Sources: the six reports under [`platforms/`](platforms/). Every row below
is traced to one of them; tags (`doc-cited` / `source-cited` / `measured` / `unverified`) live there.

## Reports

- [Claude Code and Claude Desktop](platforms/claude.md)
- [Codex CLI](platforms/codex.md)
- [Cursor IDE and CLI](platforms/cursor.md)
- [Gemini CLI and Antigravity](platforms/gemini.md)
- [OpenCode](platforms/opencode.md)
- [Prior art](platforms/prior-art.md)

## Versions researched

| Platform | Latest stable found | Repo pin | Local install |
|---|---|---|---|
| Claude Code | 2.1.317 | 2.1.317 | 2.1.317 |
| Codex CLI | 0.166.0 | 0.166.0 | 0.156.0 |
| Cursor (desktop / CLI) | 3.28.7 / 2026.10.22 | 3.27.22 / 2026.09.18 | 3.27.22 / 2026.10.22 |
| Gemini CLI | 0.66.0 (0.67 preview) | 0.66.0 | 0.60.0 |
| OpenCode (V2) | 2.2.5 (repo moved to anomalyco/opencode) | 2.2.5 | 2.2.5 |

## The one fact all five agree on

**A plugin can make the host stricter; it can never make it looser.** No platform lets a
plugin ship allow rules that beat the user (Gemini's loader drops extension `allow` rules;
Claude drops every plugin `settings` key but two; Codex and Cursor manifests have no
permission field; OpenCode config denies never reach plugin hooks). Two narrow exceptions to
design *against*: Claude's mod `tool.check` can approve over a user deny on personal accounts,
and Codex/Antigravity `PermissionRequest`/`auto_approve` hooks can answer a prompt with allow.

Consequence: the plugin's most autonomous level means **"the plugin stops asking"**, never
"the host stops asking". A user who wants zero prompts still picks the host's own mode.

## Capability matrix

| | Claude Code | Codex | Cursor | Gemini | OpenCode |
|---|---|---|---|---|---|
| Plugin hard-deny | PreToolUse `deny` | PreToolUse `deny` | hook `deny` (only reliable verdict) | extension policy `deny` + BeforeTool | permission hook / `ctx.permission.assert` |
| Host-enforced "ask" from plugin | PreToolUse `ask` (even in bypass) | **none** — `ask` is rejected and the call **proceeds** | unreliable (ignored in default Auto-review) | extension `ask_user`; hook `ask` forces prompt even in YOLO (undocumented) | `ctx.permission.assert` for plugin tools; hook `ask` |
| Headless "ask" becomes | prompt/deny | n/a | n/a | deny | deny-ish (unverified under `--auto`) |
| Install-time prompt | `userConfig`; string + `options` = picker (2.1.271+; older versions refuse to load) | none in CLI | `variables` (team admin) | `settings[]` strings only, prompted | none |
| Change later | `/plugin configure`, `claude plugin configure --values-stdin` | — | dashboard | `gemini extensions config` | `options` in `opencode.json` |
| Survives update | `${CLAUDE_PLUGIN_DATA}` | `PLUGIN_DATA` (hooks only) | **nothing** (SHA-keyed cache) | **nothing** (dir recopied) | `ctx.storage` |
| Values reach hooks | `CLAUDE_PLUGIN_OPTION_*` | — | unverified | yes (env + `${VAR}`) | `ctx.options` |
| Skill receives args | `$ARGUMENTS` (text only) | no — prompt text | undocumented — prompt text | no — prompt text | commands only (`$ARGUMENTS`) |
| Explicit-only skill | `disable-model-invocation` | `allow_implicit_invocation: false` | `disable-model-invocation` | none | hides only |
| Subagents inherit parent mode | yes | yes | yes | — | child sessions inherit |

## Design conclusions (inputs to the ADR, not decisions yet)

1. **Config file location:** outside the plugin on every platform — Cursor and Gemini have no
   update-surviving plugin directory, and Claude/Codex roots are replaced per version. A
   neutral user-level file (e.g. `~/.config/tamirs-superpowers/permissions.json`) is the only
   location all five share. Platform option stores (Claude `userConfig`, Gemini `settings`)
   carry just the preset; a project file may only **tighten** (a cloned repo must not widen).
2. **Three enforcement layers**, because no single one exists everywhere:
   - L1 skill-body confirmation gate — universal, but advisory (OWASP LLM06: not sufficient alone).
   - L2 hook hard-deny of R3/R4 actions above the ceiling — Claude, Codex, Cursor, Gemini, OpenCode.
   - L3 host-native ask — Claude, Gemini, OpenCode only. **On Codex a hook `ask` fails open**;
     the Codex wiring must use `deny` plus an in-chat confirmation, never `ask`.
3. **Danger rubric R0–R4** (reversibility × blast radius × visibility; unclassified = R4):
   R0 observe · R1 local reversible · R2 shared-additive (push own branch, open PR, comment) ·
   R3 shared-mutating (merge, delete remote branch, close) · R4 irreversible/privileged
   (force-push default, release/tag, branch protection, editing the plugin's own policy).
   R4 is never automatic at any level.
4. **Levels are ceilings over the rubric**, renamed away from host-mode names:
   `supervised` (default) / `standard` / `unattended`. With no human present, "ask" → deny
   plus the setting that would allow it.
5. **Per-run override is prompt text on every platform** — no host parses `--perms=`.
   Lowering is always accepted; **raising** needs proof the text came from the user's own
   prompt (Claude `UserPromptSubmit`/`UserPromptExpansion`, OpenCode prompt hook, maybe Gemini
   `BeforeAgent`) or an in-chat confirmation. Scope it as a ticket: one skill, one target,
   short expiry, not inherited by subagents.
6. **Self-protection:** policy file under `guard-sensitive-files.sh`; hash it and re-confirm on
   change (Cursor MCPoison class); `/plugin-config` explicit-only where the host supports it,
   and it cannot raise anything above the caller's level without a human.
7. **Merge semantics:** "auto-merge" = `gh pr merge --auto`, so GitHub protection decides.

## Conflicts inside the repo to settle first

- Auto-merge default: `core/policies/safety.md` says "off unless configured";
  `resolve-merge-policy.sh` step 5 enables it whenever the repo allows. Pick one.
- `settings.statusLine` in `plugin.json` is a dropped key per current docs (unverified live).

## Load-bearing open questions (need a live run)

- Claude: does an option with a `default` still appear in the install dialog? Does
  `UserPromptExpansion` see skill arguments? Desktop: do userConfig and hooks work?
- Codex: confirm hook `ask` → call proceeds on 0.166.0; does `PermissionRequest` fire under `granular`?
- Cursor 3.28: hook `allow`/`ask` honoured? How do args after `/pr-dev` reach the model?
- Gemini: hook `ask` headless — hang or deny? Does `BeforeAgent` see slash-command args?
- OpenCode: permission hook vs `--auto`; session allow vs config deny.

## Repo drift found (unrelated to this feature — separate fix)

Claude: statusLine key, `/config` claim. Codex: nonexistent `codex plugin install` in
`platforms.json`; retired `untrusted` in `platform-specs.md`; stale `.codex/config.toml`
comment. Cursor: `subagentStop` wired-vs-documented; hook-count contradiction; `loop_limit`
reasoning; `extension_install` stale; variables are admin-set; pins behind 3.28.7. Gemini:
settings reach hooks (docs say MCP only); antigravity doc stale (config vars, hooks, schema).
OpenCode: missing `experimental_image_generate` action; `execute` not emitted; V1 doc URLs;
stale adapter note.
