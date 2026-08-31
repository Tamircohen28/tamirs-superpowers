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

# The hook blocks via stderr + exit 2 (the one path the docs quote verbatim for
# UserPromptSubmit), so the assertions are on EXIT CODE and STDERR, not on a
# JSON decision field. RUN_ERR carries stderr for the payload assertions below.
RUN_ERR=""

# run <prompt> -> sets RUN_ERR to stderr, returns the hook's exit code.
run() {
  local errfile; errfile="$(mktemp)"
  printf '{"prompt":%s}' "$(jq -Rn --arg p "$1" '$p')" | bash "$HOOK" >/dev/null 2>"$errfile"
  local rc=$?
  RUN_ERR="$(cat "$errfile")"
  rm -f "$errfile"
  return $rc
}

# decision <prompt> -> "block" | "none" | "malformed"
#
# A blocking hook must BOTH exit 2 AND say why: an exit 2 with no stderr erases
# the user's prompt and tells them nothing, which is worse than not blocking.
decision() {
  run "$1"
  local rc=$?
  if [ "$rc" -eq 2 ]; then
    [ -n "${RUN_ERR//[[:space:]]/}" ] && printf 'block' || printf 'malformed'
  elif [ "$rc" -eq 0 ]; then
    printf 'none'
  else
    printf 'malformed'
  fi
}

expect_block() {
  local name="$1" prompt="$2" d
  d="$(decision "$prompt")"
  if [ "$d" = "block" ]; then ok "$name"; else bad "$name" "expected block, got '$d'"; fi
}

expect_pass() {
  local name="$1" prompt="$2" d
  d="$(decision "$prompt")"
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

# Question-avoidance is not a refusal to stop. An earlier revision matched
# `do not ask` and erased this exact prompt (Codex review, PR #102) — it
# terminates the moment CI is green.
expect_pass "do not ask me (question avoidance, not never-stop)" \
  "/goal deploy after CI is green; do not ask me unless credentials are missing"
expect_pass "don't ask, just do it" \
  "/goal until CI is green on main, don't ask for confirmation"

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

run "/goal complete all remainig work, merge what is green tested and validated." || true
reason="$RUN_ERR"

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
  d="$(decision "$rewrite")"
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
  d="$(decision "$forced")"
  if [ "$d" = "none" ]; then ok "force escape passes the hook"; else bad "force escape passes the hook" "got '$d'"; fi
fi

echo "--- case-insensitivity: /GOAL must behave exactly like /goal ---"

# The command match is case-insensitive but the strip was a lowercase literal,
# so `/GOAL ...` left the command word inside the condition: the menu's rewrites
# came out mangled and `force:` stopped being recognised at all.
expect_block "uppercase /GOAL is still screened" \
  "/GOAL complete all remaining work"
expect_pass  "uppercase /GOAL force: still arms (was: blocked)" \
  "/GOAL force: complete all remaining work"
expect_pass  "mixed-case /GoAl clear is still a subcommand" "/GoAl clear"

run "/GOAL complete all remaining work" || true
case "$RUN_ERR" in
  *"  complete all remaining work"*) ok "uppercase: condition echoed without the command word" ;;
  *) bad "uppercase: condition echoed without the command word" "command word leaked into the condition" ;;
esac

echo "--- a check that cannot run says so, and never blocks ---"

# The failure this hook exists to prevent, one level up: a guard that cannot run
# must not exit 0 in silence, or it looks installed while screening nothing.
cannot_run_case() {
  local name="$1" payload="$2" rc err
  err="$(printf '%s' "$payload" | bash "$HOOK" 2>&1 >/dev/null)"; rc=$?
  if [ "$rc" -eq 0 ] && printf '%s' "$err" | grep -q "CHECK DID NOT RUN"; then
    ok "$name"
  else
    bad "$name" "expected exit 0 + 'CHECK DID NOT RUN', got rc=$rc err='${err:0:60}'"
  fi
}

cannot_run_case "malformed JSON payload is loud, not silent" 'not json at all'
cannot_run_case "payload missing every known prompt field is loud" '{"session_id":"x","cwd":"/tmp"}'

# A present-but-empty prompt is a REAL state, not a masked failure — it must be
# quiet, or every empty submission cries wolf.
err="$(printf '{"prompt":""}' | bash "$HOOK" 2>&1 >/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && [ -z "$err" ]; then
  ok "present-but-empty prompt is quiet (a real state, not a failure)"
else
  bad "present-but-empty prompt is quiet" "rc=$rc err='${err:0:60}'"
fi

# No payload at all (hand-run) is likewise a real state.
err="$(printf '' | bash "$HOOK" 2>&1 >/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && [ -z "$err" ]; then
  ok "empty stdin is quiet"
else
  bad "empty stdin is quiet" "rc=$rc err='${err:0:60}'"
fi

echo "--- the prompt is read under every field name it has carried ---"

# Reading only `.prompt` means a field rename disarms the guard silently: it
# would pass every prompt while looking healthy.
for field in prompt user_input user_message; do
  payload="$(jq -cn --arg f "$field" --arg v "/goal complete all remaining work" '{($f): $v}')"
  rc=0; printf '%s' "$payload" | bash "$HOOK" >/dev/null 2>&1 || rc=$?
  if [ "$rc" -eq 2 ]; then ok "screens a prompt delivered as .$field"; else bad "screens a prompt delivered as .$field" "rc=$rc"; fi
done

echo "--- hostile input does not mangle the message ---"

# A condition carrying quotes, backticks or a backslash must come back intact.
# The reason string is assembled with `jq --arg`; doing it with plain shell
# interpolation is the obvious way to write this hook and would corrupt or
# truncate the message exactly here — leaving the user a blocked prompt and a
# mangled explanation.
for hostile in \
  '/goal complete all remaining work "with quotes" and `backticks`' \
  '/goal complete all remaining work \ with a backslash' \
  "/goal complete all remaining work with 'single quotes'"
do
  run "$hostile" || true
  # The condition must be echoed back intact and the menu must still be there —
  # shell-quoting damage would show up as a truncated or mangled message.
  if [ -n "$RUN_ERR" ] && printf '%s' "$RUN_ERR" | grep -q '3) /goal force: '; then
    ok "intact menu for hostile input: ${hostile:0:42}..."
  else
    bad "intact menu for hostile input: ${hostile:0:42}..." "menu missing or mangled"
  fi
done

echo
printf 'goal-condition-lint: %d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'failed: %s\n' "${FAILED_NAMES[*]}"
  exit 1
fi
