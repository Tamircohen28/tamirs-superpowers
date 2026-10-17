#!/usr/bin/env bash
# Tests for the agent-teams handoff hooks:
#   hooks/task-handoff-check.sh   (TaskCompleted)
#   hooks/teammate-idle-check.sh  (TeammateIdle)
#
# WHAT THESE PIN
#   1. Both are SILENT unless CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS is on. The
#      events only fire for a team, and outside one the subagent hook already
#      owns this check; a second voice there is noise.
#   2. Both are silent outside an objective — a team with no orchestrated work
#      owes no handoff to anyone.
#   3. TaskCompleted speaks when the task's handoff is missing, when its status
#      is outside the vocabulary, and when `completed` carries no validation —
#      and NOT for an honest partial/failed/blocked/cancelled with none. Flagging
#      honest reporting trains workers to overclaim.
#   4. TeammateIdle speaks when a `running` task has no handoff, names exactly
#      those tasks, and stays quiet when every running task has one.
#   5. Both always exit 0 and print exactly one JSON object. Exit 2 on these
#      events would refuse the completion or keep the teammate working; this
#      plugin's handoff hooks inform, they never gate.
#   6. The advisory reaches both channels: systemMessage (documented on every
#      event) and additionalContext (the shape the lead reads elsewhere).
#
# Fixture payloads follow the hooks reference's documented TaskCompleted and
# TeammateIdle input, including the `agent_id` field added in 2.1.290.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TASK_H="$ROOT/hooks/task-handoff-check.sh"
IDLE_H="$ROOT/hooks/teammate-idle-check.sh"
PASS=0; FAIL=0; FAILED=()
[ -f "$TASK_H" ] || { echo "FATAL: $TASK_H missing"; exit 1; }
[ -f "$IDLE_H" ] || { echo "FATAL: $IDLE_H missing"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required"; exit 1; }
TMPROOT="$(mktemp -d)"; trap 'rm -rf "$TMPROOT"' EXIT
ok(){ PASS=$((PASS+1)); echo "  ok   $1"; }
bad(){ FAIL=$((FAIL+1)); FAILED+=("$1"); echo "  FAIL $1 — $2"; }

# Payload builders — the documented input shapes, with cwd pointed at a fixture.
task_payload() {  # <cwd> <task_id> [teammate] [agent_id]
  jq -n --arg cwd "$1" --arg tid "$2" --arg tm "${3:-implementer}" --arg aid "${4:-agent-7f3a}" \
    '{session_id:"abc123",transcript_path:"/x/t.jsonl",cwd:$cwd,permission_mode:"default",
      hook_event_name:"TaskCompleted",task_id:$tid,task_subject:"Implement user authentication",
      task_description:"Add login and signup endpoints",teammate_name:$tm,team_name:"session-a1b2c3d4",agent_id:$aid}'
}
idle_payload() {  # <cwd> [teammate] [agent_id]
  jq -n --arg cwd "$1" --arg tm "${2:-researcher}" --arg aid "${3:-agent-9c21}" \
    '{session_id:"abc123",transcript_path:"/x/t.jsonl",cwd:$cwd,permission_mode:"default",
      hook_event_name:"TeammateIdle",teammate_name:$tm,team_name:"session-a1b2c3d4",agent_id:$aid}'
}
# run_on <hook> <payload> — with agent teams ON.
run_on(){ printf '%s' "$2" | CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 bash "$1" 2>/dev/null; }
# run_off <hook> <payload> — with the variable unset.
run_off(){ printf '%s' "$2" | env -u CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS bash "$1" 2>/dev/null; }
ctx(){ printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null; }
is_silent(){ printf '%s' "$1" | jq -e '. == {}' >/dev/null 2>&1; }
one_object(){ printf '%s' "$1" | jq -s 'length == 1 and (.[0] | type) == "object"' 2>/dev/null | grep -q true; }
mkobj(){ local d="$1"; mkdir -p "$d/.dev-files/objectives/auth-system/handoffs" "$d/.dev-files/objectives/auth-system/tasks"; git -C "$d" init -q; git -C "$d" config user.email t@example.invalid; git -C "$d" config user.name t; git -C "$d" commit -q --allow-empty -m init; printf '{"id":"auth-system","status":"active"}\n' > "$d/.dev-files/objectives/auth-system/objective.json"; }
mktask(){ # <objdir> <id> <status>
  jq -n --arg id "$2" --arg st "$3" '{schema_version:1,id:$id,objective_id:"auth-system",role:"implementer",depends_on:[],scope:["src/**"],validation_tier:"worker",status:$st}' \
    > "$1/.dev-files/objectives/auth-system/tasks/$2.json"
}

