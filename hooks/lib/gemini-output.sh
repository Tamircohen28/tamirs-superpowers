#!/usr/bin/env bash
# Gemini CLI hook dialect: payload and envelope translation for hooks/gemini-wrap.sh.
#
# WHY A SEPARATE FILE AND NOT A THIRD BRANCH IN hook-output.sh
#   hook-output.sh is the Claude/Cursor dialect library every canonical guard
#   sources. Gemini is reached through a WRAPPER (hooks/gemini-wrap.sh) that
#   runs the canonical hook unmodified on a Claude-shaped payload and rewrites
#   the Claude-shaped answer into Gemini's envelope. That keeps every canonical
#   hook byte-identical across hosts, so a guard proven on Claude Code is the
#   same bytes that run on Gemini. This file holds only what the wrapper needs.
#
# THE GEMINI CONTRACT, MEASURED ON 0.64.0 (packages/core/src/hooks/*):
#   stdin   {session_id, transcript_path, cwd, hook_event_name, timestamp, ...}
#           BeforeTool/AfterTool add tool_name + tool_input (AfterTool: tool_response);
#           BeforeAgent: prompt; AfterAgent: prompt, prompt_response, stop_hook_active;
#           SessionStart: source; SessionEnd: reason; Notification: notification_type,
#           message, details; PreCompress: trigger.
#   tools   write_file {file_path, content}; replace {file_path, instruction,
#           old_string, new_string, allow_multiple}; run_shell_command {command,
#           description, dir_path, is_background}.
#   stdout  exactly one JSON object. {} = allow. {"decision":"deny","reason":...}
#           blocks (alias "block"; "ask" exists too). additionalContext lives under
#           hookSpecificOutput with the event's own hookEventName, and only
#           AfterTool, BeforeAgent and SessionStart define it — BeforeTool's
#           hookSpecificOutput carries tool_input only, so a BeforeTool note goes
#           out as systemMessage (shown to the user, never to the model).
#   exit    0 parses stdout; 1 is a warning + allow; 2 AND EVERY OTHER non-zero
#           code is a deny with stderr as the reason. Claude's "non-2 non-zero is
#           a non-blocking error" does not hold here, which is why the wrapper
#           always exits 0 and encodes the decision in the JSON instead.
#   env     GEMINI_PROJECT_DIR, GEMINI_CWD, GEMINI_SESSION_ID, GEMINI_PLANS_DIR and
#           CLAUDE_PROJECT_DIR (alias) are set for every hook process.
#   text    plain text on stdout makes the parse fail and the CLI default to
#           allow, treating the whole output as a systemMessage.
#
# Usage:
#   source "$(dirname "$0")/lib/gemini-output.sh"
#   gemini_is_gemini "$payload"           # 0 on Gemini, 1 elsewhere
#   gemini_translate_input "$payload"     # Gemini payload -> Claude payload (stdout)
#   gemini_translate_output BeforeTool "$claude_stdout"   # Claude answer -> Gemini JSON
#   gemini_allow | gemini_deny "reason" | gemini_additional_context BeforeAgent "msg"

# gemini_read_stdin — the whole payload, or "" if none arrives in time.
# Same contract as hook_read_stdin in hook-output.sh (bounded, newline-preserving,
# no hang on an inherited terminal); duplicated so this file stands alone.
gemini_read_stdin() {
  local timeout="${HOOK_STDIN_TIMEOUT:-2}" line buf=""
  [[ -t 0 ]] && return 0
  while IFS= read -r -t "$timeout" line; do
    buf="${buf}${line}"$'\n'
  done
  buf="${buf}${line}"
  printf '%s' "$buf"
}

# The event vocabularies. The Claude side is this repo's canonical hooks.json;
# the Gemini side is HookEventName in 0.64.0 (and the `gemini hooks migrate
# --from-claude` EVENT_MAPPING shipped in the same build, which agrees).
GEMINI_EVENTS="BeforeTool AfterTool BeforeAgent AfterAgent BeforeModel AfterModel BeforeToolSelection SessionStart SessionEnd Notification PreCompress"

