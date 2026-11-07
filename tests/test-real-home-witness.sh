#!/usr/bin/env bash
# test-real-home-witness.sh — scripts/real-home-witness.sh catches a suite that writes to the plugin's real
# config or state, and does not fail the gate when a live host session rewrites its host-version probe cache or
# its skill context (#400).
#
# HOW
#   Every case points the witness at a fake home (--home, which exists for this suite only) and writes there
#   what a leaking suite or a live session would. Entries a "live session" writes carry a UUID minted at run
#   time (so it occurs in no file under tests/) and a real executable outside every temp dir (sh); entries a
#   "leaking suite" writes carry the ids suites really pass (sess-1, no session, the fixed UUID below) or a
#   fake host CLI in a temp dir. The last section runs the real `make test-hooks` recipe in a hermetic tree
#   whose witness is the real one aimed at the fake home, with stub suites that do those writes mid-run.
#
# Usage: bash tests/test-real-home-witness.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$REPO_ROOT/tests/lib/harness.sh"
harness_require python3 make

W="$REPO_ROOT/scripts/real-home-witness.sh"
TMP="$(harness_tmpdir)"
FAKE="$TMP/home"
CONF="$FAKE/.config/tamirs-superpowers"
STATE="$FAKE/.local/state/tamirs-superpowers"
HV="$STATE/hostver"
SNAP="$TMP/snap.json"
# A UUID that suites pass literally: being written in this file is what makes it a test's, not a host's.
FIXED_UUID="4f7c1d2e-9a3b-4c5d-8e6f-0123456789ab"
LIVE_BIN="$(python3 -c 'import os, shutil; print(os.path.realpath(shutil.which("sh")))')"

new_uuid() { python3 -c 'import uuid; print(uuid.uuid4())'; }

# probe_entry <session|-> <bin> [host] — write a host-version probe-cache entry the way cached_probe does;
# prints its path. "-" writes "session": null (the resolver called without --session).
probe_entry() {
  python3 - "$HV" "$1" "$2" "${3:-claude}" <<'PY'
import hashlib, json, os, sys, time
hv, sess, binp, host = sys.argv[1:5]
sess = None if sess == "-" else sess
key = hashlib.sha256((sess or "-").encode()).hexdigest()[:16]
os.makedirs(hv, mode=0o700, exist_ok=True)
p = os.path.join(hv, "%s.%s.json" % (host, key))
doc = {"version": 1, "host": host, "session": sess, "bin": binp, "bin_id": [1, 2, 3, 4], "have": "2.1.319",
       "line": "2.1.319 (Claude Code)", "why": None, "at": int(time.time())}
with open(p + ".tmp-1", "w") as f:
    f.write(json.dumps(doc, sort_keys=True) + "\n")
os.rename(p + ".tmp-1", p)
print(p)
PY
}

# intent_file <sid> [suffix] [session_id] — write an intent/ file the way permission-intent.sh does (through a
# .<name>.tmp-<pid>); suffix is "", .agent-<key>, .expansion or .submit; prints its path.
intent_file() {
  python3 - "$STATE/intent" "$1" "${2:-}" "${3:-$1}" <<'PY'
import json, os, sys
d, sid, suffix, session = sys.argv[1:5]
os.makedirs(d, mode=0o700, exist_ok=True)
p = os.path.join(d, sid + suffix + ".json")
doc = {"at": 1, "prompt_id": None} if suffix in (".expansion", ".submit") else \
      {"version": 1, "session_id": session, "agent": "main", "host": "claude", "skill": "pr-dev"}
tmp = os.path.join(d, ".%s.tmp-1" % os.path.basename(p))
with open(tmp, "w") as f:
    f.write(json.dumps(doc, indent=2, sort_keys=True) + "\n")
os.rename(tmp, p)
print(p)
PY
}
age_file() { python3 -c 'import os, sys, time; t = time.time() - int(sys.argv[2]); os.utime(sys.argv[1], (t, t))' "$1" "$2"; }

snap() { bash "$W" --home "$FAKE" snapshot > "$SNAP"; }
check() { bash "$W" --home "$FAKE" check "$SNAP" 2>&1; }
reset_home() { rm -rf "$FAKE"; mkdir -p "$CONF" "$STATE/intent" "$HV"; : > "$HV/.lock"; }

# ---------------------------------------------------------------------------
section "usage"

judge "-h exits 0" 0 "$(bash "$W" -h >/dev/null 2>&1; echo $?)"
judge "no command exits 2" 2 "$(bash "$W" --home "$FAKE" >/dev/null 2>&1; echo $?)"
judge "an unknown argument exits 2" 2 "$(bash "$W" --bogus >/dev/null 2>&1; echo $?)"
judge "check without a file exits 2" 2 "$(bash "$W" check >/dev/null 2>&1; echo $?)"
judge "check of a missing snapshot exits 2" 2 "$(bash "$W" --home "$FAKE" check "$TMP/nope" >/dev/null 2>&1; echo $?)"
printf 'not json\n' > "$TMP/garbage"
judge "check of a garbage snapshot exits 2" 2 "$(bash "$W" --home "$FAKE" check "$TMP/garbage" >/dev/null 2>&1; echo $?)"

