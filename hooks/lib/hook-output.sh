#!/usr/bin/env bash
# Claude Code / Cursor / Codex hook JSON helpers.
#
# Cursor fail-closes when preToolUse stdout is empty or non-JSON.
# Claude Code treats empty stdout as no decision. Codex requires a Stop or
# SubagentStop hook that exits 0 to print JSON (plain text fails the hook).
# Always emit valid JSON.
#
# HOW AN ANSWER IS PRINTED (the plugin directory's hook-permission rule)
#   Every helper prints its whole answer with ONE command: a jq program for an
#   answer that carries a reason, a single echo of a fixed literal otherwise.
#   No printf format conversions, nothing merged from stderr into stdout, and
#   no helper here can approve a tool call: the no-decision answer is `{}` on
#   every host, so the host's own permission flow decides. Diagnostics go to
#   stderr only.
#
# Usage (after reading stdin into HOOK_INPUT):
#   source "$(dirname "$0")/lib/hook-output.sh"
#   hook_detect_platform "$HOOK_INPUT"     # HOOK_PLATFORM=claude|cursor|codex
#   hook_pass                               # no decision: `{}` on every host
#   hook_deny "reason"
#   hook_ask "reason"                       # Claude only; a deny on every other host
#   hook_ask_carried                        # 0 when hook_ask would print an ask here
#   hook_cursor_ask "reason"                # Cursor beforeShellExecution ask, when the caller knows it holds
#   hook_additional_context "message"
#   hook_stop_ok                            # Stop/SubagentStop: nothing to decide
#
# Hook tiers (plugin options, read by the bash hooks — never by the mod):
#   hook_tier_enabled notification|contributor   # 0 = on, 1 = off
#   hook_tier_gate    notification|contributor [silent|pass|suppress]
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
#   fail-closes on empty stdout. So a guard that would have let the call through
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

  # A here-string adds one trailing newline; every caller reads this through
  # $(...), which strips trailing newlines, so the caller sees the same bytes.
  cat <<<"$buf"
}

# hook_detect_platform <payload> — sets and exports HOOK_PLATFORM: claude
# (the default), cursor or codex.
#
#   cursor  payload keys only Cursor sends: conversation_id, cursor_version,
#           workspace_roots.
#   codex   CODEX_HOME exported in the hook's environment. Codex's hooks doc
#           (learn.chatgpt.com/docs/hooks) sets it for every hook command, beside
#           the Codex-specific plugin variables and the Claude-compatible pair it
#           also exports; Claude Code and Cursor export none of them. Measured on
#           codex-cli 0.163.0 (2026-10-17, tests/fixtures/codex/README.md): every
#           plugin hook ran with CODEX_HOME in its environment. agent-claim.sh and
#           doctor.sh read the same variable as the Codex signal. Fallback when it
#           is not exported (a hook run by hand with a captured payload): a
#           `turn_id` key in the payload, which the same doc lists as a
#           Codex-specific extension and which every measured turn-scoped payload
#           carried; Claude Code's payloads have no such key.
#
#   Cursor is checked first: its payload keys are the only positive Cursor
#   signal, and a Cursor host exports no CODEX_HOME. Earlier versions tested the
#   Codex plugin-root variable instead; the plugin directory reads any mention of a
#   plugin-root variable that is not a full path to one file as a path to the root
#   folder, which holds the mod, and held this file for it (COMMAND_NAMES_MOD_FILE,
#   5.0.2 and 5.0.3 reports), so this file names no plugin-root variable at all.
#   The environment check precedes the payload fallback because a hook can be handed an empty payload
#   (hook_read_stdin's bounded read) and still owes the right dialect.
#
#   The codex dialect today answers exactly like claude: Codex accepts the same
#   PreToolUse deny shape (permissionDecision + a non-empty reason) and reads
#   `{}` as "no decision" on every event. What it adds is the name, so a hook
#   can branch where Codex is stricter — see hook_stop_ok.
hook_detect_platform() {
  local input="${1:-}"
  HOOK_PLATFORM=claude
  if jq -e '(.conversation_id // .cursor_version // .workspace_roots) != null' <<<"$input" >/dev/null 2>/dev/null; then
    HOOK_PLATFORM=cursor
  elif [[ -n "${CODEX_HOME:-}" ]]; then
    HOOK_PLATFORM=codex
  elif jq -e '.turn_id != null' <<<"$input" >/dev/null 2>/dev/null; then
    HOOK_PLATFORM=codex
  fi
  export HOOK_PLATFORM
}

# hook_host_bypass INPUT — true when Claude Code itself runs this call in bypassPermissions mode
# (5.6.7). The mode is read from the host's payload, never from an environment variable a cloned
# repo's settings could set; only the Claude dialect carries it. A guard that honours it steps
# aside for what can be undone and keeps judging what cannot.
hook_host_bypass() {
  [ "${HOOK_PLATFORM:-claude}" = "claude" ] &&
    [ "$(jq -r '.permission_mode // empty' <<<"${1:-}" 2>/dev/null)" = "bypassPermissions" ]
}