# gemini_claude_event <GeminiEvent> — the canonical (Claude) event name.
gemini_claude_event() {
  case "$1" in
    BeforeTool)  printf 'PreToolUse' ;;
    AfterTool)   printf 'PostToolUse' ;;
    BeforeAgent) printf 'UserPromptSubmit' ;;
    AfterAgent)  printf 'Stop' ;;
    PreCompress) printf 'PreCompact' ;;
    *)           printf '%s' "$1" ;;
  esac
}

# gemini_event_for <ClaudeEvent> — the Gemini event, or "" when Gemini has none.
gemini_event_for() {
  case "$1" in
    PreToolUse)       printf 'BeforeTool' ;;
    PostToolUse)      printf 'AfterTool' ;;
    UserPromptSubmit) printf 'BeforeAgent' ;;
    Stop)             printf 'AfterAgent' ;;
    PreCompact)       printf 'PreCompress' ;;
    SessionStart|SessionEnd|Notification) printf '%s' "$1" ;;
    *)                printf '' ;;
  esac
}

# gemini_is_gemini [payload] — 0 when this process was started by Gemini CLI.
# The environment is the primary signal (Gemini exports GEMINI_SESSION_ID and
# GEMINI_PROJECT_DIR to every hook; no other host does). The payload is the
# fallback for a hand-run invocation: a hook_event_name from Gemini's own list
# that Claude does not have.
gemini_is_gemini() {
  local payload="${1:-}" ev
  [[ -n "${GEMINI_SESSION_ID:-}" || -n "${GEMINI_PROJECT_DIR:-}" ]] && return 0
  [[ -n "$payload" ]] || return 1
  ev="$(printf '%s' "$payload" | jq -r '.hook_event_name // empty' 2>/dev/null)"
  case " $GEMINI_EVENTS " in
    *" $ev "*) [[ "$(gemini_claude_event "$ev")" != "$ev" ]] && return 0 ;;
  esac
  return 1
}

