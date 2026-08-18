#!/usr/bin/env bash
# fake-agent.sh — scripted stand-ins for the agents an orchestration run dispatches.
#
# WHY FAKE AGENTS
#   The orchestration contract is a *state machine over git and JSON*, not a
#   property of any model. Everything worth pinning — that no worker opens a PR,
#   that integration waits for dependencies, that a failure leaves the objective
#   readable, that delivery is exactly one PR — is decided by objective-state.sh,
#   handoff.sh and git. So the workers are shell functions that produce the same
#   artifacts a real worker would (a branch, a commit, a handoff JSON) on command,
#   including on command *badly*: fail, escape scope, or collide.
#
#   Nothing here calls a model, the network, or gh. `fake_gh_install` puts a
#   RECORDING gh on PATH precisely so that any attempt to reach GitHub is captured
#   and asserted on instead of executed.
#
# Sourced by tests/orchestration/*.sh via tests/test-orchestration.sh.
#
# Every function takes an explicit "world" (a SIM_* environment set up by
# `sim_new`) rather than reading globals, so scenarios can be read top to bottom.

# shellcheck shell=bash

# ---------------------------------------------------------------------------
# The simulated world
# ---------------------------------------------------------------------------

# sim_new <root-dir> <objective-id> <title>
#
# Creates:
#   <root>/repo            a real git repo (the "user's" project), branch main
#   <root>/state           OBJECTIVES_ROOT — objective/task/handoff JSON
#   <root>/bin/gh          recording gh shim
#   <root>/gh.log          every gh invocation, one line each
#   <root>/worktrees       .agent-worktrees equivalent
#
# Exports SIM_ROOT, SIM_REPO, SIM_STATE, SIM_GHLOG, SIM_OBJ, SIM_WT, and puts the
# shim dir first on PATH.
sim_new() {
  SIM_ROOT="$1"
  SIM_OBJ="$2"
  local title="$3"

  SIM_REPO="$SIM_ROOT/repo"
  SIM_STATE="$SIM_ROOT/state"
  SIM_WT="$SIM_ROOT/worktrees"
  SIM_GHLOG="$SIM_ROOT/gh.log"
  mkdir -p "$SIM_STATE" "$SIM_WT" "$SIM_ROOT/bin"

  harness_new_repo "$SIM_REPO" main
  # A little real content so workers have something to change and collide over.
  mkdir -p "$SIM_REPO/src/auth" "$SIM_REPO/src/api" "$SIM_REPO/docs"
  printf 'shared\n' > "$SIM_REPO/src/shared.txt"
  printf '# project\n' > "$SIM_REPO/docs/README.md"
  git -C "$SIM_REPO" add -A
  git -C "$SIM_REPO" commit -q -m "chore: seed project"

  fake_gh_install "$SIM_ROOT/bin" "$SIM_GHLOG"
  PATH="$SIM_ROOT/bin:$PATH"
  export PATH OBJECTIVES_ROOT="$SIM_STATE"

  sim_state init "$SIM_OBJ" --title "$title" --base-branch main >/dev/null
}

# sim_state <args...> / sim_handoff <args...> — the real scripts under test,
# always with the simulated state root.
sim_state()   { OBJECTIVES_ROOT="$SIM_STATE" bash "$REPO_ROOT/skills/dev-workflow/_shared/scripts/objective-state.sh" "$@"; }
sim_handoff() { OBJECTIVES_ROOT="$SIM_STATE" bash "$REPO_ROOT/skills/dev-workflow/_shared/scripts/handoff.sh" "$@"; }

# ---------------------------------------------------------------------------
# The recording gh shim
# ---------------------------------------------------------------------------

# fake_gh_install <bindir> <logfile>
#
# Records every argv to the log and succeeds. It never talks to GitHub. `pr create`
# prints a plausible URL so a caller that parses stdout still works, which is what
# makes "exactly one PR" an assertion about behaviour rather than about a crash.
fake_gh_install() {
  local bindir="$1" log="$2"
  : > "$log"
  cat > "$bindir/gh" <<GHSHIM
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$log"
case "\$1 \${2:-}" in
  "pr create") printf 'https://github.com/example/example/pull/1\n' ;;
  "auth status") printf 'Logged in to github.com as test\n' ;;
esac
exit 0
GHSHIM
  chmod +x "$bindir/gh"
}

# gh_calls <pattern> — how many recorded gh invocations match.
gh_calls() { grep -c -- "$1" "$SIM_GHLOG" 2>/dev/null || true; }

# ---------------------------------------------------------------------------
# Branches and worktrees
# ---------------------------------------------------------------------------

