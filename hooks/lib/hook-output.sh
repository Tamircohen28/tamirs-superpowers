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
#
# Hook tiers (plugin options, read by the bash hooks — never by the mod):
#   hook_tier_enabled notification|contributor   # 0 = on, 1 = off
#   hook_tier_gate    notification|contributor [silent|allow|suppress]
#
#   Claude Code exports every manifest `userConfig` option to a hook as
#   CLAUDE_PLUGIN_OPTION_<NAME>; the two boolean tier options arrive as
#   CLAUDE_PLUGIN_OPTION_NOTIFICATION_HOOKS (default true) and
#   CLAUDE_PLUGIN_OPTION_CONTRIBUTOR_HOOKS (default false). A host with no
#   userConfig (the Codex CLI, Cursor) exports nothing, so the default applies
#   there — a tier is an option on Claude Code and a constant elsewhere.
#   Core-safety, worktree-lifecycle and user-facing convenience hooks never
#   call these; see docs/engineering/architecture/hooks-classification.md.

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

# hook_tier_enabled <tier> — 0 when the tier's hooks should run, 1 when not.
#
#   Reads the tier's CLAUDE_PLUGIN_OPTION_* variable. Accepts true/false, 1/0,
#   yes/no and on/off in any case; unset, empty or unrecognised falls back to
#   the tier's manifest default (notification: on, contributor: off). An
#   unknown tier name is never gated — a typo must not silence a hook.
hook_tier_enabled() {
  local tier="${1:-}" raw="" default=0 value
  case "$tier" in
    notification) raw="${CLAUDE_PLUGIN_OPTION_NOTIFICATION_HOOKS:-}"; default=0 ;;
    contributor)  raw="${CLAUDE_PLUGIN_OPTION_CONTRIBUTOR_HOOKS:-}";  default=1 ;;
    *) return 0 ;;
  esac
  # bash 3.2 (macOS) has no ${var,,}; tr is portable.
  value="$(printf '%s' "$raw" | tr '[:upper:]' '[:lower:]')"
  case "$value" in
    true|1|yes|on)   return 0 ;;
    false|0|no|off)  return 1 ;;
    *)               return "$default" ;;
  esac
}

# hook_tier_gate <tier> [noop] — call first thing after stdin is read (and, for
# a PreToolUse guard, after hook_detect_platform). When the tier is off it
# emits the dialect-correct no-op and exits 0; when on it returns 0 and the
# hook carries on unchanged.
#
#   noop  silent    (default) nothing on stdout — PostToolUse, SessionStart,
#                   UserPromptSubmit and Notification hooks, where empty
#                   stdout already means "nothing to say" on every host.
#         allow     hook_allow's JSON for the detected platform — a PreToolUse
#                   guard, because Cursor fail-closes on empty stdout.
#         suppress  {"suppressOutput": true} — a hook that already answers
#                   with that shape when it has nothing to show.
hook_tier_gate() {
  local tier="${1:-}" noop="${2:-silent}"
  hook_tier_enabled "$tier" && return 0
  case "$noop" in
    allow)    hook_allow ;;
    suppress) printf '%s\n' '{"suppressOutput": true}' ;;
    *)        : ;;
  esac
  exit 0
}
