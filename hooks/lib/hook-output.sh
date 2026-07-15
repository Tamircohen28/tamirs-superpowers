#!/usr/bin/env bash
# Dual Claude Code / Cursor PreToolUse JSON helpers.
#
# Cursor fail-closes when preToolUse stdout is empty or non-JSON.
# Claude Code treats empty stdout as allow. Always emit valid JSON.
#
# Usage (after reading stdin into HOOK_INPUT):
#   source "$(dirname "$0")/lib/hook-output.sh"
#   hook_detect_platform "$HOOK_INPUT"
#   hook_allow
#   hook_deny "reason"
#   hook_additional_context "message"

hook_detect_platform() {
  local input="${1:-}"
  HOOK_PLATFORM=claude
  if printf '%s' "$input" | jq -e '(.conversation_id // .cursor_version // .workspace_roots) != null' >/dev/null 2>&1; then
    HOOK_PLATFORM=cursor
  fi
  export HOOK_PLATFORM
}

hook_allow() {
  if [[ "${HOOK_PLATFORM:-claude}" == "cursor" ]]; then
    printf '%s\n' '{"permission":"allow"}'
  else
    printf '%s\n' '{}'
  fi
  exit 0
}

hook_deny() {
  local reason="$1"
  if [[ "${HOOK_PLATFORM:-claude}" == "cursor" ]]; then
    jq -n --arg reason "$reason" \
      '{permission:"deny",user_message:$reason,agent_message:$reason}'
  else
    jq -n --arg reason "$reason" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
  fi
  exit 0
}

hook_additional_context() {
  local msg="$1"
  if [[ "${HOOK_PLATFORM:-claude}" == "cursor" ]]; then
    # Cursor preToolUse has no additional_context; agent_message is closest.
    jq -n --arg msg "$msg" '{permission:"allow",agent_message:$msg}'
  else
    jq -n --arg msg "$msg" \
      '{hookSpecificOutput:{hookEventName:"PreToolUse",additionalContext:$msg},systemMessage:$msg}'
  fi
  exit 0
}
