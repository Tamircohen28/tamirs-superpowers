#!/usr/bin/env bash
# test-cursor-lifecycle.sh — every hook platforms/cursor/hooks.json wires, fed
# the Cursor payload for its event, must answer in Cursor's dialect.
#
# WHY A SWEEP OVER THE BUNDLE AND NOT A CASE PER HOOK
#   The bundle is the contract: an entry in it is a promise that the script
#   behind it understands Cursor's payload for that event and answers with the
#   fields Cursor documents for it — nothing else. A hook ported for Claude's
#   SessionStart that still prints hookSpecificOutput on Cursor's sessionStart
#   is not wrong on Claude and not an error on Cursor; it is a hook whose whole
#   output is silently dropped, which looks exactly like a hook that works. So
#   this reads the bundle from disk, runs every entry against every fixture for
#   its event (tests/fixtures/cursor/<event>*.json, rewritten onto a temp repo),
#   and asserts the envelope. A hook added to the bundle tomorrow is judged the
#   day it lands.
#
# WHAT IS ASSERTED, PER RUN
#   - exit 0 or 2 (2 is Cursor's documented "block", and only a guard may use it)
#   - stdout is EMPTY or exactly ONE JSON object
#   - that object's keys are a subset of what Cursor documents for the event
#     (a short tolerated list, each with a reason, is reported as a warning)
#   - no hook, on any event, ever emits followup_message: on Cursor that is
#     re-submitted as the user's next message, and nothing here is allowed to
#     speak for the user
#
# PLUS THE SPECIFIC BEHAVIOURS THE PORT EXISTS FOR
#   goal-condition-lint refuses an unsatisfiable /goal with continue:false;
#   skill-suggest and scope-decompose pass with continue:true and a note; the
#   session lifecycle keys state the way the tool guards do; workspaceOpen
#   returns pluginPaths; the safety tier carries failClosed; and the Claude
#   envelope of every ported hook is unchanged.
#
# Hermetic: temp HOME, temp plugin-data and claim dirs, a temp git repo as the
# workspace, no network, no model calls.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$ROOT/tests/lib/harness.sh"

harness_require jq git bash

B="$ROOT/platforms/cursor/hooks.json"
FX="$ROOT/tests/fixtures/cursor"
[ -f "$B" ] || { echo "FATAL: $B missing"; exit 1; }
[ -d "$FX" ] || { echo "FATAL: $FX missing"; exit 1; }

TMP="$(harness_tmpdir)"
export HOME="$TMP/home"
mkdir -p "$HOME/.claude"
export CLAUDE_PLUGIN_DATA="$TMP/plugin-data"
export AGENT_CLAIM_DIR="$TMP/claims"
mkdir -p "$CLAUDE_PLUGIN_DATA" "$AGENT_CLAIM_DIR"
export SUPERPOWERS_WORKTREE_CLEANUP=0
unset CLAUDE_ENV_FILE SUPERPOWERS_CURSOR_PLUGIN_PATH SUPERPOWERS_VALIDATION_TIER \
      CLAUDE_PLUGIN_OPTION_NOTIFICATION_HOOKS CLAUDE_PLUGIN_OPTION_CONTRIBUTOR_HOOKS 2>/dev/null || true

# The workspace every fixture points at. A real repo with one uncommitted code
# file, so the Stop-family hooks have something to say if they are going to.
WS="$TMP/project"
harness_new_repo "$WS"
printf '# project\n' > "$WS/README.md"
git -C "$WS" add README.md
git -C "$WS" -c user.email=t@e.invalid -c user.name=t commit -q -m readme
printf 'echo hi\n' > "$WS/changed.sh"

# payload <fixture-basename> — the fixture with /workspace/project rewritten
# onto the temp repo, in every string field.
payload() {
  jq --arg ws "$WS" \
    'walk(if type == "string" and startswith("/workspace/project") then ($ws + .[18:]) else . end)' \
    "$FX/$1.json"
}

