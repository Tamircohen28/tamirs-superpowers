#!/usr/bin/env bash
# Notification hook — show a macOS notification when Claude needs attention.
# Uses terminalSequence for terminal-native output (supported v2.1.141+),
# with an osascript fallback for older Claude Code versions.
# Prefixes the message with the task slug so you can tell which session pinged
# you when several are running in parallel.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/worktree-common.sh
source "${SCRIPT_DIR}/lib/worktree-common.sh"

input="$(cat)"
title="$(echo "$input" | jq -r '.title // "Claude Code"')"
message="$(echo "$input" | jq -r '.message // "Claude needs your attention"')"
session_id="$(echo "$input" | jq -r '.session_id // empty')"

# Resolve the task slug: env first, then persisted session state.
task_slug="${CLAUDE_TASK_SLUG:-${CLAUDE_SESSION_SLUG:-}}"
if [[ -z "$task_slug" && -n "$session_id" ]]; then
  state="$(load_session_state "$session_id")"
  task_slug="$(echo "$state" | jq -r '.task_slug // .session_slug // empty')"
fi
if [[ -n "$task_slug" && "$task_slug" != "null" ]]; then
  message="${task_slug}: ${message}"
fi

# Sanitize for shell embedding
title_safe="${title//\"/\\\"}"
message_safe="${message//\"/\\\"}"

# Primary: terminalSequence for desktop notification via terminal OSC
# (avoids shell injection; terminal routes this to the OS notification system)
notify_osc="$(printf '\033]99;i=1:d=0;%s\033\\' "${title_safe}: ${message_safe}" 2>/dev/null || true)"

if [[ -n "$notify_osc" ]]; then
  jq -n \
    --arg seq "$notify_osc" \
    '{"hookSpecificOutput": {"hookEventName": "Notification", "terminalSequence": $seq}}'
else
  # Fallback: osascript (macOS only)
  osascript -e "display notification \"${message_safe}\" with title \"${title_safe}\" sound name \"Glass\"" 2>/dev/null || true
  echo '{"hookSpecificOutput": {"hookEventName": "Notification"}}'
fi
