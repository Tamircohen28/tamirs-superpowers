#!/usr/bin/env bash
# test-codex-contract.sh — every hook the generated Codex file wires, judged
# against Codex's documented hook contract, without a live Codex session.
#
# WHAT CODEX DEMANDS THAT CLAUDE DOES NOT (learn.chatgpt.com/docs/hooks, and
# openai/codex hooks/src/engine/output_parser.rs read at rust-v0.163.0):
#   - a Stop or SubagentStop hook that exits 0 must print JSON; plain text on
#     stdout fails the hook.
#   - a PreToolUse hook may not answer `permissionDecision: "ask"`, legacy
#     `decision: "approve"`, `continue: false`, `stopReason` or
#     `suppressOutput`; `permissionDecision: "allow"` without `updatedInput`
#     and `deny` without a non-empty `permissionDecisionReason` fail too. A
#     failed PreToolUse hook is reported and the tool call CONTINUES, so a
#     guard that answers in a rejected shape is a guard that does not guard.
#   - a PostToolUse hook may not answer `suppressOutput`; a legacy
#     `decision: "block"` needs a non-empty `reason`.
#   - the hooks file has exactly two top-level keys, `description` and
#     `hooks` (deny_unknown_fields); Codex 0.163.0 reports
#     "failed to parse plugin hooks config ...: unknown field `modules`" and
#     loads no hook from that file.
#   - `apply_patch` is Codex's edit tool; its PreToolUse/PostToolUse payload is
#     `tool_name: "apply_patch"` with `tool_input.command` holding the patch
#     envelope, and it also matches `Edit`/`Write` matchers.
#
# WHAT IS MEASURED HERE: each command in platforms/codex/hooks.json is run with
# the fixture for its event from tests/fixtures/codex/ (payload shapes recorded
# from codex-cli 0.163.0 — see the README there), with PLUGIN_ROOT/PLUGIN_DATA
# exported the way Codex exports them, and its exit code and stdout are judged
# against the rules above. The guards' verdicts on a protected and an ordinary
# apply_patch write are asserted as a matched pair, so a guard that denies
# everything cannot pass.
#
# WHAT IS NOT: trust state, the /hooks review surface, matcher evaluation and
# SessionEnd/Interrupt timeout clamping are Codex's own behaviour and need a
# live session — docs/user/install/codex.md records what one measured.
#
# Hermetic: temp HOME, temp repo, no network, no codex binary required.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$ROOT/tests/lib/harness.sh"
# shellcheck source=tests/hooks/lib/apply-patch-fixtures.sh
source "$ROOT/tests/hooks/lib/apply-patch-fixtures.sh"

harness_require git jq python3

CODEX_HOOKS="$ROOT/platforms/codex/hooks.json"
FIXTURES="$ROOT/tests/fixtures/codex"

TMP="$(harness_tmpdir)"
export HOME="$TMP/home"
mkdir -p "$HOME/.claude"
export GIT_CONFIG_NOSYSTEM=1
export SUPERPOWERS_WORKTREE_CLEANUP=0
export AGENT_CLAIM_DIR="$TMP/claims"
unset GH_TOKEN GITHUB_TOKEN PM_ALLOW_PROTECTED PM_ALLOW_DOCKER 2>/dev/null || true
unset CLAUDE_EXIT_PROXY CLAUDE_EXIT_PUBLIC_IP TAMIRS_USAGE_CAPTURE TAMIRS_USAGE_CAPTURE_DIR TAMIRS_USAGE_CAPTURE_PORT 2>/dev/null || true
unset HOOK_PLATFORM 2>/dev/null || true

# The environment Codex hands a plugin hook (measured on 0.163.0): its own
# PLUGIN_ROOT/PLUGIN_DATA plus the CLAUDE_* pair "for compatibility".
export PLUGIN_ROOT="$ROOT"
export PLUGIN_DATA="$TMP/plugin-data"
export CLAUDE_PLUGIN_ROOT="$ROOT"
export CLAUDE_PLUGIN_DATA="$TMP/plugin-data"
export CODEX_HOME="$TMP/codex-home"
mkdir -p "$PLUGIN_DATA" "$CODEX_HOME"

OBJ="codex-contract"
REPO="$(setup_apply_patch_repo "$TMP" "$OBJ")"
WORKER="$(canon "$REPO/.agent-worktrees/$OBJ/task-001")"
git -C "$REPO" remote add origin https://github.com/example/x.git 2>/dev/null || true

CODEX_EVENTS="SessionStart SessionEnd SubagentStart UserPromptSubmit PreToolUse PermissionRequest PostToolUse PreCompact PostCompact SubagentStop Stop Interrupt"