OUT=""; ERR=""; RC=0
# run_hook <script> <fixture> [VAR=value ...] — stdout in OUT, stderr in ERR, rc in RC.
run_hook() {
  local script="$1" fixture="$2"; shift 2
  local errf="$TMP/err"
  OUT="$(cd "$WS" && payload "$fixture" | env "$@" bash "$ROOT/hooks/$script" 2>"$errf")"
  RC=$?
  ERR="$(cat "$errf")"
}

# claude_run <script> <json> — the same script on a Claude payload.
claude_run() {
  local errf="$TMP/err"
  OUT="$(cd "$WS" && printf '%s' "$2" | bash "$ROOT/hooks/$1" 2>"$errf")"
  RC=$?
  ERR="$(cat "$errf")"
}

# Cursor's documented output fields per event (https://cursor.com/docs/agent/hooks).
allowed_keys() {
  case "$1" in
    preToolUse)            echo "permission user_message agent_message updated_input" ;;
    beforeShellExecution)  echo "permission user_message agent_message" ;;
    beforeMCPExecution)    echo "permission user_message agent_message" ;;
    beforeReadFile)        echo "permission user_message" ;;
    postToolUse)           echo "updated_mcp_tool_output additional_context" ;;
    postToolUseFailure)    echo "additional_context" ;;
    subagentStart)         echo "permission user_message" ;;
    subagentStop)          echo "followup_message" ;;
    beforeSubmitPrompt)    echo "continue user_message" ;;
    stop)                  echo "followup_message" ;;
    sessionStart)          echo "env additional_context" ;;
    sessionEnd)            echo "" ;;
    preCompact)            echo "user_message" ;;
    workspaceOpen)         echo "pluginPaths" ;;
    *)                     echo "" ;;
  esac
}

# Keys Cursor does not document for the event but which a wired script still
# emits, each for a stated reason. Reported as a WARNING, never a pass in
# silence, so the list shrinks instead of growing.
tolerated_keys() {
  case "$1" in
    # (none today: cursor-agent-tools-guard.sh answers its postToolUse pop with {}.)
    *)           echo "" ;;
  esac
}

in_list() { local x="$1"; shift; local y; for y in "$@"; do [ "$x" = "$y" ] && return 0; done; return 1; }

# judge_envelope <label> <event> — asserts OUT/RC for one run.
judge_envelope() {
  local label="$1" event="$2" n keys k bad_keys="" tol_keys=""
  local allowed=() tolerated=()
  read -r -a allowed <<< "$(allowed_keys "$event")"
  read -r -a tolerated <<< "$(tolerated_keys "$event")"

  if [ "$RC" -ne 0 ] && [ "$RC" -ne 2 ]; then
    bad "$label: exits 0 or 2" "rc=$RC stderr: ${ERR:0:200}"
    return
  fi
  if [ -z "${OUT//[[:space:]]/}" ]; then
    ok "$label: exit $RC, empty stdout"
    return
  fi
  n="$(printf '%s' "$OUT" | jq -s 'if (length == 1 and (.[0] | type) == "object") then 1 else 0 end' 2>/dev/null)"
  if [ "$n" != "1" ]; then
    bad "$label: stdout is one JSON object" "got: ${OUT:0:200}"
    return
  fi
  keys="$(printf '%s' "$OUT" | jq -r 'keys[]')"
  for k in $keys; do
    if in_list "$k" ${allowed[@]+"${allowed[@]}"}; then
      :
    elif in_list "$k" ${tolerated[@]+"${tolerated[@]}"}; then
      tol_keys="$tol_keys $k"
    else
      bad_keys="$bad_keys $k"
    fi
  done
  if [ -n "$bad_keys" ]; then
    bad "$label: only Cursor's $event fields" "unknown key(s):$bad_keys — allowed: ${allowed[*]:-<none>}"
    return
  fi
  if printf '%s' "$OUT" | jq -e 'has("followup_message")' >/dev/null 2>&1; then
    bad "$label: never emits followup_message" "an advisory hook must not speak as the user"
    return
  fi
  if [ -n "$tol_keys" ]; then
    warn "$label: emits tolerated non-Cursor key(s):$tol_keys (see tolerated_keys)"
  fi
  ok "$label: exit $RC, Cursor-shaped ($(printf '%s' "$keys" | tr '\n' ' '))"
}

