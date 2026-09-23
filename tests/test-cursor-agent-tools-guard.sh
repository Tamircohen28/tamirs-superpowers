#!/usr/bin/env bash
# Tests for hooks/cursor-agent-tools-guard.sh.
#
# WHAT THESE PIN
#   1. A read-only agent's Write is DENIED. That is the whole point: Cursor ignores
#      the frontmatter tools: list, so seven agents here are unconstrained there.
#   2. A permitted tool is ALLOWED. A guard that denies everything is not a guard,
#      it is an outage, and it would be indistinguishable from working if only the
#      deny case were tested.
#   3. Bash maps to Shell. Agents declare Claude names; Cursor reports Shell. Miss
#      this and every shell call from every agent is wrongly denied.
#   4. Nesting takes the INTERSECTION, and popping restores the outer frame. With
#      identical ids there is no way to attribute a call to one of two concurrent
#      subagents, so every active frame must permit it.
#   5. With no agent active, nothing is constrained — the main conversation is not
#      a subagent and must not inherit anyone's list.
#   6. It is inert off Cursor. Claude enforces tools: itself; a second opinion here
#      could only ever disagree with the platform.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
H="$ROOT/hooks/cursor-agent-tools-guard.sh"
PASS=0; FAIL=0; FAILED=()
ok(){ PASS=$((PASS+1)); echo "  ok   $1"; }
bad(){ FAIL=$((FAIL+1)); FAILED+=("$1"); echo "  FAIL $1 — $2"; }
[ -f "$H" ] || { echo "FATAL: $H missing"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required"; exit 1; }

CLAUDE_PLUGIN_DATA="$(mktemp -d)"
export CLAUDE_PLUGIN_DATA
trap 'rm -rf "$CLAUDE_PLUGIN_DATA"' EXIT
CID="test-$$"
CUR="\"conversation_id\":\"$CID\",\"cursor_version\":\"x\",\"workspace_roots\":[\"/tmp\"]"

task(){
  local err; err="$(mktemp)"
  printf '{%s,"hook_event_name":"%s","tool_name":"Task","tool_input":{"subagent_type":"%s"}}' "$CUR" "$1" "$2" | bash "$H" >/dev/null 2>"$err" || {
    echo "      task($1,$2) exited non-zero; stderr:" >&2; sed 's/^/      | /' "$err" >&2; }
  rm -f "$err"
}
# stderr is captured, not discarded: when this suite failed on Linux CI while
# passing on macOS, every assertion reported an empty result and the reason was
# in the stderr nobody kept. A test that hides the diagnostic costs more than it
# saves.
perm(){
  local out err
  err="$(mktemp)"
  out="$(printf '{%s,"hook_event_name":"preToolUse","tool_name":"%s","tool_input":{}}' "$CUR" "$1" | bash "$H" 2>"$err")"
  if [ -z "$out" ]; then
    echo "      hook produced NO stdout; stderr was:" >&2
    sed 's/^/      | /' "$err" >&2
  fi
  rm -f "$err"
  printf '%s' "$out" | jq -r '.permission // "allow"' 2>/dev/null
}

echo "--- a read-only agent cannot write ---"
task preToolUse architecture-reviewer
[ "$(perm Write)" = "deny" ] && ok "denies Write for architecture-reviewer" || bad "denies Write" "got $(perm Write)"
[ "$(perm Read)" = "allow" ] && ok "allows Read, which it declares" || bad "allows Read" "got $(perm Read)"
[ "$(perm Shell)" = "deny" ] && ok "denies Shell (it declares no Bash)" || bad "denies Shell" "got $(perm Shell)"

out="$(printf '{%s,"hook_event_name":"preToolUse","tool_name":"Write","tool_input":{}}' "$CUR" | bash "$H" 2>/dev/null)"
case "$(printf '%s' "$out" | jq -r '.user_message // empty')" in
  *architecture-reviewer*) ok "the denial names the agent" ;;
  *) bad "the denial names the agent" "got: $out" ;;
esac
task postToolUse architecture-reviewer

echo "--- Bash declarations map to Cursor's Shell ---"
task preToolUse debugging-specialist          # declares Bash
[ "$(perm Shell)" = "allow" ] && ok "allows Shell for an agent declaring Bash" || bad "allows Shell for Bash" "got $(perm Shell)"
[ "$(perm Write)" = "deny" ] && ok "still denies Write for that agent" || bad "denies Write" "got $(perm Write)"
task postToolUse debugging-specialist

echo "--- nesting takes the intersection; popping restores ---"
task preToolUse implementer                   # declares Write
[ "$(perm Write)" = "allow" ] && ok "implementer may Write" || bad "implementer may Write" "got $(perm Write)"
task preToolUse architecture-reviewer         # nested, read-only
[ "$(perm Write)" = "deny" ] && ok "nested reviewer denies Write (intersection)" || bad "intersection denies Write" "got $(perm Write)"
[ "$(perm Read)" = "allow" ] && ok "Read still allowed — both frames permit it" || bad "Read allowed under both" "got $(perm Read)"
task postToolUse architecture-reviewer
[ "$(perm Write)" = "allow" ] && ok "popping the reviewer restores Write" || bad "pop restores Write" "got $(perm Write)"
task postToolUse implementer

echo "--- nothing active constrains nothing ---"
[ "$(perm Write)" = "allow" ] && ok "no frame active => Write allowed" || bad "no frame => allowed" "got $(perm Write)"

echo "--- inert off Cursor ---"
claude_out="$(printf '{"conversation_id":"","hook_event_name":"PreToolUse","tool_name":"Write","tool_input":{}}' | bash "$H" 2>/dev/null)"
if printf '%s' "$claude_out" | jq -e '.permission == "deny"' >/dev/null 2>&1; then
  bad "inert on a Claude payload" "denied: $claude_out"
else
  ok "inert on a Claude payload (Claude enforces tools: itself)"
fi

echo "--- an unknown agent is not guessed at ---"
task preToolUse no-such-agent
[ "$(perm Write)" = "allow" ] && ok "unknown agent adds no frame" || bad "unknown agent adds no frame" "got $(perm Write)"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -gt 0 ] && { printf 'failing:'; printf ' %s' "${FAILED[@]}"; echo; exit 1; }
exit 0
