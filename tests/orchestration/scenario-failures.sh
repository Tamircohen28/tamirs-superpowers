#!/usr/bin/env bash
# Scenario: worker failure, validation failure, and scope escape.
#
# The point is NOT that a failure is detected — the point is what survives it.
# After a worker fails, the objective must still parse, still validate, still
# report the other tasks correctly, and still refuse to be delivered. A state
# model that corrupts on the first bad worker is worse than no state model.
# shellcheck shell=bash

section "worker failure does not corrupt the objective"

sim_new "$(harness_tmpdir)" resilience "Failure handling"

sim_state task-add resilience --role implementer --scope 'src/auth/**' --title "Good"   >/dev/null
sim_state task-add resilience --role implementer --scope 'src/api/**'  --title "Bad"    >/dev/null
sim_state task-add resilience --role implementer --scope 'docs/**'     --title "Other"  >/dev/null
sim_cut_integration >/dev/null

fake_worker task-001 success
fake_worker task-002 fail          # Tier 1 validation failed
fake_worker task-003 success

judge "the failed task is recorded as failed" \
  "failed" "$(sim_state task-show resilience task-002 | jq -r .status)"
judge "its attempt counter was bumped" 1 "$(sim_state task-show resilience task-002 | jq -r .attempts)"
judge "the failing handoff records the failing validation, not a fake pass" \
  1 "$(sim_handoff show resilience task-002 | jq '[.validation[] | select(.result == "fail")] | length')"
judge "and the risk is carried forward for the orchestrator" \
  "high" "$(sim_handoff show resilience task-002 | jq -r '.risks[0].severity')"

judge "the objective still validates after a worker failed" \
  true "$(sim_state validate resilience | jq -r .valid)"
judge "the sibling tasks are untouched" "completed completed" \
  "$(sim_state tasks resilience | jq -r '[.[] | select(.id != "task-002") | .status] | join(" ")')"
judge "objective.json is still parseable JSON" 0 \
  "$(jq empty "$SIM_STATE/resilience/objective.json" >/dev/null 2>&1; echo $?)"
judge "integration refuses to start with a failed task open" \
  false "$(sim_state integrate-ready resilience | jq -r .ready)"
judge "and names the failed task as the blocker" "task-002" \
  "$(sim_state integrate-ready resilience | jq -r '[.blocking[].id] | join(" ")')"
judge "a failed worker did not open a PR either" 0 "$(gh_calls 'pr create')"

section "a worker that writes outside its declared scope is refused"

# task-002's scope is src/api/** — the escaping worker writes unrelated/secret.txt.
esc_rc=0
fake_worker task-002 scope-escape || esc_rc=$?
judge "handoff.sh refuses the out-of-scope handoff (exit 4)" 4 "$esc_rc"
judge "no completed handoff was written for the escaping worker" \
  "failed" "$(sim_handoff show resilience task-002 | jq -r .status)"
judge "the objective survives the refusal" true "$(sim_state validate resilience | jq -r .valid)"

section "a blocked worker reports rather than inventing progress"

fake_worker task-003 noop 2>/dev/null || true
judge "the blocked handoff overwrote the completed one with status blocked" \
  "blocked" "$(sim_handoff show resilience task-003 | jq -r .status)"
judge "it carries a blocking followup for the orchestrator" \
  "true" "$(sim_handoff show resilience task-003 | jq -r '.followups[0].blocking')"
judge "it claims no commits" 0 "$(sim_handoff show resilience task-003 | jq '.commits | length')"
