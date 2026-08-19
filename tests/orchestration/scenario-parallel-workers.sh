#!/usr/bin/env bash
# Scenario: three parallel independent workers.
#
# The base case the whole refactor exists for. Three tasks with disjoint write
# scope run concurrently, each ends at commit + handoff, and NOTHING reaches
# GitHub. The PR assertion is repeated in almost every scenario on purpose: it is
# the single invariant whose violation reintroduces the pre-refactor behaviour.
# shellcheck shell=bash

# Fragment, not an entrypoint: sourced by tests/test-orchestration.sh. Run standalone it would die on
# the first helper call with an opaque 127, so say what to run instead.
if ! declare -f judge >/dev/null 2>&1; then
  printf 'This file is a test fragment, not an entrypoint.\nRun: bash tests/test-orchestration.sh\n' >&2
  exit 2
fi

section "three parallel independent workers"

sim_new "$(harness_tmpdir)" auth-system "Implement authentication"

sim_state task-add auth-system --role implementer   --scope 'src/auth/**'  --title "Auth core"    >/dev/null
sim_state task-add auth-system --role implementer   --scope 'src/api/**'   --title "API routes"   >/dev/null
sim_state task-add auth-system --role implementer   --scope 'docs/**'      --title "Docs"         >/dev/null

judge "the three-task graph validates (disjoint scopes)" \
  true "$(sim_state validate auth-system | jq -r .valid)"
judge "all three tasks are ready with no dependencies" \
  3 "$(sim_state ready auth-system | jq 'length')"

sim_cut_integration >/dev/null
judge "the integration branch exists before any worker runs" \
  "objective/auth-system" \
  "$(git -C "$SIM_REPO" rev-parse --abbrev-ref objective/auth-system 2>/dev/null)"

for t in task-001 task-002 task-003; do fake_worker "$t" success; done

judge "three handoffs were emitted" 3 "$(sim_handoff list auth-system | jq 'length')"
judge "every handoff is completed" 3 \
  "$(sim_handoff list auth-system | jq '[.[] | select(.status == "completed")] | length')"
judge "every handoff carries a real commit sha" 3 \
  "$(sim_handoff list auth-system | jq '[.[] | select(.commits > 0)] | length')"
judge "every handoff carries Tier 1 evidence" 3 \
  "$(sim_handoff list auth-system | jq '[.[] | select(.validation_failures == 0)] | length')"

for t in task-001 task-002 task-003; do
  judge "$t handoff validates against the schema" true "$(sim_handoff validate auth-system "$t" | jq -r .valid)"
done

judge "each worker committed on its own worker/ branch" "3" \
  "$(git -C "$SIM_REPO" for-each-ref --format='%(refname:short)' 'refs/heads/worker/auth-system/*' | wc -l | tr -d ' ')"
judge "no worker branch was pushed" 0 "$(gh_calls 'push')"

# THE assertion.
judge "NO WORKER CREATED A PR" 0 "$(gh_calls 'pr create')"
judge "no worker enabled auto-merge" 0 "$(gh_calls 'pr merge')"
judge "the objective has no pr_url yet" "null" \
  "$(sim_state show auth-system | jq -r '.delivery.pr_url // "null"')"

judge "the objective is integration-ready once all three complete" \
  true "$(sim_state integrate-ready auth-system | jq -r .ready)"
judge "objective state still validates after three workers" \
  true "$(sim_state validate auth-system | jq -r .valid)"

# Scope overlap is only meaningful between OPEN tasks — two tasks that already
# completed cannot collide with each other. So this needs its own fresh graph.
sim_new "$(harness_tmpdir)" collide "Colliding scopes"
sim_state task-add collide --role implementer --scope 'src/auth/**' --title "A" >/dev/null
sim_state task-add collide --role implementer --scope 'src/auth/**' --title "B" >/dev/null
collide_rc=0
collide_err="$(sim_state validate collide 2>&1 >/dev/null)" || collide_rc=$?
judge "overlapping write scope is rejected by the graph validator (exit 4)" 4 "$collide_rc"
judge "and it names both colliding tasks" yes "$(has "$collide_err" "task-001 and task-002 share write scope")"

# The same two tasks are legal once one depends on the other: they no longer run
# concurrently, so the shared scope is sequenced rather than raced.
sim_new "$(harness_tmpdir)" sequenced "Sequenced same scope"
sim_state task-add sequenced --role implementer --scope 'src/auth/**' --title "A" >/dev/null
sim_state task-add sequenced --role implementer --scope 'src/auth/**' --depends-on task-001 --title "B" >/dev/null
judge "the same scope is allowed when one task depends on the other" \
  true "$(sim_state validate sequenced | jq -r .valid)"
