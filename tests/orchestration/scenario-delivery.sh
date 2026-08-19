#!/usr/bin/env bash
# Scenario: one user objective produces exactly ONE PR.
#
# The delivery unit assertion, end to end: three workers, an integration, a
# review, then delivery. The recording gh shim counts every GitHub call across
# the WHOLE run, so "exactly one PR" is measured over the entire lifecycle and
# not just over the delivery step.
# shellcheck shell=bash

# Fragment, not an entrypoint: sourced by tests/test-orchestration.sh. Run standalone it would die on
# the first helper call with an opaque 127, so say what to run instead.
if ! declare -f judge >/dev/null 2>&1; then
  printf 'This file is a test fragment, not an entrypoint.\nRun: bash tests/test-orchestration.sh\n' >&2
  exit 2
fi

section "one objective, one PR"

sim_new "$(harness_tmpdir)" one-pr "Single delivery unit"

sim_state task-add one-pr --role implementer --scope 'src/auth/**' --title "Core"  >/dev/null
sim_state task-add one-pr --role implementer --scope 'src/api/**'  --title "API"   >/dev/null
sim_state task-add one-pr --role implementer --scope 'docs/**'     --title "Docs"  >/dev/null

judge "the default delivery strategy is single-pr" \
  "single-pr" "$(sim_state show one-pr | jq -r .delivery.strategy)"

sim_cut_integration >/dev/null
for t in task-001 task-002 task-003; do fake_worker "$t" success; done
judge "zero PRs exist after the entire worker phase" 0 "$(gh_calls 'pr create')"

fake_integrator >/dev/null
fake_reviewer approve "combined diff is coherent" >/dev/null
judge "zero PRs exist after integration and review" 0 "$(gh_calls 'pr create')"

fake_delivery

judge "EXACTLY ONE PR was created for the whole objective" 1 "$(gh_calls 'pr create')"
judge "the one PR targets the base branch from the integration branch" yes \
  "$(has "$(cat "$SIM_GHLOG")" "--base main --head objective/one-pr")"
judge "the PR url is recorded on the objective" \
  "https://github.com/example/example/pull/1" "$(sim_state show one-pr | jq -r .delivery.pr_url)"
judge "the objective ends completed" "completed" "$(sim_state show one-pr | jq -r .status)"
judge "no worker branch was ever pushed independently" 0 "$(gh_calls 'push .*worker/')"

section "a second delivery unit needs a stated exception"

multi_rc=0
sim_state set-delivery one-pr --strategy multi-pr >/dev/null 2>&1 || multi_rc=$?
judge "multi-pr without a reason is refused" yes \
  "$(if [ "$multi_rc" -ne 0 ]; then echo yes; else echo no; fi)"
judge "the strategy is unchanged after the refusal" \
  "single-pr" "$(sim_state show one-pr | jq -r .delivery.strategy)"

sim_state set-delivery one-pr --strategy multi-pr \
  --reason "deployment sequencing requires separation (core/policies/delivery.md)" >/dev/null
judge "multi-pr is accepted once an enumerated exception is named" \
  "multi-pr" "$(sim_state show one-pr | jq -r .delivery.strategy)"
judge "and the reason is recorded on the objective, not just asserted in chat" yes \
  "$(has "$(sim_state show one-pr | jq -r .delivery.exception_reason)" "deployment sequencing")"
