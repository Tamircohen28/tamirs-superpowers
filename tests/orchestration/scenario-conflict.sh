#!/usr/bin/env bash
# Scenario: a merge conflict, resolved at integration and nowhere else.
#
# The graph validator only catches LITERALLY identical scope globs. 'src/**' and
# 'src/shared*' are different strings that describe overlapping files, so this is
# exactly the case the orchestrate-dev skill warns about: "if the conflict shows
# the task graph was wrong, fix the graph". The assertions pin who is allowed to
# fix it — the integrator, on the integration branch, never a worker.
# shellcheck shell=bash

# Fragment, not an entrypoint: sourced by tests/test-orchestration.sh. Run standalone it would die on
# the first helper call with an opaque 127, so say what to run instead.
if ! declare -f judge >/dev/null 2>&1; then
  printf 'This file is a test fragment, not an entrypoint.\nRun: bash tests/test-orchestration.sh\n' >&2
  exit 2
fi

section "merge conflict — resolved by the integrator, on the integration branch"

sim_new "$(harness_tmpdir)" conflicting "Conflicting writes"

sim_state task-add conflicting --role implementer --scope 'src/**'        --title "Broad"  >/dev/null
sim_state task-add conflicting --role implementer --scope 'src/shared*'   --title "Narrow" >/dev/null

judge "the validator passes — the overlap is semantic, not textual" \
  true "$(sim_state validate conflicting | jq -r .valid)"

sim_cut_integration >/dev/null
fake_worker task-001 success src/shared.txt "from task-001"
fake_worker task-002 success src/shared.txt "from task-002"

judge "both workers completed independently" 2 \
  "$(sim_handoff list conflicting | jq '[.[] | select(.status == "completed")] | length')"
ahead1="$(git -C "$SIM_REPO" rev-list --count objective/conflicting..worker/conflicting/001)"
ahead2="$(git -C "$SIM_REPO" rev-list --count objective/conflicting..worker/conflicting/002)"
judge "neither worker merged the other's branch (1 commit each)" "1 1" "$ahead1 $ahead2"

merge_log="$(fake_integrator)"
judge "the first branch merges, the second conflicts" 1 \
  "$(printf '%s\n' "$merge_log" | grep -c '^conflict ')"
judge "the conflict is on the integration branch, not a worker branch" \
  "objective/conflicting" "$(git -C "$SIM_REPO" rev-parse --abbrev-ref HEAD)"
judge "git is mid-merge, so nothing was silently dropped" yes "$(exists "$SIM_REPO/.git/MERGE_HEAD")"
judge "no PR was attempted while the objective was conflicted" 0 "$(gh_calls 'pr create')"

fake_integrator_resolve src/shared.txt "resolved: task-001 + task-002"

judge "the resolution landed on the integration branch" \
  "resolved: task-001 + task-002" \
  "$(git -C "$SIM_REPO" show objective/conflicting:src/shared.txt)"
judge "the merge is finished" no "$(exists "$SIM_REPO/.git/MERGE_HEAD")"
anc1=yes; git -C "$SIM_REPO" merge-base --is-ancestor worker/conflicting/001 objective/conflicting || anc1=no
anc2=yes; git -C "$SIM_REPO" merge-base --is-ancestor worker/conflicting/002 objective/conflicting || anc2=no
judge "both worker branches are ancestors of the integration branch" "yes yes" "$anc1 $anc2"
judge "worker branches were never rewritten by the resolution" "from task-001" \
  "$(git -C "$SIM_REPO" show worker/conflicting/001:src/shared.txt)"
judge "the objective still validates after a conflicted integration" \
  true "$(sim_state validate conflicting | jq -r .valid)"
