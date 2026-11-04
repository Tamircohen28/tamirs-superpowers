---
name: plugin-config
description: 'Use when the user types /plugin-config to view or change how much the plugin''s skills do without asking — the permission level (supervised, standard, unattended), a per-skill or per-group level, an allow/ask/deny for one action, resetting overrides, trusting a repository''s .tamirs-superpowers/permissions.json, or confirming a pending widening or --perms= request by its nonce. Triggers: ''/plugin-config show'', ''/plugin-config standard'', ''/plugin-config pr-dev unattended'', ''/plugin-config pr.merge.auto allow'', ''/plugin-config reset all'', ''/plugin-config trust'', ''/plugin-config confirm <nonce>''. Explicit-only: never invoked on the model''s own initiative.'
when_to_use: '/plugin-config show; /plugin-config standard; /plugin-config pr-dev unattended; /plugin-config pr.merge.auto allow; /plugin-config confirm 0123456789abcdef0123456789abcdef.'
argument-hint: '[show|set|reset|trust|confirm] [skill|group|level] [level]'
disable-model-invocation: true
user-invocable: true
allowed-tools:
- Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/plugin-config.sh:*)
effort: low
metadata:
  tamirs:
    visibility: public
    category: toolkit
    role: none
    validation-tier: 1
    updated-date: '2026-11-04'
    capabilities:
      required:
      - skills
      - shell
      optional: []
    tags:
    - permissions
    - configuration
    - policy
    - toolkit
---

# plugin-config

The `/plugin-config` command (ADR 004 D6). It changes the plugin's permission policy, so it
is **explicit-only**: it runs when the user types it, never because the model decided to
(`disable-model-invocation: true` here; `agents/openai.yaml` on Codex; a code command on
OpenCode; on Gemini the static `ask_user` rule on `confirm` is the gate).

## The one rule: the writer does everything

Every read and write goes through `scripts/plugin-config.sh`, the one deterministic writer of
`~/.config/tamirs-superpowers/permissions.json`, its lock and the D5 tickets. It validates
against the schema, writes atomically at 0600, re-locks, and decides on its own whether a
change widens anything. You only pass the arguments through and relay the answer.

Why: a policy the agent edits by hand is a policy the agent controls (ADR 004 D10.3). The
permission guard and the sensitive-files guard deny every other write to these files, and a
hand edit would also break the lock, so the resolver would read the file tighten-only.

## Steps

1. Run the writer with the user's arguments **verbatim**, unquoted words kept as words:

   ```bash
   bash ${CLAUDE_PLUGIN_ROOT}/scripts/plugin-config.sh <the user's arguments>
   ```

   No arguments means `show`. Do not add, reorder or "fix" arguments; if the writer says
   they are wrong (exit 2), show its message and its usage line.

2. Relay the output as it is — what it wrote, the rows it widened, notes about a host
   setting that caps the level. Add nothing it did not say.

3. Act on the exit code:

   | exit | meaning | what you do |
   |---|---|---|
   | 0 | done, nothing to do, or shown | relay it |
   | 1 | failed | relay the reason; do not retry with other arguments |
   | 2 | usage error | relay the message and the grammar below |
   | 3 | refused (no host-attested channel, R4 `allow`, provision inside a session, or a Claude Code `confirm` with no usable guard stamp: `asked/<nonce>.json` missing, older than 15 minutes, or for other bytes, nonce, session or host — the pending request is kept) | relay it, including the command it names for the user's own terminal |
   | 4 | recorded **pending**: the change widens something | show the rows and the printed `confirm <nonce>` command; stop |

   On exit 4 the user decides. Run `confirm <nonce>` only when the user asks you to — on
   Claude Code the permission dialog that call raises is the human proof (D5), so it must be
   the user's own decision; on Codex, Cursor and OpenCode the writer refuses `confirm`
   inside the session and names the command to run in their own terminal.

## Grammar

```text
/plugin-config show [<skill|group|action-id>]
/plugin-config [set] <level>                       supervised | standard | unattended
/plugin-config [set] <skill|group> <level>
/plugin-config [set] <action-id> [<skill>] allow|ask|deny     (R4 ids: ask|deny only)
/plugin-config reset [<skill|group|action-id>|level|trust|all]
/plugin-config trust                               this repo's .tamirs-superpowers/permissions.json
/plugin-config confirm <nonce>
```

`provision` exists for CI steps that run before the agent starts; never run it here.

## What it never does

- Write R4 `allow` — R4 passes only on the host prompt of that very call.
- Write a host option store. On Claude Code the level is also capped by the plugin option
  (`/config` or `/plugin configure`), on Gemini CLI by `TS_PERMISSION_LEVEL`
  (`gemini extensions config`); the writer prints that route when it applies.
