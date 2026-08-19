---
name: notify-setup
description: 'Use when the user wants Claude Code to reach them on their phone, or phone notifications have stopped arriving — ''notify me on my phone'', ''send notifications to my phone'', ''set up push notifications'', ''set up Pushover'', ''ping me when Claude needs input'', ''I keep missing when Claude finishes'', ''phone alerts for Claude'', ''notifications stopped working'', ''make notifications less noisy'', ''change notification priority'', ''turn off phone alerts''. Requires the Notification hook event; on a harness without one it says so plainly instead of half-configuring.'
when_to_use: 'User wants phone/push notifications from Claude Code, or is debugging notifications that never arrive — e.g. ''notify me on my phone when Claude needs me'', ''set up Pushover'', ''I keep missing when Claude finishes'', ''push notifications stopped working'', ''make notifications less noisy''. Claude Code only: it requires the Notification hook event, which no other supported harness provides. On any other platform this skill reports that push notifications are unavailable rather than half-configuring them.'
argument-hint: '[optional: ''test'', ''disable'', or ''troubleshoot'']'
arguments: []
disable-model-invocation: false
user-invocable: true
allowed-tools:
- Bash
- Read
- Edit
- Write
- AskUserQuestion
disallowed-tools: []
model: claude-sonnet-4-6
effort: medium
context: ''
agent: ''
hooks: {}
paths: []
shell: bash
compatibility:
  claude-code: supported
  claude-desktop: partial
  codex: unsupported
  cursor: unsupported
  gemini: unsupported
  opencode: unsupported
metadata:
  tamirs:
    visibility: public
    category: toolkit
    role: none
    validation-tier: 0
    updated-date: '2026-08-19'
    capabilities:
      required:
        - hooks
        - shell
      optional:
        - ask_user_question
    tags:
      - toolkit
      - notifications
      - pushover
      - hooks
      - mobile
      - setup
      - platform-specific
  capability: notification-setup
  provider: developer-workflow
  agents: []
  updated-date: '2026-08-19'
---

# notify-setup