# sim_cut_integration — create objective/<id> from base_branch.
sim_cut_integration() {
  local base integ
  base="$(sim_state show "$SIM_OBJ" | jq -r .base_branch)"
  integ="$(sim_state show "$SIM_OBJ" | jq -r .integration_branch)"
  git -C "$SIM_REPO" branch -f "$integ" "$base"
  printf '%s\n' "$integ"
}

# sim_worktree <task-id> — a real git worktree on worker/<obj>/<NNN>, cut from the
# integration branch. Real worktrees, because branch and worktree behaviour is
# exactly what a mocked filesystem would fail to catch.
sim_worktree() {
  local tid="$1" num branch integ path
  num="${tid#task-}"
  branch="worker/$SIM_OBJ/$num"
  integ="$(sim_state show "$SIM_OBJ" | jq -r .integration_branch)"
  path="$SIM_WT/$SIM_OBJ/$tid"
  git -C "$SIM_REPO" worktree add -q -b "$branch" "$path" "$integ" 2>/dev/null \
    || git -C "$SIM_REPO" worktree add -q "$path" "$branch"
  sim_state task-set "$SIM_OBJ" "$tid" --branch "$branch" --worktree "$path" >/dev/null
  printf '%s\n' "$path"
}

# ---------------------------------------------------------------------------
# The workers
# ---------------------------------------------------------------------------

# fake_worker <task-id> <mode> [file-relpath] [content]
#
# Modes:
#   success       commit inside scope, Tier 1 validation passes, handoff completed
#   fail          Tier 1 validation FAILS; commit still exists; handoff failed
#   scope-escape  writes outside the task's declared scope (handoff must refuse)
#   noop          no commit at all; handoff blocked
#
# The worker deliberately runs `gh auth status` first: a real worker is allowed to
# look at GitHub, it is only forbidden from *delivering*. Recording that call and
# still asserting zero `pr create` is a sharper assertion than "gh was never run".
_FAKE_WORKER_RUNS=0
fake_worker() {
  local tid="$1" mode="$2" rel="${3:-}"
  local wt scope branch sha content
  _FAKE_WORKER_RUNS=$((_FAKE_WORKER_RUNS + 1))
  # Distinct content per invocation: a retry must produce a real second commit,
  # not silently no-op on an identical file.
  content="${4:-worker $1 run $_FAKE_WORKER_RUNS}"

  wt="$(sim_state task-show "$SIM_OBJ" "$tid" | jq -r '.worktree // empty')"
  [ -n "$wt" ] && [ -d "$wt" ] || wt="$(sim_worktree "$tid")"
  branch="$(sim_state task-show "$SIM_OBJ" "$tid" | jq -r '.branch')"
  scope="$(sim_state task-show "$SIM_OBJ" "$tid" | jq -r '.scope[0]')"

  sim_state task-set "$SIM_OBJ" "$tid" --status running >/dev/null

  gh auth status >/dev/null 2>&1 || true   # allowed; delivery is not

  if [ -z "$rel" ]; then
    # Derive an in-scope path from the first scope glob: 'src/auth/**' -> src/auth/w.txt
    rel="${scope%%\**}"
    rel="${rel%/}/${tid}.txt"
  fi
  [ "$mode" = "scope-escape" ] && rel="unrelated/secret.txt"

  if [ "$mode" = "noop" ]; then
    sim_handoff emit "$SIM_OBJ" "$tid" --status blocked \
      --summary "could not start: precondition missing" \
      --followup "unblock the precondition|blocking|orchestrator" >/dev/null
    sim_state task-set "$SIM_OBJ" "$tid" --status blocked >/dev/null
    return 0
  fi

  mkdir -p "$wt/$(dirname "$rel")"
  printf '%s\n' "$content" > "$wt/$rel"
  git -C "$wt" add -A
  git -C "$wt" commit -q -m "feat($tid): simulated change"
  sha="$(git -C "$wt" rev-parse HEAD)"

  case "$mode" in
    success)
      sim_handoff emit "$SIM_OBJ" "$tid" --status completed --branch "$branch" \
        --commit "$sha" --file "$rel:added" \
        --validation "tier1-lint $rel|worker|pass" \
        --summary "simulated worker completed $tid" >/dev/null
      sim_state task-set "$SIM_OBJ" "$tid" --status completed >/dev/null
      ;;
    fail)
      sim_handoff emit "$SIM_OBJ" "$tid" --status failed --branch "$branch" \
        --commit "$sha" --file "$rel:added" \
        --validation "tier1-lint $rel|worker|fail|3 lint errors" \
        --risk "the change does not lint|high|revert or re-plan" \
        --summary "Tier 1 validation failed for $tid" >/dev/null
      sim_state task-set "$SIM_OBJ" "$tid" --status failed --bump-attempts >/dev/null
      ;;
    scope-escape)
      # Expected to be REFUSED by handoff.sh. Return its exit code to the caller.
      sim_handoff emit "$SIM_OBJ" "$tid" --status completed --branch "$branch" \
        --commit "$sha" --file "$rel:added" \
        --validation "tier1-lint $rel|worker|pass" >/dev/null 2>&1
      return $?
      ;;
    *) echo "fake_worker: unknown mode '$mode'" >&2; return 64 ;;
  esac
}