section "the sweep: every bundle entry × every fixture for its event"

while IFS=$'\t' read -r event cmd; do
  [ -n "$event" ] || continue
  script="${cmd##*/}"
  [ -f "$ROOT/hooks/$script" ] || { bad "$event → $script exists" "missing"; continue; }
  found=0
  for f in "$FX/$event".json "$FX/$event"-*.json; do
    [ -f "$f" ] || continue
    found=1
    fx="$(basename "$f" .json)"
    run_hook "$script" "$fx"
    judge_envelope "$event → $script [$fx]" "$event"
  done
  [ "$found" = 1 ] || bad "$event has a fixture" "no tests/fixtures/cursor/$event*.json"
done < <(jq -r '.hooks | to_entries[] | .key as $e | .value[] | "\($e)\t\(.command)"' "$B")

section "every fixture carries the fields hook_detect_platform keys on"
for f in "$FX"/*.json; do
  fx="$(basename "$f" .json)"
  case "$fx" in
    workspaceOpen) field='.cursor_version' ;;   # omits the conversation fields by design
    *)             field='.conversation_id' ;;
  esac
  judge "fixture $fx is recognisably Cursor ($field)" yes \
    "$(if jq -e "$field != null and (.workspace_roots | length) > 0" "$f" >/dev/null 2>&1; then echo yes; else echo no; fi)"
done

section "beforeSubmitPrompt: goal-condition-lint blocks with continue:false"
run_hook goal-condition-lint.sh beforeSubmitPrompt-goal-unsatisfiable
judge "unsatisfiable /goal exits 0 (the JSON is the block)" 0 "$RC"
judge "unsatisfiable /goal → continue:false" false "$(printf '%s' "$OUT" | jq -r '.continue')"
judge "the block carries the menu as user_message" yes \
  "$(if printf '%s' "$OUT" | jq -e '.user_message | test("/goal clear") and test("force:")' >/dev/null 2>&1; then echo yes; else echo no; fi)"
judge "nothing on stderr on the Cursor block path" "" "$ERR"
run_hook goal-condition-lint.sh beforeSubmitPrompt-goal-ok
judge "a checkable /goal → continue:true" true "$(printf '%s' "$OUT" | jq -r '.continue')"
judge "a checkable /goal carries no user_message" no "$(has "$OUT" user_message)"
run_hook goal-condition-lint.sh beforeSubmitPrompt
judge "a non-/goal prompt → explicit {\"continue\":true}, never empty stdout" '{"continue":true}' "$(printf '%s' "$OUT" | jq -c .)"

section "beforeSubmitPrompt: skill-suggest passes with continue:true and a note"
# The sweep above already fired skill-suggest once for this conversation_id;
# clear its once-per-session markers so this is a first fire again.
rm -rf "$CLAUDE_PLUGIN_DATA/skill-suggest"
run_hook skill-suggest.sh beforeSubmitPrompt-cost
judge "cost prompt → continue:true" true "$(printf '%s' "$OUT" | jq -r '.continue')"
judge "cost prompt → user_message names session-report" yes \
  "$(if printf '%s' "$OUT" | jq -e '.user_message | test("session-report")' >/dev/null 2>&1; then echo yes; else echo no; fi)"
judge "Cursor wording addresses the user (no model-directed 'invoke the skill')" no \
  "$(has "$(printf '%s' "$OUT" | jq -r '.user_message')" "invoke the skill, or tell the user")"
run_hook skill-suggest.sh beforeSubmitPrompt-cost
judge "second fire in the same conversation is quiet (once per skill per session)" '{"continue":true}' "$(printf '%s' "$OUT" | jq -c .)"
run_hook skill-suggest.sh beforeSubmitPrompt
judge "a prompt with nothing to suggest → explicit {\"continue\":true}" '{"continue":true}' "$(printf '%s' "$OUT" | jq -c .)"

section "beforeSubmitPrompt: scope-decompose-reminder passes with continue:true"
run_hook scope-decompose-reminder.sh beforeSubmitPrompt-sweeping
judge "sweeping mandate → continue:true" true "$(printf '%s' "$OUT" | jq -r '.continue')"
judge "sweeping mandate → the decomposition nudge as user_message" yes \
  "$(if printf '%s' "$OUT" | jq -e '.user_message | test("Large-scope")' >/dev/null 2>&1; then echo yes; else echo no; fi)"
run_hook scope-decompose-reminder.sh beforeSubmitPrompt
judge "ordinary prompt → explicit {\"continue\":true}" '{"continue":true}' "$(printf '%s' "$OUT" | jq -c .)"

section "sessionStart: session-init answers with additional_context and keys state like the guards"
run_hook session-init.sh sessionStart
judge "session-init exits 0" 0 "$RC"
judge "session-init → additional_context names the session files dir" yes \
  "$(if printf '%s' "$OUT" | jq -e '.additional_context | test("Session files dir")' >/dev/null 2>&1; then echo yes; else echo no; fi)"
judge "session-init → no hookSpecificOutput on Cursor" no "$(has "$OUT" hookSpecificOutput)"
sid="$(jq -r '.session_id' "$FX/sessionStart.json")"
judge "session state is keyed by session_id ($sid), as enforce-worktree-edits keys it" yes \
  "$(exists "$HOME/.claude/session-state/$sid.json")"

section "sessionEnd: nothing on stdout (Cursor documents no output)"
for s in session-end.sh release-agent-claims.sh handoff-reminder.sh; do
  run_hook "$s" sessionEnd
  judge "$s exits 0 on sessionEnd" 0 "$RC"
  judge "$s prints nothing on sessionEnd" "" "$OUT"
done
# handoff-reminder from a Cursor CLI worktree: the reminder goes to stderr only.
WT="$TMP/home/.cursor/worktrees/project/feature-x"
harness_new_repo "$WT"
errf="$TMP/err"
OUT="$(cd "$WT" && jq --arg ws "$WT" '.workspace_roots = [$ws]' "$FX/sessionEnd.json" | bash "$ROOT/hooks/handoff-reminder.sh" 2>"$errf")"; RC=$?; ERR="$(cat "$errf")"
judge "handoff-reminder in ~/.cursor/worktrees/… exits 0" 0 "$RC"
judge "handoff-reminder in a worktree keeps stdout empty" "" "$OUT"
judge "handoff-reminder in a worktree says switch-dev on stderr" yes "$(has "$ERR" switch-dev)"

section "stop / preCompact: advisory, never a followup_message"
run_hook check-done.sh stop
judge "check-done exits 0 on stop" 0 "$RC"
# Empty stdout or the cross-host no-op `{}` (hook_stop_ok): both carry no
# followup_message, which is the whole point.
judge "check-done's stdout on stop is empty or {} (its reminder is stderr)" yes \
  "$(if [ -z "${OUT//[[:space:]]/}" ] || [ "$(printf '%s' "$OUT" | jq -c . 2>/dev/null)" = "{}" ]; then echo yes; else echo no; fi)"
judge "check-done's reminder reaches stderr" yes "$(has "$ERR" "DoD reminder")"
run_hook precompact-snapshot.sh preCompact
judge "precompact-snapshot exits 0" 0 "$RC"
judge "precompact-snapshot writes its snapshot file on Cursor too" yes "$(exists "$WS/.dev-files/compaction/latest.md")"

section "workspaceOpen: pluginPaths"
run_hook cursor-workspace-open.sh workspaceOpen
judge "no SUPERPOWERS_CURSOR_PLUGIN_PATH → {\"pluginPaths\":[]}" '{"pluginPaths":[]}' "$(printf '%s' "$OUT" | jq -c .)"
run_hook cursor-workspace-open.sh workspaceOpen SUPERPOWERS_CURSOR_PLUGIN_PATH="$ROOT"
judge "a checkout with .cursor-plugin/plugin.json is returned" "$ROOT" "$(printf '%s' "$OUT" | jq -r '.pluginPaths[0]')"
judge "exactly one path" 1 "$(printf '%s' "$OUT" | jq -r '.pluginPaths | length')"
mkdir -p "$TMP/notaplugin"
run_hook cursor-workspace-open.sh workspaceOpen SUPERPOWERS_CURSOR_PLUGIN_PATH="$TMP/notaplugin:relative/path:$TMP/does-not-exist"
judge "non-plugin, relative and missing paths are dropped" '{"pluginPaths":[]}' "$(printf '%s' "$OUT" | jq -c .)"
judge "…and each is named on stderr" 3 "$(printf '%s\n' "$ERR" | grep -c 'ignoring')"

section "the safety tier fails closed; the advisory tier does not"
SAFETY=(enforce-worktree-edits.sh guard-sensitive-files.sh protect-other-branches.sh cursor-agent-tools-guard.sh)
while IFS=$'\t' read -r event cmd fc; do
  script="${cmd##*/}"
  case "$event" in
    preToolUse|beforeShellExecution)
      if in_list "$script" "${SAFETY[@]}"; then
        judge "$event → $script carries failClosed: true" true "$fc"
      else
        judge "$event → $script (advisory) is fail-open" "false" "$( [ "$fc" = "true" ] && echo true || echo false )"
      fi ;;
    *)
      judge "$event → $script (advisory/observational) is fail-open" "false" "$( [ "$fc" = "true" ] && echo true || echo false )" ;;
  esac
