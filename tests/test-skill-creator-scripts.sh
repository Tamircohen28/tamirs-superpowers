#!/usr/bin/env bash
# tests/test-skill-creator-scripts.sh — skill-creator's nested `claude -p` runs
# and its eval viewer.
#
# WHAT IS PINNED
#   run_eval.py / improve_description.py  every nested `claude -p` child runs
#                             with an explicit --permission-mode dontAsk (never
#                             the user's own default, bypass included);
#                             improve_description also passes --tools ""
#   eval-viewer               stops only a viewer it started: a foreign process
#                             on the port is left alone and a free port used; a
#                             pid file naming a non-viewer is never signalled
#
# HOW
#   `claude` is a fake on PATH that logs its argv; HOME is a temp dir. No
#   network, no model calls.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$ROOT/tests/lib/harness.sh"
harness_require python3

TMP="$(harness_tmpdir)"
REAL_HOME="$HOME"
export HOME="$TMP/home"; mkdir -p "$HOME"
export BROWSER=true           # the viewer never opens a real browser
BG_PIDS="$TMP/bg.pids"; : > "$BG_PIDS"
cleanup() {
  local p
  while IFS= read -r p; do [ -n "$p" ] && kill "$p" 2>/dev/null; done < "$BG_PIDS"
  _harness_cleanup
}
trap cleanup EXIT

