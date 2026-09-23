#!/usr/bin/env bash
# Tests for hooks/rate-limit-handoff.sh (StopFailure, matcher `rate_limit`).
#
# WHAT THESE PIN, AND WHY EACH ONE IS A REAL FAILURE MODE
#   1. It must SPEAK when there is work to hand off. A hook that fires on the
#      right event and says nothing is indistinguishable from one that is not
#      wired at all — and this event only fires when a session has just died,
#      so nobody is watching for a missing message.
#   2. It must STAY SILENT when there is nothing in flight. A rate limit during
#      a read-only session costs nothing; a reminder there is noise at a bad
#      moment, and noise is how a hook earns its way into being ignored.
#   3. It must use `systemMessage`, not `hookSpecificOutput.additionalContext`.
#      The turn has already failed, so there is no model turn left to read
#      context. Getting this backwards yields a hook that fires correctly and
#      is seen by nobody — which no assertion about *firing* would catch.
#   4. It must never hang or exit non-zero on a degenerate payload. An advisory
#      hook that blocks a failing turn from ending makes a bad moment worse.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
H="$ROOT/hooks/rate-limit-handoff.sh"

PASS=0
FAIL=0
FAILED_NAMES=()

[ -f "$H" ] || { echo "FATAL: hook not found at $H"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq is required"; exit 1; }

TMPROOT="$(mktemp -d)"
cleanup() { [ -n "${TMPROOT:-}" ] && rm -rf "$TMPROOT"; }
trap cleanup EXIT

ok()  { PASS=$((PASS+1)); echo "  ok   $1"; }
bad() { FAIL=$((FAIL+1)); FAILED_NAMES+=("$1"); echo "  FAIL $1 — $2"; }

run() { printf '{"cwd":"%s"}' "$1" | bash "$H" 2>&1; }

echo "--- rate-limit-handoff: work in flight => speaks ---"

DIRTY="$TMPROOT/dirty"
mkdir -p "$DIRTY" && git -C "$DIRTY" init -q
git -C "$DIRTY" config user.email t@e.x && git -C "$DIRTY" config user.name t
echo hello > "$DIRTY/a.txt"

out="$(run "$DIRTY")"
msg="$(printf '%s' "$out" | jq -r '.systemMessage // empty' 2>/dev/null)"

if [ -n "$msg" ]; then ok "emits a message when the tree is dirty"
else bad "emits a message when the tree is dirty" "got: $out"; fi

case "$msg" in
  *"switch-dev"*) ok "names the skill that does the handoff" ;;
  *) bad "names the skill that does the handoff" "got: $msg" ;;
esac

case "$msg" in
  *"1 uncommitted file"*) ok "counts the work actually at risk" ;;
  *) bad "counts the work actually at risk" "got: $msg" ;;
esac

# The channel matters as much as the content — see note 3 above.
if printf '%s' "$out" | jq -e '.hookSpecificOutput' >/dev/null 2>&1; then
  bad "uses systemMessage, not additionalContext" "emitted hookSpecificOutput on a failed turn"
else
  ok "uses systemMessage, not additionalContext"
fi

echo "--- rate-limit-handoff: nothing in flight => silent ---"

CLEAN="$TMPROOT/clean"
mkdir -p "$CLEAN" && git -C "$CLEAN" init -q
out="$(run "$CLEAN")"
if printf '%s' "$out" | jq -e '.suppressOutput == true' >/dev/null 2>&1; then
  ok "suppresses output on a clean repo with no objective"
else
  bad "suppresses output on a clean repo with no objective" "got: $out"
fi

NOGIT="$TMPROOT/nogit"
mkdir -p "$NOGIT"
out="$(run "$NOGIT")"
if printf '%s' "$out" | jq -e '.suppressOutput == true' >/dev/null 2>&1; then
  ok "suppresses output outside a git repo"
else
  bad "suppresses output outside a git repo" "got: $out"
fi

echo "--- rate-limit-handoff: an open objective alone is enough ---"

OBJ="$TMPROOT/obj"
mkdir -p "$OBJ/.dev-files/objectives/auth-system" && git -C "$OBJ" init -q
out="$(run "$OBJ")"
msg="$(printf '%s' "$out" | jq -r '.systemMessage // empty' 2>/dev/null)"
case "$msg" in
  *"auth-system"*) ok "names the open objective even with a clean tree" ;;
  *) bad "names the open objective even with a clean tree" "got: ${out}" ;;
esac

echo "--- rate-limit-handoff: degenerate payloads never hang or fail ---"

for label in empty malformed devnull; do
  start="$(date +%s)"
  case "$label" in
    empty)     printf ''                | bash "$H" >/dev/null 2>&1; rc=$? ;;
    malformed) printf 'not json at all' | bash "$H" >/dev/null 2>&1; rc=$? ;;
    devnull)   bash "$H" </dev/null     >/dev/null 2>&1; rc=$? ;;
  esac
  elapsed=$(( $(date +%s) - start ))
  if [ "$rc" -eq 0 ] && [ "$elapsed" -lt 5 ]; then
    ok "$label stdin exits 0 promptly (${elapsed}s)"
  else
    bad "$label stdin exits 0 promptly" "rc=$rc elapsed=${elapsed}s"
  fi
done

echo "--- rate-limit-handoff: it is wired to the one event that fires here ---"

WIRED="$(jq -r '(.hooks.StopFailure // .StopFailure // [])[0].matcher // empty' "$ROOT/hooks/hooks.json" 2>/dev/null)"
if [ "$WIRED" = "rate_limit" ]; then
  ok "hooks.json wires StopFailure with matcher rate_limit"
else
  bad "hooks.json wires StopFailure with matcher rate_limit" "got matcher: '${WIRED}'"
fi

CMD="$(jq -r '(.hooks.StopFailure // .StopFailure // [])[0].hooks[0].command // empty' "$ROOT/hooks/hooks.json" 2>/dev/null)"
case "$CMD" in
  *rate-limit-handoff.sh) ok "the wired command points at this hook" ;;
  *) bad "the wired command points at this hook" "got: $CMD" ;;
esac

echo
echo "passed: $PASS   failed: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'failing:'; printf ' %s' "${FAILED_NAMES[@]}"; echo
  exit 1
fi
exit 0