# ---------------------------------------------------------------------------
section "no plugin dirs (CI): stable"

rm -rf "$FAKE"; mkdir -p "$FAKE"
snap
judge "absent dirs: check exits 0" 0 "$(check >/dev/null; echo $?)"
judge "absent dirs: the snapshot records both as absent" 2 "$(grep -o '"absent"' "$SNAP" | grep -c .)"

# ---------------------------------------------------------------------------
section "a suite that leaks is caught, and the path is named"

reset_home; snap
judge "unchanged state: exit 0, nothing printed" "0:" "$(o="$(check)"; echo "$?:$o")"

reset_home; snap
printf '{"level":"autonomous"}\n' > "$CONF/permissions.json"
out="$(check)"; rc=$?
judge "a config file written: exit 1" 1 "$rc"
judge "  ... named as a leak" yes "$(has "$out" "LEAK added ~/.config/tamirs-superpowers/permissions.json")"

reset_home; snap
printf '{"session_id":"sess-1"}\n' > "$STATE/intent/sess-1.json"
out="$(check)"; rc=$?
judge "an intent file written (the 5.2.0 leak): exit 1" 1 "$rc"
judge "  ... named as a leak" yes "$(has "$out" "LEAK added ~/.local/state/tamirs-superpowers/intent/sess-1.json")"

reset_home; printf 'x\n' > "$STATE/intent/old.json"; snap
printf 'y\n' > "$STATE/intent/old.json"
judge "an existing state file overwritten: exit 1" 1 "$(check >/dev/null; echo $?)"

reset_home; printf 'x\n' > "$STATE/intent/old.json"; snap
rm -f "$STATE/intent/old.json"
out="$(check)"; rc=$?
judge "a state file deleted: exit 1" 1 "$rc"
judge "  ... named as deleted" yes "$(has "$out" "LEAK deleted ~/.local/state/tamirs-superpowers/intent/old.json")"

reset_home; printf 'same\n' > "$STATE/stamp"; snap
printf 'same\n' > "$STATE/stamp"; touch -m -t 202001010000 "$STATE/stamp"
judge "a same-content rewrite (mtime moved): exit 1" 1 "$(check >/dev/null; echo $?)"

# ---------------------------------------------------------------------------
section "the host-version probe cache: a live session's rewrite is excused"

reset_home; snap
p="$(probe_entry "$(new_uuid)" "$LIVE_BIN")"
out="$(check)"; rc=$?
judge "a live session's new probe entry: exit 0" 0 "$rc"
judge "  ... reported as ignored, not hidden" yes "$(has "$out" "ignored added ~/.local/state/tamirs-superpowers/hostver/$(basename "$p")")"
judge "  ... and the hostver dir's own mtime is ignored with it" no "$(has "$out" "LEAK")"

reset_home; u="$(new_uuid)"; probe_entry "$u" "$LIVE_BIN" >/dev/null; snap
sleep 1; probe_entry "$u" "$LIVE_BIN" >/dev/null
judge "a live session refreshing its own entry: exit 0" 0 "$(check >/dev/null; echo $?)"

reset_home; snap
probe_entry "$(new_uuid)" "$LIVE_BIN" >/dev/null; probe_entry "$(new_uuid)" "$LIVE_BIN" codex >/dev/null
judge "two live sessions on two hosts: exit 0" 0 "$(check >/dev/null; echo $?)"

rm -rf "$FAKE"; mkdir -p "$HV"; snap
: > "$HV/.lock"
judge "the probe lock created empty: exit 0" 0 "$(check >/dev/null; echo $?)"

reset_home; snap
probe_entry "$(new_uuid)" "$LIVE_BIN" >/dev/null
printf '{"session_id":"sess-1"}\n' > "$STATE/intent/sess-1.json"
out="$(check)"; rc=$?
judge "a live probe write beside a real leak: still exit 1" 1 "$rc"
judge "  ... the leak is named" yes "$(has "$out" "LEAK added ~/.local/state/tamirs-superpowers/intent/sess-1.json")"

# ---------------------------------------------------------------------------
section "intent/: a live session's skill context is excused"

reset_home; snap
u="$(new_uuid)"; p="$(intent_file "$u")"
out="$(check)"; rc=$?
judge "a live session's new context: exit 0" 0 "$rc"
judge "  ... reported as ignored" yes "$(has "$out" "ignored added ~/.local/state/tamirs-superpowers/intent/$u.json")"

