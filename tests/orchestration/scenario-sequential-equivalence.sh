#!/usr/bin/env bash
# Scenario: the sequential fallback reaches the same final state as the parallel path.
#
# orchestrate-dev promises that a platform without subagents loses concurrency and
# nothing else: "same state model, same handoffs, same integration, same one PR —
# only the concurrency is gone". That is a testable claim, so it is tested by
# running one identical task graph twice and comparing fingerprints.
#
# The fingerprint deliberately excludes worktree paths, branch names, shas and
# timestamps. Those are concurrency artefacts; demanding they match would assert
# the opposite of the spec, which says the layout is metadata.
# shellcheck shell=bash

# Fragment, not an entrypoint: sourced by tests/test-orchestration.sh. Run standalone it would die on
# the first helper call with an opaque 127, so say what to run instead.
if ! declare -f judge >/dev/null 2>&1; then
  printf 'This file is a test fragment, not an entrypoint.\nRun: bash tests/test-orchestration.sh\n' >&2
  exit 2
fi

section "sequential fallback vs parallel dispatch"

build_graph() {
  sim_state task-add "$SIM_OBJ" --role implementer   --scope 'src/auth/**' --title "Core"  >/dev/null
  sim_state task-add "$SIM_OBJ" --role implementer   --scope 'src/api/**'  --title "API"   >/dev/null
  sim_state task-add "$SIM_OBJ" --role test-engineer --scope 'tests/**' --depends-on task-001,task-002 \
    --title "Tests" >/dev/null
}

# --- parallel path: worker worktrees, dispatched in one wave ---------------
sim_new "$(harness_tmpdir)" equivalence "Equivalence"
build_graph
sim_cut_integration >/dev/null
fake_worker task-001 success
fake_worker task-002 success
fake_worker task-003 success
fake_integrator >/dev/null
fake_delivery
parallel_fp="$(sim_fingerprint)"
parallel_prs="$(gh_calls 'pr create')"
parallel_merges="$(git -C "$SIM_REPO" ls-tree -r --name-only objective/equivalence | grep -c 'task-00')"

# --- sequential path: no subagents, `next` in a loop ------------------------
sim_new "$(harness_tmpdir)" equivalence "Equivalence"
build_graph
sim_cut_integration >/dev/null

guard=0
while :; do
  nxt="$(sim_state next equivalence)"
  [ -n "$nxt" ] || break
  guard=$((guard + 1)); [ "$guard" -le 10 ] || { bad "sequential loop terminates" "ran away"; break; }
  fake_worker "$nxt" success
done
judge "the sequential loop drained the graph in exactly 3 turns" 3 "$guard"
judge "and it respected the dependency (tests ran last)" "task-003" \
  "$(sim_state tasks equivalence | jq -r '.[-1].id')"

fake_integrator >/dev/null
fake_delivery
sequential_fp="$(sim_fingerprint)"
sequential_prs="$(gh_calls 'pr create')"
sequential_merges="$(git -C "$SIM_REPO" ls-tree -r --name-only objective/equivalence | grep -c 'task-00')"

judge "the sequential path reaches the SAME final state as the parallel path" \
  "$parallel_fp" "$sequential_fp"
judge "both paths deliver exactly one PR" "1 1" "$parallel_prs $sequential_prs"
judge "both paths integrate the same three contributions" \
  "$parallel_merges" "$sequential_merges"