SC="$ROOT/skills/toolkit/skill-creator"
free_port() { python3 -I -S -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()'; }
alive() { if kill -0 "$1" 2>/dev/null; then echo yes; else echo no; fi; }
mode_of() { python3 -c 'import os,sys; print(oct(os.stat(sys.argv[1]).st_mode & 0o777)[2:])' "$1" 2>/dev/null; }

# ==============================================================================
section "skill-creator nested claude -p"

FAKEBIN="$TMP/fakebin"; mkdir -p "$FAKEBIN"
CLAUDE_LOG="$TMP/claude.log"; export CLAUDE_LOG
cat > "$FAKEBIN/claude" <<'EOF'
#!/usr/bin/env bash
printf 'ARGV' >> "$CLAUDE_LOG"; for a in "$@"; do printf ' [%s]' "$a" >> "$CLAUDE_LOG"; done; printf '\n' >> "$CLAUDE_LOG"
cat >/dev/null 2>&1 || true
printf '<new_description>a better description</new_description>\n'
EOF
chmod +x "$FAKEBIN/claude"
SKILLDIR="$TMP/skill"; mkdir -p "$SKILLDIR"
printf -- '---\nname: demo\ndescription: demo skill for tests\n---\n\n# demo\n' > "$SKILLDIR/SKILL.md"
printf '[{"query":"q1","should_trigger":true},{"query":"q2","should_trigger":false}]\n' > "$TMP/evalset.json"
printf '{"description":"demo skill for tests","results":[],"summary":{"passed":0,"failed":0,"total":0}}\n' > "$TMP/evalres.json"
mkdir -p "$TMP/proj/.claude"
sc() { (cd "$TMP/proj" && PATH="$FAKEBIN:$PATH" PYTHONPATH="$SC" "$@"); }

: > "$CLAUDE_LOG"
sc python3 -m scripts.run_eval --eval-set "$TMP/evalset.json" --skill-path "$SKILLDIR" \
  --runs-per-query 1 --num-workers 1 --timeout 5 </dev/null >"$TMP/run_eval.out" 2>&1; rc=$?
judge "run_eval exits 0" 0 "$rc"
judge "run_eval: claude -p ran once per query" 2 "$(grep -c '^ARGV' "$CLAUDE_LOG")"
judge "run_eval: each child gets an explicit --permission-mode dontAsk" 2 \
  "$(grep -c '\[--permission-mode\] \[dontAsk\]' "$CLAUDE_LOG")"
judge "run_eval: a child is never bypass" 0 "$(grep -c 'bypassPermissions' "$CLAUDE_LOG")"
judge "run_eval: the transient command file is cleaned up" "" "$(ls -A "$TMP/proj/.claude/commands" 2>/dev/null)"

: > "$CLAUDE_LOG"
sc python3 -m scripts.improve_description --eval-results "$TMP/evalres.json" \
  --skill-path "$SKILLDIR" --model test-model </dev/null >"$TMP/improve.out" 2>&1; rc=$?
judge "improve_description exits 0" 0 "$rc"
judge "improve_description: its child runs with no tools and dontAsk" 1 \
  "$(grep -c '\[--tools\] \[\] \[--permission-mode\] \[dontAsk\]' "$CLAUDE_LOG")"

# ==============================================================================
section "skill-creator eval viewer stops only a viewer it started"

WS="$TMP/ws/iteration-1/eval-1/with_skill"; mkdir -p "$WS/outputs"
printf 'out\n' > "$WS/outputs/a.txt"
VTMP="$TMP/vtmp"; mkdir -p "$VTMP"
viewer() { TMPDIR="$VTMP" python3 -u "$SC/eval-viewer/generate_review.py" "$TMP/ws/iteration-1" --port "$1" >"$2" 2>&1 </dev/null & }
wait_for() { local _; for _ in $(seq 1 50); do grep -q "$2" "$1" 2>/dev/null && return 0; sleep 0.2; done; return 1; }

# A foreign server on the port: left alone, the viewer moves to a free port.
VPORT="$(free_port)"
python3 -m http.server "$VPORT" --bind 127.0.0.1 >/dev/null 2>&1 & FOREIGN=$!; echo "$FOREIGN" >> "$BG_PIDS"
sleep 0.5
viewer "$VPORT" "$TMP/v0.log"; V0=$!; echo "$V0" >> "$BG_PIDS"
wait_for "$TMP/v0.log" 'URL:'
judge "a foreign process on the port is left running" yes "$(alive "$FOREIGN")"
judge "the viewer reports the port in use" yes "$(has "$(cat "$TMP/v0.log")" "port $VPORT is in use")"
kill "$V0" "$FOREIGN" 2>/dev/null; wait "$V0" "$FOREIGN" 2>/dev/null

# Its own previous viewer, recorded in its pid file: stopped and replaced.
VPORT="$(free_port)"
viewer "$VPORT" "$TMP/v1.log"; V1=$!; echo "$V1" >> "$BG_PIDS"
wait_for "$TMP/v1.log" 'URL:'
PIDFILE="$VTMP/tamirs-skill-creator-$(id -u)/viewer-$VPORT.pid"
judge "the viewer records its pid" "$V1" "$(cat "$PIDFILE" 2>/dev/null)"
judge "in a private 0700 directory" 700 "$(mode_of "$(dirname "$PIDFILE")")"
viewer "$VPORT" "$TMP/v2.log"; V2=$!; echo "$V2" >> "$BG_PIDS"
wait_for "$TMP/v2.log" 'URL:'
sleep 0.3
judge "a restart stops the viewer it started" no "$(alive "$V1")"
judge "and serves on the same port" yes "$(has "$(cat "$TMP/v2.log")" "localhost:$VPORT")"
kill "$V2" 2>/dev/null; wait "$V2" 2>/dev/null
judge "a stopped viewer removes its pid file" no "$(exists "$PIDFILE")"

# A pid file naming a process that is not a viewer is never signalled.
VPORT="$(free_port)"
mkdir -p "$(dirname "$PIDFILE")"; chmod 700 "$(dirname "$PIDFILE")"
sleep 300 & SLEEPER=$!; echo "$SLEEPER" >> "$BG_PIDS"
printf '%s\n' "$SLEEPER" > "$VTMP/tamirs-skill-creator-$(id -u)/viewer-$VPORT.pid"
viewer "$VPORT" "$TMP/v3.log"; V3=$!; echo "$V3" >> "$BG_PIDS"
wait_for "$TMP/v3.log" 'URL:'
judge "a pid file naming a non-viewer process does not kill it" yes "$(alive "$SLEEPER")"
kill "$V3" "$SLEEPER" 2>/dev/null; wait "$V3" "$SLEEPER" 2>/dev/null

# ==============================================================================
section "the suite touched nothing real"
judge "HOME was a temp dir" no "$(if [ "$HOME" = "$REAL_HOME" ]; then echo yes; else echo no; fi)"

harness_summary
