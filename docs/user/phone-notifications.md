# Phone notifications (Pushover)

Get a push notification on your phone when Claude Code needs you — an idle prompt
waiting for input, or a permission request blocking a tool call.

This is **opt-in**. Nothing here activates unless you supply Pushover credentials.

## How it relates to the desktop notification

The plugin already ships `hooks/notify.sh`, which raises a **macOS desktop banner**
via a terminal OSC escape sequence (with an `osascript` fallback). That is wired
through `hooks/hooks.json` and needs no configuration.

Phone notifications are a **second, independent** Notification hook. Both fire:

| | Desktop banner (`notify.sh`) | Phone push (`notify-pushover.sh`) |
|---|---|---|
| Wired via | `hooks/hooks.json` (automatic) | `~/.claude/settings.json` (opt-in at install) |
| Needs credentials | No | Yes — Pushover token + user key |
| Reaches you | At the machine | Anywhere |
| Cost | Free | One-time ~$5 per platform, after a 30-day trial |

You are not replacing the banner. If you never configure Pushover, nothing changes.

## Why Pushover

The obvious free alternative is [ntfy.sh](https://ntfy.sh), which needs no account.
It was tried first and rejected: on iOS its push can be deferred indefinitely under
Low Power Mode, which is exactly when a long-running session is most likely to need
you. Pushover is built for server→phone alerting and delivers reliably in that state.

## Setup

The easiest path is the guided skill:

```
/tamirs-superpowers:notify-setup
```

It collects both credentials, validates them, wires the hook, and sends a test.

### Manual setup

Pushover needs **two** 30-character credentials. Supplying only one is the most
common mistake — they are not interchangeable:

| Credential | Starts with | Where to get it |
|---|---|---|
| Application/API token | `a` | <https://pushover.net/apps/build> — register an app, name it "Claude Code" |
| User key | `u` | <https://pushover.net> — dashboard, top right |

Then re-run the installer with both in the environment:

```bash
PUSHOVER_TOKEN=a... PUSHOVER_USER=u... bash scripts/install.sh
```

That writes `~/.claude/pushover.env` (mode 600) and appends a Notification hook to
`~/.claude/settings.json`. It is idempotent — re-running replaces the existing
Pushover hook rather than duplicating it, and leaves any other Notification hooks
alone.

Hooks are read at **session start**, so the wiring takes effect in your next session.

### Why credentials live outside the plugin

`~/.claude/pushover.env`, not the plugin directory. The marketplace cache lives at
`~/.claude/plugins/cache/tamirs-plugins/tamirs-superpowers/<version>/` and is replaced
wholesale on every plugin update — anything stored there is deleted on upgrade.

For the same reason the hook command resolves the script path at runtime:

```bash
f=$(ls "$HOME"/.claude/plugins/cache/tamirs-plugins/tamirs-superpowers/*/scripts/notify-pushover.sh 2>/dev/null | sort -rV | head -1) && [ -n "$f" ] && bash "$f"
```

A hardcoded version path breaks on the next update. This is the same pattern the
statusline uses.

## Tuning

All of these go in `~/.claude/pushover.env`, which is sourced alongside the credentials:

| Variable | Default | Effect |
|---|---|---|
| `PUSHOVER_IDLE_PRIORITY` | `0` | Priority for idle prompts |
| `PUSHOVER_PERMISSION_PRIORITY` | `1` | Priority for permission requests |
| `PUSHOVER_INCLUDE_SNIPPET` | `1` | `0` sends the alert without any transcript excerpt |
| `PUSHOVER_RETRY` / `PUSHOVER_EXPIRE` | `60` / `600` | Emergency retry cadence, seconds |
| `PUSHOVER_DEBUG` | `0` | `1` prints the API response instead of discarding it |

Pushover priority levels: `-2` lowest, `-1` low, `0` normal, `1` high (bypasses quiet
hours), `2` emergency (re-alerts until you acknowledge it on the device).

Permission prompts default to `1` because they block work. Idle prompts default to `0`
on purpose: priority `1` bypasses Do Not Disturb, so raising it means a session going
quiet at 3am will wake you.

## Notification content

The title is `Claude Code — <project>`, where project is the basename of the session's
working directory, so parallel sessions are distinguishable at a glance.

For idle prompts the body includes up to 300 characters of Claude's last message.
That text is **converted from Markdown to plain text** first, by
`scripts/pushover_format.py` — headings, tables, code fences, links, bold, and list
markers are all flattened. Raw Markdown is unreadable in a notification, and
truncating it can leave an unterminated code fence.

### Privacy

With snippets enabled, that excerpt transits Pushover's servers. On a machine handling
sensitive work, set `PUSHOVER_INCLUDE_SNIPPET=0` — you still get the alert and the
project name, just no conversation content.

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| Nothing arrives, no error at all | Unconfigured — the script exits 0 silently by design | Check `~/.claude/pushover.env` exists and has both values |
| `"application token is invalid"` | User key pasted into the token field | Token starts `a`, user key starts `u` |
| `"user identifier is not a valid user"` | Token pasted into the user key field | Same swap, other direction |
| Credentials validate, phone stays silent | Pushover app not installed / signed in | Run the validate call and check the `devices` array is non-empty |
| Stopped working right after a plugin update | Hardcoded version path in `settings.json` | Re-run the installer to restore the glob-resolving command |
| Notification is a wall of `**` and `##` | Missing or stale `pushover_format.py` | Confirm it sits beside `notify-pushover.sh` in `scripts/` |
| Arrives at the desk, missed when away | Idle priority too low for your setup | Set `PUSHOVER_IDLE_PRIORITY=1` |

Validate credentials independently of sending:

```bash
curl -s --form-string "token=$TOKEN" --form-string "user=$USER_KEY" \
  https://api.pushover.net/1/users/validate.json
```

`{"status":1,...,"devices":["iphone"]}` means both credentials are good *and* a device
is registered. This separates two failures that look identical on the send endpoint.

Send a test through the real script:

```bash
echo '{"message":"test","notification_type":"permission_prompt","cwd":"'"$PWD"'"}' \
  | PUSHOVER_DEBUG=1 bash scripts/notify-pushover.sh
```

## Disabling

```bash
bash scripts/uninstall.sh   # unwires the hook, keeps credentials
rm ~/.claude/pushover.env   # purge credentials
```

Deleting only the credentials file is enough: the script exits 0 silently when
unconfigured, so the hook becomes a no-op.