# gemini_translate_input <gemini-payload> — a Claude-shaped payload on stdout.
#
#   tool_name   write_file -> Write, replace -> Edit, run_shell_command -> Bash;
#               anything else (an MCP tool, read_file, ...) passes through, so an
#               unmapped name stays visibly foreign instead of being coerced.
#   tool_input  write_file and replace already use `file_path`, which is the key
#               every canonical guard reads (and write-targets.py's first
#               EDIT_PATH_KEYS entry); content/old_string/new_string pass through.
#               run_shell_command's `command` is the key the Bash guards read; its
#               `dir_path`, when set, becomes the payload `cwd`, because that is
#               the directory the command will actually run in and the canonical
#               guards judge the cwd (resolved against the session cwd when
#               relative).
#   hook_event_name  BeforeTool -> PreToolUse etc., so a hook that branches on
#               the event name sees the vocabulary it was written against.
#   cwd         falls back to GEMINI_CWD, then GEMINI_PROJECT_DIR, when absent.
gemini_translate_input() {
  local payload="${1:-}"
  [[ -n "$payload" ]] || payload='{}'
  printf '%s' "$payload" | jq -c \
    --arg cwd_env "${GEMINI_CWD:-${GEMINI_PROJECT_DIR:-}}" '
    {"write_file":"Write","replace":"Edit","run_shell_command":"Bash"} as $tool
    | {"BeforeTool":"PreToolUse","AfterTool":"PostToolUse","BeforeAgent":"UserPromptSubmit",
       "AfterAgent":"Stop","PreCompress":"PreCompact"} as $ev
    | . as $in
    | (if (.cwd // "") == "" and $cwd_env != "" then .cwd = $cwd_env else . end)
    | (if has("tool_name") and (.tool_name|type) == "string"
       then .tool_name = ($tool[.tool_name] // .tool_name) else . end)
    | (if has("hook_event_name") and (.hook_event_name|type) == "string"
       then .hook_event_name = ($ev[.hook_event_name] // .hook_event_name) else . end)
    | (if $in.tool_name == "run_shell_command"
          and ((.tool_input // {}) | type) == "object"
          and ((.tool_input.dir_path // "") | type) == "string"
          and (.tool_input.dir_path // "") != ""
       then .cwd = (if (.tool_input.dir_path | startswith("/")) then .tool_input.dir_path
                    elif (.cwd // "") != "" then (.cwd | rtrimstr("/")) + "/" + .tool_input.dir_path
                    else .tool_input.dir_path end)
       else . end)
    | .gemini_tool_name = ($in.tool_name // null)
    | del(.gemini_tool_name | select(. == null))
  '
}

# gemini_translate_output <GeminiEvent> <claude-stdout> — exactly one Gemini JSON
# object on stdout. Non-JSON or empty input is an allow ({}); the wrapper forwards
# any such text to stderr so nothing is lost and nothing breaks the parse.
#
#   Claude                                    Gemini
#   hookSpecificOutput.permissionDecision     decision: deny (+ reason)
#     "deny" / decision "block"|"deny"
#   hookSpecificOutput.permissionDecision     decision: ask (+ reason)
#     "ask"
#   hookSpecificOutput.additionalContext      AfterTool/BeforeAgent/SessionStart:
#                                               hookSpecificOutput{hookEventName,
#                                               additionalContext}
#                                             every other event: systemMessage
#                                             (not repeated when the hook already
#                                             put the same text in systemMessage,
#                                             as hook_additional_context does)
#   hookSpecificOutput.updatedInput           BeforeTool: hookSpecificOutput.tool_input
#   systemMessage, suppressOutput, continue,  unchanged
#     stopReason
#   hookEventName, terminalSequence, ...      dropped (Claude-only)
gemini_translate_output() {
  local event="${1:-}" text="${2:-}"
  if [[ -z "${text//[[:space:]]/}" ]] \
     || ! printf '%s' "$text" | jq -e 'type == "object"' >/dev/null 2>&1; then
    printf '{}\n'
    return 0
  fi
  printf '%s' "$text" | jq -c --arg ev "$event" '
    . as $c
    | ($c.hookSpecificOutput // {}) as $h
    | ($h.permissionDecision // null) as $pd
    | ($h.additionalContext // null) as $ac
    | {}
    | (if $pd == "deny" or $c.decision == "block" or $c.decision == "deny" then
         .decision = "deny"
         | .reason = ($h.permissionDecisionReason // $c.reason // $c.stopReason
                      // "Blocked by a tamirs-superpowers hook.")
       elif $pd == "ask" then
         .decision = "ask" | .reason = ($h.permissionDecisionReason // $c.reason // "")
       else . end)
    | (if $ac != null then
         (if ($ev == "AfterTool" or $ev == "BeforeAgent" or $ev == "SessionStart") then
            .hookSpecificOutput = {hookEventName: $ev, additionalContext: $ac}
          else
            .systemMessage = (if $c.systemMessage == null or $c.systemMessage == $ac then $ac
                              else $c.systemMessage + "\n" + $ac end)
          end)
       else . end)
    | (if $ev == "BeforeTool" and ($h.updatedInput // null) != null then
         .hookSpecificOutput = {hookEventName: "BeforeTool", tool_input: $h.updatedInput}
       else . end)
    | (if $c.systemMessage != null and .systemMessage == null then .systemMessage = $c.systemMessage else . end)
    | (if $c.suppressOutput != null then .suppressOutput = $c.suppressOutput else . end)
    | (if $c.continue != null then .continue = $c.continue else . end)
    | (if $c.stopReason != null then .stopReason = $c.stopReason else . end)
  '
}

# The three emitters, for a hook that targets Gemini directly. They print one
# JSON object and exit 0, like hook_allow/hook_deny/hook_additional_context.
gemini_allow() {
  printf '{}\n'
  exit 0
}

gemini_deny() {
  jq -cn --arg reason "${1:-Blocked by a tamirs-superpowers hook.}" '{decision:"deny", reason:$reason}'
  exit 0
}

# gemini_additional_context <GeminiEvent> <msg>
gemini_additional_context() {
  local event="${1:-}" msg="${2:-}"
  case "$event" in
    AfterTool|BeforeAgent|SessionStart)
      jq -cn --arg ev "$event" --arg msg "$msg" '{hookSpecificOutput:{hookEventName:$ev, additionalContext:$msg}}' ;;
    *)
      jq -cn --arg msg "$msg" '{systemMessage:$msg}' ;;
  esac
  exit 0
}
