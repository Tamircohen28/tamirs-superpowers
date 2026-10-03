# Phone notifications (Pushover)

Get a push notification on your phone when Claude Code needs you — an idle prompt
waiting for input, or a permission request blocking a tool call.

This is **opt-in**. Nothing here activates unless you supply Pushover credentials.

## How it relates to the desktop notification

The plugin already ships `hooks/notify.sh`, which raises a **macOS desktop banner**
via a terminal OSC escape sequence (with an `osascript` fallback). That is wired
through the hook manifest and needs no configuration.

Phone notifications are a **second, independent** Notification hook. Both fire:

| | Desktop banner (`notify.sh`) | Phone push (`notify-pushover.sh`) |
|---|---|---|
| Wired via | the hook manifest (automatic) | the hook manifest (automatic; inert until configured) |
| Needs credentials | No | Yes — Pushover token + user key, as plugin options |
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

Then store them as the plugin's **options** — the manifest's sensitive
`pushover_token` / `pushover_user` fields. Either:

- in the session: `/plugin` > **tamirs-superpowers** > **Configure**, or
- from a shell: `claude plugin configure tamirs-superpowers` (Claude Code 2.1.285+).

The host keeps them in its own credential store (the macOS Keychain, or its file-backed
fallback where there is no Keychain) and exports them to the plugin's own hooks as option variables. There is
nothing to wire: the hook ships in the plugin's the hook manifest on the `Notification`
event, beside the desktop banner, and stays inert until both options are set.

Options are read at **session start**, so they take effect in your next session.

### Why the options, and nothing else

The notifier reads exactly those two options. It does **not** read plain environment
variables, and it does not read a dotfile.
Installs before 4.11.0 did both; the Anthropic directory policy forbids a plugin sending a
credential it found on the machine rather than one you handed it, and a notifier that
picks up whatever it finds is exactly that. If you upgraded from an older install, enter
the two values as options once and delete the old credentials dotfile under `~/.claude` —
nothing reads it.

A `Notification` hook in `~/.claude/settings.json` that names `notify-pushover.sh` is
also a leftover of those installs. It runs without the options and sends nothing;
`bash scripts/uninstall.sh` strips it, or remove the entry by hand.

## Tuning

These are ordinary environment variables the hook reads — export them in the shell that
starts Claude Code. They are not credentials and not plugin options:

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
| Nothing arrives, no error at all | Unconfigured — the script exits 0 silently by design | Open `/plugin` > tamirs-superpowers > Configure and check both options are set |
| Worked before 4.11.0, stopped after updating | Credentials were in a dotfile, which nothing reads now | Enter them as the plugin's options; delete the file |
| `"application token is invalid"` | User key pasted into the token field | Token starts `a`, user key starts `u` |
| `"user identifier is not a valid user"` | Token pasted into the user key field | Same swap, other direction |
| Credentials validate, phone stays silent | Pushover app not installed / signed in | Run the validate call and check the `devices` array is non-empty |
| Notification is a wall of `**` and `##` | Missing or stale `pushover_format.py` | Confirm it sits beside `notify-pushover.sh` in `scripts/` |
| Arrives at the desk, missed when away | Idle priority too low for your setup | Set `PUSHOVER_IDLE_PRIORITY=1` |

Validate credentials independently of sending:

```bash
curl -s --form-string "token=<application token>" --form-string "user=<user key>" \
  https://api.pushover.net/1/users/validate.json
```

`{"status":1,...,"devices":["iphone"]}` means both credentials are good *and* a device
is registered. This separates two failures that look identical on the send endpoint.

Send a test through the real script, with the options in its environment the way the
host exports them:

```bash
echo '{"message":"test","notification_type":"permission_prompt","cwd":"'"$(pwd)"'"}' \
  | PUSHOVER_DEBUG=1 bash scripts/notify-pushover.sh   # with the two option variables exported the way the host does
```

## Disabling

Clear both options (`/plugin` > tamirs-superpowers > Configure, or
`claude plugin configure tamirs-superpowers`). The script exits 0 silently when
unconfigured, so the hook becomes a harmless no-op. Nothing else to unwire.

Deleting only the credentials file is enough: the script exits 0 silently when
unconfigured, so the hook becomes a no-op.
