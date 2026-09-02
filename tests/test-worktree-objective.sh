#!/usr/bin/env bash
# End-to-end tests for the objective-aware worktree lifecycle:
#   hooks/capture-task-slug.sh      — stands down under an active objective
#   hooks/enforce-worktree-edits.sh — accepts BOTH layouts
#   hooks/worktree-create.sh        — --list sees both layouts
#
# WHY END-TO-END
#   Same reasoning as test-concurrency-guard.sh: the value is in the seam. A
#   unit test of active_objective_id would pass against a capture hook that
#   calls it and then creates the worktree anyway — which is the exact defect
#   this file pins. So every case runs the real hook against a real temporary
#   repo with real git worktrees, and asserts on the real side effect.
#
#   HOME is redirected to a temp dir for the whole run: the hooks write session
#   state and legacy worktrees under $HOME/.claude, and a test must never touch
#   the developer's actual ones.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

PASS=0
FAIL=0
FAILED_NAMES=()

command -v jq >/dev/null 2>&1 || { echo "FATAL: jq is required"; exit 1; }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

export HOME="$TMPROOT/home"
mkdir -p "$HOME/.claude"

ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); printf '  FAIL %s — %s\n' "$1" "$2"; }
judge() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$2', got '$3'"; fi; }

# has <haystack> <needle> — prints yes/no. A `case` statement cannot be written
# inline inside $( ), because its `)` closes the substitution.
has() { case "$1" in *"$2"*) echo yes ;; *) echo no ;; esac; }

# On macOS /var is a symlink to /private/var, so a path built by the test and
# the same path resolved by git compare unequal. Normalize both sides.
canon() { (cd "$1" 2>/dev/null && pwd -P) || printf '%s' "$1"; }

new_repo() {
  local dir="$1"
  mkdir -p "$dir"
  git -C "$dir" init -q -b main
  git -C "$dir" config user.email t@e
  git -C "$dir" config user.name t
  git -C "$dir" commit -q --allow-empty -m init
}

# run_capture <cwd> <prompt> <session-id> — stdout of capture-task-slug.sh
run_capture() {
  jq -n --arg cwd "$1" --arg p "$2" --arg s "$3" \
    '{session_id:$s, prompt:$p, cwd:$cwd}' \
    | bash "$ROOT/hooks/capture-task-slug.sh" 2>/dev/null
}

# run_enforce <file-path> <cwd> — ALLOW | DENY:<reason>
run_enforce() {
  local out decision
  out=$(jq -n --arg f "$1" --arg cwd "$2" \
          '{tool_name:"Edit", tool_input:{file_path:$f}, cwd:$cwd, session_id:"enforce-session"}' \
        | bash "$ROOT/hooks/enforce-worktree-edits.sh" 2>/dev/null)
  printf '%s' "$out" | jq -e . >/dev/null 2>&1 || { printf 'MALFORMED:%s' "$out"; return; }
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"')
  if [ "$decision" = "deny" ]; then
    printf 'DENY:%s' "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')"
  else
    printf 'ALLOW'
  fi
}

verdict() { case "$1" in ALLOW) printf ALLOW ;; DENY:*) printf DENY ;; *) printf '%s' "$1" ;; esac; }

# ---------------------------------------------------------------------------
echo "--- capture-task-slug: no objective => legacy worktree is still created ---"

PLAIN="$TMPROOT/plain"
new_repo "$PLAIN"
out="$(run_capture "$PLAIN" "add a login form" "sess-plain")"
legacy_wt="$HOME/.claude/worktrees/plain/add-a-login-form"

if [ -d "$legacy_wt" ]; then ok "creates ~/.claude/worktrees/<repo>/<slug>"; else bad "creates ~/.claude/worktrees/<repo>/<slug>" "missing $legacy_wt"; fi
judge "reports the worktree in additionalContext" \
  "yes" \
  "$(has "$out" "Dedicated worktree")"
judge "records the slug as sessionTitle" "add-a-login-form" \
  "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.sessionTitle')"

# ---------------------------------------------------------------------------
echo "--- capture-task-slug: active objective => STAND DOWN ---"

OBJ="$TMPROOT/objrepo"
new_repo "$OBJ"
mkdir -p "$OBJ/.dev-files/objectives/auth-system"
jq -n '{id:"auth-system", title:"Implement auth", base_branch:"main",
        integration_branch:"objective/auth-system", status:"active",
        tasks:["task-001"], delivery:{strategy:"single-pr"}}' \
  > "$OBJ/.dev-files/objectives/auth-system/objective.json"