done < <(jq -r '.hooks | to_entries[] | .key as $e | .value[] | "\($e)\t\(.command)\t\(.failClosed // false)"' "$B")
judge "guard-sensitive-files fails closed on BOTH preToolUse and beforeShellExecution" 2 \
  "$(jq -r '[.hooks.preToolUse[], .hooks.beforeShellExecution[]] | map(select((.command | test("guard-sensitive-files")) and .failClosed == true)) | length' "$B")"

section "events deliberately left unwired stay unwired while their Claude peers speak Claude"
# subagent-handoff-check.sh is a SubagentStop peer. It is wired here only once
# its Cursor stdout, ON THE PATH WHERE IT HAS SOMETHING TO SAY, is Cursor-shaped
# (empty, {} or user_message — never followup_message, never a Claude key).
# Its quiet path already prints the cross-host `{}`; the informative path
# (an objective with no handoff) still prints hookSpecificOutput, a Claude
# field that Cursor drops. If that changes, this case flips to a warning
# saying it can now be wired.
mkdir -p "$WS/.dev-files/objectives/obj-probe"
errf="$TMP/err"
OUT="$(cd "$WS" && payload subagentStop | bash "$ROOT/hooks/subagent-handoff-check.sh" 2>"$errf")"; RC=$?
rm -rf "$WS/.dev-files/objectives/obj-probe"
shc_keys="$(printf '%s' "$OUT" | jq -r 'keys[]' 2>/dev/null | tr '\n' ' ')"
if [ -z "${OUT//[[:space:]]/}" ] || ! printf '%s' "$OUT" | jq -e 'has("suppressOutput") or has("hookSpecificOutput") or has("systemMessage")' >/dev/null 2>&1; then
  # 5.0.0: the informative path answers with user_message on Cursor, so the hook is wired.
  judge "subagent-handoff-check answers subagentStop in Cursor's dialect (keys: ${shc_keys:-none})" yes \
    "$(if printf '%s' "$OUT" | jq -e 'has("user_message") and (has("followup_message") | not)' >/dev/null 2>&1; then echo yes; else echo no; fi)"
  judge "subagentStop is wired to subagent-handoff-check.sh" yes \
    "$(if jq -e '.hooks.subagentStop[] | select(.command | test("subagent-handoff-check"))' "$B" >/dev/null 2>&1; then echo yes; else echo no; fi)"
