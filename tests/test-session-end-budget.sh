#!/usr/bin/env bash
# SessionEnd hooks must return inside Claude Code's 1.5 s SessionEnd budget.
#
# WHY A TIME BOUND IS THE ASSERTION
#   Claude Code cancels a plugin's SessionEnd hook after 1.5 s whatever
#   `timeout` hooks.json declares, and prints "SessionEnd hook [...] failed:
#   Hook cancelled" on every exit. A cancelled release-agent-claims.sh also
#   releases nothing, so "correct but slow" is indistinguishable from broken.
#   The bound is checked against a realistically bloated claim dir (the claim
#   layer never deletes expired claims, so they pile up), not an empty one —
#   an empty dir is exactly where the old one-jq-per-file loop looked fine.
#
# WHY BOTH DIRECTIONS
#   A release that deletes everything is fast too. Every timing case also
#   asserts that other agents' claims survive and this agent's are gone.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUDGET_MS="${SESSION_END_BUDGET_MS:-1500}"

PASS=0
FAIL=0
FAILED_NAMES=()

command -v jq >/dev/null 2>&1 || { echo "FATAL: jq is required to run these tests"; exit 1; }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

ok()   { PASS=$((PASS + 1)); printf '  ok    %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); printf '  FAIL  %s — %s\n' "$1" "$2"; }

now_ms() { perl -MTime::HiRes=time -e 'printf "%d", time * 1000'; }

# run_timed <stdin-json> <script> [env assignments...] — sets ELAPSED_MS, OUT, RC
run_timed() {
  local input="$1" script="$2" t0
  shift 2
  t0="$(now_ms)"
  OUT="$(printf '%s' "$input" | env "$@" bash "$script" 2>/dev/null)"
  RC=$?
  ELAPSED_MS=$(( $(now_ms) - t0 ))
}

# plant <dir> <resource-key> <agent-id>
plant() {
  jq -n --arg a "$3" --argjson hb "$(( $(date +%s) - 86400 ))" \
    '{schema:"agent-work-claim/1", resource:"synthetic", agent_id:$a,
      tool:"codex", host:"some-other-host", pid:1, heartbeat_at:$hb,
      note:"synthetic claim"}' > "$1/$2.json"
}

SESSION="11111111-2222-3333-4444-555555555555"
ME="claude-code:${SESSION}"
PAYLOAD="$(jq -n --arg s "$SESSION" '{session_id:$s, cwd:"/tmp", hook_event_name:"SessionEnd", reason:"prompt_input_exit"}')"

echo "--- release-agent-claims.sh ---"

claims="$TMPROOT/claims"
mkdir -p "$claims"
for i in $(seq 1 1500); do plant "$claims" "other-$i" "codex:other-$i"; done
plant "$claims" mine-1 "$ME"
plant "$claims" mine-2 "$ME"
# Mentions this agent's id without holding the claim: must survive.
jq -n --arg n "handed off from $ME" '{agent_id:"codex:successor", heartbeat_at:1, note:$n}' \
  > "$claims/mentions-me.json"

run_timed "$PAYLOAD" "$ROOT/hooks/release-agent-claims.sh" \
  AGENT_CLAIM_DIR="$claims" AGENT_CLAIM_TOOL="claude-code"

name="release returns within ${BUDGET_MS}ms against 1503 claims"
[ "$ELAPSED_MS" -lt "$BUDGET_MS" ] && ok "$name (${ELAPSED_MS}ms)" || bad "$name" "took ${ELAPSED_MS}ms"

name="release removes this agent's claims"
[ ! -e "$claims/mine-1.json" ] && [ ! -e "$claims/mine-2.json" ] && ok "$name" || bad "$name" "own claim still present"

name="release keeps other agents' claims"
left="$(find "$claims" -name 'other-*.json' | wc -l | tr -d ' ')"
[ "$left" = 1500 ] && ok "$name" || bad "$name" "expected 1500 left, found $left"

name="release keeps a claim that only mentions this agent"
[ -e "$claims/mentions-me.json" ] && ok "$name" || bad "$name" "deleted a claim held by someone else"

name="release exits 0"
[ "$RC" -eq 0 ] && ok "$name" || bad "$name" "rc=$RC"

echo "--- session-end.sh ---"

home="$TMPROOT/home"
files="$TMPROOT/session-files-src"
mkdir -p "$home/.claude/session-state" "$files"
for i in $(seq 1 200); do printf 'note %s\n' "$i" > "$files/note-$i.md"; done
jq -n --arg d "$files" '{session_files_dir:$d, session_slug:"budget-test"}' \
  > "$home/.claude/session-state/${SESSION}.json"

run_timed "$PAYLOAD" "$ROOT/hooks/session-end.sh" \
  HOME="$home" SUPERPOWERS_WORKTREE_CLEANUP=0

name="session-end returns within ${BUDGET_MS}ms"
[ "$ELAPSED_MS" -lt "$BUDGET_MS" ] && ok "$name (${ELAPSED_MS}ms)" || bad "$name" "took ${ELAPSED_MS}ms"

name="session-end emits valid JSON"
printf '%s' "$OUT" | jq -e '.suppressOutput == true' >/dev/null 2>&1 && ok "$name" || bad "$name" "stdout: $OUT"

# The archive is written detached; give it a bounded moment to land.
archive="$home/.claude/session-files/budget-test"
for _ in $(seq 1 50); do
  [ "$(find "$archive" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')" = 200 ] && break
  perl -e 'select(undef, undef, undef, 0.1)'
done
name="session-end still archives session files (detached)"
got="$(find "$archive" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
[ "$got" = 200 ] && ok "$name" || bad "$name" "archived $got of 200 files"

echo
echo "passed: $PASS   failed: $FAIL"
if [ "$FAIL" -ne 0 ]; then
  printf 'failing: %s\n' "${FAILED_NAMES[*]}"
  exit 1
fi
exit 0
