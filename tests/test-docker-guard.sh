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
#   Claude Code reads empty stdout as no objection; Cursor fail-closes on it.
#   So a bare exit(0) is not a portable pass, and per hooks/lib/hook-output.sh
#   a pass is `{}` on every host, Cursor included: an object with no decision.
#
# WHO APPROVES (ADR 004 D5, D8; permissions-gates task-004)
#   The guard no longer takes an approval token: every flagged command is the
#   catalog action docker.state and scripts/resolve-permission.sh decides it.
#   The guard finds the resolver from its own location, so the suite runs a
#   COPY of the guard inside a temp plugin tree whose resolver is a stub
#   (tests/test-merge-policy.sh Part A's pattern) and picks the stub's answer
#   per case. The pre-existing protections run with the stub answering deny,
#   so their assertions are unchanged. Changed: the two token cases — "inline
#   PM_ALLOW_DOCKER=1 approves" and "PM_ALLOW_DOCKER=1 in env approves" — now
#   assert that the token approves nothing. Added: the verdict mapping per host,
#   fail-closed resolver failures. The in-tree guard on the real resolver is
#   judged in tests/test-permission-guard.sh, under its test root (#400).
#
# WHY THE TEMP TREE CARRIES THE PERMISSIONS SCHEMA
#   The guard does not spell the resolver's pass verdict: it reads it from
#   core/schemas/permissions.schema.json (the one $defs/verdict member outside
#   $defs/verdict_r4), next to itself in the plugin. The tree copies the real
#   schema, and two cases below take it away or reshape it to show that an
#   unreadable vocabulary passes nothing.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REAL_HOOK="$ROOT/hooks/docker-guard.py"

PASS=0
FAIL=0
FAILED_NAMES=()

ok()  { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad() { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); printf '  FAIL %s — %s\n' "$1" "$2"; }

if ! command -v python3 >/dev/null 2>&1; then
  printf '  skip docker-guard — python3 not available\n'
  exit 0
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/docker-guard.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
PLUG="$TMP/plugin"
mkdir -p "$PLUG/hooks" "$PLUG/scripts"
cp "$REAL_HOOK" "$PLUG/hooks/docker-guard.py"
mkdir -p "$PLUG/core/schemas"
SCHEMA="$PLUG/core/schemas/permissions.schema.json"
cp "$ROOT/core/schemas/permissions.schema.json" "$SCHEMA"
HOOK="$PLUG/hooks/docker-guard.py"
STUB_LOG="$TMP/stub.log"
export STUB_LOG
# The stub records its argv, then answers per STUB_MODE: allow | ask | deny
# (exit 0), exit3 (deny, exit 3), allow-exit1 (claims allow, exits 1),
# garbage (not JSON), noverdict ({}), slow (sleeps past the guard's deadline).
cat > "$PLUG/scripts/resolve-permission.sh" <<'STUB'
#!/usr/bin/env bash
printf 'ARGV %s\n' "$*" >> "$STUB_LOG"
mode="${STUB_MODE:-deny}"
case "$mode" in
  garbage)   printf 'not json\n'; exit 0 ;;
  noverdict) printf '{}\n'; exit 0 ;;
  slow)      sleep 6; printf '{"verdict":"allow"}\n'; exit 0 ;;
  exit3)     printf '{"verdict":"deny","reason":"stub internal error"}\n'; exit 3 ;;
  allow-exit1) printf '{"verdict":"allow"}\n'; exit 1 ;;
esac
printf '{"action":"docker.state","verdict":"%s","reason":"stub says %s","setting_that_would_allow":{"once":null,"durable":[],"note":"docker.state is never automatic at any level"}}\n' "$mode" "$mode"
STUB
chmod +x "$PLUG/scripts/resolve-permission.sh"

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

  # The old per-command approval token is agent-typeable text (audit D5): it
  # must approve nothing, through both tools.
  out="$(run "$tool" 'PM_ALLOW_DOCKER=1 docker run -it ubuntu')"
  if [ "$(is_deny "$out")" = "yes" ]; then
    ok "$tool: inline PM_ALLOW_DOCKER=1 approves nothing"
  else
    bad "$tool: inline PM_ALLOW_DOCKER=1 approves nothing" "out='$out'"
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

# The old session-wide suppression approves nothing either.
out="$(printf '{"tool_name":"Bash","tool_input":{"command":"docker run -it ubuntu"}}' \
  | PM_ALLOW_DOCKER=1 python3 "$HOOK" 2>/dev/null)"
