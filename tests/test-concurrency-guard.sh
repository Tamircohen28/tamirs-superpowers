#!/usr/bin/env bash
# End-to-end tests for the agent-concurrency guard (hooks/protect-other-branches.sh
# + hooks/lib/agent-claim.sh).
#
# WHY END-TO-END AND NOT UNIT
#   The guard's value is entirely in the seam: a command string on one side, a
#   claim file written by some *other* agent on the other. A unit test of the
#   parser alone would pass against a parser whose output the hook then ignores,
#   and a unit test of claim_inspect alone would pass against a hook that asks
#   it about the wrong branch — which is exactly the defect this file exists to
#   pin. So every case here feeds real JSON to the real hook against a real
#   temporary repo and a real planted claim, and asserts on the real decision.
#
# WHY BOTH DIRECTIONS
#   A guard that only ever blocks is indistinguishable from a broken guard.
#   Half of these cases assert ALLOW.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/hooks/protect-other-branches.sh"

PASS=0
FAIL=0
FAILED_NAMES=()

command -v jq >/dev/null 2>&1 || { echo "FATAL: jq is required to run these tests"; exit 1; }
[ -f "$HOOK" ] || { echo "FATAL: hook not found at $HOOK"; exit 1; }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

# A throwaway repo whose origin is acme/repo and whose checked-out branch is
# `main` — so a naive positional parser that falls back to the current branch
# resolves to exactly the branch our synthetic claim holds.
REPO="$TMPROOT/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q -b main
git -C "$REPO" remote add origin https://github.com/acme/repo.git
git -C "$REPO" -c user.email=t@e -c user.name=t commit -q --allow-empty -m init

# plant_claim <resource> <age-seconds>
# Writes a claim held by a DIFFERENT agent, on a DIFFERENT host (so the
# same-host pid liveness short-circuit does not apply and `age` governs).
plant_claim() {
  local resource="$1" age="$2" dir="$3" key
  mkdir -p "$dir"
  key="$(printf '%s' "$resource" | tr '/:@#' '____' | tr -c 'A-Za-z0-9._-' '_')"
  jq -n --arg r "$resource" --argjson hb "$(( $(date +%s) - age ))" \
    '{schema:"agent-work-claim/1", resource:$r, agent_id:"other-agent",
      tool:"codex", host:"some-other-host", pid:1, heartbeat_at:$hb,
      note:"synthetic claim"}' > "$dir/${key}.json"
}

# run_hook <command> <claim-dir> — prints the decision: ALLOW | DENY:<reason>
run_hook() {
  local cmd="$1" dir="$2" out decision reason
  out=$(jq -n --arg c "$cmd" --arg cwd "$REPO" \
          '{tool_name:"Bash", tool_input:{command:$c}, cwd:$cwd, session_id:"test-session"}' \
        | AGENT_CLAIM_DIR="$dir" AGENT_CLAIM_ID="test-agent" AGENT_CLAIM_TOOL="claude-code" \
          bash "$HOOK" 2>/dev/null)
  if ! printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
    printf 'MALFORMED:%s' "$out"; return
  fi
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"')
  reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""')
  if [ "$decision" = "deny" ]; then printf 'DENY:%s' "$reason"; else printf 'ALLOW'; fi
}

# check <name> <expect: ALLOW|BLOCKED|CANNOTRUN> <command> [claim-age-seconds]
check() {
  local name="$1" expect="$2" cmd="$3" age="${4:-0}"
  local dir result ok=0
  dir="$TMPROOT/claims.$((PASS + FAIL))"
  plant_claim "git:acme/repo@main" "$age" "$dir"
  result="$(run_hook "$cmd" "$dir")"

  case "$expect" in
    ALLOW)     [ "$result" = "ALLOW" ] && ok=1 ;;
    BLOCKED)   case "$result" in DENY:BLOCKED*) ok=1 ;; esac ;;
    CANNOTRUN) case "$result" in DENY*"CONCURRENCY GUARD CANNOT RUN"*) ok=1 ;; esac ;;
  esac

  if [ "$ok" = 1 ]; then
    PASS=$((PASS + 1)); printf '  ok   %-58s [%s]\n' "$name" "$expect"
  else
    FAIL=$((FAIL + 1)); FAILED_NAMES+=("$name")
    printf '  FAIL %-58s expected %s, got: %s\n' "$name" "$expect" "${result%%$'\n'*}"
  fi
}