# ===========================================================================
section "the generated file is the shape Codex's parser accepts"
# ===========================================================================

judge "platforms/codex/hooks.json is valid JSON" yes "$(if jq empty "$CODEX_HOOKS" 2>/dev/null; then echo yes; else echo no; fi)"
judge "top-level keys are exactly description and hooks (deny_unknown_fields)" "description,hooks" \
  "$(jq -r 'keys_unsorted | sort | join(",")' "$CODEX_HOOKS")"
judge "no modules key (Codex 0.163.0: unknown field \`modules\` -> no hook loads)" no \
  "$(if jq -e 'has("modules")' "$CODEX_HOOKS" >/dev/null; then echo yes; else echo no; fi)"

bad_events=""
for ev in $(jq -r '.hooks | keys[]' "$CODEX_HOOKS"); do
  case " $CODEX_EVENTS " in *" $ev "*) ;; *) bad_events="$bad_events $ev" ;; esac
done
judge "every wired event is one of Codex's twelve" "" "$bad_events"
judge "onFailure appears on no hook entry (Codex's command hook has no such field)" 0 \
  "$(jq '[.hooks[][].hooks[] | select(has("onFailure"))] | length' "$CODEX_HOOKS")"
judge "every entry is a command hook (Codex skips prompt/agent handlers)" 0 \
  "$(jq '[.hooks[][].hooks[] | select(.type != "command")] | length' "$CODEX_HOOKS")"
