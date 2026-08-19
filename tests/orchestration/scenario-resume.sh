#!/usr/bin/env bash
# Scenario: the objective is resumable after a process restart.
#
# "Restart" is simulated the only honest way: a FRESH bash process, given nothing
# but the state root and the objective id, with every shell variable and function
# from this session unavailable to it. If that process can rebuild what the
# orchestrator knew — task graph, handoffs, what is next, whether integration may
# start — the state model genuinely lives on disk (spec §7, §28 "objective can
# resume after process/session restart").
# shellcheck shell=bash

# Fragment, not an entrypoint: sourced by tests/test-orchestration.sh. Run standalone it would die on
# the first helper call with an opaque 127, so say what to run instead.
if ! declare -f judge >/dev/null 2>&1; then
  printf 'This file is a test fragment, not an entrypoint.\nRun: bash tests/test-orchestration.sh\n' >&2
  exit 2
fi

section "resume after a simulated process restart"

sim_new "$(harness_tmpdir)" resumable "Resumable objective"

sim_state task-add resumable --role implementer   --scope 'src/auth/**' --title "Core" >/dev/null
sim_state task-add resumable --role implementer   --scope 'src/api/**'  --title "API"  >/dev/null
sim_state task-add resumable --role test-engineer --scope 'tests/**' --depends-on task-001 --title "Tests" >/dev/null
sim_cut_integration >/dev/null
fake_worker task-001 success
fake_worker task-002 success

before_tasks="$(sim_state tasks resumable | jq -S .)"
before_hand="$(sim_handoff list resumable | jq -S .)"
before_next="$(sim_state next resumable)"

# --- the restart -----------------------------------------------------------
# `env -i` clears the environment entirely: the child inherits no SIM_*, no
# exported OBJECTIVES_ROOT, nothing but what is passed explicitly.
S="$REPO_ROOT/skills/dev-workflow/_shared/scripts"
after_tasks="$(env -i PATH="$PATH" HOME="$HOME" OBJECTIVES_ROOT="$SIM_STATE" \
  bash "$S/objective-state.sh" tasks resumable | jq -S .)"
after_hand="$(env -i PATH="$PATH" HOME="$HOME" OBJECTIVES_ROOT="$SIM_STATE" \
  bash "$S/handoff.sh" list resumable | jq -S .)"
after_next="$(env -i PATH="$PATH" HOME="$HOME" OBJECTIVES_ROOT="$SIM_STATE" \
  bash "$S/objective-state.sh" next resumable)"
after_ready="$(env -i PATH="$PATH" HOME="$HOME" OBJECTIVES_ROOT="$SIM_STATE" \
  bash "$S/objective-state.sh" integrate-ready resumable | jq -r .ready)"
after_valid="$(env -i PATH="$PATH" HOME="$HOME" OBJECTIVES_ROOT="$SIM_STATE" \
  bash "$S/objective-state.sh" validate resumable | jq -r .valid)"

judge "the task graph survives the restart byte for byte" "$before_tasks" "$after_tasks"
judge "the handoffs survive the restart byte for byte"   "$before_hand"  "$after_hand"
judge "the next task to dispatch is unchanged"           "$before_next"  "$after_next"
judge "the restarted process knows integration is not ready" false "$after_ready"
judge "the restarted process can still validate the objective" true "$after_valid"
judge "and it recovers the dependent task's promotion" \
  "ready" "$(sim_state task-show resumable task-003 | jq -r .status)"

# The crucial negative: a completed task must never be re-run after a restart.
judge "the resumed run sees task-001 already completed" "completed" \
  "$(printf '%s' "$after_tasks" | jq -r '.[] | select(.id == "task-001") | .status')"
judge "its handoff is on disk and readable, so it is read, not redone" \
  "completed" "$(sim_handoff show resumable task-001 | jq -r .status)"

# A half-written state file must not be papered over.
printf '{ "id": "resumable",\n' > "$SIM_STATE/resumable/tasks/task-002.json"
torn_rc=0
sim_state validate resumable >/dev/null 2>&1 || torn_rc=$?
judge "a torn task file fails validation loudly rather than being ignored" \
  yes "$(if [ "$torn_rc" -ne 0 ]; then echo yes; else echo no; fi)"