# ---------------------------------------------------------------------------
# Reviewer and integrator
# ---------------------------------------------------------------------------

# fake_reviewer <verdict> <finding-text> — structured findings per spec §11.
# Read-only by contract: it writes a findings file into the state dir and touches
# no source file. Prints the findings JSON.
fake_reviewer() {
  local verdict="$1" text="${2:-combined diff finding}"
  local out="$SIM_STATE/$SIM_OBJ/review.json"
  jq -n --arg v "$verdict" --arg t "$text" '{
    reviewer: "simulated", verdict: $v,
    findings: [ { severity: (if $v == "reject" then "high" else "low" end),
                  confidence: "high", files: ["src/auth/task-001.txt"],
                  evidence: $t, recommended_fix: "apply the fix on the integration branch",
                  blocking: ($v == "reject") } ]
  }' > "$out"
  cat "$out"
}

# fake_integrator — merge every completed task's branch into the integration
# branch, in task-id order. Prints "merged <branch>" or "conflict <branch>" per
# branch; conflicts are left staged so a scenario can resolve them explicitly.
fake_integrator() {
  local integ tid branch
  integ="$(sim_state show "$SIM_OBJ" | jq -r .integration_branch)"
  git -C "$SIM_REPO" checkout -q "$integ"
  for tid in $(sim_state tasks "$SIM_OBJ" | jq -r '.[] | select(.status == "completed") | .id'); do
    branch="$(sim_state task-show "$SIM_OBJ" "$tid" | jq -r '.branch // empty')"
    [ -n "$branch" ] || continue
    if git -C "$SIM_REPO" merge -q --no-ff -m "merge($tid)" "$branch" >/dev/null 2>&1; then
      printf 'merged %s\n' "$branch"
    else
      printf 'conflict %s\n' "$branch"
    fi
  done
}

# fake_integrator_resolve <path> <content> — the integrator, and ONLY the
# integrator, writes on the integration branch: to finish a conflicted merge, or
# to apply a reviewer's blocking finding. Both are integrator work per spec §11.
fake_integrator_resolve() {
  printf '%s\n' "$2" > "$SIM_REPO/$1"
  git -C "$SIM_REPO" add "$1"
  if [ -f "$SIM_REPO/.git/MERGE_HEAD" ]; then
    git -C "$SIM_REPO" commit -q --no-edit
  else
    git -C "$SIM_REPO" commit -q -m "fix(integration): $1"
  fi
}

# fake_delivery — what deliver-dev does to GitHub, and nothing more: push once,
# create exactly one PR. Runs through the recording shim.
fake_delivery() {
  local integ base
  integ="$(sim_state show "$SIM_OBJ" | jq -r .integration_branch)"
  base="$(sim_state show "$SIM_OBJ" | jq -r .base_branch)"
  sim_state set-status "$SIM_OBJ" delivering >/dev/null
  gh pr create --base "$base" --head "$integ" --title "objective: $SIM_OBJ" --body "one objective, one PR" >/dev/null
  sim_state set-delivery "$SIM_OBJ" --pr-url "https://github.com/example/example/pull/1" >/dev/null
  sim_state set-status "$SIM_OBJ" completed >/dev/null
}

# ---------------------------------------------------------------------------
# Fingerprinting — for "the sequential path reaches the same state"
# ---------------------------------------------------------------------------

# sim_fingerprint — the parts of the final state that must NOT depend on whether
# the run was parallel or sequential. Deliberately excludes timestamps, worktree
# paths, branch names and commit shas: those are concurrency artefacts, and
# demanding they match would assert the opposite of what the spec says (provider
# and layout are metadata, the state model is the contract).
sim_fingerprint() {
  local obj tasks hand
  obj="$(sim_state show "$SIM_OBJ" | jq -S '{id, status, base_branch, integration_branch,
                                              tasks, delivery: (.delivery | {strategy, pr_url: (.pr_url != null)})}')"
  tasks="$(sim_state tasks "$SIM_OBJ" | jq -S 'map({id, role, status, depends_on, validation_tier})')"
  hand="$(sim_handoff list "$SIM_OBJ" | jq -S 'map({task_id, status, files, validation_failures, blocking_followups})')"
  jq -n --argjson o "$obj" --argjson t "$tasks" --argjson h "$hand" \
    '{objective: $o, tasks: $t, handoffs: $h}'
}