else
  judge "subagentStop is not wired (subagent-handoff-check's informative path emits: ${shc_keys% })" no \
    "$(if jq -e '.hooks.subagentStop' "$B" >/dev/null 2>&1; then echo yes; else echo no; fi)"
fi
judge "subagentStart is not wired (cursor-agent-tools-guard would deny a spawn under an active frame: no tool_name)" no \
  "$(if jq -e '.hooks.subagentStart' "$B" >/dev/null 2>&1; then echo yes; else echo no; fi)"

section "the Claude envelope of every ported hook is unchanged"
claude_run goal-condition-lint.sh '{"prompt":"/goal do not yield for anything from me until all remaining work is done","session_id":"s1","cwd":"'"$WS"'"}'
judge "goal-condition-lint on Claude still blocks via exit 2" 2 "$RC"
judge "goal-condition-lint on Claude still prints the menu on stderr" yes "$(has "$ERR" "/goal clear")"
judge "goal-condition-lint on Claude prints nothing on stdout" "" "$OUT"
claude_run goal-condition-lint.sh '{"prompt":"rename a helper","session_id":"s1","cwd":"'"$WS"'"}'
judge "goal-condition-lint on Claude is silent on a pass" "" "$OUT"
claude_run skill-suggest.sh '{"prompt":"why is this session so expensive, how many tokens did that cost?","session_id":"s-claude","cwd":"'"$WS"'"}'
judge "skill-suggest on Claude still emits hookSpecificOutput.additionalContext" yes \
  "$(if printf '%s' "$OUT" | jq -e '.hookSpecificOutput.additionalContext | test("session-report")' >/dev/null 2>&1; then echo yes; else echo no; fi)"
