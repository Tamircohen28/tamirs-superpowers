#!/usr/bin/env bash
# hooks/docker-guard.py — behaviour tests.
#
# WHY THIS SUITE EXISTS AT ALL
#   Until 2026-08-31 docker-guard.py had no tests. tests/test-hook-stdin.sh
#   sweeps `hooks/*.sh` and so never saw the one Python hook, and the guard's
#   own defect — `tool_name != "Bash"` dropping every Shell payload while
#   hooks.json wired it on `Bash|Shell` — sat in a matcher that claimed to
#   cover Shell. Nothing was watching the gap.
#
# WHY EVERY BLOCK ASSERTION IS PAIRED WITH AN ALLOW
#   A suite that only asserts "Bash + docker run is denied" passes unchanged
#   against the broken code, because Bash was the path that always worked. The
#   defect only shows up as the DIFFERENCE between two tools on the same
#   command, so every risky/safe command below is asserted through every name
#   in the guard's TOOLS — Bash and Shell alike. If a name is added to that
#   tuple (and to the hooks.json matcher) without being added to TOOLS here,
#   `matcher and TOOLS agree` fails.
#
#   To confirm the pairing actually bites, revert the `not in TOOLS` line to
#   `!= "Bash"` and re-run: the Shell block cases fail, the Bash ones do not.
#
# WHY THE ALLOW PATHS ARE ASSERTED AS *JSON*, NOT AS SILENCE
#   Claude Code reads empty stdout as allow; Cursor fail-closes on it. So a
#   bare exit(0) is not a portable pass, and per hooks/lib/hook-output.sh an
#   allow is `{}` on Claude Code and `{"permission":"allow"}` on Cursor.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOK="$ROOT/hooks/docker-guard.py"

PASS=0
FAIL=0
FAILED_NAMES=()

ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); printf '  FAIL %s — %s\n' "$1" "$2"; }

if ! command -v python3 >/dev/null 2>&1; then
  printf '  skip docker-guard — python3 not available\n'
  exit 0
fi

# The tool names this suite exercises. Kept in step with TOOLS in the guard and
# with the PreToolUse matcher in hooks/hooks.json; asserted below.
GUARDED_TOOLS=(Bash Shell)

# run <tool_name> <command> — hook stdout for a Claude Code shaped payload.
run() {
  python3 -c '
import json, sys
print(json.dumps({"tool_name": sys.argv[1], "tool_input": {"command": sys.argv[2]}}))
' "$1" "$2" | env -u PM_ALLOW_DOCKER python3 "$HOOK" 2>/dev/null
}

# is_deny <output> — yes when the payload carries a deny decision.
is_deny() {
  printf '%s' "$1" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("no"); raise SystemExit
hs = d.get("hookSpecificOutput") or {}
print("yes" if hs.get("permissionDecision") == "deny" or d.get("permission") == "deny" else "no")
' 2>/dev/null
}

# is_json <output> — yes when stdout is non-empty and parses.
is_json() {
  [ -n "$1" ] || { echo no; return; }
  printf '%s' "$1" | python3 -c 'import json,sys; json.load(sys.stdin); print("yes")' 2>/dev/null || echo no
}

printf '\n--- matcher/TOOLS agreement ---\n'

# The defect was a guard narrower than its own matcher. Pin them together so a
# future edit to one without the other is a test failure, not a silent bypass.
declared="$(python3 -c '
import json, sys
cfg = json.load(open(sys.argv[1]))
names = set()
for group in cfg.get("hooks", {}).get("PreToolUse", []):
    cmds = " ".join(h.get("command", "") for h in group.get("hooks", []))
    if "docker-guard.py" in cmds:
        names.update(group.get("matcher", "").split("|"))
print(" ".join(sorted(n for n in names if n)))
' "$ROOT/hooks/hooks.json" 2>/dev/null)"

guard_tools="$(python3 -c '
import ast, sys
tree = ast.parse(open(sys.argv[1]).read())
for node in tree.body:
    if isinstance(node, ast.Assign) and getattr(node.targets[0], "id", "") == "TOOLS":
        print(" ".join(sorted(ast.literal_eval(node.value))))
' "$HOOK" 2>/dev/null)"

expected="$(printf '%s\n' "${GUARDED_TOOLS[@]}" | sort | tr '\n' ' ' | sed 's/ $//')"

if [ "$declared" = "$guard_tools" ]; then
  ok "matcher and TOOLS agree ($declared)"
else
  bad "matcher and TOOLS agree" "hooks.json='$declared' guard TOOLS='$guard_tools'"
fi

if [ "$guard_tools" = "$expected" ]; then
  ok "this suite covers every guarded tool"
else
  bad "this suite covers every guarded tool" "guard='$guard_tools' suite='$expected'"
fi

