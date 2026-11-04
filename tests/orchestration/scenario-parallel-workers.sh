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

# Transitive ordering counts too. In A -> B -> C, A and C never run together even
# though neither lists the other in depends_on, so a scope they share is sequenced.
# Mirrors plan-dev's validate_plan.py, which exempts any dependency PATH.
sim_new "$(harness_tmpdir)" chain "Transitive chain, shared scope"
sim_state task-add chain --role implementer --scope 'src/shared.txt' --title "A" >/dev/null
sim_state task-add chain --role implementer --scope 'src/api/**' --depends-on task-001 --title "B" >/dev/null
sim_state task-add chain --role implementer --scope 'src/shared.txt' --depends-on task-002 --title "C" >/dev/null
judge "a 3-task chain whose ends share a file validates" \
  true "$(sim_state validate chain | jq -r .valid)"

# The exemption must not leak: an unrelated task on the same file still races both.
sim_state task-add chain --role implementer --scope 'src/shared.txt' --title "D (unrelated)" >/dev/null
chain_rc=0
chain_err="$(sim_state validate chain 2>&1 >/dev/null)" || chain_rc=$?
judge "an unrelated task sharing that file is still rejected (exit 4)" 4 "$chain_rc"
judge "it collides with the chain's first task" yes "$(has "$chain_err" "task-001 and task-004 share write scope")"
judge "and with the chain's last task" yes "$(has "$chain_err" "task-003 and task-004 share write scope")"
judge "but the transitively ordered pair is still not reported" no \
  "$(has "$chain_err" "task-001 and task-003 share write scope")"

section "worktree placement — --worktree-base / AGENT_WORKTREE_BASE"

# --root names the repository; the worktree base is a separate choice. Every
# call passes --base so no default-branch lookup (and no gh) is involved.
rw="$REPO_ROOT/skills/dev-workflow/_shared/scripts/resolve-worktree.sh"
# canon: git reports the repo root physically (/private/var on macOS), so build
# every expected path from the physical temp dir.
wb_tmp="$(canon "$(harness_tmpdir)")"
wb_repo="$wb_tmp/repo"; wb_base="$wb_tmp/elsewhere/wt"; wb_other="$wb_tmp/other-base"
harness_new_repo "$wb_repo" main

wb_int="$(bash "$rw" --objective demo --integration --base main --root "$wb_repo" --worktree-base "$wb_base" 2>/dev/null)"
judge "--worktree-base places the integration worktree at <base>/<slug>/integration" \
  "$wb_base/demo/integration" "$(jq -r .worktree_path <<<"$wb_int")"
judge "the integration branch name is unchanged" "objective/demo" "$(jq -r .branch <<<"$wb_int")"
judge "it reports the objective layout and was created" "objective true" \
  "$(jq -r '"\(.layout) \(.created)"' <<<"$wb_int")"
judge "the worktree really exists there" yes "$(exists "$wb_base/demo/integration/.git")"

wb_t1="$(AGENT_WORKTREE_BASE="$wb_base" bash "$rw" --objective demo --task 1 --root "$wb_repo" 2>/dev/null)"
judge "AGENT_WORKTREE_BASE places a task worktree at <base>/<slug>/task-NNN" \
  "$wb_base/demo/task-001" "$(jq -r .worktree_path <<<"$wb_t1")"
judge "the worker branch name is unchanged, and it starts off the integration branch" \
  "worker/demo/001 objective/demo" "$(jq -r '"\(.branch) \(.base)"' <<<"$wb_t1")"

wb_t2="$(AGENT_WORKTREE_BASE="$wb_other" bash "$rw" --objective demo --task 2 --base main \
  --root "$wb_repo" --worktree-base "$wb_base" 2>/dev/null)"
judge "the flag wins over the environment variable" \
  "$wb_base/demo/task-002" "$(jq -r .worktree_path <<<"$wb_t2")"
judge "nothing was created under the losing env base" no "$(exists "$wb_other")"
judge "nothing was created under <repo>/.agent-worktrees" no "$(exists "$wb_repo/.agent-worktrees")"

wb_again="$(bash "$rw" --objective demo --task 1 --root "$wb_repo" 2>/dev/null)"
judge "a re-resolve without the flag resumes the existing custom-base worktree" \
  "$wb_base/demo/task-001 true false" "$(jq -r '"\(.worktree_path) \(.resumed) \(.created)"' <<<"$wb_again")"
judge "and still classifies it as the objective layout" objective "$(jq -r .layout <<<"$wb_again")"

wb_list="$(bash "$rw" --list --root "$wb_repo" 2>/dev/null)"
judge "--list (no flag) finds all three custom-base worktrees" 3 "$(jq length <<<"$wb_list")"
judge "--list classifies them as the objective layout, objective demo" "objective/demo" \
  "$(jq -r '[.[] | "\(.layout)/\(.objective)"] | unique | join(",")' <<<"$wb_list")"

# Legacy adoption is unchanged: a legacy platform worktree for the slug still wins.
git -C "$wb_repo" worktree add -q "$wb_repo/.claude/.worktrees/oldobj" -b feature/oldobj main 2>/dev/null
wb_legacy="$(bash "$rw" --objective oldobj --integration --base main --root "$wb_repo" --worktree-base "$wb_base" 2>/dev/null)"
judge "a legacy worktree is adopted even with a custom base" \
  "legacy-platform $wb_repo/.claude/.worktrees/oldobj" \
  "$(jq -r '"\(.layout) \(.worktree_path)"' <<<"$wb_legacy")"
judge "and no parallel worktree is created under the custom base" no "$(exists "$wb_base/oldobj")"

# The default is unchanged when neither the flag nor the env var is given.
wb_repo2="$wb_tmp/repo2"; harness_new_repo "$wb_repo2" main
wb_default="$(env -u AGENT_WORKTREE_BASE bash "$rw" --objective plain --integration --base main --root "$wb_repo2" 2>/dev/null)"
judge "without a base the worktree still lands in <repo>/.agent-worktrees" \
  "$wb_repo2/.agent-worktrees/plain/integration" "$(jq -r .worktree_path <<<"$wb_default")"