# The PreToolUse answer shapes, as jq programs over $reason. The helpers below print one each;
# hooks/permission-guard.sh's batch entries (--judge-batch) render many at once through these
# same programs, so a batch answer and a hook answer are the same bytes once compacted and the
# two cannot drift. HOOK_JQ_PASS is the no-decision answer, the same `{}` on every host,
# Cursor included: Cursor reads `{}` as no decision and runs its own flow (measured on
# beforeShellExecution, Cursor 3.28.7, S2 runs 4 and 6 in
# docs/engineering/research/permissions/spikes/implementation-measurements.md), and its hooks
# reference marks no output field required. $reason in each is jq's variable, bound by --arg at
# the call (SC2016).
# shellcheck disable=SC2034  # for permission-guard.sh's batch renderer, beside the other shapes
HOOK_JQ_PASS='{}'
# shellcheck disable=SC2016
HOOK_JQ_DENY='{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"deny",permissionDecisionReason:$reason}}'
# shellcheck disable=SC2016
HOOK_JQ_ASK='{hookSpecificOutput:{hookEventName:"PreToolUse",permissionDecision:"ask",permissionDecisionReason:$reason}}'
# shellcheck disable=SC2016
HOOK_JQ_CURSOR_DENY='{permission:"deny",user_message:$reason,agent_message:$reason}'
# shellcheck disable=SC2016
HOOK_JQ_CURSOR_ASK='{permission:"ask",user_message:$reason,agent_message:$reason}'

# hook_pass — PreToolUse: no decision, on every host. Prints `{}` and exits 0.
#
#   A fixed literal printed by one echo, so it needs no jq: a host without jq
#   still gets a well-formed answer. hook_allow is the older name, kept so its
#   callers need no change; it is the same function and prints the same `{}`.
hook_pass() {
  echo '{}'
  exit 0
}

hook_allow() { hook_pass; }

hook_deny() {
  local reason="$1"
  if [[ "${HOOK_PLATFORM:-claude}" == "cursor" ]]; then
    jq -n --arg reason "$reason" "$HOOK_JQ_CURSOR_DENY"
  else
    jq -n --arg reason "$reason" "$HOOK_JQ_DENY"
  fi
  exit 0
}

# hook_ask <reason> — PreToolUse: ask the human, on Claude Code only.
#
#   Claude Code honours a hook `ask` in every permission mode, bypass included,
#   and turns it into a deny when no human is present (measured, ADR 004 D8,
#   spike C4/U3). Every other host gets hook_deny with the same reason, because
#   none of them can carry an ask from a plugin hook (ADR 004 D8):
#     codex   an `ask` is rejected as unsupported and the call RUNS (fail open,
#             source-cited X1);
#     cursor  preToolUse drops `ask` (U1.4, S2), and Cursor's CLI runs a command
#             under --yolo whatever beforeShellExecution asks (measured S1); the
#             one Cursor ask that holds is hook_cursor_ask, below;
#     gemini  a hook `ask` hangs a headless run (G1), and hook input cannot tell
#             headless from interactive. Under gemini-wrap.sh HOOK_PLATFORM reads
#             claude (the payload is translated first), so Gemini is recognised by
#             the GEMINI_SESSION_ID / GEMINI_PROJECT_DIR it exports to every hook;
#             a variable that is wrongly present only turns an ask into a deny.
#
#   hook_ask_carried is the predicate alone (0 when hook_ask would print an ask), for a caller
#   that must know the delivered answer without printing it (permission-guard.sh's batch entry).
hook_ask_carried() {
  [[ "${HOOK_PLATFORM:-claude}" == "claude" && -z "${GEMINI_SESSION_ID:-}" && -z "${GEMINI_PROJECT_DIR:-}" ]]
}

hook_ask() {
  local reason="$1"
  if hook_ask_carried; then
    jq -n --arg reason "$reason" "$HOOK_JQ_ASK"
    exit 0
  fi
  hook_deny "$reason"
}

# hook_cursor_ask <reason> — Cursor beforeShellExecution: ask the human.
#
#   Cursor's desktop app shows a beforeShellExecution `ask` as an approval card in
#   Auto-Review, Allowlist and Run Everything alike, and runs the command only when
#   the user picks Run (measured S2, 2026-11-04, Cursor 3.28.7). That holds for that
#   event on the desktop app only: preToolUse drops an ask, and the CLI ignores one
#   under --yolo (S1). So this helper does not decide; the caller does
#   (hooks/permission-guard.sh: desktop >= 3.28.7, beforeShellExecution), and every
#   other Cursor answer stays hook_deny. The Allowlist card shows the command but
#   not the reason, so a caller also writes the reason to stderr.
hook_cursor_ask() {
  jq -n --arg reason "$1" "$HOOK_JQ_CURSOR_ASK"
  exit 0
}

hook_additional_context() {
  local msg="$1"
  if [[ "${HOOK_PLATFORM:-claude}" == "cursor" ]]; then
    # Cursor preToolUse has no additional_context; agent_message is closest. No
    # permission field: the answer is no decision plus a note, as on every host.
    jq -n --arg msg "$msg" '{agent_message:$msg}'
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
  echo '{}'
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
  # bash 3.2 (macOS) has no ${var,,}; tr is portable. $(...) drops the
  # here-string's trailing newline.
  value="$(tr '[:upper:]' '[:lower:]' <<<"$raw")"
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
#         pass      hook_pass's `{}` — a PreToolUse guard, because Cursor
#                   fail-closes on empty stdout. The older spelling of this
#                   argument is still read, so its callers need no change.
#         suppress  {"suppressOutput": true} — a hook that already answers
#                   with that shape when it has nothing to show.
hook_tier_gate() {
  local tier="${1:-}" noop="${2:-silent}"
  hook_tier_enabled "$tier" && return 0
  case "$noop" in
    pass|allow) hook_pass ;;
    suppress)   echo '{"suppressOutput": true}' ;;
    *)        : ;;
  esac
  exit 0
}
