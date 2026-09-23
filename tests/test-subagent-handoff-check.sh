#!/usr/bin/env bash
# Tests for hooks/subagent-handoff-check.sh (SubagentStop).
#
# WHAT THESE PIN
#   1. It speaks when a subagent finishes under an objective with NO handoff — the
#      case where an orchestrator would otherwise integrate off a closing summary.
#   2. It speaks when a handoff claims `completed` with an empty validation[], which
#      worker-dev names as "a claim with no evidence".
#   3. It does NOT speak for `partial`/`failed`/`blocked` with no validation. Honest
#      partial reporting is the behaviour this repo wants; flagging it would train
#      workers to overclaim, which is the opposite of the point.
#   4. It uses additionalContext, not systemMessage. The reader here is the
#      ORCHESTRATOR, which is about to decide whether to integrate — the opposite
#      call from rate-limit-handoff.sh, where the turn was dead and only the user
#      remained. Getting it backwards would send this to someone not making the call.
#   5. It is silent outside orchestration, and never blocks.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
H="$ROOT/hooks/subagent-handoff-check.sh"
PASS=0; FAIL=0; FAILED=()
[ -f "$H" ] || { echo "FATAL: $H missing"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required"; exit 1; }
TMPROOT="$(mktemp -d)"; trap 'rm -rf "$TMPROOT"' EXIT
ok(){ PASS=$((PASS+1)); echo "  ok   $1"; }
bad(){ FAIL=$((FAIL+1)); FAILED+=("$1"); echo "  FAIL $1 — $2"; }
run(){ printf '{"cwd":"%s"}' "$1" | bash "$H" 2>&1; }
ctx(){ printf '%s' "$1" | jq -r '.hookSpecificOutput.additionalContext // empty' 2>/dev/null; }
mkobj(){ local d="$1"; mkdir -p "$d/.dev-files/objectives/auth-system/handoffs"; git -C "$d" init -q; }

echo "--- silent outside orchestration ---"
P="$TMPROOT/plain"; mkdir -p "$P"; git -C "$P" init -q
out="$(run "$P")"
printf '%s' "$out" | jq -e '.suppressOutput == true' >/dev/null 2>&1 \
  && ok "no objective => silent" || bad "no objective => silent" "got: $out"

echo "--- a missing handoff is surfaced ---"
O="$TMPROOT/obj"; mkobj "$O"
out="$(run "$O")"; m="$(ctx "$out")"
[ -n "$m" ] && ok "warns when no handoff exists" || bad "warns when no handoff exists" "got: $out"
case "$m" in *"auth-system"*) ok "names the objective" ;; *) bad "names the objective" "got: $m" ;; esac
case "$m" in *partial*) ok "tells the orchestrator what to do instead" ;; *) bad "tells the orchestrator what to do instead" "got: $m" ;; esac

echo "--- the channel is the orchestrator's, not the user's ---"
if printf '%s' "$out" | jq -e '.systemMessage' >/dev/null 2>&1; then
  bad "uses additionalContext, not systemMessage" "emitted systemMessage"
else ok "uses additionalContext, not systemMessage"; fi
ev="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName // empty')"
[ "$ev" = "SubagentStop" ] && ok "declares the right hookEventName" || bad "declares the right hookEventName" "got: '$ev'"

echo "--- evidence decides, not status alone ---"
HD="$O/.dev-files/objectives/auth-system/handoffs"
echo '{"status":"completed","validation":[{"cmd":"npm test","result":"pass"}]}' > "$HD/task-001.json"
out="$(run "$O")"
printf '%s' "$out" | jq -e '.suppressOutput == true' >/dev/null 2>&1 \
  && ok "completed WITH validation => silent" || bad "completed WITH validation => silent" "got: $out"

echo '{"status":"completed","validation":[]}' > "$HD/task-002.json"
m="$(ctx "$(run "$O")")"
case "$m" in *task-002*) ok "flags completed with empty validation" ;; *) bad "flags completed with empty validation" "got: $m" ;; esac

for st in partial failed blocked; do
  echo "{\"status\":\"$st\",\"validation\":[]}" > "$HD/task-002.json"
  out="$(run "$O")"
  if printf '%s' "$out" | jq -e '.suppressOutput == true' >/dev/null 2>&1; then
    ok "'$st' with no validation is NOT flagged (honest reporting)"
  else
    bad "'$st' with no validation is NOT flagged" "got: $(ctx "$out")"
  fi
done

echo "--- never blocks ---"
for label in empty malformed devnull; do
  case "$label" in
    empty)     printf ''                | bash "$H" >/dev/null 2>&1; rc=$? ;;
    malformed) printf 'not json at all' | bash "$H" >/dev/null 2>&1; rc=$? ;;
    devnull)   bash "$H" </dev/null     >/dev/null 2>&1; rc=$? ;;
  esac
  [ "$rc" -eq 0 ] && ok "$label stdin exits 0" || bad "$label stdin exits 0" "rc=$rc"
done

echo "--- wired ---"
CMD="$(jq -r '(.hooks.SubagentStop // .SubagentStop // [])[0].hooks[0].command // empty' "$ROOT/hooks/hooks.json" 2>/dev/null)"
case "$CMD" in *subagent-handoff-check.sh) ok "hooks.json wires SubagentStop to this hook" ;;
  *) bad "hooks.json wires SubagentStop to this hook" "got: $CMD" ;; esac

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -gt 0 ] && { printf 'failing:'; printf ' %s' "${FAILED[@]}"; echo; exit 1; }
exit 0