judge "every command runs a script that exists under the plugin root" 0 \
  "$(jq -r '.hooks[][].hooks[].command' "$CODEX_HOOKS" | sed -E 's/.*\$\{CLAUDE_PLUGIN_ROOT\}"?\/?([^ "]+).*/\1/' | while read -r f; do [ -f "$ROOT/$f" ] || echo "$f"; done | wc -l | tr -d ' ')"

# Codex clamps SessionEnd and Interrupt hook timeouts to 3s and reports the clamp
# as an error item (measured on 0.163.0). Not a failure of this file — the
# hooks still run — but a reviewer should know the declared number is not the
# effective one.
over="$(jq -r '[.hooks.SessionEnd // [] | .[].hooks[] | select((.timeout // 0) > 3) | .command] | length' "$CODEX_HOOKS")"
[ "$over" -gt 0 ] && warn "$over SessionEnd hook(s) declare timeout > 3s; Codex clamps them to 3s at load (measured on 0.163.0)"

# ===========================================================================
section "fixtures carry the documented common stdin fields"
# ===========================================================================

for f in "$FIXTURES"/*.json; do
  name="$(basename "$f" .json)"
  judge "$name has session_id, transcript_path, cwd, hook_event_name, model" yes \
    "$(if jq -e 'has("session_id") and has("transcript_path") and has("cwd") and has("hook_event_name") and has("model")' "$f" >/dev/null; then echo yes; else echo no; fi)"
done
judge "apply_patch fixtures put the envelope in tool_input.command (Bash and apply_patch use command)" yes \
  "$(if jq -e '.tool_name == "apply_patch" and (.tool_input.command | startswith("*** Begin Patch"))' "$FIXTURES/pre-tool-use-apply-patch-protected.json" >/dev/null; then echo yes; else echo no; fi)"

# ===========================================================================
# run_hook <command> <fixture> <cwd> — runs one hooks.json command the way
# Codex does (a shell line, cwd = session cwd, payload on stdin) and leaves
# stdout/stderr/rc in RUN_OUT/RUN_ERR/RUN_RC. A hook that hangs is killed at
# 20s and reported as rc 124, bash built-ins only (no coreutils timeout on
# macOS).
# ===========================================================================
RUN_OUT=""; RUN_ERR=""; RUN_RC=0
run_hook() {
  local command="$1" fixture="$2" cwd="$3" outf errf pid watcher waited=0
  outf="$TMP/run.out"; errf="$TMP/run.err"
  jq --arg cwd "$cwd" '.cwd = $cwd' "$fixture" \
    | ( cd "$cwd" && bash -c "$command" ) >"$outf" 2>"$errf" &
  pid=$!
  ( while kill -0 "$pid" 2>/dev/null; do
      [ "$waited" -ge 20 ] && { kill -9 "$pid" 2>/dev/null; exit 0; }
      sleep 1; waited=$((waited + 1))
    done ) &
  watcher=$!
  wait "$pid" 2>/dev/null; RUN_RC=$?
  kill "$watcher" 2>/dev/null; wait "$watcher" 2>/dev/null
  [ "$RUN_RC" = 137 ] && RUN_RC=124
  RUN_OUT="$(cat "$outf")"; RUN_ERR="$(cat "$errf")"
}

# stdout_shape <stdout> -> empty | object | invalid
stdout_shape() {
  local s="$1"
  [ -z "$(printf '%s' "$s" | tr -d '[:space:]')" ] && { echo empty; return; }
  if [ "$(printf '%s' "$s" | jq -s 'length == 1 and (.[0] | type) == "object"' 2>/dev/null)" = "true" ]; then
    echo object
  else
    echo invalid
  fi
}

# pre_tool_use_violation <stdout> -> "" or the Codex rule it breaks
pre_tool_use_violation() {
  printf '%s' "$1" | jq -r '
    def hs: .hookSpecificOutput // {};
    if (hs | .permissionDecision) == "ask" then "permissionDecision:ask"
    elif (hs | .permissionDecision) == "allow" and ((hs | .updatedInput) == null) then "permissionDecision:allow without updatedInput"
    elif (hs | .permissionDecision) == "deny" and (((hs | .permissionDecisionReason) // "" | gsub("^\\s+|\\s+$";"")) == "") then "deny without a non-empty permissionDecisionReason"
    elif .decision == "approve" then "decision:approve"
    elif .decision == "block" and ((.reason // "" | gsub("^\\s+|\\s+$";"")) == "") then "decision:block without reason"
    elif (.reason != null) and (.decision == null) and ((hs | .permissionDecision) == null) and ((hs | .permissionDecisionReason) == null) and ((hs | .updatedInput) == null) then "reason without decision"
    elif .continue == false then "continue:false"
    elif has("stopReason") then "stopReason"
    elif has("suppressOutput") then "suppressOutput"
    else "" end' 2>/dev/null
}

# post_tool_use_violation <stdout> -> "" or the Codex rule it breaks
post_tool_use_violation() {
  printf '%s' "$1" | jq -r '
    if has("suppressOutput") then "suppressOutput"
    elif .decision == "block" and ((.reason // "" | gsub("^\\s+|\\s+$";"")) == "") then "decision:block without reason"
    elif (.reason != null) and (.decision == null) then "reason without decision"
    else "" end' 2>/dev/null
}

# denies <stdout> -> yes|no — a deny Codex would honour
denies() {
  if printf '%s' "$1" | jq -e '(.hookSpecificOutput.permissionDecision == "deny" and ((.hookSpecificOutput.permissionDecisionReason // "") | length) > 0) or (.decision == "block" and ((.reason // "") | length) > 0)' >/dev/null 2>&1; then echo yes; else echo no; fi
}

# matches <matcher> <tool_name> -> yes|no, Codex's rule: regex, "*"/""/absent
# match all, and apply_patch also matches Edit and Write.
matches() {
  local m="$1" tool="$2"
  [ -z "$m" ] || [ "$m" = "*" ] && { echo yes; return; }
  if printf '%s' "$tool" | grep -Eq "^($m)$"; then echo yes; return; fi
  if [ "$tool" = "apply_patch" ] && { printf 'Edit' | grep -Eq "^($m)$" || printf 'Write' | grep -Eq "^($m)$"; }; then echo yes; return; fi
  echo no
}

# fixture_for <event> -> path, or "" for an event with no fixture
fixture_for() {
  case "$1" in
    SessionStart) echo "$FIXTURES/session-start.json" ;;
    SessionEnd) echo "$FIXTURES/session-end.json" ;;
    UserPromptSubmit) echo "$FIXTURES/user-prompt-submit.json" ;;
    PostToolUse) echo "$FIXTURES/post-tool-use.json" ;;
    PreCompact) echo "$FIXTURES/pre-compact.json" ;;
    Stop) echo "$FIXTURES/stop.json" ;;
    SubagentStop) echo "$FIXTURES/subagent-stop.json" ;;
    *) echo "" ;;
  esac
}

# ===========================================================================
section "every non-PreToolUse command: exit 0 or 2, stdout empty or one JSON object"
# ===========================================================================

# Fields are joined with US (0x1f), not a tab: bash's `read` folds a run of
# whitespace IFS characters into one delimiter, so an empty matcher field
# would vanish and the command would shift into its place.
while IFS=$'\037' read -r event matcher command; do
  [ "$event" = "PreToolUse" ] && continue
  fixture="$(fixture_for "$event")"
  script="$(printf '%s' "$command" | sed -E 's/.*\/hooks\/([^ "]+).*/\1/')"
  if [ -z "$fixture" ]; then
    bad "$event: $script" "no fixture for event $event — add tests/fixtures/codex/<event>.json"
    continue
  fi
  run_hook "$command" "$fixture" "$REPO"
  case "$RUN_RC" in
    0|2) ok "$event: $script exits $RUN_RC" ;;
    124) bad "$event: $script" "hung for 20s" ;;
    *) bad "$event: $script" "exit $RUN_RC (Codex: 0 continues, 2 blocks; anything else is a hook failure)" ;;
  esac
  shape="$(stdout_shape "$RUN_OUT")"
  case "$event" in
    Stop|SubagentStop)
      judge "$event: $script stdout is one JSON object on exit $RUN_RC (Codex: plain text is invalid)" object "$shape"
      ;;
    PostToolUse)
      judge "$event: $script stdout is empty or one JSON object" yes "$(if [ "$shape" != invalid ]; then echo yes; else echo "no: $(printf '%s' "$RUN_OUT" | head -c 160)"; fi)"
      [ "$shape" = object ] && judge "$event: $script answers in a shape Codex's PostToolUse parser accepts" "" "$(post_tool_use_violation "$RUN_OUT")"
      ;;
    *)
      judge "$event: $script stdout is empty or one JSON object" yes "$(if [ "$shape" != invalid ]; then echo yes; else echo "no: $(printf '%s' "$RUN_OUT" | head -c 160)"; fi)"
      ;;
  esac