echo "--- concurrency guard: git push destination resolution ---"
echo "    (synthetic live claim on git:acme/repo@main, held by another agent)"

# The regression. A leading flag used to shift the positional read, the parse
# came back empty, and the guard silently fell back to the current branch
# (`main`) — blocking a push that cannot possibly collide.
check "push -q to a feature branch is allowed"      ALLOW   "git push -q origin feature-x"
check "push HEAD:feature-x is allowed"              ALLOW   "git push origin HEAD:feature-x"
check "push -u to a feature branch is allowed"      ALLOW   "git push -u origin feature-x"
check "push --force-with-lease to feature allowed"  ALLOW   "git push --force-with-lease origin feature-x"
check "push +src:feature-x is allowed"              ALLOW   "git push origin +HEAD:feature-x"
check "push -o ci.skip origin feature-x allowed"    ALLOW   "git push -o ci.skip origin feature-x"

# The other direction: the claimed branch must still be blocked in every shape.
check "push -q to the claimed branch is blocked"    BLOCKED "git push -q origin main"
check "push HEAD:main is blocked"                   BLOCKED "git push origin HEAD:main"
check "push --force-with-lease main is blocked"     BLOCKED "git push --force-with-lease origin main"
check "push refs/heads/main is blocked"             BLOCKED "git push origin refs/heads/main"
check "multiple refspecs: main among them blocked"  BLOCKED "git push origin feature-x main"
check "push --delete origin main is blocked"        BLOCKED "git push --delete origin main"
check "bare push (upstream is main) is blocked"     BLOCKED "git push"
check "push origin (no refspec) is blocked"         BLOCKED "git push origin"
check "push origin HEAD is blocked"                 BLOCKED "git push origin HEAD"
check "push chained after && is blocked"            BLOCKED "git add -A && git push -q origin main"

# Undeterminable destination: must be LOUD. Not allowed (would miss a real
# collision) and not silently blocked (would be the old guessing bug wearing a
# different hat).
check "push --all cannot be resolved -> CANNOT RUN" CANNOTRUN "git push --all origin"
check "push --mirror cannot be resolved"            CANNOTRUN "git push --mirror origin"

# Staleness still releases: a claim whose heartbeat is older than the threshold
# (900s) is not a live holder.
check "stale claim on main releases the branch"     ALLOW   "git push origin main" 1000

echo "--- concurrency guard: non-push targets (regression guard, must not change) ---"
# Bug B: an issue number that is not in the literal command string (a shell
# variable, or a wrapper function) is NOT determinable, and the guard says so
# rather than reporting 'free'.
check "gh issue comment with non-literal number"    CANNOTRUN 'gh issue comment "$ISSUE" --body hi'
check "unrelated command is allowed"                ALLOW   "ls -la"

echo "--- liveness probe uses ps -p, not kill -0 ---"
# `kill -0` returns EPERM for a live process owned by another user, which reads
# as "dead" and would release a live claim. pin the implementation.
if grep -q 'ps -p' "$ROOT/hooks/lib/agent-claim.sh" \
   && ! grep -qE '^[^#]*kill -0' "$ROOT/hooks/lib/agent-claim.sh"; then
  PASS=$((PASS + 1)); printf '  ok   %-58s [PIN]\n' "claim_pid_alive uses ps -p and not kill -0"
else
  FAIL=$((FAIL + 1)); FAILED_NAMES+=("ps -p liveness pin")
  printf '  FAIL %-58s\n' "claim_pid_alive must use ps -p, never kill -0"
fi

echo
echo "passed: $PASS   failed: $FAIL"
if [ "$FAIL" -ne 0 ]; then
  printf 'failing: %s\n' "${FAILED_NAMES[*]}"
  exit 1
fi
exit 0