before="$(git -C "$OBJ" worktree list | wc -l | tr -d ' ')"
out="$(run_capture "$OBJ" "add a login form" "sess-obj")"
after="$(git -C "$OBJ" worktree list | wc -l | tr -d ' ')"

judge "creates NO competing git worktree" "$before" "$after"
if [ -d "$HOME/.claude/worktrees/objrepo/add-a-login-form" ]; then
  bad "creates no legacy worktree directory" "it created one anyway"
else
  ok "creates no legacy worktree directory"
fi
judge "names the active objective in context" "yes" \
  "$(has "$out" "auth-system")"
judge "tells the agent not to create one" "yes" \
  "$(has "$out" "do not create one")"
judge "records objective_id in session state" "auth-system" \
  "$(jq -r '.objective_id // "none"' "$HOME/.claude/session-state/sess-obj.json" 2>/dev/null)"

echo "--- capture-task-slug: SUPERPOWERS_OBJECTIVE_ID alone is enough ---"

ENVOBJ="$TMPROOT/envobj"
new_repo "$ENVOBJ"
before="$(git -C "$ENVOBJ" worktree list | wc -l | tr -d ' ')"
out="$(SUPERPOWERS_OBJECTIVE_ID=env-driven run_capture "$ENVOBJ" "do the thing" "sess-env")"
after="$(git -C "$ENVOBJ" worktree list | wc -l | tr -d ' ')"
judge "env marker also suppresses worktree creation" "$before" "$after"
judge "env objective id is reported" "yes" \
  "$(has "$out" "env-driven")"

# ---------------------------------------------------------------------------
echo "--- enforce-worktree-edits: layouts accepted and rejected ---"

E="$TMPROOT/enforce"
new_repo "$E"

# Objective layout: integration + worker.
git -C "$E" worktree add -q -B objective/auth "$E/.agent-worktrees/auth/integration" main 2>/dev/null
git -C "$E" worktree add -q -B worker/auth/001 "$E/.agent-worktrees/auth/task-001" main 2>/dev/null
# Legacy platform-shaped layout (recognized, never generated).
git -C "$E" worktree add -q -B legacy/platform "$E/.claude/.worktrees/old-task" main 2>/dev/null
# Legacy global layout.
mkdir -p "$HOME/.claude/worktrees/enforce"
git -C "$E" worktree add -q -B wt/old-slug "$HOME/.claude/worktrees/enforce/old-slug" main 2>/dev/null

judge "main checkout is DENIED" DENY \
  "$(verdict "$(run_enforce "$E/src/app.ts" "$E")")"
judge "objective integration worktree is ALLOWED" ALLOW \
  "$(verdict "$(run_enforce "$E/.agent-worktrees/auth/integration/src/app.ts" "$E")")"
judge "objective worker worktree is ALLOWED" ALLOW \
  "$(verdict "$(run_enforce "$E/.agent-worktrees/auth/task-001/src/app.ts" "$E")")"
judge "legacy platform worktree is ALLOWED (never orphaned)" ALLOW \
  "$(verdict "$(run_enforce "$E/.claude/.worktrees/old-task/src/app.ts" "$E")")"
judge "legacy global worktree is ALLOWED" ALLOW \
  "$(verdict "$(run_enforce "$HOME/.claude/worktrees/enforce/old-slug/src/app.ts" "$E")")"

echo "--- enforce-worktree-edits: denial message follows the active objective ---"

mkdir -p "$E/.dev-files/objectives/auth"
jq -n '{id:"auth", status:"active"}' > "$E/.dev-files/objectives/auth/objective.json"
reason="$(run_enforce "$E/src/app.ts" "$E")"
judge "denial names the objective worktrees, not a new session worktree" "yes" \
  "$(has "$reason" ".agent-worktrees/auth/task-NNN")"
judge "denial forbids creating a new worktree" "yes" \
  "$(has "$reason" "do not create a new worktree")"
rm -rf "$E/.dev-files"

# ---------------------------------------------------------------------------
echo "--- worktree-create --list: sees both layouts, ignores the main checkout ---"

listing="$(bash "$ROOT/hooks/worktree-create.sh" --list --repo "$E" </dev/null 2>/dev/null)"
judge "lists the objective integration worktree" "yes" \
  "$(has "$listing" "objective-integration")"
judge "lists the objective worker worktree" "yes" \
  "$(has "$listing" "objective-worker")"
judge "lists the legacy platform worktree" "yes" \
  "$(has "$listing" "legacy-platform")"
judge "lists the legacy global worktree" "yes" \
  "$(has "$listing" "legacy-global")"
