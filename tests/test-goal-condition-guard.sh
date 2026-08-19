#!/usr/bin/env bash
# hooks/goal-condition-guard.sh — behaviour tests.
#
# WHAT THESE PIN DOWN, AND WHY EACH ONE IS HERE
#   The hook refuses a `/goal` whose condition cannot be satisfied by
#   construction (dev#637). Three properties matter, and they pull against each
#   other, so each has tests on both sides:
#
#     `blocks …`      The point of the hook. A warning-only version adds nothing
#                     over the prose guidance that already exists and did not
#                     prevent the incident, so "exit 2" is the contract, not an
#                     implementation detail.
#     `passes …`      A false positive blocks the USER's prompt. That is the
#                     real cost here, so the well-formed phrasings — especially
#                     `do not stop UNTIL <predicate>`, which is the shape the
#                     docs recommend — are pinned as hard requirements.
#     `is loud when it cannot run`
#                     A check that cannot run must say so. The nastiest variant
#                     is a field rename: `.prompt` disappearing would make this
#                     hook pass everything while looking perfectly healthy, so
#                     an unrecognised payload shape is a LOUD event, not a quiet
#                     exit 0.
#
#   Plus the property every hook here must hold: never hang, including with no
#   stdin at all — the shape that wedges a `$(cat)`-based hook until the harness
#   kills it.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/hooks/goal-condition-guard.sh"

PASS=0
FAIL=0
FAILED_NAMES=()

ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); printf '  FAIL %s — %s\n' "$1" "$2"; }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT

OUT="$TMPROOT/out"
ERR="$TMPROOT/err"
RC=0

# run <prompt> — populates $OUT, $ERR, $RC.
run() {
  jq -nc --arg p "$1" '{prompt:$p, session_id:"t", cwd:"/tmp"}' \
    | bash "$HOOK" >"$OUT" 2>"$ERR"
  RC=$?
}

# run_raw <literal stdin> — for payload shapes jq cannot express as a prompt.
run_raw() {
  printf '%s' "$1" | bash "$HOOK" >"$OUT" 2>"$ERR"
  RC=$?
}

blocked() { [ "$RC" -eq 2 ]; }
silent()  { [ "$RC" -eq 0 ] && [ -z "$(tr -d '[:space:]' <"$OUT")" ] && [ -z "$(tr -d '[:space:]' <"$ERR")" ]; }

echo "=== hooks/goal-condition-guard.sh ==="

# --- blocks the exact condition from the recorded incident ------------------
# dev#637, 2026-08-17 — the string that produced 21 consecutive blocks.
run '/goal complete ci/cd new system and then all of the remaing work, using sub agents. do not yield for anything from me, i approve all in advance.'
if blocked && grep -q 'stopping-forbidden' "$ERR"; then
  ok "blocks the verbatim dev#637 condition"
else
  bad "blocks the verbatim dev#637 condition" "rc=$RC err=$(head -c200 "$ERR")"
fi

# --- blocks each clause family independently --------------------------------
run '/goal keep going, do not yield for anything from me'
if blocked && grep -q 'stopping-forbidden' "$ERR"; then
  ok "blocks a stopping-forbidden clause"
else
  bad "blocks a stopping-forbidden clause" "rc=$RC err=$(head -c200 "$ERR")"
fi

run '/goal finish all the remaining work in the service repo'
if blocked && grep -q 'unbounded' "$ERR"; then
  ok "blocks an unbounded clause"
else
  bad "blocks an unbounded clause" "rc=$RC err=$(head -c200 "$ERR")"
fi

# Phrasing variants: the incident string is one sample, not the shape.
for variant in \
  "/goal don't stop for anything" \
  "/goal never stop, just keep shipping" \
  "/goal do all the work needed to ship this" \
  "/goal handle everything remaining on the board"
do
  run "$variant"
  if blocked; then
    ok "blocks variant: ${variant}"
  else
    bad "blocks variant: ${variant}" "rc=$RC (expected 2)"
  fi
done

# --- the rejection is actionable, not a bare refusal ------------------------
# A refusal that does not say how to rephrase just gets worked around.
run '/goal do not yield for anything'
if grep -q 'CHECKABLE PREDICATE' "$ERR" \
   && grep -q 'until issue #N is closed' "$ERR" \
   && grep -q 'dev#637' "$ERR"; then
  ok "rejection names the fix (checkable predicate) and cites the incident"
else
  bad "rejection names the fix and cites the incident" "err=$(head -c300 "$ERR")"
fi

# --- the rejection admits it is a heuristic ---------------------------------
# So nobody later reads a pass as proof the goal is satisfiable.
if grep -qi 'heuristic' "$ERR" && grep -qi 'not proof' "$ERR"; then
  ok "rejection states its own limits (heuristic, a pass is not proof)"
else
  bad "rejection states its own limits" "err=$(head -c300 "$ERR")"
fi

