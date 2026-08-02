---
name: notify-setup
description: 'Use when the user wants Claude Code notifications on their phone, or is fixing phone notifications that never arrive — ''notify me on my phone'', ''send notifications to my phone'', ''set up push notifications'', ''set up Pushover'', ''ping me when Claude needs input'', ''I keep missing when Claude finishes'', ''phone alerts for Claude'', ''notifications stopped working'', ''make notifications less noisy'', ''change notification priority'', ''turn off phone notifications''.'
when_to_use: User wants phone/push notifications from Claude Code, or is debugging notifications that never arrive — e.g. 'notify me on my phone when Claude needs me', 'set up Pushover', 'I keep missing when Claude finishes', 'push notifications stopped working', 'make notifications less noisy'.
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
metadata:
  capability: notification-setup
  provider: developer-workflow
  agents: []
  platforms:
  - claude
  tags:
  - toolkit
  - notifications
  - pushover
  - hooks
  - mobile
  - setup
  updated-date: '2026-08-02'
---

# notify-setup

Configure phone push notifications for Claude Code via [Pushover](https://pushover.net).

## Why this exists

The plugin already ships `hooks/notify.sh`, which raises a **macOS desktop banner**
when Claude needs attention. That works at the machine and is useless away from it.
This skill adds a second, independent Notification hook that pushes to your phone.

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
   `~/.claude/plugins/cache/tamirs-plugins/tamirs-superpowers/<version>/` is
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
       "command": "f=$(ls \"$HOME\"/.claude/plugins/cache/tamirs-plugins/tamirs-superpowers/*/scripts/notify-pushover.sh 2>/dev/null | sort -rV | head -1) && [ -n \"$f\" ] && bash \"$f\"",
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