echo "=== task-handoff-check (TaskCompleted) ==="

echo "--- gated silently without agent teams ---"
G="$TMPROOT/gated"; mkobj "$G"
out="$(run_off "$TASK_H" "$(task_payload "$G" task-001)")"
is_silent "$out" && ok "teams unset => {} even with a missing handoff" || bad "teams unset => {}" "got: $out"
out="$(printf '%s' "$(task_payload "$G" task-001)" | CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=0 bash "$TASK_H" 2>/dev/null)"
is_silent "$out" && ok "teams=0 => {}" || bad "teams=0 => {}" "got: $out"

echo "--- silent outside orchestration ---"
P="$TMPROOT/plain"; mkdir -p "$P"; git -C "$P" init -q
out="$(run_on "$TASK_H" "$(task_payload "$P" task-001)")"
is_silent "$out" && ok "no objective => {}" || bad "no objective => {}" "got: $out"

echo "--- a missing handoff is surfaced ---"
O="$TMPROOT/obj"; mkobj "$O"
HD="$O/.dev-files/objectives/auth-system/handoffs"
out="$(run_on "$TASK_H" "$(task_payload "$O" task-001)")"; m="$(ctx "$out")"
[ -n "$m" ] && ok "warns when the task's handoff is missing" || bad "warns when the task's handoff is missing" "got: $out"
case "$m" in *"task-001"*) ok "names the task" ;; *) bad "names the task" "got: $m" ;; esac
case "$m" in *"auth-system"*) ok "names the objective" ;; *) bad "names the objective" "got: $m" ;; esac
case "$m" in *"implementer"*) ok "names the teammate" ;; *) bad "names the teammate" "got: $m" ;; esac
case "$m" in *"agent-7f3a"*) ok "carries agent_id" ;; *) bad "carries agent_id" "got: $m" ;; esac
case "$m" in *partial*) ok "tells the lead what to do instead" ;; *) bad "tells the lead what to do instead" "got: $m" ;; esac
ev="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName // empty')"
[ "$ev" = "TaskCompleted" ] && ok "declares hookEventName TaskCompleted" || bad "declares hookEventName TaskCompleted" "got: '$ev'"
sm="$(printf '%s' "$out" | jq -r '.systemMessage // empty')"
[ "$sm" = "$m" ] && ok "the same advisory goes out as systemMessage (the documented channel on this event)" \
  || bad "systemMessage mirrors additionalContext" "got: '$sm'"
one_object "$out" && ok "exactly one JSON object on stdout" || bad "exactly one JSON object on stdout" "got: $out"
if printf '%s' "$out" | jq -e '.continue == false or .decision == "block"' >/dev/null 2>&1; then
  bad "never blocks via JSON" "emitted continue:false or decision:block"
else ok "never blocks via JSON"; fi

echo "--- the objective is resolved from the main checkout, by status ---"
# Fired from inside a linked worker worktree: .dev-files/objectives lives only in the
# main checkout, so a hook that looked beside its own cwd would fall silent.
git -C "$O" worktree add -q -B agent/auth-system/task-001 "$O/.agent-worktrees/auth-system/task-001" HEAD 2>/dev/null
m="$(ctx "$(run_on "$TASK_H" "$(task_payload "$O/.agent-worktrees/auth-system/task-001" task-001)")")"
case "$m" in *"auth-system"*) ok "fired from a worker worktree, the main checkout's objective is found" ;; *) bad "fired from a worker worktree, the main checkout's objective is found" "got: '$m'" ;; esac
# A finished objective that sorts first on disk must not shadow the active one.
mkdir -p "$O/.dev-files/objectives/aaa-done/handoffs" "$O/.dev-files/objectives/aaa-done/tasks"
printf '{"id":"aaa-done","status":"completed"}\n' > "$O/.dev-files/objectives/aaa-done/objective.json"
m="$(ctx "$(run_on "$TASK_H" "$(task_payload "$O" task-001)")")"
case "$m" in *"auth-system"*) ok "a completed objective listed first does not shadow the active one" ;; *) bad "a completed objective listed first does not shadow the active one" "got: '$m'" ;; esac
rm -rf "$O/.dev-files/objectives/aaa-done"

