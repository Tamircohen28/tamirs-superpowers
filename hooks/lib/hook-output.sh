#!/usr/bin/env bash
# Claude Code / Cursor / Codex hook JSON helpers.
#
# Cursor fail-closes when preToolUse stdout is empty or non-JSON.
# Claude Code treats empty stdout as allow. Codex requires a Stop or
# SubagentStop hook that exits 0 to print JSON (plain text fails the hook).
# Always emit valid JSON.
#
# Usage (after reading stdin into HOOK_INPUT):
#   source "$(dirname "$0")/lib/hook-output.sh"
#   hook_detect_platform "$HOOK_INPUT"     # HOOK_PLATFORM=claude|cursor|codex
#   hook_allow
#   hook_deny "reason"
#   hook_additional_context "message"
#   hook_stop_ok                            # Stop/SubagentStop: nothing to decide
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

# hook_detect_platform <payload> — sets and exports HOOK_PLATFORM: claude
# (the default), cursor or codex.
#
#   cursor  payload keys only Cursor sends: conversation_id, cursor_version,
#           workspace_roots.
#   codex   PLUGIN_ROOT or PLUGIN_DATA exported in the hook's environment.
#           Codex's hooks doc (learn.chatgpt.com/docs/hooks) names them "a
#           Codex-specific extension" set for plugin hook commands, beside the
#           CLAUDE_PLUGIN_ROOT/CLAUDE_PLUGIN_DATA it also sets "for compatibility
#           with existing plugin hooks". Claude Code exports only the CLAUDE_*
#           pair, and Cursor's plugin reference says it does not expand the
#           Codex pair. Measured on codex-cli 0.163.0
#           (2026-10-17, tests/fixtures/codex/README.md): every plugin hook ran
#           with PLUGIN_ROOT, PLUGIN_DATA, CLAUDE_PLUGIN_ROOT, CLAUDE_PLUGIN_DATA
#           and CODEX_HOME in its environment. Fallback when neither variable is
#           exported (a hook run by hand with a captured payload): a `turn_id`
#           key in the payload, which the same doc lists as a Codex-specific
#           extension and which every measured turn-scoped payload carried;
#           Claude Code's payloads have no such key.
#
#   Cursor is checked first: its payload keys are the only positive Cursor
#   signal, and a Cursor host exports no PLUGIN_ROOT. The environment check asks
#   `declare -p` whether the variable exists rather than expanding it: the plugin
#   directory reads an expansion of the root variable that carries a modifier
#   inside its braces as a path to the plugin root and holds the file (COMMAND_NAMES_MOD_FILE,
#   5.0.2 report). The environment check
#   precedes the payload fallback because a hook can be handed an empty payload
#   (hook_read_stdin's bounded read) and still owes the right dialect.
#
#   The codex dialect today answers exactly like claude: Codex accepts the same
#   PreToolUse deny shape (permissionDecision + a non-empty reason) and reads
#   `{}` as "no decision" on every event. What it adds is the name, so a hook
#   can branch where Codex is stricter — see hook_stop_ok.
hook_detect_platform() {
  local input="${1:-}"
  HOOK_PLATFORM=claude
  if printf '%s' "$input" | jq -e '(.conversation_id // .cursor_version // .workspace_roots) != null' >/dev/null 2>&1; then
    HOOK_PLATFORM=cursor
  elif declare -p PLUGIN_ROOT >/dev/null 2>&1 || declare -p PLUGIN_DATA >/dev/null 2>&1; then
    HOOK_PLATFORM=codex
  elif printf '%s' "$input" | jq -e '.turn_id != null' >/dev/null 2>&1; then
    HOOK_PLATFORM=codex
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

# hook_stop_ok — the exit-0 answer of a Stop/SubagentStop hook with nothing
# to decide. Prints exactly one JSON object and exits 0.
#
#   Codex's hooks doc: Stop and SubagentStop "must print JSON on exit 0, plain
#   text is invalid" — a bare `exit 0` after advisory text on stderr is fine,
#   but any non-JSON byte on stdout fails the hook. Its parser (hooks/src/
#   events/stop.rs, read at rust-v0.163.0) tolerates empty stdout, but the doc
#   does not promise that, so this prints `{}` rather than nothing. `{}` is the
#   one answer that is a no-op on every host: Claude Code reads it as "no
#   decision", Codex parses an object with no continue/decision/systemMessage
#   and does nothing, and Cursor's stop event takes `{}` as "nothing to add" too. Advisory
#   text belongs on stderr, as check-done.sh already does.
hook_stop_ok() {
  printf '%s\n' '{}'
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
