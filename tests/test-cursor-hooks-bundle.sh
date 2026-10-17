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
#   emits {permission, user_message, agent_message}; hooks/lib/cursor-output.sh
#   speaks the lifecycle and prompt shapes; hooks/lib/write-targets.py already
#   treats Cursor's `Shell` like `Bash`. A fork would be two things to keep in
#   step, and the drift would be invisible until a guard failed to fire.
#
# WHAT THIS SUITE COVERS VS test-cursor-lifecycle.sh
#   This one is STRUCTURE: the file, the manifest pointer, which events are wired,
#   which entries fail closed, that every command resolves. Behaviour under a
#   Cursor payload — exit codes, output shapes, blocks and passes — is
#   tests/test-cursor-lifecycle.sh, which reads the same bundle from disk.

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

for e in preToolUse beforeShellExecution postToolUse beforeSubmitPrompt sessionStart sessionEnd stop preCompact workspaceOpen; do
  jq -e --arg e "$e" '.hooks[$e] | length > 0' "$B" >/dev/null 2>&1 \
    && ok "wires $e" || bad "wires $e" "absent or empty"
done
# Every wired event is one Cursor actually has (21, from the hooks reference).
CURSOR_EVENTS="sessionStart sessionEnd preToolUse postToolUse postToolUseFailure subagentStart subagentStop beforeShellExecution afterShellExecution beforeMCPExecution afterMCPExecution beforeReadFile afterFileEdit beforeSubmitPrompt preCompact stop afterAgentResponse afterAgentThought beforeTabFileRead afterTabFileEdit workspaceOpen"
unknown=""
for e in $(jq -r '.hooks | keys[]' "$B"); do
  case " $CURSOR_EVENTS " in *" $e "*) ;; *) unknown="$unknown $e" ;; esac
done
[ -z "$unknown" ] && ok "every wired event is one of Cursor's 21" || bad "every wired event is one of Cursor's 21" "unknown:$unknown"
# Each entry's command names a script that exists; a typo here is a hook that
# never runs and never says so.
unresolved=""
for cmd in $(jq -r '.hooks[][].command' "$B" | sed 's/^bash //; s#${CURSOR_PLUGIN_ROOT}/##'); do
  [ -f "$ROOT/$cmd" ] || unresolved="$unresolved $cmd"
done
[ -z "$unresolved" ] && ok "every command resolves to a script in the repo" || bad "every command resolves" "missing:$unresolved"
# Timeouts are seconds on Cursor; a Claude-style millisecond value would be hours.
bigt="$(jq -r '.hooks[][] | select((.timeout // 0) > 120) | .command' "$B")"
[ -z "$bigt" ] && ok "every timeout is in seconds (<= 120)" || bad "timeouts are seconds" "suspiciously large: $bigt"

echo "--- the safety tier fails closed; nothing else does ---"
for s in enforce-worktree-edits.sh guard-sensitive-files.sh protect-other-branches.sh cursor-agent-tools-guard.sh; do
  n="$(jq -r --arg s "$s" '[.hooks.preToolUse[] | select(.command | test($s))] | map(select(.failClosed == true)) | length' "$B")"
  [ "$n" -ge 1 ] && ok "preToolUse → $s carries failClosed: true" || bad "preToolUse → $s failClosed" "not set"
  n="$(jq -r --arg s "$s" '[.hooks.preToolUse[] | select(.command | test($s))] | map(select(.loop_limit == null and has("loop_limit"))) | length' "$B")"
  [ "$n" -ge 1 ] && ok "preToolUse → $s removes the loop_limit cap" || bad "preToolUse → $s loop_limit" "a guard capped at 5 firings stops guarding"
done
n="$(jq -r '[.hooks.beforeShellExecution[] | select(.command | test("guard-sensitive-files")) | select(.failClosed == true)] | length' "$B")"
[ "$n" -ge 1 ] && ok "beforeShellExecution → guard-sensitive-files.sh carries failClosed: true" || bad "beforeShellExecution failClosed" "not set"
loose="$(jq -r '.hooks | to_entries[] | .key as $e | .value[] | select(.failClosed == true) | select($e != "preToolUse" and $e != "beforeShellExecution") | "\($e):\(.command | sub(".*/"; ""))"' "$B")"
[ -z "$loose" ] && ok "no advisory or observational entry fails closed" || bad "advisory entries are fail-open" "failClosed on: $loose"
adv="$(jq -r '.hooks.preToolUse[] | select(.command | test("skill-creator-guard")) | .failClosed // false' "$B")"
[ "$adv" = "false" ] && ok "skill-creator-guard.sh (contributor tier) is fail-open" || bad "skill-creator-guard fail-open" "failClosed=$adv"

echo "--- events left unwired on purpose stay that way (see platforms/cursor/README.md) ---"
for e in subagentStart beforeMCPExecution beforeReadFile beforeTabFileRead; do
  jq -e --arg e "$e" '.hooks[$e]' "$B" >/dev/null 2>&1 \
    && bad "$e stays unwired" "wired — a permission hook that emits a non-Cursor key blocks every call" \
    || ok "$e stays unwired"
done
[ -f "$ROOT/platforms/cursor/README.md" ] && ok "platforms/cursor/README.md explains the bundle" || bad "platforms/cursor/README.md" "missing"

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

echo "--- the shared libraries really do speak Cursor ---"
out3="$(bash -c 'source "$1"/hooks/lib/hook-output.sh; source "$1"/hooks/lib/cursor-output.sh; cursor_prompt_block "why"' _ "$ROOT" 2>/dev/null)"
if printf '%s' "$out3" | jq -e '.continue == false and .user_message == "why"' >/dev/null 2>&1; then
  ok "cursor_prompt_block emits {continue:false,user_message}"
else
  bad "cursor_prompt_block shape" "got: $out3"
fi
out4="$(bash -c 'source "$1"/hooks/lib/hook-output.sh; source "$1"/hooks/lib/cursor-output.sh; cursor_session_context "ctx"' _ "$ROOT" 2>/dev/null)"
if printf '%s' "$out4" | jq -e '.additional_context == "ctx" and (keys == ["additional_context"])' >/dev/null 2>&1; then
  ok "cursor_session_context emits {additional_context} and nothing else"
else
  bad "cursor_session_context shape" "got: $out4"
fi
if grep -q 'followup_message:' "$ROOT/hooks/lib/cursor-output.sh"; then
  bad "cursor-output.sh never builds a followup_message" "a helper emits it"
else
  ok "cursor-output.sh never builds a followup_message"
fi
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
