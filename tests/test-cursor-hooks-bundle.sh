#!/usr/bin/env bash
# Tests for platforms/cursor/hooks.json — the Cursor-format hook bundle.
#
# WHY THIS BUNDLE EXISTS AT A NON-DEFAULT PATH
#   A Cursor plugin's `hooks` component auto-discovers `hooks/hooks.json`, which in
#   this repo is the CLAUDE-format file: PascalCase events Cursor cannot read. An
#   undeclared component does not disable itself — it binds to that default and
#   yields nothing. So the bundle lives at platforms/cursor/ and the manifest points
#   at it explicitly. Both halves are asserted here, because either one silently
#   alone is a bundle that loads nothing.
#
# WHY IT RUNS THE SAME SCRIPTS
#   No forked copies. hooks/lib/hook-output.sh detects Cursor from the payload and
#   emits {permission, user_message, agent_message}; hooks/lib/write-targets.py
#   already treats Cursor's `Shell` like `Bash`. A fork would be two things to keep
#   in step, and the drift would be invisible until a guard failed to fire.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
B="$ROOT/platforms/cursor/hooks.json"
M="$ROOT/.cursor-plugin/plugin.json"
PASS=0; FAIL=0; FAILED=()
ok(){ PASS=$((PASS+1)); echo "  ok   $1"; }
bad(){ FAIL=$((FAIL+1)); FAILED+=("$1"); echo "  FAIL $1 — $2"; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required"; exit 1; }

echo "--- the bundle exists and is Cursor-shaped ---"
[ -f "$B" ] && ok "platforms/cursor/hooks.json exists" || { bad "bundle exists" "missing"; echo; exit 1; }
jq empty "$B" 2>/dev/null && ok "parses as JSON" || bad "parses as JSON" "invalid"
[ "$(jq -r '.version' "$B")" = "1" ] && ok "declares version 1" || bad "declares version 1" "got $(jq -r '.version' "$B")"

# camelCase, not PascalCase: the whole reason this file is separate.
bad_events="$(jq -r '.hooks|keys[]' "$B" | grep -E '^[A-Z]' || true)"
[ -z "$bad_events" ] && ok "every event is camelCase (Cursor format)" \
  || bad "every event is camelCase" "PascalCase found: $bad_events"

for e in preToolUse beforeShellExecution; do
  jq -e --arg e "$e" '.hooks[$e] | length > 0' "$B" >/dev/null 2>&1 \
    && ok "wires $e" || bad "wires $e" "absent or empty"
done

echo "--- the manifest points at it (an undeclared component binds to the wrong default) ---"
declared="$(jq -r '.hooks // empty' "$M")"
[ "$declared" = "./platforms/cursor/hooks.json" ] \
  && ok "manifest declares the bundle path" \
  || bad "manifest declares the bundle path" "got: '${declared:-<undeclared>}' — discovery would bind to hooks/hooks.json, which is Claude-format"

echo "--- it runs the real scripts, not forked copies ---"
for g in enforce-worktree-edits.sh guard-sensitive-files.sh; do
  if jq -r '.hooks[][].command' "$B" | grep -q "$g"; then
    ok "invokes $g"
  else
    bad "invokes $g" "not referenced"
  fi
  [ -f "$ROOT/hooks/$g" ] && ok "$g exists at the canonical path" || bad "$g exists" "missing"
done
if jq -r '.hooks[][].command' "$B" | grep -qE 'platforms/cursor/.*\.sh'; then
  bad "no forked guard scripts under platforms/cursor/" "a copy would drift silently"
else
  ok "no forked guard scripts under platforms/cursor/"
fi

echo "--- the shared library really does speak Cursor ---"
out="$(printf '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x"},"cwd":"/tmp","conversation_id":"c1","cursor_version":"t","workspace_roots":["/tmp"]}' \
  | bash -c 'source "$1"/hooks/lib/hook-output.sh; input="$(cat)"; hook_detect_platform "$input"; hook_deny "probe"' _ "$ROOT" 2>/dev/null)"
if printf '%s' "$out" | jq -e '.permission == "deny" and (.user_message|length>0)' >/dev/null 2>&1; then
  ok "hook_deny emits Cursor's {permission,user_message} on a Cursor payload"
else
  bad "hook_deny emits Cursor's shape" "got: $out"
fi
out2="$(printf '{"tool_name":"Write","tool_input":{"file_path":"/tmp/x"},"cwd":"/tmp"}' \
  | bash -c 'source "$1"/hooks/lib/hook-output.sh; input="$(cat)"; hook_detect_platform "$input"; hook_deny "probe"' _ "$ROOT" 2>/dev/null)"
if printf '%s' "$out2" | jq -e '.hookSpecificOutput.permissionDecision == "deny"' >/dev/null 2>&1; then
  ok "the same call still emits Claude's shape on a Claude payload"
else
  bad "Claude shape preserved" "got: $out2"
fi

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -gt 0 ] && { printf 'failing:'; printf ' %s' "${FAILED[@]}"; echo; exit 1; }
exit 0