# --- emits a machine-readable decision as well as prose ---------------------
if jq -e '.decision == "block"' "$OUT" >/dev/null 2>&1 \
   && jq -e '.hookSpecificOutput.hookEventName == "UserPromptSubmit"' "$OUT" >/dev/null 2>&1; then
  ok "emits valid JSON in both decision dialects"
else
  bad "emits valid JSON in both decision dialects" "out=$(head -c200 "$OUT")"
fi

# --- PASSES: the shapes that must never be blocked --------------------------
# `until` is the recommended phrasing. Blocking it would punish correct usage.
run '/goal do not stop until CI is green on main'
if silent; then
  ok "passes 'do not stop UNTIL <predicate>' — the recommended shape"
else
  bad "passes 'do not stop UNTIL <predicate>'" "rc=$RC out=$(head -c120 "$OUT") err=$(head -c120 "$ERR")"
fi

for good in \
  "/goal until gh pr list --state open --repo ProductionMasterAI/dev is empty" \
  "/goal until issue #637 is closed" \
  "/goal fix all the failing tests in web" \
  "/goal run all tests and all linters until they pass"
do
  run "$good"
  if silent; then
    ok "passes clean: ${good}"
  else
    bad "passes clean: ${good}" "rc=$RC err=$(head -c150 "$ERR")"
  fi
done

# A bare "all" must not trip the unbounded pattern.
run '/goal update all the docs under docs/reference'
if silent; then
  ok "the bare word 'all' does not trip the unbounded pattern"
else
  bad "the bare word 'all' does not trip the unbounded pattern" "rc=$RC err=$(head -c150 "$ERR")"
fi

# --- silent on anything that is not /goal -----------------------------------
run 'rename the helper function in utils.go to parseHeader'
if silent; then
  ok "silent on a non-/goal prompt"
else
  bad "silent on a non-/goal prompt" "rc=$RC out=$(head -c120 "$OUT") err=$(head -c120 "$ERR")"
fi

# The clause families are only fatal in a /goal condition; in ordinary prose
# they are just words, and blocking them would be intolerable.
run 'the deploy script says do not stop the container mid-write'
if silent; then
  ok "does not screen ordinary prose containing the trigger words"
else
  bad "does not screen ordinary prose containing the trigger words" "rc=$RC err=$(head -c150 "$ERR")"
fi

# --- LOUD when it cannot run ------------------------------------------------
run_raw 'not json at all'
if [ "$RC" -eq 0 ] && grep -q 'CHECK DID NOT RUN' "$ERR"; then
  ok "malformed JSON: loud, and does not block"
else
  bad "malformed JSON: loud, and does not block" "rc=$RC err=$(head -c200 "$ERR")"
fi

# The field-rename trap. Valid JSON, recognised nowhere — this is the shape that
# would silently disarm the hook, so it must be the loudest case of all.
run_raw '{"message":"/goal do not yield for anything"}'
if [ "$RC" -eq 0 ] && grep -q 'CHECK DID NOT RUN' "$ERR" && grep -q 'renamed' "$ERR"; then
  ok "unknown payload shape is loud about a possible field rename"
else
  bad "unknown payload shape is loud about a possible field rename" "rc=$RC err=$(head -c200 "$ERR")"
fi

# `.user_input` is the name in the current published schema; `.prompt` is what
# this repo's other hooks read. Both must work, or a rename disarms the guard.
run_raw '{"user_input":"/goal do not yield for anything from me"}'
if blocked; then
  ok "reads .user_input as well as .prompt"
else
  bad "reads .user_input as well as .prompt" "rc=$RC (expected 2)"
fi

# An empty prompt is a real state, not a masked failure — quiet is correct here.
run_raw '{"prompt":""}'
if [ "$RC" -eq 0 ] && [ -z "$(tr -d '[:space:]' <"$ERR")" ]; then
  ok "an empty prompt field is quiet (a real state, not a failure)"
else
  bad "an empty prompt field is quiet" "rc=$RC err=$(head -c150 "$ERR")"
fi

# Bare `/goal` queries the current goal; there is nothing to screen, and that is
# reported rather than passed over in silence.
run '/goal'
if [ "$RC" -eq 0 ] && grep -q 'nothing to screen' "$ERR"; then
  ok "bare /goal says there was nothing to screen"
else
  bad "bare /goal says there was nothing to screen" "rc=$RC err=$(head -c150 "$ERR")"
fi

# --- never hangs ------------------------------------------------------------
bash "$HOOK" </dev/null >"$OUT" 2>"$ERR"
RC=$?
if [ "$RC" -eq 0 ] && [ -z "$(tr -d '[:space:]' <"$OUT")" ]; then
  ok "exits 0 and stays silent with no stdin"
else
  bad "exits 0 and stays silent with no stdin" "rc=$RC out=$(cat "$OUT")"
fi

echo
printf 'goal-condition-guard: %d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'failed: %s\n' "${FAILED_NAMES[*]}"
  exit 1
fi