reset_home; u="$(new_uuid)"; intent_file "$u" >/dev/null; snap
sleep 1; intent_file "$u" >/dev/null; intent_file "$u" .agent-a1b2 >/dev/null
intent_file "$u" .expansion >/dev/null; intent_file "$u" .submit >/dev/null
judge "a live session rewriting its context, a subagent's, and both halves: exit 0" 0 "$(check >/dev/null; echo $?)"

reset_home; u="$(new_uuid)"; intent_file "$u" .submit >/dev/null; snap
rm -f "$STATE/intent/$u.submit.json"
judge "a fresh half deleted (paired): exit 1" 1 "$(check >/dev/null; echo $?)"

reset_home; p="$(intent_file sess-1 .submit)"; age_file "$p" 700; snap
rm -f "$p"
judge "a half past 10 min pruned, even a test's: exit 0" 0 "$(check >/dev/null; echo $?)"

reset_home; p="$(intent_file sess-1)"; age_file "$p" 700; snap
rm -f "$p"
judge "a context only 11 min old deleted: exit 1" 1 "$(check >/dev/null; echo $?)"

reset_home; p="$(intent_file sess-1)"; age_file "$p" 90000; snap
rm -f "$p"
judge "a context past 24 h pruned: exit 0" 0 "$(check >/dev/null; echo $?)"

section "intent/: a suite's write there is still a leak"

reset_home; snap
intent_file sess-1 >/dev/null
out="$(check)"; rc=$?
judge "a test session's context (sess-1): exit 1" 1 "$rc"
judge "  ... the reason names the session" yes "$(has "$out" "session 'sess-1' is not a host-minted UUID")"

reset_home; snap
intent_file "$FIXED_UUID" >/dev/null
judge "a context under a UUID a suite passes literally: exit 1" 1 "$(check >/dev/null; echo $?)"

reset_home; snap
intent_file "$(new_uuid)" "" sess-1 >/dev/null
out="$(check)"; rc=$?
judge "a context whose session_id is not the one its name carries: exit 1" 1 "$rc"
judge "  ... said so" yes "$(has "$out" "is not the session its name carries")"

reset_home; snap
printf 'not json\n' > "$STATE/intent/$(new_uuid).json"
judge "a non-JSON context: exit 1" 1 "$(check >/dev/null; echo $?)"

reset_home; snap
printf '{}\n' > "$STATE/intent/$(new_uuid).notes.json"
judge "an unknown intent/ name under a live session: exit 1" 1 "$(check >/dev/null; echo $?)"

reset_home; snap
mkdir -p "$STATE/tickets"; printf '{}\n' > "$STATE/tickets/$(new_uuid).json"
judge "a ticket, even under a live-looking id: exit 1" 1 "$(check >/dev/null; echo $?)"

section "the host-version probe cache: a suite's write there is still a leak"

reset_home; snap
probe_entry sess-1 "$LIVE_BIN" >/dev/null
out="$(check)"; rc=$?
judge "a test session id (sess-1, test-docker-guard's): exit 1" 1 "$rc"
judge "  ... the reason names the session" yes "$(has "$out" "session 'sess-1' is not a host-minted UUID")"

reset_home; snap
probe_entry - "$LIVE_BIN" >/dev/null
judge "no session (a resolver called without --session): exit 1" 1 "$(check >/dev/null; echo $?)"

reset_home; snap
probe_entry "$FIXED_UUID" "$LIVE_BIN" >/dev/null
out="$(check)"; rc=$?
judge "a UUID that a suite passes literally: exit 1" 1 "$rc"
judge "  ... the reason says it is a literal in tests/" yes "$(has "$out" "is a literal in tests/")"

reset_home; snap
mkdir -p "$TMP/bin"; printf '#!/bin/sh\necho 2.1.319\n' > "$TMP/bin/claude"; chmod +x "$TMP/bin/claude"
probe_entry "$(new_uuid)" "$TMP/bin/claude" >/dev/null
out="$(check)"; rc=$?
judge "a fake host CLI in a temp dir: exit 1" 1 "$rc"
judge "  ... the reason names the temp bin" yes "$(has "$out" "is under a temp directory or this checkout")"

reset_home; snap
probe_entry "$(new_uuid)" "$REPO_ROOT/tests/test-real-home-witness.sh" >/dev/null
judge "a bin inside this checkout: exit 1" 1 "$(check >/dev/null; echo $?)"

reset_home; snap
probe_entry "$(new_uuid)" /nonexistent/claude >/dev/null
judge "a bin that does not exist: exit 1" 1 "$(check >/dev/null; echo $?)"

reset_home; snap
p="$(probe_entry "$(new_uuid)" "$LIVE_BIN")"; mv "$p" "$HV/claude.0000000000000000.json"
out="$(check)"; rc=$?
judge "an entry whose name does not match its session: exit 1" 1 "$rc"
judge "  ... said so" yes "$(has "$out" "its name does not match its session")"

