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

# hook_read_stdin — the whole payload, or "" if none arrives in time.
#
# A FAITHFUL DROP-IN FOR $(cat), MINUS THE HANG.
#   `input=$(cat)` waits for EOF. A hook is normally handed JSON and a closed
#   descriptor, so it returns instantly — but when it does not (a harness that
#   forgets to close stdin, an inherited terminal, a hand-run invocation while
#   debugging), the hook blocks until the harness kills it.
#
#   For a PreToolUse guard that is not merely slow, it is WRONG: a killed hook
#   writes nothing to stdout, and per this file's own contract Cursor
#   fail-closes on empty stdout. So a guard whose answer would have been ALLOW
#   instead DENIES the user's tool call, for a reason that has nothing to do
#   with what was being guarded. Bounding the read converts that into the
#   correct answer for an empty payload.
#
#   Newlines are preserved, so a pretty-printed multi-line JSON payload
#   survives exactly as `cat` would have delivered it. Bash's `read -t` is used
#   rather than `timeout(1)`, which is GNU coreutils and absent on macOS.
#
#   HOOK_STDIN_TIMEOUT overrides the per-line bound (seconds, default 2).
hook_read_stdin() {
  local timeout="${HOOK_STDIN_TIMEOUT:-2}" line buf=""

  # An interactive terminal on stdin means nobody is piping a payload; reading
  # would block on the user's keyboard.
  [[ -t 0 ]] && return 0

  while IFS= read -r -t "$timeout" line; do
    buf="${buf}${line}"$'\n'
  done
  # A final line with no trailing newline lands in $line, not in the loop.
  buf="${buf}${line}"

  printf '%s' "$buf"
}

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