printf '\n--- matched block/allow pairs, per guarded tool ---\n'

for tool in "${GUARDED_TOOLS[@]}"; do
  # BLOCK: creates durable state. This is the assertion that fails for Shell
  # against the pre-fix guard and passes for Bash — the whole point of pairing.
  out="$(run "$tool" 'docker run -it ubuntu')"
  judged="$(is_deny "$out")"
  if [ "$judged" = "yes" ]; then
    ok "$tool: docker run is denied"
  else
    bad "$tool: docker run is denied" "out='$out'"
  fi

  # ALLOW, same tool: read-only inspection must stay unprompted...
  out="$(run "$tool" 'docker ps')"
  if [ "$(is_deny "$out")" = "no" ]; then
    ok "$tool: docker ps is allowed"
  else
    bad "$tool: docker ps is allowed" "out='$out'"
  fi
  # ...and must say so in JSON rather than by falling silent.
  if [ "$(is_json "$out")" = "yes" ]; then
    ok "$tool: allow verdict is valid JSON"
  else
    bad "$tool: allow verdict is valid JSON" "out='$out'"
  fi

  # The documented per-command approval path, asserted through both tools so it
  # cannot regress into working on one only.
  out="$(run "$tool" 'PM_ALLOW_DOCKER=1 docker run -it ubuntu')"
  if [ "$(is_deny "$out")" = "no" ] && [ "$(is_json "$out")" = "yes" ]; then
    ok "$tool: inline PM_ALLOW_DOCKER=1 approves"
  else
    bad "$tool: inline PM_ALLOW_DOCKER=1 approves" "out='$out'"
  fi

  # A wrapper that has historically shelled out to docker.
  out="$(run "$tool" 'make e2e-db')"
  if [ "$(is_deny "$out")" = "yes" ]; then
    ok "$tool: docker-shaped wrapper is denied"
  else
    bad "$tool: docker-shaped wrapper is denied" "out='$out'"
  fi
done

printf '\n--- non-guarded payloads still answer in JSON ---\n'

# A tool this guard has no opinion about must still emit an allow, not silence.
out="$(run 'Read' 'docker run -it ubuntu')"
if [ "$(is_deny "$out")" = "no" ] && [ "$(is_json "$out")" = "yes" ]; then
  ok "unguarded tool allows in JSON"
else
  bad "unguarded tool allows in JSON" "out='$out'"
fi

# Session-wide suppression.
out="$(printf '{"tool_name":"Bash","tool_input":{"command":"docker run -it ubuntu"}}' \
  | PM_ALLOW_DOCKER=1 python3 "$HOOK" 2>/dev/null)"
if [ "$(is_deny "$out")" = "no" ] && [ "$(is_json "$out")" = "yes" ]; then
  ok "PM_ALLOW_DOCKER=1 in env approves in JSON"
else
  bad "PM_ALLOW_DOCKER=1 in env approves in JSON" "out='$out'"
fi

printf '\n--- host-shaped allow verdicts ---\n'

# Cursor is identified by keys only it sends; its allow shape differs.
out="$(printf '{"tool_name":"Bash","cursor_version":"1.0","tool_input":{"command":"docker ps"}}' \
  | env -u PM_ALLOW_DOCKER python3 "$HOOK" 2>/dev/null)"
verdict="$(printf '%s' "$out" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("permission",""))' 2>/dev/null)"
if [ "$verdict" = "allow" ]; then
  ok "cursor payload gets {\"permission\":\"allow\"}"
else
  bad "cursor payload gets {\"permission\":\"allow\"}" "out='$out'"
fi

out="$(run 'Bash' 'docker ps')"
keys="$(printf '%s' "$out" | python3 -c 'import json,sys; print(",".join(sorted(json.load(sys.stdin))))' 2>/dev/null)"
if [ -z "$keys" ]; then
  ok "claude payload gets {}"
else
  bad "claude payload gets {}" "out='$out'"
fi

printf '\n--- degenerate stdin never hangs or blocks ---\n'

# No payload at all: must answer quickly and in JSON, not wait on a descriptor.
out="$(DOCKER_GUARD_STDIN_TIMEOUT=1 python3 "$HOOK" </dev/null 2>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(is_json "$out")" = "yes" ]; then
  ok "empty stdin allows in JSON"
else
  bad "empty stdin allows in JSON" "rc=$rc out='$out'"
fi

out="$(printf 'this is not json' | python3 "$HOOK" 2>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(is_json "$out")" = "yes" ]; then
  ok "non-JSON stdin allows in JSON"
else
  bad "non-JSON stdin allows in JSON" "rc=$rc out='$out'"
fi

echo
printf 'docker-guard: %d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'failed: %s\n' "${FAILED_NAMES[*]}"
  exit 1
fi
