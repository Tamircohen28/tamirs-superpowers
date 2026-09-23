#!/usr/bin/env bash
# subagent-handoff-check.sh — SubagentStop hook (ADVISORY, never blocks).
#
# WHY THIS EXISTS
#   A worker's contract is `implementation -> targeted validation -> commit ->
#   handoff`, and worker-dev is blunt about the last step: "The handoff is your
#   entire output. The integrator will never read your reasoning — only this file."
#
#   The failure this catches is the orchestrator reading a subagent's closing
#   summary, seeing something that sounds finished, and integrating — when no
#   handoff was written, or one was written that claims success with no evidence.
#   worker-dev already names that second case: "A `completed` handoff with an empty
#   `validation[]` is a warning for good reason: it is a claim with no evidence."
#   Nothing enforced it at the moment it matters.
#
# WHY additionalContext AND NOT systemMessage
#   Deliberately the opposite choice from rate-limit-handoff.sh. There, the turn had
#   already failed and only the user remained, so `systemMessage` was right. Here the
#   session continues and the reader who must act is the ORCHESTRATOR — it is about
#   to decide whether to integrate. `hookSpecificOutput.additionalContext` is the
#   model-visible channel, and Stop/SubagentStop is one of the events that supports
#   it. A user-facing message would reach a human who is not making this call.
#
# CONTRACT
#   Never blocks. Always exits 0. Silent unless there is an objective in play — a
#   subagent spawned outside orchestration has no handoff to owe anyone.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hook-output.sh
source "${SCRIPT_DIR}/lib/hook-output.sh"

input="$(hook_read_stdin)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -n "$cwd" ] || cwd="$PWD"

repo_root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$cwd")"
obj_dir="${repo_root}/.dev-files/objectives"

# No orchestrated work in play: a subagent here owes no handoff. Say nothing.
[ -d "$obj_dir" ] || { echo '{"suppressOutput": true}'; exit 0; }

objective="$(find "$obj_dir" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null | head -1 || true)"
[ -n "$objective" ] || { echo '{"suppressOutput": true}'; exit 0; }

obj_id="$(basename "$objective")"
handoff_dir="${objective}/handoffs"

# Collect handoffs that claim success without evidence. `completed` with an empty
# validation[] is the case worker-dev calls out by name.
unevidenced=()
if [ -d "$handoff_dir" ]; then
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    status="$(jq -r '.status // empty' "$f" 2>/dev/null || true)"
    [ "$status" = "completed" ] || continue
    n="$(jq -r '(.validation // []) | length' "$f" 2>/dev/null || echo 0)"
    [ "${n:-0}" -eq 0 ] && unevidenced+=("$(basename "$f" .json)")
  done < <(find "$handoff_dir" -maxdepth 1 -name '*.json' -print 2>/dev/null)
fi

handoff_count=0
if [ -d "$handoff_dir" ]; then
  handoff_count="$(find "$handoff_dir" -maxdepth 1 -name '*.json' 2>/dev/null | grep -c . || true)"
fi

# Nothing to report: there are handoffs and none of them claim success unevidenced.
if [ "${handoff_count:-0}" -gt 0 ] && [ "${#unevidenced[@]}" -eq 0 ]; then
  echo '{"suppressOutput": true}'
  exit 0
fi

msg="Subagent finished under objective '${obj_id}'."
if [ "${handoff_count:-0}" -eq 0 ]; then
  msg="${msg} No handoff has been written to .dev-files/objectives/${obj_id}/handoffs/ yet. A worker's handoff is its entire output — the integrator reads that file, not the closing summary. Confirm the task actually wrote one before integrating; if the worker stopped early, treat that as 'partial', never as done."
else
  msg="${msg} These handoffs report status 'completed' with an empty validation[]: ${unevidenced[*]}. That is a claim with no evidence. Verify before integrating, or have the task re-report honestly as partial/failed/blocked."
fi

jq -n --arg m "$msg" '{hookSpecificOutput:{hookEventName:"SubagentStop",additionalContext:$m}}'
