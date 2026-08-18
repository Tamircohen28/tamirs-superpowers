#!/usr/bin/env bash
# Scenario: a dependent worker, and integration waiting for it.
#
# Two invariants live here. (1) A task with unmet dependencies is never handed
# out — `ready` must not list it, and `next` must not return it. (2) Integration
# does not start while any task is open, which is what "integration waits for
# dependencies" means in a state model with no scheduler.
# shellcheck shell=bash

section "dependent worker — dependencies gate dispatch and integration"

sim_new "$(harness_tmpdir)" payments "Payments objective"

sim_state task-add payments --role implementer   --scope 'src/auth/**' --title "Core"  >/dev/null
sim_state task-add payments --role implementer   --scope 'src/api/**'  --title "API"   >/dev/null
sim_state task-add payments --role test-engineer --scope 'tests/**' --depends-on task-001,task-002 \
  --title "Integration tests" >/dev/null

judge "the dependent task starts pending, not ready" \
  "pending" "$(sim_state task-show payments task-003 | jq -r .status)"
judge "ready lists only the two independent tasks" \
  "task-001 task-002" "$(sim_state ready payments | jq -r '[.[].id] | join(" ")')"
judge "next never hands out the dependent task" \
  "task-001" "$(sim_state next payments)"
judge "integration is NOT ready while three tasks are open" \
  false "$(sim_state integrate-ready payments | jq -r .ready)"

sim_cut_integration >/dev/null
fake_worker task-001 success

judge "one dependency done is not enough to promote the dependent" \
  "pending" "$(sim_state ready payments >/dev/null; sim_state task-show payments task-003 | jq -r .status)"
judge "integration still blocked, and says by what" \
  "task-002 task-003" \
  "$(sim_state integrate-ready payments | jq -r '[.blocking[].id] | join(" ")')"

fake_worker task-002 success

judge "the dependent task is promoted once BOTH dependencies complete" \
  "ready" "$(sim_state task-show payments task-003 | jq -r .status)"
judge "and it is now the next task to dispatch" \
  "task-003" "$(sim_state next payments)"
judge "integration is still blocked by the dependent task itself" \
  false "$(sim_state integrate-ready payments | jq -r .ready)"

fake_worker task-003 success

judge "integration is ready only after the dependent task completes" \
  true "$(sim_state integrate-ready payments | jq -r .ready)"
judge "no PR was created at any point in the dependency chain" 0 "$(gh_calls 'pr create')"

# Dependency order is also the merge order — the integrator must not merge a
# dependent's branch before the branch it was built on.
merge_log="$(fake_integrator)"
judge "every completed branch merged cleanly in dependency order" 3 \
  "$(printf '%s\n' "$merge_log" | grep -c '^merged ')"
judge "the integrated branch contains all three contributions" 3 \
  "$(git -C "$SIM_REPO" ls-tree -r --name-only objective/payments | grep -c 'task-00')"
