#!/usr/bin/env bash
# Tests for the integrator carve-out in hooks/protect-other-branches.sh.
#
# WHY THIS IS A SEPARATE FILE FROM test-concurrency-guard.sh
#   That file pins the guard's general contract and must keep asserting it
#   unchanged. This one pins the single, deliberately narrow exception the
#   objective model needs — and, just as importantly, its boundaries. A
#   carve-out that is not tested for what it REFUSES to cover is not a
#   carve-out, it is a hole: three of the six cases here assert that the
#   exception does NOT apply.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/hooks/protect-other-branches.sh"

PASS=0
FAIL=0
FAILED_NAMES=()

command -v jq >/dev/null 2>&1 || { echo "FATAL: jq is required"; exit 1; }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT
export HOME="$TMPROOT/home"
mkdir -p "$HOME/.claude"

REPO="$TMPROOT/repo"
mkdir -p "$REPO"
git -C "$REPO" init -q -b main
git -C "$REPO" remote add origin https://github.com/acme/repo.git
git -C "$REPO" -c user.email=t@e -c user.name=t commit -q --allow-empty -m init
mkdir -p "$REPO/.dev-files/objectives/auth"
jq -n '{id:"auth", status:"active", integration_branch:"objective/auth"}' \
  > "$REPO/.dev-files/objectives/auth/objective.json"

ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); printf '  FAIL %s — %s\n' "$1" "$2"; }

plant_claim() {
  local resource="$1" dir="$2" key
  mkdir -p "$dir"
  key="$(printf '%s' "$resource" | tr '/:@#' '____' | tr -c 'A-Za-z0-9._-' '_')"
  jq -n --arg r "$resource" --argjson hb "$(date +%s)" \
    '{schema:"agent-work-claim/1", resource:$r, agent_id:"worker-agent",
      tool:"claude-code", host:"some-other-host", pid:1, heartbeat_at:$hb,
      note:"worker holds its own branch"}' > "$dir/${key}.json"
}

# run <name> <expect: ALLOW|BLOCKED> <command> <claimed-resource> [env...]
run() {
  local name="$1" expect="$2" cmd="$3" resource="$4"; shift 4
  local dir="$TMPROOT/claims.$((PASS + FAIL))" out decision result
  plant_claim "$resource" "$dir"
  out=$(jq -n --arg c "$cmd" --arg cwd "$REPO" \
          '{tool_name:"Bash", tool_input:{command:$c}, cwd:$cwd, session_id:"integrator-session"}' \
        | env AGENT_CLAIM_DIR="$dir" AGENT_CLAIM_ID="integrator-agent" \
              AGENT_CLAIM_TOOL="claude-code" "$@" bash "$HOOK" 2>/dev/null)
  decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)
  [ "$decision" = "deny" ] && result=BLOCKED || result=ALLOW
  if [ "$result" = "$expect" ]; then ok "$name"; else bad "$name" "expected $expect, got $result"; fi
}

echo "--- without the integrator role, nothing changes ---"

run "a worker branch held by another agent is BLOCKED" BLOCKED \
  "git push origin worker/auth/001" "git:acme/repo@worker/auth/001"

run "SUPERPOWERS_ROLE=implementer gets no carve-out" BLOCKED \
  "git push origin worker/auth/001" "git:acme/repo@worker/auth/001" \
  SUPERPOWERS_ROLE=implementer

echo "--- the integrator may take worker branches of ITS objective ---"

run "integrator pushing a worker branch of its objective is ALLOWED" ALLOW \
  "git push origin worker/auth/001" "git:acme/repo@worker/auth/001" \
  SUPERPOWERS_ROLE=integrator

run "integrator pushing a different worker of the same objective is ALLOWED" ALLOW \
  "git push origin worker/auth/007" "git:acme/repo@worker/auth/007" \
  SUPERPOWERS_ROLE=integrator

echo "--- and nothing else ---"

run "integrator does NOT get another objective's worker branch" BLOCKED \
  "git push origin worker/billing/001" "git:acme/repo@worker/billing/001" \
  SUPERPOWERS_ROLE=integrator

run "two integrators still collide on the integration branch" BLOCKED \
  "git push origin objective/auth" "git:acme/repo@objective/auth" \
  SUPERPOWERS_ROLE=integrator

run "integrator does NOT get main" BLOCKED \
  "git push origin main" "git:acme/repo@main" \
  SUPERPOWERS_ROLE=integrator

run "integrator does NOT get a held PR" BLOCKED \
  "gh pr merge 42 --squash" "github:acme/repo#pr-42" \
  SUPERPOWERS_ROLE=integrator

echo "--- reading and local integration are never guarded at all ---"

for cmd in \
  "git fetch origin" \
  "git log worker/auth/001" \
  "git cherry-pick abc123" \
  "git merge --no-ff worker/auth/001" \
  "git show worker/auth/001:src/app.ts"
do
  run "'$cmd' is not a guarded operation" ALLOW "$cmd" "git:acme/repo@worker/auth/001"
done

echo
echo "passed: $PASS   failed: $FAIL"
if [ "$FAIL" -ne 0 ]; then
  printf 'failing: %s\n' "${FAILED_NAMES[*]}"
  exit 1
fi
exit 0
