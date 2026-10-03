#!/usr/bin/env bash
# notify-pushover.sh — Notification hook that pushes to your phone via Pushover.
#
# Complements hooks/notify.sh (macOS desktop banner) rather than replacing it:
# the banner catches you at the machine, this catches you away from it.
#
# Reads Claude Code's Notification hook JSON on stdin. Falls back to
# $1/$2 (message / priority-name) when stdin is empty.
#
# Credentials come from ONE place: the manifest's `userConfig` block, declared
# with "sensitive": true, which the host stores in the macOS Keychain (falling
# back to ~/.claude/.credentials.json) and exports to hook processes as
# CLAUDE_PLUGIN_OPTION_PUSHOVER_TOKEN / CLAUDE_PLUGIN_OPTION_PUSHOVER_USER. The
# person is prompted for both once when the plugin is enabled, or sets them with
# `claude plugin configure tamirs-superpowers`.
#
# Earlier versions also read PUSHOVER_TOKEN/PUSHOVER_USER from the environment
# and from ~/.claude/pushover.env. Both are gone: the Anthropic directory policy
# forbids a plugin reading a credential already on the user's machine and sending
# it to a server, and a notifier that silently picks up whatever it finds is
# exactly that. A host that exports no option (the Codex CLI loads this same
# hook and never sets CLAUDE_PLUGIN_OPTION_*) gets no notification and no error.
#
# Exits 0 and stays silent when unconfigured, so an un-set-up install never
# breaks the notification chain.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORMATTER="${PUSHOVER_FORMATTER:-${SCRIPT_DIR}/pushover_format.py}"

# Host-managed userConfig values are the only credential source (see above).
TOKEN="${CLAUDE_PLUGIN_OPTION_PUSHOVER_TOKEN:-}"
USER_KEY="${CLAUDE_PLUGIN_OPTION_PUSHOVER_USER:-}"

# Unconfigured is a normal state, not an error — bail quietly.
if [[ -z "$TOKEN" || -z "$USER_KEY" ]]; then
  exit 0
fi

# 0 = never send conversation snippets; 1 = include a plain-text excerpt.
export INCLUDE_SNIPPET="${PUSHOVER_INCLUDE_SNIPPET:-1}"

INPUT=""
[[ -t 0 ]] || INPUT="$(cat 2>/dev/null || true)"

# pushover_format.py parses the event, converts any Markdown snippet to plain
# text, and prints shell-quoted MESSAGE/PRIORITY/PROJECT assignments to eval.
if [[ -n "$INPUT" && -f "$FORMATTER" ]]; then
  eval "$(printf '%s' "$INPUT" | python3 "$FORMATTER" 2>/dev/null)"
fi

# Fallback path: $2 arrives as a name, map it onto a Pushover level.
if [[ -z "${PRIORITY:-}" ]]; then
  case "${2:-default}" in
    urgent | high) PRIORITY=1 ;;
    emergency) PRIORITY=2 ;;
    low) PRIORITY=-1 ;;
    *) PRIORITY=0 ;;
  esac
fi
MESSAGE="${MESSAGE:-${1:-Claude Code needs you}}"
PROJECT="${PROJECT:-claude}"

# Pushover caps message at 1024 chars and title at 250.
MESSAGE="${MESSAGE:0:1024}"
TITLE="Claude Code — ${PROJECT}"
TITLE="${TITLE:0:250}"

# --form-string (not -F) so a message beginning with @ or < is never
# interpreted by curl as a file upload.
args=(
  --form-string "token=${TOKEN}"
  --form-string "user=${USER_KEY}"
  --form-string "title=${TITLE}"
  --form-string "message=${MESSAGE}"
  --form-string "priority=${PRIORITY}"
)

# Emergency priority is rejected unless retry/expire accompany it.
if [[ "$PRIORITY" == "2" ]]; then
  args+=(--form-string "retry=${PUSHOVER_RETRY:-60}" --form-string "expire=${PUSHOVER_EXPIRE:-600}")
fi

# PUSHOVER_DEBUG=1 surfaces the API response instead of discarding it.
if [[ "${PUSHOVER_DEBUG:-0}" == "1" ]]; then
  curl -s -m 10 "${args[@]}" https://api.pushover.net/1/messages.json
  echo
else
  curl -s -m 10 "${args[@]}" https://api.pushover.net/1/messages.json > /dev/null 2>&1 || true
fi

exit 0
