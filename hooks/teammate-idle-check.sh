#!/usr/bin/env bash
# teammate-idle-check.sh — TeammateIdle hook for agent teams (ADVISORY, never blocks).
#
# WHY THIS EXISTS
#   An agent-team teammate goes idle when its turn ends. The agent-teams doc
#   names the failure this catches: "teammates sometimes fail to mark tasks as
#   completed, which blocks dependent tasks." In this plugin's vocabulary that
#   is a task left `running` with no handoff written — the lead sees an idle
#   teammate and nothing on disk that says whether the work is done, partial, or
#   abandoned. `TeammateIdle` fires at exactly that moment, so this nudges once,
#   naming the running tasks that have no handoff, and lets the lead decide.
#
# WHY THE CHECK IS OBJECTIVE-WIDE
#   core/workflow/task-schema.json has no assignee field, so a task cannot be
#   tied to a teammate by name; the host's own task list under
#   ~/.claude/tasks/<team>/ is undocumented and is not read. The nudge therefore
#   lists every `running` task without a handoff in the active objective and
#   names the idle teammate — the lead knows who owns what. (An `assignee` field
#   is proposed in docs/engineering/architecture/handoff-protocol.md.)
#
# WHY exit 0 AND BOTH CHANNELS
#   TeammateIdle documents exit 2 (teammate kept working, stderr as feedback)
#   and `{"continue": false}` (teammate stopped). Both enforce; this plugin's
#   handoff hooks inform. `systemMessage` is the documented advisory channel on
#   this event; `hookSpecificOutput.additionalContext` is emitted alongside it
#   in the same shape as subagent-handoff-check.sh, but the hooks reference does
#   not list TeammateIdle among the events that read additionalContext, so
#   whether the lead sees it is unverified.
#
# CONTRACT
#   - Silent (`{}`) unless CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS is on (the event
#     does not fire otherwise) and an objective is active.
#   - Always exits 0. Exactly one JSON object on stdout.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hook-output.sh
source "${SCRIPT_DIR}/lib/hook-output.sh"
# shellcheck source=lib/worktree-common.sh
source "${SCRIPT_DIR}/lib/worktree-common.sh"
# shellcheck source=lib/objective-common.sh
source "${SCRIPT_DIR}/lib/objective-common.sh"

teams="$(printf '%s' "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}" | tr '[:upper:]' '[:lower:]')"
case "$teams" in
  1|true|yes|on) ;;
  *) hook_stop_ok ;;
esac

input="$(hook_read_stdin)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -n "$cwd" ] || cwd="$PWD"
teammate="$(printf '%s' "$input" | jq -r '.teammate_name // empty' 2>/dev/null || true)"
agent_id="$(printf '%s' "$input" | jq -r '.agent_id // empty' 2>/dev/null || true)"

# The ACTIVE objective, resolved from the main checkout (a hook fired inside a linked
# worker worktree would otherwise look for .dev-files/objectives where it does not
# exist and fall silent), honouring SUPERPOWERS_OBJECTIVE_ID, never "the first
# directory on disk", which may be a finished objective beside the live one.
objective="$(active_objective_dir "$cwd" 2>/dev/null || true)"
[ -n "$objective" ] && [ -d "$objective" ] || hook_stop_ok
obj_id="$(basename "$objective")"

# Tasks still `running` (this repo's in-progress state) with no handoff file.
open=()
if [ -d "${objective}/tasks" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    st="$(jq -r '.status // empty' "$f" 2>/dev/null || true)"
    [ "$st" = "running" ] || continue
    tid="$(jq -r '.id // empty' "$f" 2>/dev/null || true)"
    [ -n "$tid" ] || tid="$(basename "$f" .json)"
    [ -f "${objective}/handoffs/${tid}.json" ] && continue
    open+=("$tid")
  done < <(find "${objective}/tasks" -maxdepth 1 -name 'task-*.json' -print 2>/dev/null | sort)
fi

[ "${#open[@]}" -gt 0 ] || hook_stop_ok

who="A teammate"
[ -n "$teammate" ] && who="Teammate '${teammate}'"
[ -n "$agent_id" ] && who="${who} (${agent_id})"

msg="${who} is going idle under objective '${obj_id}' while these tasks are still running with no handoff: ${open[*]}. If the teammate owns one of them, the work is not done until a handoff is written (handoff.sh emit ${obj_id} <task-id> --status completed|partial|failed|blocked|cancelled); a task with no handoff is partial, never done. If it has stopped for good, mark the task failed or cancelled so dependents are not blocked on it."
jq -n --arg m "$msg" \
  '{hookSpecificOutput:{hookEventName:"TeammateIdle",additionalContext:$m},systemMessage:$m}'
