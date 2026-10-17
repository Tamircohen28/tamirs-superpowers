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

echo "--- rate-limit-handoff: the structured record (handoff-protocol.md) ---"

# The systemMessage reaches the user and nobody else. The next session, a
# sibling, or diagnose-objective needs the same facts as data, so a record is
# dropped at .dev-files/handoffs/rate-limit-<ts>.json — only when the repo
# already keeps a .dev-files/ workspace, and never touching stdout.
REC="$TMPROOT/rec"
mkdir -p "$REC/.dev-files/objectives/auth-system" && git -C "$REC" init -q
git -C "$REC" config user.email t@e.x && git -C "$REC" config user.name t
echo hello > "$REC/a.txt"; echo world > "$REC/b.txt"
run_rec() {  # <cwd> [env...] — passes session_id, strips the messaging vars unless given
  local d="$1"; shift
  rm -f "$d"/.dev-files/handoffs/rate-limit-*.json 2>/dev/null   # one record per case
  printf '{"cwd":"%s","session_id":"sess-42","hook_event_name":"StopFailure","error":"rate_limit"}' "$d" \
    | env -u CLAUDE_CODE_MESSAGING_SOCKET -u CLAUDE_CODE_MESSAGING_TOKEN "$@" bash "$H" 2>/dev/null
}
latest_rec() { find "$1/.dev-files/handoffs" -name 'rate-limit-*.json' 2>/dev/null | sort | tail -1; }

out="$(run_rec "$REC")"
keys="$(printf '%s' "$out" | jq -c 'keys' 2>/dev/null)"
[ "$keys" = '["systemMessage"]' ] && ok "no socket vars => stdout is exactly {systemMessage}" \
  || bad "no socket vars => stdout is exactly {systemMessage}" "keys: $keys out: $out"
rec="$(latest_rec "$REC")"
[ -n "$rec" ] && [ -f "$rec" ] && ok "a record is written under .dev-files/handoffs/" \
  || bad "a record is written under .dev-files/handoffs/" "none found"
if [ -n "$rec" ]; then
  jq -e '.kind == "rate-limit-handoff" and .schema_version == 1' "$rec" >/dev/null 2>&1 \
    && ok "record: kind and schema_version" || bad "record: kind and schema_version" "$(cat "$rec")"
  jq -e '.objective == "auth-system"' "$rec" >/dev/null 2>&1 \
    && ok "record: names the open objective" || bad "record: names the open objective" "$(jq -c .objective "$rec")"
  jq -e '.uncommitted == 2' "$rec" >/dev/null 2>&1 \
    && ok "record: uncommitted is the real count, as a number" || bad "record: uncommitted is a number" "$(jq -c .uncommitted "$rec")"
  jq -e '.resume == "/switch-dev handoff objective=auth-system"' "$rec" >/dev/null 2>&1 \
    && ok "record: resume is the switch-dev command for the objective" || bad "record: resume command" "$(jq -c .resume "$rec")"
  jq -e '.session_id == "sess-42"' "$rec" >/dev/null 2>&1 \
    && ok "record: carries the session id" || bad "record: carries the session id" "$(jq -c .session_id "$rec")"
  jq -e '.branch != null and .cwd != null and .written_at != null' "$rec" >/dev/null 2>&1 \
    && ok "record: branch, cwd and written_at" || bad "record: branch, cwd and written_at" "$(cat "$rec")"
  [ "$(jq -r .message "$rec")" = "$(printf '%s' "$out" | jq -r .systemMessage)" ] \
    && ok "record: message equals the systemMessage text" || bad "record: message equals the systemMessage" "differs"
  jq -e '.messaging.socket == null and .messaging.posted == false' "$rec" >/dev/null 2>&1 \
    && ok "record: messaging.socket null, posted false without the vars" || bad "record: messaging without vars" "$(jq -c .messaging "$rec")"
fi