if [ "$(is_deny "$out")" = "yes" ]; then
  ok "PM_ALLOW_DOCKER=1 in env approves nothing"
else
  bad "PM_ALLOW_DOCKER=1 in env approves nothing" "out='$out'"
fi

printf '\n--- host-shaped allow verdicts ---\n'

# Cursor is identified by keys only it sends; its pass is `{}` like every
# host's (hooks/lib/hook-output.sh): no permission key, no decision at all.
out="$(printf '{"tool_name":"Bash","cursor_version":"1.0","tool_input":{"command":"docker ps"}}' \
  | env -u PM_ALLOW_DOCKER python3 "$HOOK" 2>/dev/null)"
keys="$(printf '%s' "$out" | python3 -c 'import json,sys; print(",".join(sorted(json.load(sys.stdin))) or "none")' 2>/dev/null)"
if [ "$keys" = "none" ]; then
  ok "cursor payload gets {}"
else
  bad "cursor payload gets {}" "out='$out'"
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

printf '\n--- the resolver decides (stub answers per case) ---\n'

# runp <mode> <payload-json> [env...] — the copy's stdout with the stub answering <mode>.
runp() {
  local mode="$1" payload="$2"; shift 2
  : > "$STUB_LOG"
  printf '%s' "$payload" | env -u PM_ALLOW_DOCKER -u CODEX_HOME -u GEMINI_SESSION_ID \
    -u GEMINI_PROJECT_DIR STUB_MODE="$mode" "$@" python3 "$HOOK" 2>/dev/null
}
decision() {
  printf '%s' "$1" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    print("invalid"); raise SystemExit
hs = d.get("hookSpecificOutput") or {}
print(hs.get("permissionDecision") or d.get("permission") or ("allow" if d == {} else "?"))
' 2>/dev/null
}
reason_of() {
  printf '%s' "$1" | python3 -c '
import json, sys
d = json.load(sys.stdin)
print((d.get("hookSpecificOutput") or {}).get("permissionDecisionReason") or d.get("user_message") or "")
' 2>/dev/null
}
check() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$2', got '$3'"; fi; }
contains() { case "$1" in *"$2"*) echo yes ;; *) echo no ;; esac; }

CL='{"tool_name":"Bash","session_id":"sess-1","cwd":"/","tool_input":{"command":"docker compose up -d"}}'
CX='{"tool_name":"Bash","turn_id":"t-1","tool_input":{"command":"docker compose up -d"}}'
OC='{"tool_name":"Bash","host":"opencode","tool_input":{"command":"docker compose up -d"}}'
CU='{"tool_name":"Bash","cursor_version":"1.0","tool_input":{"command":"docker compose up -d"}}'
SUB='{"tool_name":"Bash","session_id":"sess-1","agent_id":"agent-7","tool_input":{"command":"docker run x"}}'

out="$(runp allow "$CL")"
check "allow => the call runs ({} on Claude)" allow "$(decision "$out")"
argv="$(sed -n 's/^ARGV //p' "$STUB_LOG")"
check "  ... the resolver was asked for docker.state" yes "$(contains "$argv" "docker.state --host claude")"
check "  ... with this session and the main-thread agent" yes "$(contains "$argv" "--session sess-1 --agent main")"
check "  ... and the payload's cwd as the repo" yes "$(contains "$argv" "--repo /")"
out="$(runp allow "$SUB")"
check "a subagent's call names its agent_id" yes "$(contains "$(sed -n 's/^ARGV //p' "$STUB_LOG")" "--agent agent-7")"
out="$(runp allow "$CU")"
check "allow on Cursor => {} (no decision, Cursor's rules apply)" "{}" "$out"

out="$(runp ask "$CL")"
check "ask on Claude Code => a hook ask (the host's dialog)" ask "$(decision "$out")"
r="$(reason_of "$out")"
check "  ... the dialog names the exact command" yes "$(contains "$r" "docker compose up -d")"
check "  ... and the action id" yes "$(contains "$r" "docker.state")"
check "  ... and offers no token" no "$(contains "$r" "PM_ALLOW_DOCKER")"

out="$(runp ask "$CX")"
check "ask on Codex => deny (a Codex hook ask fails open)" deny "$(decision "$out")"
out="$(runp ask "$OC")"
check "ask on OpenCode => deny (R3: --auto would approve an ask)" deny "$(decision "$out")"
out="$(runp ask "$CU")"
check "ask on Cursor => deny in Cursor's shape" deny "$(decision "$out")"
out="$(runp ask "$CL" CODEX_HOME=/nonexistent)"
check "ask on a Claude-shaped payload with CODEX_HOME set => deny (stricter host wins)" deny "$(decision "$out")"