done < <(jq -r '.hooks | to_entries[] | .key as $e | .value[] | (.matcher // "") as $m | .hooks[] | [$e, $m, .command] | join("\u001f")' "$CODEX_HOOKS")

# ===========================================================================
section "Stop / SubagentStop: the silent paths print JSON too"
# ===========================================================================
# check-done.sh is silent when nothing changed; subagent-handoff-check.sh is
# silent when no objective is in play. Those are the paths a plain `exit 0`
# used to take, and the ones Codex would have failed.
CLEAN="$TMP/clean-repo"
harness_new_repo "$CLEAN" main
run_hook "bash \"\${CLAUDE_PLUGIN_ROOT}\"/hooks/check-done.sh" "$FIXTURES/stop.json" "$CLEAN"
judge "check-done.sh with a clean tree: exit 0" 0 "$RUN_RC"
judge "check-done.sh with a clean tree: stdout is exactly {}" "{}" "$(printf '%s' "$RUN_OUT" | jq -c . 2>/dev/null)"
run_hook "bash \"\${CLAUDE_PLUGIN_ROOT}\"/hooks/check-done.sh" "$FIXTURES/stop.json" "$TMP"
judge "check-done.sh outside any repo: stdout is exactly {}" "{}" "$(printf '%s' "$RUN_OUT" | jq -c . 2>/dev/null)"
printf 'x\n' > "$CLEAN/dirty.sh"
run_hook "bash \"\${CLAUDE_PLUGIN_ROOT}\"/hooks/check-done.sh" "$FIXTURES/stop.json" "$CLEAN"
judge "check-done.sh with a changed code file: stdout is exactly {} (reminder goes to stderr)" "{}" "$(printf '%s' "$RUN_OUT" | jq -c . 2>/dev/null)"
judge "check-done.sh with a changed code file: the reminder is on stderr" yes "$(has "$RUN_ERR" "DoD reminder")"
run_hook "bash \"\${CLAUDE_PLUGIN_ROOT}\"/hooks/subagent-handoff-check.sh" "$FIXTURES/subagent-stop.json" "$CLEAN"
judge "subagent-handoff-check.sh with no objective: stdout is exactly {}" "{}" "$(printf '%s' "$RUN_OUT" | jq -c . 2>/dev/null)"