judge "skill-suggest on Claude keeps the model-directed wording" yes "$(has "$OUT" "invoke the skill")"
claude_run skill-suggest.sh '{"prompt":"rename a helper","session_id":"s-claude","cwd":"'"$WS"'"}'
judge "skill-suggest on Claude is silent with nothing to say" "" "$OUT"
claude_run scope-decompose-reminder.sh '{"prompt":"do everything in the roadmap","session_id":"s1","cwd":"'"$WS"'"}'
judge "scope-decompose on Claude still emits hookSpecificOutput" UserPromptSubmit "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.hookEventName')"
claude_run scope-decompose-reminder.sh '{"prompt":"rename a helper","session_id":"s1","cwd":"'"$WS"'"}'
judge "scope-decompose on Claude is silent with nothing to say" "" "$OUT"
claude_run session-init.sh '{"session_id":"s-claude-init","cwd":"'"$WS"'","source":"startup"}'
judge "session-init on Claude still emits hookSpecificOutput.hookEventName SessionStart" SessionStart "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.hookEventName')"
claude_run session-end.sh '{"session_id":"s-claude-init","cwd":"'"$WS"'"}'
judge "session-end on Claude still answers suppressOutput" true "$(printf '%s' "$OUT" | jq -r '.suppressOutput')"
claude_run handoff-reminder.sh '{"session_id":"s1","cwd":"'"$WS"'"}'
judge "handoff-reminder on Claude still answers suppressOutput outside a worktree" true "$(printf '%s' "$OUT" | jq -r '.suppressOutput')"

harness_summary
