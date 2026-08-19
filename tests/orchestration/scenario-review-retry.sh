#!/usr/bin/env bash
# Scenario: reviewer rejection, then one retry.
#
# Two contracts are under test. The reviewer is READ-ONLY — a rejection produces
# structured findings and changes no source file; the integrator applies the fix.
# And retry is bounded: one retry per task, tracked in `attempts`, so a second
# failure is a re-plan signal rather than an infinite loop.
# shellcheck shell=bash

# Fragment, not an entrypoint: sourced by tests/test-orchestration.sh. Run standalone it would die on
# the first helper call with an opaque 127, so say what to run instead.
if ! declare -f judge >/dev/null 2>&1; then
  printf 'This file is a test fragment, not an entrypoint.\nRun: bash tests/test-orchestration.sh\n' >&2
  exit 2
fi

section "reviewer rejection on the combined diff"

sim_new "$(harness_tmpdir)" review-loop "Review and retry"

sim_state task-add review-loop --role implementer --scope 'src/auth/**' --title "Core" >/dev/null
sim_state task-add review-loop --role implementer --scope 'src/api/**'  --title "API"  >/dev/null
sim_cut_integration >/dev/null
fake_worker task-001 success
fake_worker task-002 success
fake_integrator >/dev/null

tree_before="$(git -C "$SIM_REPO" rev-parse "objective/review-loop^{tree}")"
findings="$(fake_reviewer reject "the two contributions duplicate the token parser")"

judge "the reviewer returned a verdict" "reject" "$(printf '%s' "$findings" | jq -r .verdict)"
judge "findings are structured (severity/confidence/evidence/blocking)" "true" \
  "$(printf '%s' "$findings" | jq -r '[.findings[0] | has("severity"), has("confidence"), has("evidence"), has("blocking")] | all')"
judge "the finding is blocking" "true" "$(printf '%s' "$findings" | jq -r '.findings[0].blocking')"
judge "the reviewer changed NOTHING — read-only by contract" \
  "$tree_before" "$(git -C "$SIM_REPO" rev-parse "objective/review-loop^{tree}")"
judge "a rejected review does not open a PR" 0 "$(gh_calls 'pr create')"

# The integrator owns the fix (spec §11), on the integration branch.
fake_integrator_resolve src/auth/dedup.txt "single token parser"
judge "the integrator applied the fix on the integration branch" \
  "single token parser" "$(git -C "$SIM_REPO" show objective/review-loop:src/auth/dedup.txt)"
judge "worker branches were not touched by the fix" no \
  "$(has "$(git -C "$SIM_REPO" ls-tree -r --name-only worker/review-loop/001)" "dedup.txt")"

approved="$(fake_reviewer approve "duplication resolved")"
judge "re-review approves" "approve" "$(printf '%s' "$approved" | jq -r .verdict)"

section "bounded retry after a worker failure"

sim_new "$(harness_tmpdir)" retry-once "Retry policy"
sim_state task-add retry-once --role implementer --scope 'src/auth/**' --title "Flaky" >/dev/null
sim_cut_integration >/dev/null

fake_worker task-001 fail
judge "first attempt failed and was counted" "failed 1" \
  "$(sim_state task-show retry-once task-001 | jq -r '"\(.status) \(.attempts)"')"

# Retry: the orchestrator re-readies the task and dispatches once more.
sim_state task-set retry-once task-001 --status ready >/dev/null
fake_worker task-001 success
judge "the retry succeeded" "completed" "$(sim_state task-show retry-once task-001 | jq -r .status)"
judge "the attempt counter still reads 1 — one retry, not an open loop" \
  1 "$(sim_state task-show retry-once task-001 | jq -r .attempts)"
judge "the successful handoff replaced the failed one" \
  "completed" "$(sim_handoff show retry-once task-001 | jq -r .status)"
judge "no validation failure survives in the final handoff" 0 \
  "$(sim_handoff show retry-once task-001 | jq '[.validation[] | select(.result == "fail")] | length')"
judge "the objective is integration-ready after the retry" \
  true "$(sim_state integrate-ready retry-once | jq -r .ready)"
judge "the retry loop never touched GitHub" 0 "$(gh_calls 'pr create')"
