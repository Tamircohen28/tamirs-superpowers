#!/usr/bin/env bash
# task-handoff-check.sh — TaskCompleted hook for agent teams (ADVISORY, never blocks).
#
# WHY THIS EXISTS
#   subagent-handoff-check.sh covers the subagent path: when a worker returns,
#   it checks that a handoff exists and that `completed` carries evidence. With
#   CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 a named subagent launches as a
#   teammate instead, and SubagentStop is no longer the moment that matters —
#   the moment is the teammate marking its task complete on the shared task
#   list. `TaskCompleted` fires exactly then, with the host task id and the
#   teammate's name, so the same contract is checked at the same point in the
#   team flow: a handoff file exists for the task, its status is in the
#   vocabulary (completed | partial | failed | blocked | cancelled, per
#   core/workflow/handoff-schema.json), and `completed` has a non-empty
#   validation[]. The full contract is docs/engineering/architecture/handoff-protocol.md.
#
# HOW THE HOST TASK MAPS TO A HANDOFF FILE
#   The hooks reference shows `task_id` as "task-001", which is this repo's own
#   `task-NNN` id and maps to handoffs/task-001.json directly. A bare integer id
#   ("1") is zero-padded to the same shape. Anything else is reported as
#   unmappable rather than guessed at — a wrong guess would either pass a task
#   that owes a handoff or flag one that does not.
#
# WHY exit 0 AND BOTH CHANNELS
#   TaskCompleted documents two controls: exit 2 (completion refused, stderr fed
#   back to the teammate) and `{"continue": false}` (teammate stopped). Both are
#   enforcement, and this plugin's handoff hooks inform; they never gate, for the
#   reason worker-dev gives — flagging honest `partial` reporting trains workers
#   to overclaim. So this always exits 0. The documented advisory channel on this
#   event is `systemMessage` (shown to the user). `hookSpecificOutput.
#   additionalContext` is emitted alongside it for the lead, the same shape
#   subagent-handoff-check.sh uses, but the hooks reference does not list
#   TaskCompleted among the events that read additionalContext, so whether the
#   lead sees it is unverified; the user-visible message is the guaranteed path.
#
# CONTRACT
#   - Silent (`{}`) unless CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS is on. The event
#     also fires from the plain TaskUpdate tool without a team, but outside a
#     team the subagent hook already covers the handoff and this one stays out
#     of the way.
#   - Silent unless an objective is active under .dev-files/objectives/.
#   - Always exits 0. Exactly one JSON object on stdout.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hook-output.sh
source "${SCRIPT_DIR}/lib/hook-output.sh"

teams="$(printf '%s' "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}" | tr '[:upper:]' '[:lower:]')"
case "$teams" in
  1|true|yes|on) ;;
  *) hook_stop_ok ;;
esac

input="$(hook_read_stdin)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -n "$cwd" ] || cwd="$PWD"
task_id="$(printf '%s' "$input" | jq -r '.task_id // empty' 2>/dev/null || true)"
task_subject="$(printf '%s' "$input" | jq -r '.task_subject // empty' 2>/dev/null || true)"
teammate="$(printf '%s' "$input" | jq -r '.teammate_name // empty' 2>/dev/null || true)"
agent_id="$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null || true)"

repo_root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$cwd")"
obj_dir="${repo_root}/.dev-files/objectives"
[ -d "$obj_dir" ] || hook_stop_ok
objective="$(find "$obj_dir" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | head -1 || true)"
[ -n "$objective" ] || hook_stop_ok
obj_id="$(basename "$objective")"

who="teammate"
[ -n "$teammate" ] && who="teammate '${teammate}'"
[ -n "$agent_id" ] && who="${who} (${agent_id})"
what="task"
[ -n "$task_id" ] && what="task '${task_id}'"
[ -n "$task_subject" ] && what="${what} (${task_subject})"

# Map the host task id onto this repo's task-NNN handoff name.
handoff_id=""
case "$task_id" in
  task-[0-9][0-9][0-9]) handoff_id="$task_id" ;;
  *)
    if printf '%s' "$task_id" | grep -Eq '^[0-9]{1,3}$'; then
      handoff_id="$(printf 'task-%03d' "$((10#$task_id))")"
    fi
    ;;
esac

vocab="completed partial failed blocked cancelled"
problem=""
if [ -z "$handoff_id" ]; then
  problem="its id does not map to a task-NNN handoff name, so no handoff file could be checked. Confirm .dev-files/objectives/${obj_id}/handoffs/ has a handoff for this work before treating it as done"
else
  handoff="${objective}/handoffs/${handoff_id}.json"
  if [ ! -f "$handoff" ]; then
    problem="no handoff exists at .dev-files/objectives/${obj_id}/handoffs/${handoff_id}.json. A handoff is a task's entire output — the integrator reads that file, not the task-list status. Have the teammate emit one (handoff.sh emit ${obj_id} ${handoff_id} --status ...); until then treat the work as partial, never as done"
  else
    status="$(jq -r '.status // empty' "$handoff" 2>/dev/null || true)"
    case " $vocab " in
      *" $status "*) ;;
      *) problem="its handoff reports status '${status:-<missing>}', which is not in the vocabulary (${vocab// /|}). Re-report honestly with one of those before integrating" ;;
    esac
    if [ -z "$problem" ] && [ "$status" = "completed" ]; then
      n="$(jq -r '(.validation // []) | length' "$handoff" 2>/dev/null || echo 0)"
      if [ "${n:-0}" -eq 0 ]; then
        problem="its handoff reports 'completed' with an empty validation[]. That is a claim with no evidence. Verify before integrating, or have the teammate re-report as partial/failed/blocked"
      fi
    fi
  fi
fi

[ -n "$problem" ] || hook_stop_ok

msg="${who} is marking ${what} complete under objective '${obj_id}', but ${problem}."
jq -n --arg m "$msg" \
  '{hookSpecificOutput:{hookEventName:"TaskCompleted",additionalContext:$m},systemMessage:$m}'