Configure phone push notifications for Claude Code via [Pushover](https://pushover.net).

## Platform support — check this first

**This is a platform-specific capability, not a universal one.** It is built on Claude Code's
`Notification` hook event: the harness fires a hook when the agent needs attention, and that
hook pushes to the phone.

Be precise about what is missing elsewhere. Several targets *do* have lifecycle hooks of some
shape — the registry records Codex CLI's manifest `hooks` field as native and Cursor's as
partial. What none of them has is an **agent-needs-attention event**. Without that event
there is no moment to fire on, so a correctly-wired hook would simply never run.

| Target | Status | Why |
|---|---|---|
| Claude Code | supported | Native `Notification` hook event |
| Claude Desktop | unverified | Same plugin artifact, but the registry marks its `hooks` status `unknown` — whether the plugin hook bundle fires in Desktop sessions has not been verified. Do not claim it works; verify first |
| Codex CLI | unsupported | Has manifest hooks, but not in Claude's shape and with no needs-attention event |
| Cursor | unsupported | Claude-shaped plugin hooks do not run under a Cursor plugin install, and there is no needs-attention event |
| Gemini CLI, OpenCode | unsupported | Registry marks hooks `unknown` and `unsupported` respectively; no needs-attention event either way |

**Before step 1**, confirm the `hooks` capability for the current platform in
`core/capabilities/platforms.json`, and confirm the target actually exposes a
needs-attention event. If `hooks` is `unsupported` or `unknown`, or the event does not
exist, stop and say so:

```
Phone push notifications are a Claude Code capability — they rely on its Notification hook
event, which <platform> does not provide (it may have lifecycle hooks of its own, but none
that fires when the agent needs attention). Nothing to configure here.
What is available on <platform>: <whatever its own notification story is, or "nothing I can
wire from this skill">.
```

Then stop. **Do not** write `~/.claude/pushover.env`, do not edit a settings file, and do not
partially configure something that will never fire — a half-configured notifier is worse than
none, because the user believes they are covered and stops watching the terminal.

Pushover itself remains **optional even on Claude Code**. It is a paid third-party service;
a user who declines it keeps the desktop banner and loses nothing else. Never present it as
required.

### Interaction

Where `AskUserQuestion` is available, use it to collect the two credentials. Where it is not,
ask in plain prose with numbered options — the credential collection is identical either way.
`AskUserQuestion` is an enhancement, never a prerequisite.

## Why this exists

The plugin already ships `hooks/notify.sh`, which raises a desktop banner when Claude needs
attention. It emits an OSC 99 terminal sequence and lets the terminal route it to the OS —
portable in principle, but only where the terminal emulator implements OSC 99. Its fallback
is `osascript`, which is macOS-only, so on a Linux or Windows machine in a terminal without
OSC 99 support there is no banner at all, and this skill's push hook is the only alert there
is. Either way the banner works at the machine and is useless away from it. This skill adds a
second, independent Notification hook that pushes to your phone.

Both fire. You are not replacing the banner.

Pushover was chosen over ntfy.sh because it delivers reliably on iOS under Low Power
Mode, where ntfy's push can be deferred indefinitely.

## Prerequisites

Pushover needs **two** 30-character credentials. Users routinely supply only one, so
confirm you have both before writing anything:

| Credential | Starts with | Where |
|---|---|---|
| Application/API token | `a` | https://pushover.net/apps/build — register an app (name it "Claude Code") |
| User key | `u` | https://pushover.net — dashboard, top right |

Pushover is a one-time ~$5 purchase per platform after a 30-day trial. There is no
subscription.

## Setup

1. **Collect both credentials.** If the user supplies only one, ask for the other —
   do not guess or proceed. The `a`/`u` prefix tells them apart; if a pasted value
   does not match its claimed role, say so rather than writing it.

2. **Validate before writing.** This distinguishes "wrong credentials" from
   "no device registered" — both of which fail identically on the send endpoint:

   ```bash
   curl -s --form-string "token=$TOKEN" --form-string "user=$USER_KEY" \
     https://api.pushover.net/1/users/validate.json
   ```

   Expect `{"status":1,...,"devices":["..."]}`. A `status` of 0 means bad
   credentials; an empty `devices` array means the Pushover app is installed
   nowhere yet.

3. **Write the credentials** to `~/.claude/pushover.env`, mode 600:

   ```bash
   umask 077
   cat > ~/.claude/pushover.env <<EOF
   PUSHOVER_TOKEN=<token>
   PUSHOVER_USER=<user key>
   EOF
   chmod 600 ~/.claude/pushover.env
   ```

   This path is deliberate. The plugin cache at
   `~/.claude/plugins/cache/tamirs-marketplace/tamirs-superpowers/<version>/` is
   version-pathed and replaced wholesale on every plugin update — credentials
   stored there would vanish on upgrade.

4. **Wire the hook.** Easiest is to re-run the installer, which is idempotent and
   preserves any other Notification hooks:

   ```bash
   PUSHOVER_TOKEN=<token> PUSHOVER_USER=<user key> bash scripts/install.sh
   ```

   For a manual wire, append to `.hooks.Notification` in `~/.claude/settings.json`:

   ```json
   {
     "hooks": [{
       "type": "command",
       "command": "f=$(ls \"$HOME\"/.claude/plugins/cache/tamirs-marketplace/tamirs-superpowers/*/scripts/notify-pushover.sh 2>/dev/null | sort -rV | head -1) && [ -n \"$f\" ] && bash \"$f\"",
       "timeout": 10
     }]
   }
   ```

   The glob-and-sort resolves the newest installed version at runtime, so the hook
   survives plugin updates. Never hardcode a version path.

5. **Send a test** through the real script, not a hand-rolled curl:

   ```bash
   echo '{"message":"Test from notify-setup","notification_type":"permission_prompt","cwd":"'"$PWD"'"}' \
     | PUSHOVER_DEBUG=1 bash scripts/notify-pushover.sh
   ```

   Success is `{"status":1,"request":"..."}`. Report the raw response — do not
   claim delivery without it.

6. **Tell the user hooks load at session start**, so the new hook takes effect in
   their *next* session. The test above bypasses that by invoking the script directly.

## Tuning

Set these in `~/.claude/pushover.env` (they are sourced with the credentials):

| Variable | Default | Effect |
|---|---|---|
| `PUSHOVER_IDLE_PRIORITY` | `0` | Priority for idle prompts |
| `PUSHOVER_PERMISSION_PRIORITY` | `1` | Priority for permission requests |
| `PUSHOVER_INCLUDE_SNIPPET` | `1` | `0` stops sending transcript excerpts |
| `PUSHOVER_RETRY` / `PUSHOVER_EXPIRE` | `60` / `600` | Emergency (priority 2) retry cadence |

Pushover priorities: `-2` lowest, `-1` low, `0` normal, `1` high (bypasses quiet
hours), `2` emergency (re-alerts until acknowledged; requires retry/expire).

Idle defaults to `0` on purpose — priority `1` bypasses Do Not Disturb, so raising
it means quiet sessions can wake the user at night. Only raise it if they ask.

## Privacy

With `PUSHOVER_INCLUDE_SNIPPET=1` (the default), up to 300 characters of Claude's
last message transit Pushover's servers. Markdown is stripped to plain text first
(`scripts/pushover_format.py`), since raw Markdown is unreadable in a notification.
Flag this to the user when setting up on a machine handling sensitive work, and set
`PUSHOVER_INCLUDE_SNIPPET=0` if they prefer message-only alerts.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Nothing arrives, no error | Script exits 0 silently when unconfigured | Check `~/.claude/pushover.env` exists and has both values |
| `{"status":0,"errors":["application token is invalid"]}` | User key pasted as token | Token starts `a`, user key starts `u` — they are not interchangeable |
| `{"status":0,...,"user identifier is not a valid user"}` | Token pasted as user key | Same swap, other direction |
| Validates fine, nothing on phone | No device registered | Install the Pushover app and sign in; re-run validate and check `devices` |
| Arrives at desk but not when away | Wired but priority too low | Raise `PUSHOVER_IDLE_PRIORITY` to `1` |
| Notification is unreadable Markdown | Old version, or formatter missing | Confirm `scripts/pushover_format.py` sits beside `notify-pushover.sh` |
| Worked, then stopped after update | Hardcoded version path in settings | Re-run installer to restore the glob-resolving command |

Debug any send with `PUSHOVER_DEBUG=1`, which prints the API response instead of
discarding it.

## Disabling

```bash
bash scripts/uninstall.sh   # unwires the hook, keeps credentials
rm ~/.claude/pushover.env   # purge credentials
```

Removing only the credentials file is also sufficient: the script exits 0 silently
when unconfigured, so the hook becomes a harmless no-op.