out="$(runp deny "$CL")"
check "deny => deny" deny "$(decision "$out")"
r="$(reason_of "$out")"
check "  ... naming the resolver's reason" yes "$(contains "$r" "stub says deny")"
check "  ... and the setting that would allow it" yes "$(contains "$r" "never automatic")"
check "  ... and no token to retry with" no "$(contains "$r" "PM_ALLOW_DOCKER")"

for mode in exit3 allow-exit1 garbage noverdict; do
  out="$(runp "$mode" "$CL")"
  check "resolver answers '$mode' => deny (fail closed)" deny "$(decision "$out")"
done
start=$(date +%s)
out="$(runp slow "$CL")"
elapsed=$(( $(date +%s) - start ))
check "a resolver slower than the deadline => deny (fail closed)" deny "$(decision "$out")"
check "  ... decided inside the hook's 5 s timeout" yes "$([ "$elapsed" -lt 5 ] && echo yes || echo no)"

mv "$PLUG/scripts/resolve-permission.sh" "$PLUG/scripts/resolve-permission.sh.off"
out="$(runp allow "$CL")"
check "resolver missing => deny (fail closed)" deny "$(decision "$out")"
check "  ... and says why" yes "$(contains "$(reason_of "$out")" "missing")"
mv "$PLUG/scripts/resolve-permission.sh.off" "$PLUG/scripts/resolve-permission.sh"

# The pass verdict comes from the schema; without it, nothing passes.
mv "$SCHEMA" "$SCHEMA.off"
out="$(runp allow "$CL")"
check "permissions schema missing => the resolver's pass is denied (fail closed)" deny "$(decision "$out")"
check "  ... as 'gave no verdict'" yes "$(contains "$(reason_of "$out")" "gave no verdict")"
out="$(runp ask "$CL")"
check "  ... while an ask is still an ask" ask "$(decision "$out")"
python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
d["$defs"]["verdict_r4"]["enum"] = ["deny"]
json.dump(d, open(sys.argv[2], "w"))
' "$SCHEMA.off" "$SCHEMA"
out="$(runp allow "$CL")"
check "permissions schema reshaped (verdict_r4 is not ask+deny) => deny (fail closed)" deny "$(decision "$out")"
mv "$SCHEMA.off" "$SCHEMA"
out="$(runp allow "$CL")"
check "  ... and restored, the pass passes again" allow "$(decision "$out")"

out="$(runp allow '{"tool_name":"Bash","tool_input":{"command":"docker ps"}}')"
check "an unflagged command never calls the resolver" "" "$(cat "$STUB_LOG")"

# The in-tree guard on the REAL resolver lives in tests/test-permission-guard.sh
# ("the in-tree docker guard on the real resolver, at every level"). It ran here
# against the developer's own configuration, which this suite cannot redirect (the
# resolver honours its test root only under the permission suites): on a machine
# above supervised the resolver's host-version probe wrote a sess-1 entry into the
# real ~/.local/state/tamirs-superpowers/hostver, and make test-hooks' witness
# rightly failed this suite (#400).

# Claude Code's bypass mode (5.6.7): the resolver is not consulted for what can be removed; a prune still asks.
BY='{"tool_name":"Bash","session_id":"sess-1","cwd":"/","permission_mode":"bypassPermissions","tool_input":{"command":"docker compose up -d"}}'
BYP='{"tool_name":"Bash","session_id":"sess-1","cwd":"/","permission_mode":"bypassPermissions","tool_input":{"command":"docker system prune -af"}}'
check "bypass: compose up runs even when the resolver denies" allow "$(decision "$(runp deny "$BY")")"
check "bypass: a prune still asks" ask "$(decision "$(runp deny "$BYP")")"
BYC='{"tool_name":"Bash","session_id":"sess-1","cwd":"/","permission_mode":"bypassPermissions","tool_input":{"command":"docker compose up -d; docker system prune -af"}}'
check "bypass: a prune after an allowed docker command still asks" ask "$(decision "$(runp deny "$BYC")")"
check "bypass on a Codex payload changes nothing" deny "$(decision "$(runp deny "$(printf '%s' "$CX" | jq -c '.permission_mode="bypassPermissions"')")")"

echo
printf 'docker-guard: %d passed, %d failed\n' "$PASS" "$FAIL"
if [ "$FAIL" -gt 0 ]; then
  printf 'failed: %s\n' "${FAILED_NAMES[*]}"
  exit 1
fi