judge "does NOT list the main checkout" "no" \
  "$(has "$listing" "main-checkout")"

echo "--- worktree-create --migrate: prints a plan, changes nothing ---"

sha_before="$(git -C "$E" worktree list --porcelain | shasum -a 256 2>/dev/null || git -C "$E" worktree list --porcelain | cksum)"
plan="$(bash "$ROOT/hooks/worktree-create.sh" --migrate --objective auth --repo "$E" </dev/null 2>/dev/null)"
sha_after="$(git -C "$E" worktree list --porcelain | shasum -a 256 2>/dev/null || git -C "$E" worktree list --porcelain | cksum)"
judge "migration is a no-op on disk" "$sha_before" "$sha_after"
judge "plan proposes worktree move commands" "yes" \
  "$(has "$plan" "worktree move")"
judge "plan proposes worker branch renames" "yes" \
  "$(has "$plan" "worker/auth/")"

echo "--- worktree-create --objective/--unit: creates the objective layout ---"

C="$TMPROOT/create"
new_repo "$C"
path="$(bash "$ROOT/hooks/worktree-create.sh" --objective pay --unit integration --repo "$C" </dev/null 2>/dev/null)"
judge "integration worktree lands at .agent-worktrees/pay/integration" "$(canon "$C")/.agent-worktrees/pay/integration" "$path"
judge "integration worktree is on objective/pay" "objective/pay" \
  "$(git -C "$C/.agent-worktrees/pay/integration" symbolic-ref --short HEAD 2>/dev/null)"

path="$(bash "$ROOT/hooks/worktree-create.sh" --objective pay --unit task-002 --repo "$C" </dev/null 2>/dev/null)"
judge "worker worktree lands at .agent-worktrees/pay/task-002" "$(canon "$C")/.agent-worktrees/pay/task-002" "$path"
judge "worker worktree is on worker/pay/002" "worker/pay/002" \
  "$(git -C "$C/.agent-worktrees/pay/task-002" symbolic-ref --short HEAD 2>/dev/null)"

echo "--- worktree-remove: refuses what is not an agent worktree ---"

out="$(jq -n --arg p "$C" '{worktree_path:$p}' | bash "$ROOT/hooks/worktree-remove.sh" 2>&1 >/dev/null)"
judge "main checkout is refused" "yes" \
  "$(has "$out" "refusing to remove")"
if [ -d "$C/.git" ]; then ok "main checkout still exists"; else bad "main checkout still exists" "it was deleted"; fi

printf 'dirty\n' > "$C/.agent-worktrees/pay/task-002/uncommitted.txt"
out="$(jq -n --arg p "$C/.agent-worktrees/pay/task-002" '{worktree_path:$p}' | bash "$ROOT/hooks/worktree-remove.sh" 2>&1 >/dev/null)"
judge "worker with uncommitted work is not removed" "yes" \
  "$(has "$out" "uncommitted changes")"
if [ -d "$C/.agent-worktrees/pay/task-002" ]; then ok "uncommitted worker survives"; else bad "uncommitted worker survives" "it was deleted"; fi

jq -n --arg p "$C/.agent-worktrees/pay/integration" '{worktree_path:$p}' \
  | bash "$ROOT/hooks/worktree-remove.sh" >/dev/null 2>&1
if [ -d "$C/.agent-worktrees/pay/integration" ]; then
  bad "clean objective worktree is removed" "still present"
else
  ok "clean objective worktree is removed"
fi

# ---------------------------------------------------------------------------
echo "--- dependency install: configurable, cached, capped ---"

D="$TMPROOT/deps"
new_repo "$D"
printf '{"name":"x","version":"1.0.0"}\n' > "$D/package.json"
printf '{"lockfileVersion":3}\n' > "$D/package-lock.json"

run_setup() {
  bash -c 'source "$1/hooks/lib/worktree-common.sh"; run_worktree_post_setup "$2"' _ "$ROOT" "$D" >/dev/null 2>&1
}

SUPERPOWERS_WORKTREE_INSTALL_DEPS=0 run_setup
judge "disable switch is honoured" "yes" \
  "$(grep -q 'disabled' "$D/session-files/worktree-setup.log" && echo yes || echo no)"

