#!/usr/bin/env bash
# Scenario: worker failure, validation failure, and scope escape.
#
# The point is NOT that a failure is detected — the point is what survives it.
# After a worker fails, the objective must still parse, still validate, still
# report the other tasks correctly, and still refuse to be delivered. A state
# model that corrupts on the first bad worker is worse than no state model.
# shellcheck shell=bash

# Fragment, not an entrypoint: sourced by tests/test-orchestration.sh. Run standalone it would die on
# the first helper call with an opaque 127, so say what to run instead.
if ! declare -f judge >/dev/null 2>&1; then
  printf 'This file is a test fragment, not an entrypoint.\nRun: bash tests/test-orchestration.sh\n' >&2
  exit 2
fi

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

section "scope-glob boundary semantics (bash * matches /)"

# WHY THIS IS HERE
#   The scope check in handoff.sh is the boundary that stops a worker writing
#   outside its declared area — the safety property scenario-failures.sh exercises
#   with an obvious escape. It is implemented with bash pattern matching, where
#   `*` matches `/` as well. That is easy to get wrong in the AUTHORING of a
#   scope, not just in the matcher, so the semantics are pinned here rather than
#   left to whoever next reads the glob and assumes shell-globbing rules.
#
#   Prompted by gh-test-harness hitting the same class in a `case` pattern, where
#   `repos/*/*` also matched `repos/{o}/{r}/collaborators`.

scope_matches() {  # scope_matches <glob> <path> -> yes|no
  local glob="$1" path="$2"
  # shellcheck disable=SC2053
  if [[ "$path" == $glob ]]; then echo yes; else echo no; fi
}

# The boundary that must hold: a trailing-slash prefix does not leak sideways.
judge "src/auth/** admits its own subtree" yes "$(scope_matches 'src/auth/**' 'src/auth/token.txt')"
judge "src/auth/** does NOT reach a sibling with a shared prefix" no \
  "$(scope_matches 'src/auth/**' 'src/authorization/secret.txt')"
judge "src/auth/** does NOT reach a hyphenated sibling" no \
  "$(scope_matches 'src/auth/**' 'src/auth-backup/x.txt')"
judge "src/api/** does NOT reach src/apikeys" no \
  "$(scope_matches 'src/api/**' 'src/apikeys/leak.txt')"

# The sharp edge, pinned deliberately as CURRENT behaviour rather than as desired
# behaviour: a single `*` segment does not mean "one level". Every shipped example
# uses `**`, so nothing in-repo is exposed today — but `src/*` is a natural way to
# write "files directly under src", and it silently grants the whole subtree.
# Reported to the handoff.sh owner; if that is tightened, this assertion is the
# one that will fail and should be updated to `no`.
judge "KNOWN SHARP EDGE: a single-* scope grants the whole subtree" yes \
  "$(scope_matches 'src/*' 'src/deep/nested/secret.txt')"
