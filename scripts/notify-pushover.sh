#!/usr/bin/env bash
# notify-pushover.sh — Notification hook that pushes to your phone via Pushover.
#
# Complements hooks/notify.sh (macOS desktop banner) rather than replacing it:
# the banner catches you at the machine, this catches you away from it.
#
# Reads Claude Code's Notification hook JSON on stdin. Falls back to
# $1/$2 (message / priority-name) when stdin is empty.
#
# Credentials are read from, in order of precedence:
#   1. PUSHOVER_TOKEN / PUSHOVER_USER already in the environment
#   2. CLAUDE_PLUGIN_OPTION_PUSHOVER_TOKEN / _USER  (userConfig, Keychain-backed)
#   3. $PUSHOVER_ENV                    (override, mainly for tests)
#   4. ~/.claude/pushover.env           (written by scripts/install.sh)
#
# They deliberately live OUTSIDE the plugin directory: the marketplace cache
# lives at ~/.claude/plugins/cache/.../<version>/ and is replaced wholesale on
# every plugin update, which would take any credentials stored here with it.
#
# Source 2 is the manifest's `userConfig` block, declared with "sensitive": true,
# which the host stores in the macOS Keychain (falling back to
# ~/.claude/.credentials.json) and exports to hook processes as
# CLAUDE_PLUGIN_OPTION_<KEY>. That satisfies the same constraint by a better
# route than a 600-mode dotfile, and it is prompted for once at enable time
# rather than passed as an env var through `make install`.
#
# It is inserted ABOVE the file and BELOW an explicit environment override: a
# caller that exports PUSHOVER_TOKEN directly (a test, a CI job) still wins, and
# an existing install whose credentials are already in pushover.env keeps working
# untouched. Nothing here is Claude-only in a breaking way either - Codex also
# loads this hook and simply never sets the variable, so it falls through.
#
# Exits 0 and stays silent when unconfigured, so an un-set-up install never
# breaks the notification chain.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CREDS="${PUSHOVER_ENV:-${HOME}/.claude/pushover.env}"
FORMATTER="${PUSHOVER_FORMATTER:-${SCRIPT_DIR}/pushover_format.py}"

# Host-managed userConfig values, when the host provides them.
if [[ -z "${PUSHOVER_TOKEN:-}" ]]; then
  PUSHOVER_TOKEN="${CLAUDE_PLUGIN_OPTION_PUSHOVER_TOKEN:-}"
fi
if [[ -z "${PUSHOVER_USER:-}" ]]; then
  PUSHOVER_USER="${CLAUDE_PLUGIN_OPTION_PUSHOVER_USER:-}"
fi

# The file fills in only what is still missing. Sourcing it plainly would
# overwrite a value that a higher-precedence source already supplied: with a
# token from the environment but no user, the `-z USER` arm fires and the file's
# token silently replaces it. That was reachable before userConfig existed and is
# more reachable now, so the pre-file values are restored afterwards.
if [[ -z "${PUSHOVER_TOKEN:-}" || -z "${PUSHOVER_USER:-}" ]] && [[ -f "$CREDS" ]]; then
  _pre_token="${PUSHOVER_TOKEN:-}"
  _pre_user="${PUSHOVER_USER:-}"
  # shellcheck source=/dev/null
  . "$CREDS"
  [[ -n "$_pre_token" ]] && PUSHOVER_TOKEN="$_pre_token"
  [[ -n "$_pre_user" ]] && PUSHOVER_USER="$_pre_user"
  unset _pre_token _pre_user
fi

# Unconfigured is a normal state, not an error — bail quietly.
if [[ -z "${PUSHOVER_TOKEN:-}" || -z "${PUSHOVER_USER:-}" ]]; then
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
  --form-string "token=${PUSHOVER_TOKEN}"
  --form-string "user=${PUSHOVER_USER}"
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
