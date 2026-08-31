#!/usr/bin/env bash
# Behaviour tests for hooks/goal-condition-lint.sh.
#
# WHAT IS ACTUALLY BEING PROTECTED
#   This hook BLOCKS a user's prompt. That makes false positives expensive in a
#   way an advisory hook's are not: a wrongly-blocked `/goal` is a workflow the
#   user cannot run at all. So the PASS cases below outnumber the BLOCK cases on
#   purpose, and several of them are near-misses — phrasings that contain the
#   trigger words but are legitimate. If a future pattern is added to the hook,
#   it has to keep all of these passing.
#
#   The two BLOCK cases are the exact conditions that caused real incidents:
#   2026-08-17 ("do not yield for anything from me", 21 consecutive blocks) and
#   2026-08-31 ("complete all remainig work…", ~15). Both are kept verbatim,
#   typo included, because the hook must match what a user actually types rather
#   than a tidied-up paraphrase.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/hooks/goal-condition-lint.sh"

PASS=0
FAIL=0
FAILED_NAMES=()

ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); printf '  FAIL %s — %s\n' "$1" "$2"; }

# run <prompt> -> stdout of the hook
run() {
  printf '{"prompt":%s}' "$(jq -Rn --arg p "$1" '$p')" | bash "$HOOK" 2>/dev/null
}

# A passing hook writes NOTHING at all. `jq` on empty stdin also writes nothing
# and exits 0, so `jq -r '.decision // "none"'` yields "" rather than the
# intended default — the empty case has to be handled before jq sees it.
decision() {
  local out="$1"
  [ -z "${out//[[:space:]]/}" ] && { printf 'none'; return; }
  printf '%s' "$out" | jq -r '.decision // "none"' 2>/dev/null || printf 'malformed'
}

expect_block() {
  local name="$1" prompt="$2" out d
  out="$(run "$prompt")"; d="$(decision "$out")"
  if [ "$d" = "block" ]; then ok "$name"; else bad "$name" "expected block, got '$d'"; fi
}

expect_pass() {
  local name="$1" prompt="$2" out d
  out="$(run "$prompt")"; d="$(decision "$out")"
  if [ "$d" = "none" ]; then ok "$name"; else bad "$name" "expected pass, got '$d'"; fi
}

echo "--- goal-condition-lint: blocks conditions that cannot terminate ---"

# The two real incidents, verbatim.
expect_block "2026-08-31 incident (unbounded scope)" \
  "/goal complete all remainig work, merge what is green tested and validated."
expect_block "2026-08-17 incident (stopping is the violation)" \
  "/goal complete ci/cd new system and then all of the remaining work, using sub agents, do not yield for anything from me"

expect_block "don't stop" "/goal ship the release, don't stop until it's out"
expect_block "never yield"        "/goal never yield, keep working"
expect_block "finish everything"  "/goal finish everything in the backlog"
expect_block "everything left"    "/goal do everything thats left"

echo "--- passes: legitimate goals must not be blocked ---"

expect_pass "checkable predicate" \
  "/goal merge every PR whose required checks are green"
expect_pass "gh predicate" \
  "/goal until gh pr list --state open is empty in dev and infra"
expect_pass "issue closed" \
  "/goal until issue #842 is closed"
expect_pass "CI green" \
  "/goal until CI is green on main"

echo "--- passes: unbounded scope WITH a carve-out terminates ---"

expect_pass "excluding blocked" \
  "/goal complete all remaining work, excluding anything blocked on billing or my decision"
expect_pass "stop and report" \
  "/goal finish everything you can, then stop and report anything blocked"
expect_pass "actionable" \
  "/goal complete all remaining actionable work"
expect_pass "within your control" \
  "/goal do all the remaining work within your control"

echo "--- passes: management subcommands and non-goal prompts ---"

expect_pass "goal clear"   "/goal clear"
expect_pass "goal status"  "/goal status"
expect_pass "bare goal"    "/goal"
expect_pass "not a goal"   "what is the project status?"
expect_pass "goal-ish word in prose" \
  "our goal is to complete all remaining work this quarter"
expect_pass "another slash command" "/decision everything needed from me"

echo "--- passes: explicit override ---"

expect_pass "force prefix" \
  "/goal force: complete all remaining work, do not yield"

echo "--- the block payload is usable ---"

out="$(run "/goal complete all remainig work, merge what is green tested and validated.")"
reason="$(printf '%s' "$out" | jq -r '.reason // ""')"

case "$reason" in
  *"1) /goal "*) ok "menu offers rewrite 1" ;;
  *) bad "menu offers rewrite 1" "no numbered rewrite in reason" ;;
esac
case "$reason" in
  *"2) /goal "*) ok "menu offers rewrite 2" ;;
  *) bad "menu offers rewrite 2" "no second rewrite in reason" ;;
esac
case "$reason" in
  *"3) /goal force: "*) ok "menu offers keep-as-is via force" ;;
  *) bad "menu offers keep-as-is via force" "no force escape in reason" ;;
esac
case "$reason" in
  *"4) /goal <your own wording>"*) ok "menu offers free-form" ;;
  *) bad "menu offers free-form" "no free-form option in reason" ;;
esac

# The recommended rewrite must itself pass the hook, or the menu sends the user
# straight back into the block. This is the case most likely to rot as patterns
# are added, and the cheapest to get wrong.
rewrite="$(printf '%s' "$reason" | sed -n 's@^  1) \(/goal .*\)$@\1@p' | head -1)"
if [ -z "$rewrite" ]; then
  bad "recommended rewrite is extractable" "could not parse option 1 out of the menu"
else
  ok "recommended rewrite is extractable"
  d="$(decision "$(run "$rewrite")")"
  if [ "$d" = "none" ]; then
    ok "recommended rewrite passes the hook"
  else
    bad "recommended rewrite passes the hook" "option 1 would be blocked again ('$d')"
  fi
fi

# Same for the force escape: option 3 must actually arm.
forced="$(printf '%s' "$reason" | sed -n 's@^  3) \(/goal force: .*\)$@\1@p' | head -1)"
if [ -z "$forced" ]; then
  bad "force escape is extractable" "could not parse option 3 out of the menu"
else
  ok "force escape is extractable"
  d="$(decision "$(run "$forced")")"
  if [ "$d" = "none" ]; then ok "force escape passes the hook"; else bad "force escape passes the hook" "got '$d'"; fi
fi

echo "--- hostile input does not break the JSON ---"

# A condition carrying quotes, backticks and a newline must still produce valid
# JSON. Assembling the reason with string interpolation rather than jq --arg is
# the obvious way to write this hook and would fail exactly here.
for hostile in \
  '/goal complete all remaining work "with quotes" and `backticks`' \
  '/goal complete all remaining work \ with a backslash' \
  "/goal complete all remaining work with 'single quotes'"
do
  out="$(run "$hostile")"
  if printf '%s' "$out" | jq -e . >/dev/null 2>&1; then
    ok "valid JSON for hostile input: ${hostile:0:42}..."
  else
    bad "valid JSON for hostile input: ${hostile:0:42}..." "output was not parseable JSON"
  fi
done

echo
printf 'goal-condition-lint: %d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'failed: %s\n' "${FAILED_NAMES[*]}"
  exit 1
fi