reset_home; snap
p="$(probe_entry "$(new_uuid)" "$LIVE_BIN")"; mv "$p" "$HV/codex.${p##*/claude.}"
judge "an entry whose host does not match its name: exit 1" 1 "$(check >/dev/null; echo $?)"

reset_home; snap
printf 'not json\n' > "$HV/claude.0123456789abcdef.json"
judge "a non-JSON entry: exit 1" 1 "$(check >/dev/null; echo $?)"

reset_home; snap
printf 'x\n' > "$HV/notes.txt"
judge "an unknown file name in hostver/: exit 1" 1 "$(check >/dev/null; echo $?)"

reset_home; printf 'x\n' > "$HV/.lock"; snap
printf 'y\n' > "$HV/.lock"
judge "a non-empty lock written: exit 1" 1 "$(check >/dev/null; echo $?)"

reset_home; probe_entry "$(new_uuid)" "$LIVE_BIN" >/dev/null; snap
rm -f "$HV"/claude.*.json
out="$(check)"; rc=$?
judge "a live entry deleted: exit 1" 1 "$rc"
judge "  ... named as deleted" yes "$(has "$out" "LEAK deleted")"

reset_home; snap
ln -s "$LIVE_BIN" "$HV/claude.0123456789abcdef.json"
judge "a symlink in hostver/: exit 1" 1 "$(check >/dev/null; echo $?)"

# ---------------------------------------------------------------------------
section "the gate: make test-hooks with a concurrent probe write and with a real leak"

TREE="$TMP/tree"
mkdir -p "$TREE/scripts/ci" "$TREE/tests"
cp "$REPO_ROOT/Makefile" "$TREE/Makefile"
cp "$REPO_ROOT/scripts/ci/shard-suites.sh" "$TREE/scripts/ci/shard-suites.sh"
# The tree's witness is the real one, aimed at the fake home.
printf '#!/usr/bin/env bash\nexec bash "%s" --home "%s" "$@"\n' "$W" "$FAKE" > "$TREE/scripts/real-home-witness.sh"
RAN="$TMP/ran.log"
write_suite() { # <name> <body> — a stub suite that logs its name, then runs <body>
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$0" >> "%s"\n%s\n' "$RAN" "$2" > "$TREE/tests/$1"
}
# A concurrent live session, mid-suite: it refreshes its probe-cache entry and records a skill context.
LIVE_WRITE="$(declare -f probe_entry intent_file); HV='$HV'; STATE='$STATE'
u=\"\$(python3 -c 'import uuid; print(uuid.uuid4())')\"
probe_entry \"\$u\" '$LIVE_BIN' >/dev/null; intent_file \"\$u\" >/dev/null"
write_suite test-a-concurrent.sh "$LIVE_WRITE"
write_suite test-b-quiet.sh ":"
run_make() {
  : > "$RAN"
  env -u SHARD -u MAKEFLAGS -u MAKEOVERRIDES -u MFLAGS -u MAKELEVEL make -C "$TREE" --no-print-directory test-hooks 2>&1 </dev/null
}

reset_home
out="$(run_make)"; rc=$?
judge "a live session's probe and intent writes during a suite: the gate passes" 0 "$rc"
judge "  ... both suites ran" 2 "$(grep -c . "$RAN")"
judge "  ... the closing line counts them" yes "$(has "$out" "--- 2 of 2 suites ran ---")"
judge "  ... the ignored probe write is in the log" yes "$(has "$out" "witness: ignored added ~/.local/state/tamirs-superpowers/hostver/claude.")"
judge "  ... and the ignored context write" yes "$(has "$out" "witness: ignored added ~/.local/state/tamirs-superpowers/intent/")"

write_suite test-c-leak.sh "$(declare -f probe_entry); HV='$HV'; probe_entry sess-1 '$LIVE_BIN' >/dev/null"
reset_home
out="$(run_make)"; rc=$?
judge "a suite that leaks a probe entry: the gate fails" yes "$([ "$rc" -ne 0 ] && echo yes || echo no)"
judge "  ... naming the suite" yes "$(has "$out" "FAIL tests/test-c-leak.sh wrote to the real")"
judge "  ... and the leaked path" yes "$(has "$out" "LEAK added ~/.local/state/tamirs-superpowers/hostver/claude.")"

write_suite test-c-leak.sh "mkdir -p '$STATE/staged'; printf x > '$STATE/staged/confirm'"
reset_home
out="$(run_make)"; rc=$?
judge "a suite that leaks a confirm stamp: the gate fails" yes "$([ "$rc" -ne 0 ] && echo yes || echo no)"
judge "  ... naming the suite and the path" yes "$(has "$out" "LEAK added ~/.local/state/tamirs-superpowers/staged")"

harness_summary