echo "--- rate-limit-handoff: socket vars set but no socket there ---"
out="$(run_rec "$REC" CLAUDE_CODE_MESSAGING_SOCKET="$TMPROOT/no-such.sock" CLAUDE_CODE_MESSAGING_TOKEN="tok-SECRET-9f1")"
rc=$?
[ "$rc" -eq 0 ] && ok "exits 0 with the vars set and the socket absent" || bad "exits 0 with the vars set and the socket absent" "rc=$rc"
msg="$(printf '%s' "$out" | jq -r '.systemMessage // empty' 2>/dev/null)"
[ -n "$msg" ] && ok "still emits the systemMessage" || bad "still emits the systemMessage" "got: $out"
rec="$(latest_rec "$REC")"
jq -e '.messaging.posted == false and (.messaging.reason | test("no socket exists"))' "$rec" >/dev/null 2>&1 \
  && ok "record: posted false, reason says the socket is absent" || bad "record: absent-socket reason" "$(jq -c .messaging "$rec")"
jq -e --arg s "$TMPROOT/no-such.sock" '.messaging.socket == $s' "$rec" >/dev/null 2>&1 \
  && ok "record: names the socket path a reader could post to" || bad "record: names the socket path" "$(jq -c .messaging "$rec")"
if grep -q 'tok-SECRET-9f1' "$rec" || printf '%s' "$out" | grep -q 'tok-SECRET-9f1'; then
  bad "the token never reaches the record or stdout" "token found"
else ok "the token never reaches the record or stdout"; fi

echo "--- rate-limit-handoff: socket vars set and a socket present ---"
# A real listening socket, so the hook sees -S true. Nothing may be written to
# it today (the message line format is undocumented); the record says so.
SOCK="$TMPROOT/live.sock"
if command -v python3 >/dev/null 2>&1; then
  python3 - "$SOCK" <<'PY2' &
import socket, sys, time
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM); s.bind(sys.argv[1]); s.listen(1); s.settimeout(8)
try:
    c, _ = s.accept(); c.settimeout(2)
    data = c.recv(4096)
    sys.stdout.write(data.decode('utf-8', 'replace')); sys.stdout.flush()
except Exception:
    pass
PY2
  listener=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -S "$SOCK" ] && break; sleep 0.2; done
  out="$(run_rec "$REC" CLAUDE_CODE_MESSAGING_SOCKET="$SOCK" CLAUDE_CODE_MESSAGING_TOKEN="tok-SECRET-9f1")"
  rc=$?
  [ "$rc" -eq 0 ] && ok "exits 0 with a live socket" || bad "exits 0 with a live socket" "rc=$rc"
  rec="$(latest_rec "$REC")"
  jq -e '.messaging.posted == false and (.messaging.reason | test("undocumented"))' "$rec" >/dev/null 2>&1 \
    && ok "record: posted false, reason names the undocumented line format" || bad "record: live-socket reason" "$(jq -c .messaging "$rec")"
  kill "$listener" 2>/dev/null; wait "$listener" 2>/dev/null
else
  echo "  skip live-socket case — python3 not available"
fi

echo "--- rate-limit-handoff: no .dev-files workspace => message only, nothing created ---"
NOWS="$TMPROOT/nows"
mkdir -p "$NOWS" && git -C "$NOWS" init -q && echo x > "$NOWS/a.txt"
out="$(run_rec "$NOWS" CLAUDE_CODE_MESSAGING_SOCKET="$TMPROOT/no-such.sock" CLAUDE_CODE_MESSAGING_TOKEN="t")"
printf '%s' "$out" | jq -e '.systemMessage' >/dev/null 2>&1 && ok "still speaks" || bad "still speaks" "got: $out"
[ ! -e "$NOWS/.dev-files" ] && ok "does not create .dev-files/ in a repo that never opted in" \
  || bad "does not create .dev-files/ in a repo that never opted in" "created"

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