echo "--- host task ids map onto task-NNN handoffs ---"
m="$(ctx "$(run_on "$TASK_H" "$(task_payload "$O" 1)")")"
case "$m" in *"task-001"*) ok "numeric id '1' maps to task-001" ;; *) bad "numeric id '1' maps to task-001" "got: $m" ;; esac
m="$(ctx "$(run_on "$TASK_H" "$(task_payload "$O" "feature-x")")")"
case "$m" in *"does not map"*) ok "an unmappable id is reported, not guessed" ;; *) bad "an unmappable id is reported, not guessed" "got: $m" ;; esac

echo "--- the vocabulary is enforced ---"
echo '{"task_id":"task-001","status":"done","validation":[{"command":"npm test","result":"pass"}]}' > "$HD/task-001.json"
m="$(ctx "$(run_on "$TASK_H" "$(task_payload "$O" task-001)")")"
case "$m" in *"not in the vocabulary"*) ok "a status outside the vocabulary is flagged" ;; *) bad "a status outside the vocabulary is flagged" "got: $m" ;; esac
case "$m" in *"cancelled"*) ok "the flagged message lists the vocabulary including cancelled" ;; *) bad "lists the vocabulary" "got: $m" ;; esac

echo "--- evidence decides, not status alone ---"
echo '{"task_id":"task-001","status":"completed","validation":[{"command":"npm test","result":"pass"}]}' > "$HD/task-001.json"
out="$(run_on "$TASK_H" "$(task_payload "$O" task-001)")"
is_silent "$out" && ok "completed WITH validation => {}" || bad "completed WITH validation => {}" "got: $out"
echo '{"task_id":"task-001","status":"completed","validation":[]}' > "$HD/task-001.json"
m="$(ctx "$(run_on "$TASK_H" "$(task_payload "$O" task-001)")")"
case "$m" in *"no evidence"*) ok "completed with empty validation is flagged" ;; *) bad "completed with empty validation is flagged" "got: $m" ;; esac
for st in partial failed blocked cancelled; do
  echo "{\"task_id\":\"task-001\",\"status\":\"$st\",\"validation\":[]}" > "$HD/task-001.json"
  out="$(run_on "$TASK_H" "$(task_payload "$O" task-001)")"
  is_silent "$out" && ok "'$st' with no validation is NOT flagged (honest reporting)" \
    || bad "'$st' with no validation is NOT flagged" "got: $(ctx "$out")"
done

echo "=== teammate-idle-check (TeammateIdle) ==="

echo "--- gated silently without agent teams ---"
I="$TMPROOT/idle"; mkobj "$I"; mktask "$I" task-002 running
out="$(run_off "$IDLE_H" "$(idle_payload "$I")")"
is_silent "$out" && ok "teams unset => {} even with a running task and no handoff" || bad "teams unset => {}" "got: $out"

echo "--- silent outside orchestration ---"
out="$(run_on "$IDLE_H" "$(idle_payload "$P")")"
is_silent "$out" && ok "no objective => {}" || bad "no objective => {}" "got: $out"

