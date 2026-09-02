#!/usr/bin/env bash
# Tests for hooks/session-init.sh's Claude Code 2.1.251+ resume-staleness note.
#
# SessionStart payloads for source "resume"/"fork" can carry
# prompt_cache_likely_expired (bool), context_tokens, and
# estimated_cache_write_usd — new in 2.1.251. session-init.sh surfaces a
# one-line warning in additionalContext when the cache is likely cold, so the
# agent (and a human skimming the transcript) sees it before the first
# request re-caches, not after an unexplained cost/latency spike.
#
# These cases run in a plain (non-git) tmpdir cwd so worktree/session-files
# machinery takes its simplest path and the assertions stay about the
# staleness note specifically.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/hooks/session-init.sh"

PASS=0
FAIL=0
FAILED_NAMES=()

[ -f "$HOOK" ] || { echo "FATAL: session-init hook not found at $HOOK"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq is required"; exit 1; }

TMPROOT="$(mktemp -d)"
trap 'rm -rf "$TMPROOT"' EXIT
export HOME="$TMPROOT/home"
mkdir -p "$HOME/.claude"
CWD="$TMPROOT/work"
mkdir -p "$CWD"

ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); printf '  FAIL %s — %s\n' "$1" "$2"; }

run_with_timeout() {
  local secs="$1"; shift
  "$@" &
  local pid=$!
  ( local waited=0
    while kill -0 "$pid" 2>/dev/null; do
      if [ "$waited" -ge "$secs" ]; then kill -9 "$pid" 2>/dev/null; exit 0; fi
      sleep 1; waited=$((waited + 1))
    done ) &
  local watcher=$!
  wait "$pid" 2>/dev/null
  local rc=$?
  kill "$watcher" 2>/dev/null; wait "$watcher" 2>/dev/null
  [ "$rc" = 137 ] && rc=124
  return "$rc"
}

run_hook() {
  local payload="$1" out="$2"
  run_with_timeout 10 bash -c 'printf "%s" "$1" | bash "$2" > "$3" 2>&1' _ "$payload" "$HOOK" "$out"
}

echo "--- session-init: resume with a likely-expired cache ---"

STALE_JSON="$(jq -n --arg cwd "$CWD" '{
  session_id: "test-stale-session",
  cwd: $cwd,
  source: "resume",
  prompt_cache_likely_expired: true,
  context_tokens: 48213,
  estimated_cache_write_usd: 0.6027
}')"

out="$TMPROOT/stale.out"
if run_hook "$STALE_JSON" "$out"; then
  rendered="$(cat "$out")"
  ctx="$(echo "$rendered" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"
  case "$ctx" in
    *"prompt cache has likely expired"*) ok "notes the expired prompt cache" ;;
    *) bad "notes the expired prompt cache" "got: $rendered" ;;
  esac
  case "$ctx" in
    *"48213 tokens"*) ok "includes the context token estimate" ;;
    *) bad "includes the context token estimate" "got: $ctx" ;;
  esac
  case "$ctx" in
    *'$0.6027'*) ok "includes the estimated re-cache cost" ;;
    *) bad "includes the estimated re-cache cost" "got: $ctx" ;;
  esac
else
  bad "resume with expired cache completes" "timed out or exited non-zero"
fi

echo "--- session-init: resume with a still-warm cache ---"

WARM_JSON="$(jq -n --arg cwd "$CWD" '{
  session_id: "test-warm-session",
  cwd: $cwd,
  source: "resume",
  prompt_cache_likely_expired: false,
  context_tokens: 12000,
  estimated_cache_write_usd: 0.15
}')"

out="$TMPROOT/warm.out"
if run_hook "$WARM_JSON" "$out"; then
  rendered="$(cat "$out")"
  ctx="$(echo "$rendered" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"
  case "$ctx" in
    *"prompt cache has likely expired"*) bad "stays silent when the cache is still warm" "got: $ctx" ;;
    *) ok "stays silent when the cache is still warm" ;;
  esac
else
  bad "resume with warm cache completes" "timed out or exited non-zero"
fi

echo "--- session-init: plain startup (no staleness fields at all) ---"

STARTUP_JSON="$(jq -n --arg cwd "$CWD" '{
  session_id: "test-startup-session",
  cwd: $cwd,
  source: "startup"
}')"

out="$TMPROOT/startup.out"
if run_hook "$STARTUP_JSON" "$out"; then
  rendered="$(cat "$out")"
  ctx="$(echo "$rendered" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null)"
  case "$ctx" in
    *"prompt cache has likely expired"*) bad "startup (no resume fields) stays silent" "got: $ctx" ;;
    *) ok "startup (no resume fields) stays silent" ;;
  esac
  case "$rendered" in
    *'"hookEventName": "SessionStart"'*) ok "still emits well-formed SessionStart output" ;;
    *) bad "still emits well-formed SessionStart output" "got: $rendered" ;;
  esac
else
  bad "plain startup completes" "timed out or exited non-zero"
fi

echo
echo "passed: $PASS   failed: $FAIL"
if [ "$FAIL" -ne 0 ]; then
  printf 'failing: %s\n' "${FAILED_NAMES[*]}"
  exit 1
fi
exit 0