# ===========================================================================
section "PreToolUse: guards answer in shapes Codex honours, and still guard"
# ===========================================================================
# For every PreToolUse group whose matcher would fire on the fixture's
# tool_name (apply_patch matches Edit|Write... by Codex's rule), run each
# command with the protected write and its ordinary sibling. One hook must
# deny the protected write; none may deny the ordinary one; and no answer may
# use a shape Codex rejects — a rejected deny is reported and the write goes
# through.
protected_denied=no
docker_denied=no
while IFS=$'\037' read -r matcher command; do
  script="$(printf '%s' "$command" | sed -E 's/.*\/hooks\/([^ "]+).*/\1/')"
  if [ "$(matches "$matcher" apply_patch)" = yes ]; then
    run_hook "$command" "$FIXTURES/pre-tool-use-apply-patch-protected.json" "$WORKER"
    judge "PreToolUse[$matcher] $script on a protected apply_patch write: exit 0 or 2" yes "$(case "$RUN_RC" in 0|2) echo yes ;; *) echo "no: $RUN_RC" ;; esac)"
    shape="$(stdout_shape "$RUN_OUT")"
    judge "PreToolUse[$matcher] $script: stdout is empty or one JSON object" yes "$(if [ "$shape" != invalid ]; then echo yes; else echo "no: $(printf '%s' "$RUN_OUT" | head -c 160)"; fi)"
    [ "$shape" = object ] && judge "PreToolUse[$matcher] $script: no shape Codex rejects (ask/continue:false/stopReason/suppressOutput/bare allow/empty deny reason)" "" "$(pre_tool_use_violation "$RUN_OUT")"
    [ "$(denies "$RUN_OUT")" = yes ] && protected_denied=yes
    [ "$RUN_RC" = 2 ] && protected_denied=yes

    run_hook "$command" "$FIXTURES/pre-tool-use-apply-patch-ordinary.json" "$WORKER"
    judge "PreToolUse[$matcher] $script on an ordinary apply_patch write: not denied" no "$(if [ "$RUN_RC" = 2 ]; then echo yes; else denies "$RUN_OUT"; fi)"
    shape="$(stdout_shape "$RUN_OUT")"
    [ "$shape" = object ] && judge "PreToolUse[$matcher] $script (ordinary): no shape Codex rejects" "" "$(pre_tool_use_violation "$RUN_OUT")"
  fi
  if [ "$(matches "$matcher" Bash)" = yes ]; then
    run_hook "$command" "$FIXTURES/pre-tool-use-bash-docker.json" "$WORKER"
    judge "PreToolUse[$matcher] $script on a Docker-creating Bash call: exit 0 or 2" yes "$(case "$RUN_RC" in 0|2) echo yes ;; *) echo "no: $RUN_RC" ;; esac)"
    shape="$(stdout_shape "$RUN_OUT")"
    [ "$shape" = object ] && judge "PreToolUse[$matcher] $script (docker): no shape Codex rejects" "" "$(pre_tool_use_violation "$RUN_OUT")"
    [ "$(denies "$RUN_OUT")" = yes ] && docker_denied=yes
    run_hook "$command" "$FIXTURES/pre-tool-use-bash-ordinary.json" "$WORKER"
    judge "PreToolUse[$matcher] $script on an ordinary Bash call: not denied" no "$(if [ "$RUN_RC" = 2 ]; then echo yes; else denies "$RUN_OUT"; fi)"
    shape="$(stdout_shape "$RUN_OUT")"
    [ "$shape" = object ] && judge "PreToolUse[$matcher] $script (ordinary Bash): no shape Codex rejects" "" "$(pre_tool_use_violation "$RUN_OUT")"
  fi
done < <(jq -r '.hooks.PreToolUse[] | (.matcher // "") as $m | .hooks[] | [$m, .command] | join("\u001f")' "$CODEX_HOOKS")

judge "the protected apply_patch write (yarn.lock) is denied by at least one wired guard" yes "$protected_denied"
judge "the Docker-creating Bash call is denied by at least one wired guard, with a non-empty reason" yes "$docker_denied"

# ===========================================================================
section "hook_detect_platform names the host"
# ===========================================================================
detect() {
  local kv
  ( unset PLUGIN_ROOT PLUGIN_DATA CODEX_HOME
    for kv in "$@"; do export "${kv?}"; done
    . "$ROOT/hooks/lib/hook-output.sh"
    hook_detect_platform "$PAYLOAD"
    printf '%s' "$HOOK_PLATFORM" )
}
PAYLOAD="$(cat "$FIXTURES/pre-tool-use-apply-patch-ordinary.json")"
judge "CODEX_HOME exported -> codex" codex "$(detect CODEX_HOME="$TMP/codex-home" PAYLOAD="$PAYLOAD")"
judge "PLUGIN_ROOT alone is not the signal; the turn_id fallback still names codex" codex "$(detect PLUGIN_ROOT="$ROOT" PAYLOAD="$PAYLOAD")"
judge "no CODEX_HOME but a turn_id in the payload -> codex" codex "$(detect PAYLOAD="$PAYLOAD")"
judge "no CODEX_HOME, no turn_id -> claude" claude "$(detect PAYLOAD="$(jq -c 'del(.turn_id)' "$FIXTURES/pre-tool-use-apply-patch-ordinary.json")")"
judge "Cursor payload keys win over CODEX_HOME" cursor "$(detect CODEX_HOME="$TMP/codex-home" PAYLOAD='{"conversation_id":"c1","tool_name":"Write"}')"
judge "empty payload, CODEX_HOME exported -> codex" codex "$(detect CODEX_HOME="$TMP/codex-home" PAYLOAD="")"

harness_summary