echo "--- a running task with no handoff earns a nudge ---"
out="$(run_on "$IDLE_H" "$(idle_payload "$I")")"; m="$(ctx "$out")"
[ -n "$m" ] && ok "nudges when a running task has no handoff" || bad "nudges when a running task has no handoff" "got: $out"
case "$m" in *"task-002"*) ok "names the running task" ;; *) bad "names the running task" "got: $m" ;; esac
case "$m" in *"researcher"*) ok "names the idle teammate" ;; *) bad "names the idle teammate" "got: $m" ;; esac
case "$m" in *"agent-9c21"*) ok "carries agent_id" ;; *) bad "carries agent_id" "got: $m" ;; esac
case "$m" in *cancelled*) ok "offers the way out (failed/cancelled) so dependents unblock" ;; *) bad "offers the way out" "got: $m" ;; esac
ev="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName // empty')"
[ "$ev" = "TeammateIdle" ] && ok "declares hookEventName TeammateIdle" || bad "declares hookEventName TeammateIdle" "got: '$ev'"
sm="$(printf '%s' "$out" | jq -r '.systemMessage // empty')"
[ "$sm" = "$m" ] && ok "the same nudge goes out as systemMessage" || bad "systemMessage mirrors additionalContext" "got: '$sm'"
one_object "$out" && ok "exactly one JSON object on stdout" || bad "exactly one JSON object on stdout" "got: $out"
if printf '%s' "$out" | jq -e '.continue == false' >/dev/null 2>&1; then
  bad "never stops the teammate via JSON" "emitted continue:false"
else ok "never stops the teammate via JSON"; fi

echo "--- only tasks that owe a handoff are named ---"
mktask "$I" task-003 running
echo '{"task_id":"task-003","status":"partial","validation":[]}' > "$I/.dev-files/objectives/auth-system/handoffs/task-003.json"
m="$(ctx "$(run_on "$IDLE_H" "$(idle_payload "$I")")")"
case "$m" in *"task-002"*) ok "still names the task without a handoff" ;; *) bad "still names the task without a handoff" "got: $m" ;; esac
case "$m" in *"task-003"*) bad "does not name a running task whose handoff exists" "got: $m" ;; *) ok "does not name a running task whose handoff exists" ;; esac
echo '{"task_id":"task-002","status":"completed","validation":[{"command":"make test","result":"pass"}]}' > "$I/.dev-files/objectives/auth-system/handoffs/task-002.json"
out="$(run_on "$IDLE_H" "$(idle_payload "$I")")"
is_silent "$out" && ok "every running task has a handoff => {}" || bad "every running task has a handoff => {}" "got: $out"
rm -f "$I/.dev-files/objectives/auth-system/handoffs/task-002.json"
mktask "$I" task-002 pending
m="$(ctx "$(run_on "$IDLE_H" "$(idle_payload "$I")")")"
[ -z "$m" ] && ok "a pending task owes nothing yet" || bad "a pending task owes nothing yet" "got: $m"

echo "=== never blocks, never hangs ==="
for H in "$TASK_H" "$IDLE_H"; do
  n="$(basename "$H")"
  for label in empty malformed devnull; do
    for teams in 1 ""; do
      case "$label" in
        empty)     printf ''                | CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS="$teams" bash "$H" >/dev/null 2>&1; rc=$? ;;
        malformed) printf 'not json at all' | CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS="$teams" bash "$H" >/dev/null 2>&1; rc=$? ;;
        devnull)   CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS="$teams" bash "$H" </dev/null >/dev/null 2>&1; rc=$? ;;
      esac
      [ "$rc" -eq 0 ] && ok "$n: $label stdin exits 0 (teams='${teams}')" || bad "$n: $label stdin exits 0 (teams='${teams}')" "rc=$rc"
    done
  done
  out="$(printf 'not json at all' | CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 bash "$H" 2>/dev/null)"
  one_object "$out" && ok "$n: malformed stdin still prints one JSON object" || bad "$n: malformed stdin still prints one JSON object" "got: $out"
done

echo "=== wiring (advisory until hooks.json carries these events) ==="
for pair in "TaskCompleted:task-handoff-check.sh" "TeammateIdle:teammate-idle-check.sh"; do
  ev="${pair%%:*}"; script="${pair##*:}"
  cmd="$(jq -r --arg ev "$ev" '(.hooks[$ev] // [])[0].hooks[0].command // empty' "$ROOT/hooks/hooks.json" 2>/dev/null)"
  case "$cmd" in
    *"$script") ok "hooks.json wires $ev to $script" ;;
    "") echo "  warn hooks.json does not wire $ev yet (expected entry: bash \"\${CLAUDE_PLUGIN_ROOT}\"/hooks/$script)" ;;
    *) bad "hooks.json wires $ev to $script" "got: $cmd" ;;
  esac
done

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -gt 0 ] && { printf 'failing:'; printf ' %s' "${FAILED[@]}"; echo; exit 1; }
exit 0
