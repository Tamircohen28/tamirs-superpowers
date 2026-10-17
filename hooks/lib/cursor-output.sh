#!/usr/bin/env bash
# cursor-output.sh — Cursor-only output helpers for the events hook-output.sh
# does not cover.
#
# hook-output.sh owns the PreToolUse dialect (permission / user_message /
# agent_message) that every tool guard shares across Claude Code and Cursor.
# The lifecycle and prompt events Cursor offers speak different shapes, and
# every one of them is documented at https://cursor.com/docs/agent/hooks:
#
#   beforeSubmitPrompt  out  continue (boolean), user_message
#   sessionStart        out  env (applies to later hooks), additional_context
#   sessionEnd          out  (nothing — fire-and-forget)
#   stop                out  followup_message  ("auto-submitted as next user message")
#   subagentStart       out  permission (ask = deny), user_message
#   subagentStop        out  followup_message  ("consumed only when completed")
#   preCompact          out  user_message      (observational)
#   workspaceOpen       out  pluginPaths       (absolute paths to load)
#
# TWO RULES EVERY HELPER HERE ENFORCES
#   1. An advisory hook NEVER writes `followup_message`. On Claude a Stop hook's
#      output is advice the model may read; on Cursor `followup_message` is
#      re-submitted AS THE USER'S NEXT MESSAGE, which turns a reminder into an
#      instruction the user never typed. The Stop-family helpers below therefore
#      emit `user_message` only, and the Cursor lifecycle test asserts that no
#      hook in the bundle ever emits `followup_message`.
#   2. One JSON object per call, then exit 0. Cursor's permission hooks block on
#      invalid JSON or a schema mismatch whatever `failClosed` says, and the
#      documented block route for beforeSubmitPrompt is `continue:false` on
#      exit 0 — not exit 2, whose reason delivery is undocumented for that event.
#
# Usage (after reading stdin and calling hook_detect_platform from hook-output.sh):
#   source "${SCRIPT_DIR}/lib/cursor-output.sh"
#   [ "${HOOK_PLATFORM:-claude}" = cursor ] && cursor_prompt_block "reason"
#
# Every helper exits, like hook_allow/hook_deny do, so a caller branches with
# `[ cursor ] && cursor_x "..."` and lets the Claude path follow unchanged.

# cursor_prompt_block <msg> — beforeSubmitPrompt: refuse the prompt, show why.
cursor_prompt_block() {
  jq -n --arg m "$1" '{continue:false,user_message:$m}'
  exit 0
}

# cursor_prompt_pass [msg] — beforeSubmitPrompt: let the prompt through, with an
# optional note to the user. Cursor has no additional_context on this event, so
# a message here reaches the USER, not the model — word it for them.
cursor_prompt_pass() {
  if [ -n "${1:-}" ]; then
    jq -n --arg m "$1" '{continue:true,user_message:$m}'
  else
    printf '%s\n' '{"continue":true}'
  fi
  exit 0
}

# cursor_session_context <msg> [env-json-object] — sessionStart: inject context
# and, when given, a JSON object of environment variables Cursor applies to the
# later hooks of the session.
cursor_session_context() {
  local msg="$1" env="${2:-}"
  if [ -n "$env" ] && printf '%s' "$env" | jq -e 'type == "object"' >/dev/null 2>&1; then
    jq -n --arg m "$msg" --argjson e "$env" '{additional_context:$m,env:$e}'
  else
    jq -n --arg m "$msg" '{additional_context:$m}'
  fi
  exit 0
}

# cursor_stop_note <msg> — stop / preCompact: a note to the user. Deliberately
# never followup_message (see rule 1 above).
cursor_stop_note() {
  jq -n --arg m "$1" '{user_message:$m}'
  exit 0
}

# cursor_subagent_note <msg> — subagentStart / subagentStop: a note to the user
# that neither denies the spawn nor injects a follow-up. Never followup_message.
cursor_subagent_note() {
  jq -n --arg m "$1" '{user_message:$m}'
  exit 0
}

# cursor_plugin_paths [path...] — workspaceOpen: the plugin directories to load.
# No arguments yields {"pluginPaths":[]}, the documented "nothing to add".
cursor_plugin_paths() {
  if [ "$#" -eq 0 ]; then
    printf '%s\n' '{"pluginPaths":[]}'
  else
    printf '%s\n' "$@" | jq -R . | jq -s '{pluginPaths:.}'
  fi
  exit 0
}

# cursor_silent — nothing on stdout, exit 0. For sessionEnd, which documents no
# output at all, and for any advisory path that has nothing to say.
cursor_silent() {
  exit 0
}