# Second run with the same lockfile must skip rather than reinstall. Stamp the
# digest directly so the test does not depend on npm being installed.
stamp="$(bash -c 'source "$1/hooks/lib/worktree-common.sh"; worktree_deps_stamp_path "$2"' _ "$ROOT" "$D")"
hash="$(bash -c 'source "$1/hooks/lib/worktree-common.sh"; worktree_lockfile_hash "$2"' _ "$ROOT" "$D")"
printf '%s\n' "$hash" > "$stamp"
: > "$D/session-files/worktree-setup.log"
run_setup
judge "unchanged lockfiles skip the install" "yes" \
  "$(grep -q 'lockfiles unchanged' "$D/session-files/worktree-setup.log" && echo yes || echo no)"

judge "the stamp lives outside the work tree" "" \
  "$(git -C "$D" status --porcelain -- "$(basename "$stamp")" 2>/dev/null)"

printf '{"lockfileVersion":4}\n' > "$D/package-lock.json"
hash2="$(bash -c 'source "$1/hooks/lib/worktree-common.sh"; worktree_lockfile_hash "$2"' _ "$ROOT" "$D")"
if [ "$hash" != "$hash2" ]; then ok "a lockfile change moves the digest"; else bad "a lockfile change moves the digest" "digest unchanged"; fi

slots="$(bash -c 'source "$1/hooks/lib/worktree-common.sh"
  export SUPERPOWERS_MAX_CONCURRENT_INSTALLS=2 SUPERPOWERS_INSTALL_SLOT_WAIT=0
  a=$(_acquire_install_slot); b=$(_acquire_install_slot)
  c=$(_acquire_install_slot) || c=NONE
  printf "%s|%s|%s" "${a##*/}" "${b##*/}" "${c##*/}"
  _release_install_slot "$a"; _release_install_slot "$b"' _ "$ROOT")"
judge "the third concurrent installer is capped out" "slot-0|slot-1|NONE" "$slots"

# --- SUPERPOWERS_WORKTREE_CLEANUP ---------------------------------------------
#
# Two layers, because the interesting one cannot be asserted synchronously.
#
# The predicate is a pure function, so its accepted spellings are checked
# directly. The end-to-end case then proves the guard is actually WIRED to the
# pass — a correct predicate nobody calls would pass the first layer alone.
for v in 0 false off no never disabled; do
  judge "worktree_cleanup_enabled rejects '$v'" "disabled" \
    "$(bash -c 'source "$1/hooks/lib/worktree-common.sh"
       SUPERPOWERS_WORKTREE_CLEANUP="$2" worktree_cleanup_enabled && echo enabled || echo disabled' _ "$ROOT" "$v")"
done
for v in unset auto 1 true yes; do
  judge "worktree_cleanup_enabled accepts '$v'" "enabled" \
    "$(bash -c 'source "$1/hooks/lib/worktree-common.sh"
       if [ "$2" = unset ]; then unset SUPERPOWERS_WORKTREE_CLEANUP; else export SUPERPOWERS_WORKTREE_CLEANUP="$2"; fi
       worktree_cleanup_enabled && echo enabled || echo disabled' _ "$ROOT" "$v")"
done

# End-to-end. `cleanup_stale_worktrees` detaches, so there is no exit status to
# wait on and no synchronous moment to assert at: poll instead. "retired" is
# proven by the directory going away; "kept" is proven by it still being there
# after a window several times longer than the removal actually takes.
cleanup_case() {  # cleanup_case <value or "unset">
  local home="$TMPROOT/cleanup-home" stale i
  rm -rf "$home"
  stale="$home/.claude/worktrees/somerepo/old-task"
  mkdir -p "$stale/.git"
  touch -t 202001010000 "$stale"   # older than the 3-day default retention
  bash -c '
    export HOME="$1"
    source "$2/hooks/lib/worktree-common.sh"
    if [ "$3" = unset ]; then unset SUPERPOWERS_WORKTREE_CLEANUP; else export SUPERPOWERS_WORKTREE_CLEANUP="$3"; fi
    cleanup_stale_worktrees
  ' _ "$home" "$ROOT" "$1" >/dev/null 2>&1
  for i in 1 2 3 4 5 6 7 8 9 10; do
    [ -d "$stale" ] || { echo retired; return; }
    sleep 0.2
  done
  echo kept
}

judge "cleanup retires a stale worktree by default"     "retired" "$(cleanup_case unset)"
judge "SUPERPOWERS_WORKTREE_CLEANUP=0 skips the pass"   "kept"    "$(cleanup_case 0)"
judge "SUPERPOWERS_WORKTREE_CLEANUP=1 still runs"       "retired" "$(cleanup_case 1)"

echo
echo "passed: $PASS   failed: $FAIL"
if [ "$FAIL" -ne 0 ]; then
  printf 'failing: %s\n' "${FAILED_NAMES[*]}"
  exit 1
fi
exit 0
