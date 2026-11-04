#!/usr/bin/env bash
# tests/test-toolkit-gates.sh — the ADR 004 L1 gates in the toolkit skills.
#
# WHAT IS PINNED
#   usage-capture enable.sh   config.global.write (R4), secrets.capture.bodies
#                             (R4, its own gate), daemon.start / daemon.stop (R2);
#                             all gates before the first write; a timestamped
#                             settings backup; --dry-run asks and writes nothing;
#                             collector --stop never signals a PID that is not it
#   retro gate-writes.sh      every approved write classified and asked; core/**
#                             and rules/** of the framework are always blocked
#   skill-creator             nested `claude -p` (process.spawn.agent_host, R4)
#                             gated before the first spawn, and run with an
#                             explicit restrictive --permission-mode; the eval
#                             viewer stops only a viewer it started
#   (capture-config's policy-hunk gate lives in tests/test-capture.sh.)
#
#   For every gate: allow => runs; ask with no terminal => stops; deny => stops
#   naming the setting; resolver missing or garbage => stops (fail closed, D4);
#   and, through a pty, ask + a typed "yes" => runs.
#
# HOW
#   Each script finds scripts/resolve-permission.sh from its own location, never
#   from the environment, so each runs as a COPY inside a temp plugin tree whose
#   resolver is a stub (the pattern of tests/test-merge-policy.sh Part A). The
#   stub answers STUB_MODE (allow | ask | deny | garbage | exit3), or
#   STUB_DENY=<action> denies one action and allows the rest; ask becomes deny
#   under --headless, as the real resolver does; every call is logged.
#   HOME is a temp dir; `claude` is a fake on PATH that logs its argv; headless
#   runs start a new session with no controlling terminal (no_tty), so the suite
#   behaves the same from a terminal and from CI. No network, no model calls.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$ROOT/tests/lib/harness.sh"
harness_require python3 jq git

TMP="$(harness_tmpdir)"
REAL_HOME="$HOME"
export HOME="$TMP/home"; mkdir -p "$HOME"
unset TS_PERMISSION_LEVEL CLAUDE_PLUGIN_OPTION_PERMISSION_LEVEL TAMIRS_PERMISSION_TEST_ROOT 2>/dev/null || true
export BROWSER=true           # the viewer and run_loop never open a real browser
BG_PIDS="$TMP/bg.pids"; : > "$BG_PIDS"
cleanup() {
  local p
  while IFS= read -r p; do [ -n "$p" ] && kill "$p" 2>/dev/null; done < "$BG_PIDS"
  _harness_cleanup
}
trap cleanup EXIT

# --- the temp plugin tree ------------------------------------------------------
PLUG="$TMP/plugin"
mkdir -p "$PLUG/scripts/usage-capture" "$PLUG/skills/toolkit/retro/scripts" "$PLUG/core/permissions" "$PLUG/rules"
cp "$ROOT/scripts/usage-capture/enable.sh" "$ROOT/scripts/usage-capture/collector.py" "$PLUG/scripts/usage-capture/"
cp "$ROOT/skills/toolkit/retro/scripts/gate-writes.sh" "$PLUG/skills/toolkit/retro/scripts/"
cp -R "$ROOT/skills/toolkit/skill-creator" "$PLUG/skills/toolkit/skill-creator"
printf '{}\n' > "$PLUG/core/permissions/actions.json"   # marks the tree as the framework
STUB="$PLUG/scripts/resolve-permission.sh"
STUB_LOG="$TMP/stub.log"; export STUB_LOG
write_stub() {
  cat > "$STUB" <<'EOF'
#!/usr/bin/env bash
printf 'ARGV %s\n' "$*" >> "$STUB_LOG"
action=""; prev=""
for a in "$@"; do [ "$prev" = --action ] && action="$a"; prev="$a"; done
mode="${STUB_MODE:-ask}"
if [ -n "${STUB_DENY:-}" ]; then
  if [ "$action" = "$STUB_DENY" ]; then mode=deny; else mode=allow; fi
fi
case " $* " in *" --headless "*) [ "$mode" = ask ] && mode=headless-deny ;; esac
case "$mode" in
  garbage) printf 'not json\n' ;;
  exit3) printf '{"verdict":"deny","reason":"resolver error"}\n'; exit 3 ;;
  allow) printf '{"verdict":"allow","reason":"stub allows %s","setting_that_would_allow":null}\n' "$action" ;;
  ask) printf '{"verdict":"ask","reason":"stub asks %s","setting_that_would_allow":{"once":null,"durable":[],"note":"R4 stub note"}}\n' "$action" ;;
  headless-deny) printf '{"verdict":"deny","reason":"denied: headless (stub) %s","setting_that_would_allow":{"once":null,"durable":[],"note":"run it yourself (stub)"}}\n' "$action" ;;
  *) printf '{"verdict":"deny","reason":"stub denies %s","setting_that_would_allow":{"once":null,"durable":["/plugin-config stub allow"],"note":null}}\n' "$action" ;;
esac
EOF
  chmod +x "$STUB"
}
write_stub

# no_tty <cmd...> — a new session with no controlling terminal (/dev/tty cannot open).
no_tty() { python3 -I -S -c 'import os, sys; os.setsid(); os.execvp(sys.argv[1], sys.argv[1:])' "$@"; }

# in_pty <answer> <cmd...> — the pty IS the controlling terminal; <answer> is
# typed at every 'Type "yes"' prompt. Output (pty) on stdout, exit code kept.
in_pty() {
  python3 -I -S - "$@" <<'PYTTY'
import os, pty, select, sys, time
answer, argv = sys.argv[1], sys.argv[2:]
pid, fd = pty.fork()
if pid == 0:
    os.execvp(argv[0], argv)
out, buf, status = b"", b"", None
deadline = time.time() + 120
while time.time() < deadline:
    r, _, _ = select.select([fd], [], [], 0.2)
    if r:
        try:
            chunk = os.read(fd, 4096)
        except OSError:
            chunk = b""
        if not chunk:
            break
        out += chunk
        buf += chunk
        while b'Type "yes"' in buf:
            os.write(fd, (answer + "\n").encode())
            buf = buf.split(b'Type "yes"', 1)[1]
    elif status is None:
        p, st = os.waitpid(pid, os.WNOHANG)
        if p:
            status = st
if status is None:
    try:
        _, status = os.waitpid(pid, 0)
    except ChildProcessError:
        status = 0
sys.stdout.write(out.decode("utf-8", "replace"))
sys.exit(os.waitstatus_to_exitcode(status))
PYTTY
}

free_port() { python3 -I -S -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1]); s.close()'; }
alive() { if kill -0 "$1" 2>/dev/null; then echo yes; else echo no; fi; }
stub_calls() { cat "$STUB_LOG" 2>/dev/null; }

# ==============================================================================
section "usage-capture enable.sh"

EN="$PLUG/scripts/usage-capture/enable.sh"
COL="$PLUG/scripts/usage-capture/collector.py"
SET="$HOME/.claude/settings.json"
LOGDIR="$TMP/usage"
PORT="$(free_port)"
seed_settings() { mkdir -p "$HOME/.claude"; printf '{\n  "theme": "dark",\n  "env": {"KEEP": "1"}\n}\n' > "$SET"; rm -f "$SET".bak.*; }
stop_collector() { python3 "$COL" --dir "$LOGDIR" --port "$PORT" --stop >/dev/null 2>&1 || true; }
settings_sum() { shasum "$SET" 2>/dev/null | awk '{print $1}'; }

# --dry-run asks nothing and writes nothing.
seed_settings; : > "$STUB_LOG"; before="$(settings_sum)"
out="$(STUB_MODE=allow no_tty bash "$EN" --dry-run --json --dir "$LOGDIR" --port "$PORT" 2>&1)"; rc=$?
judge "--dry-run exits 0" 0 "$rc"
judge "--dry-run does not ask the resolver" "" "$(stub_calls)"
judge "--dry-run leaves settings.json untouched" "$before" "$(settings_sum)"
judge "--dry-run writes no backup" no "$(if ls "$SET".bak.* >/dev/null 2>&1; then echo yes; else echo no; fi)"

# allow => writes (with a backup) and starts the collector.
seed_settings; : > "$STUB_LOG"; orig="$(cat "$SET")"
out="$(STUB_MODE=allow no_tty bash "$EN" --json --dir "$LOGDIR" --port "$PORT" 2>&1)"; rc=$?
judge "allow: enable exits 0" 0 "$rc"
judge "allow: settings carry the OTEL env, prompts off" yes \
  "$(if jq -e '.env.OTEL_EXPORTER_OTLP_PROTOCOL == "http/json" and .env.KEEP == "1" and (.env | has("OTEL_LOG_USER_PROMPTS") | not)' "$SET" >/dev/null 2>&1; then echo yes; else echo no; fi)"
BAK="$(ls "$SET".bak.* 2>/dev/null | head -1)"
judge "allow: a timestamped backup was written first" yes "$(has "$BAK" "settings.json.bak.")"
judge "allow: the backup is the original file" "$orig" "$(cat "$BAK" 2>/dev/null)"
judge "allow: the backup is 0600" 600 "$(stat -f '%Lp' "$BAK" 2>/dev/null || stat -c '%a' "$BAK" 2>/dev/null)"
judge "allow: the result names the backup" yes "$(has "$out" '"backup"')"
judge "allow: config.global.write was asked, on settings.json" yes \
  "$(has "$(stub_calls)" "--action config.global.write --skill usage-capture --target $SET")"
judge "allow: daemon.start was asked" yes "$(has "$(stub_calls)" '--action daemon.start')"
judge "allow: no bodies gate without --bodies" no "$(has "$(stub_calls)" 'secrets.capture.bodies')"
running=false
for _ in $(seq 1 50); do
  running="$(python3 "$COL" --dir "$LOGDIR" --port "$PORT" --status --json 2>/dev/null | jq -r '.running')"
  [ "$running" = true ] && break
  sleep 0.2
done
judge "allow: the collector is running" true "$running"
stop_collector

# ask with no terminal => stops, nothing written, the setting and the command named.
for mode in ask deny garbage exit3; do
  seed_settings; : > "$STUB_LOG"; before="$(settings_sum)"
  out="$(STUB_MODE=$mode no_tty bash "$EN" --dir "$LOGDIR" --port "$PORT" 2>&1)"; rc=$?
  judge "$mode: enable stops with exit 3" 3 "$rc"
  judge "$mode: settings.json untouched" "$before" "$(settings_sum)"
  judge "$mode: no backup written" no "$(if ls "$SET".bak.* >/dev/null 2>&1; then echo yes; else echo no; fi)"
  judge "$mode: the collector was not started" false \
    "$(python3 "$COL" --dir "$LOGDIR" --port "$PORT" --status --json 2>/dev/null | jq -r '.running')"
  case "$mode" in
    ask)  judge "ask headless: the resolver was told --headless" yes "$(has "$(stub_calls)" '--headless')"
          judge "ask headless: says how to run it yourself" yes "$(has "$out" 'Run it yourself in a terminal')"
          judge "ask headless: names the setting" yes "$(has "$out" 'allow with: run it yourself (stub)')" ;;
    deny) judge "deny: names the setting that would allow it" yes "$(has "$out" 'allow with: /plugin-config stub allow')" ;;
    *)    judge "$mode: fails closed, naming the resolver" yes "$(has "$out" 'resolver is missing or failed')" ;;
  esac
done

# resolver missing => stops.
seed_settings; mv "$STUB" "$STUB.off"; before="$(settings_sum)"
out="$(STUB_MODE=allow no_tty bash "$EN" --dir "$LOGDIR" --port "$PORT" 2>&1)"; rc=$?
judge "missing resolver: enable stops with exit 3" 3 "$rc"
judge "missing resolver: settings.json untouched" "$before" "$(settings_sum)"
judge "missing resolver: says so" yes "$(has "$out" 'resolver is missing or failed')"
mv "$STUB.off" "$STUB"

# --bodies is its own gate, and every gate runs before the first write.
seed_settings; : > "$STUB_LOG"; before="$(settings_sum)"
out="$(STUB_DENY=secrets.capture.bodies no_tty bash "$EN" --bodies --dir "$LOGDIR" --port "$PORT" 2>&1)"; rc=$?
judge "--bodies denied: enable stops with exit 3" 3 "$rc"
judge "--bodies denied: settings untouched though config.global.write allowed" "$before" "$(settings_sum)"
judge "--bodies: secrets.capture.bodies asked separately" yes \
  "$(has "$(stub_calls)" "--action secrets.capture.bodies --skill usage-capture --target $LOGDIR/bodies")"
seed_settings
out="$(STUB_DENY=daemon.start no_tty bash "$EN" --dir "$LOGDIR" --port "$PORT" 2>&1)"; rc=$?
judge "daemon.start denied: stops before writing settings" "$before" "$(settings_sum)"

# --force never skips the gate.
seed_settings
python3 - "$SET" <<'PYSET'
import json, sys
d = json.load(open(sys.argv[1])); d["env"]["OTEL_EXPORTER_OTLP_ENDPOINT"] = "http://collector.example:4318"
json.dump(d, open(sys.argv[1], "w"))
PYSET
before="$(settings_sum)"
out="$(STUB_MODE=ask no_tty bash "$EN" --force --dir "$LOGDIR" --port "$PORT" 2>&1)"; rc=$?
judge "--force does not skip the gate (headless ask => exit 3)" 3 "$rc"
judge "--force: the foreign endpoint is untouched" "$before" "$(settings_sum)"

# ask + a typed yes on a real terminal => runs; anything else => stops.
seed_settings; : > "$STUB_LOG"
out="$(STUB_MODE=ask in_pty yes bash "$EN" --bodies --dir "$LOGDIR" --port "$PORT")"; rc=$?
judge "pty yes: enable exits 0" 0 "$rc"
judge "pty yes: the prompt named the R4 action and target" yes "$(has "$out" "action config.global.write · target $SET")"
judge "pty yes: --bodies had its own prompt" yes "$(has "$out" 'action secrets.capture.bodies')"
judge "pty yes: settings written with bodies on" yes \
  "$(if jq -e '.env.OTEL_LOG_RAW_API_BODIES | startswith("file:")' "$SET" >/dev/null 2>&1; then echo yes; else echo no; fi)"
stop_collector
seed_settings; before="$(settings_sum)"
out="$(STUB_MODE=ask in_pty no bash "$EN" --dir "$LOGDIR" --port "$PORT")"; rc=$?
judge "pty no: enable stops with exit 3" 3 "$rc"
judge "pty no: settings untouched" "$before" "$(settings_sum)"

# --disable: gated, backed up, keys removed.
seed_settings
STUB_MODE=allow no_tty bash "$EN" --dir "$LOGDIR" --port "$PORT" >/dev/null 2>&1; stop_collector
rm -f "$SET".bak.*; : > "$STUB_LOG"
out="$(STUB_MODE=ask no_tty bash "$EN" --disable --dir "$LOGDIR" --port "$PORT" 2>&1)"; rc=$?
judge "--disable headless ask: exit 3" 3 "$rc"
judge "--disable headless ask: keys still present" 1 "$(jq -r '.env.TAMIRS_USAGE_CAPTURE' "$SET")"
out="$(STUB_MODE=allow no_tty bash "$EN" --disable --dir "$LOGDIR" --port "$PORT" 2>&1)"; rc=$?
judge "--disable allow: exit 0" 0 "$rc"
judge "--disable allow: owned keys removed, others kept" "null 1" \
  "$(jq -r '"\(.env.TAMIRS_USAGE_CAPTURE) \(.env.KEEP)"' "$SET")"
judge "--disable allow: daemon.stop was asked" yes "$(has "$(stub_calls)" '--action daemon.stop')"
judge "--disable allow: backup written" yes "$(if ls "$SET".bak.* >/dev/null 2>&1; then echo yes; else echo no; fi)"

# collector --stop never signals a PID that is not the collector.
mkdir -p "$LOGDIR"
sleep 300 & SLEEPER=$!; echo "$SLEEPER" >> "$BG_PIDS"
PIDF="$(python3 -I -S - "$COL" "$LOGDIR" "$PORT" <<'PYPID'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("collector", sys.argv[1]); m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
m.STATE["dir"] = sys.argv[2]; m.STATE["port"] = int(sys.argv[3])
print(m.pid_path())
PYPID
)"
printf '%s\n' "$SLEEPER" > "$PIDF"
python3 "$COL" --dir "$LOGDIR" --port "$PORT" --stop >/dev/null 2>&1
judge "collector --stop leaves a foreign PID alive" yes "$(alive "$SLEEPER")"
judge "and removes the stale pid file" no "$(exists "$PIDF")"
kill "$SLEEPER" 2>/dev/null

# ==============================================================================
section "retro gate-writes.sh"

GW="$PLUG/skills/toolkit/retro/scripts/gate-writes.sh"
REPO="$TMP/repo"; harness_new_repo "$REPO"
gw() { (cd "$REPO" && no_tty bash "$GW" "$@"); }
dec() { printf '%s\n' "$1" | jq -r --arg p "$2" 'select(.path | endswith($p)) | "\(.action) \(.decision)"' | head -1; }

: > "$STUB_LOG"
out="$(STUB_MODE=allow gw .claude/memory/lesson.md)"; rc=$?
judge "allow: a repo file is written" "file.write.repo write" "$(dec "$out" .claude/memory/lesson.md)"
judge "allow: exit 0" 0 "$rc"
judge "the resolver is asked with --skill retro and the absolute target" yes \
  "$(has "$(stub_calls)" "--skill retro --target $(canon "$REPO")/.claude/memory/lesson.md")"

out="$(STUB_MODE=ask gw "$HOME/.claude/CLAUDE.md" "$HOME/.claude/settings.json" "$HOME/.claude/projects/p/memory/x.md" \
        .claude/settings.json .github/workflows/ci.yml .git/hooks/pre-commit)"; rc=$?
judge "ask: ~/.claude/CLAUDE.md is config.global.write, asked" "config.global.write ask" "$(dec "$out" .claude/CLAUDE.md)"
judge "ask: ~/.claude/settings.json is policy.edit" "policy.edit ask" "$(dec "$out" home/.claude/settings.json)"
judge "ask: the memory dir is file.write.outside_repo" "file.write.outside_repo ask" "$(dec "$out" memory/x.md)"
judge "ask: repo .claude/settings.json is policy.edit" "policy.edit ask" "$(dec "$out" repo/.claude/settings.json)"
judge "ask: a workflow is workflow.edit" "workflow.edit ask" "$(dec "$out" workflows/ci.yml)"
judge "ask: .git/hooks is config.global.write" "config.global.write ask" "$(dec "$out" .git/hooks/pre-commit)"
judge "ask: exit 0 (the skill asks in chat)" 0 "$rc"

out="$(STUB_MODE=ask gw --headless "$HOME/.claude/CLAUDE.md")"; rc=$?
judge "ask --headless: blocked" "config.global.write blocked" "$(dec "$out" .claude/CLAUDE.md)"
judge "ask --headless: exit 3" 3 "$rc"
out="$(STUB_MODE=deny gw "$HOME/.claude/CLAUDE.md")"; rc=$?
judge "deny: blocked with exit 3" "3 config.global.write blocked" "$rc $(dec "$out" .claude/CLAUDE.md)"
judge "deny: names the setting" "/plugin-config stub allow" "$(printf '%s' "$out" | jq -r '.allow_with')"
for mode in garbage exit3; do
  out="$(STUB_MODE=$mode gw notes.md)"; rc=$?
  judge "$mode: blocked, fail closed" "3 file.write.repo blocked" "$rc $(dec "$out" notes.md)"
done
mv "$STUB" "$STUB.off"
out="$(STUB_MODE=allow gw notes.md)"; rc=$?
judge "missing resolver: blocked, fail closed" "3 file.write.repo blocked" "$rc $(dec "$out" notes.md)"
mv "$STUB.off" "$STUB"
: > "$STUB_LOG"
out="$(STUB_MODE=allow gw "$PLUG/core/global-rules.md" "$PLUG/rules/x.md")"; rc=$?
judge "framework core/** is blocked even when the resolver allows" "framework blocked" "$(dec "$out" core/global-rules.md)"
judge "framework rules/** is blocked too" "framework blocked" "$(dec "$out" rules/x.md)"
judge "framework: exit 3" 3 "$rc"
judge "framework: the resolver is not even asked" "" "$(stub_calls)"
out="$(STUB_MODE=allow gw "$PLUG/hooks/new-hook.sh")"
judge "the plugin's own hooks/ are policy.edit" "policy.edit write" "$(dec "$out" hooks/new-hook.sh)"
judge "usage error: no path => exit 2" 2 "$(gw >/dev/null 2>&1; echo $?)"

# ==============================================================================
section "skill-creator nested claude -p (process.spawn.agent_host, R4)"

SC="$PLUG/skills/toolkit/skill-creator"
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
run_eval() { sc no_tty python3 -m scripts.run_eval --eval-set "$TMP/evalset.json" --skill-path "$SKILLDIR" --runs-per-query 1 --num-workers 1 --timeout 5; }

: > "$CLAUDE_LOG"; : > "$STUB_LOG"
out="$(STUB_MODE=allow run_eval 2>&1)"; rc=$?
judge "allow: run_eval exits 0" 0 "$rc"
judge "allow: the gate asked for process.spawn.agent_host" yes \
  "$(has "$(stub_calls)" '--action process.spawn.agent_host --skill skill-creator')"
judge "allow: claude -p ran once per query" 2 "$(grep -c '^ARGV' "$CLAUDE_LOG")"
judge "allow: the child gets an explicit --permission-mode dontAsk" 2 \
  "$(grep -c '\[--permission-mode\] \[dontAsk\]' "$CLAUDE_LOG")"
judge "allow: the child is never bypass" 0 "$(grep -c 'bypassPermissions' "$CLAUDE_LOG")"
judge "allow: the transient command file is cleaned up" "" "$(ls -A "$TMP/proj/.claude/commands" 2>/dev/null)"

for mode in ask deny garbage exit3; do
  : > "$CLAUDE_LOG"
  out="$(STUB_MODE=$mode run_eval 2>&1)"; rc=$?
  judge "$mode: run_eval stops with exit 3" 3 "$rc"
  judge "$mode: no claude -p was started" 0 "$(grep -c '^ARGV' "$CLAUDE_LOG")"
  case "$mode" in
    ask)  judge "ask headless: says how to run it yourself" yes "$(has "$out" 'Run it yourself in a terminal')" ;;
    deny) judge "deny: names the setting" yes "$(has "$out" 'allow with: /plugin-config stub allow')" ;;
    *)    judge "$mode: fails closed" yes "$(has "$out" 'resolver is missing or failed')" ;;
  esac
done
mv "$STUB" "$STUB.off"; : > "$CLAUDE_LOG"
out="$(STUB_MODE=allow run_eval 2>&1)"; rc=$?
judge "missing resolver: run_eval stops with exit 3, nothing started" "3 0" "$rc $(grep -c '^ARGV' "$CLAUDE_LOG")"
mv "$STUB.off" "$STUB"

: > "$CLAUDE_LOG"
out="$(cd "$TMP/proj" && STUB_MODE=ask PATH="$FAKEBIN:$PATH" PYTHONPATH="$SC" in_pty yes python3 -m scripts.run_eval \
        --eval-set "$TMP/evalset.json" --skill-path "$SKILLDIR" --runs-per-query 1 --num-workers 1 --timeout 5)"; rc=$?
judge "pty yes: run_eval exits 0" 0 "$rc"
judge "pty yes: the prompt states how many sessions" yes "$(has "$out" 'start 2 nested `claude -p` sessions')"
judge "pty yes: claude -p ran" 2 "$(grep -c '^ARGV' "$CLAUDE_LOG")"

: > "$CLAUDE_LOG"
out="$(STUB_MODE=allow sc no_tty python3 -m scripts.improve_description --eval-results "$TMP/evalres.json" \
        --skill-path "$SKILLDIR" --model test-model 2>&1)"; rc=$?
judge "allow: improve_description exits 0" 0 "$rc"
judge "allow: its child runs with no tools and dontAsk" 1 \
  "$(grep -c '\[--tools\] \[\] \[--permission-mode\] \[dontAsk\]' "$CLAUDE_LOG")"
: > "$CLAUDE_LOG"
out="$(STUB_MODE=ask sc no_tty python3 -m scripts.improve_description --eval-results "$TMP/evalres.json" \
        --skill-path "$SKILLDIR" --model test-model 2>&1)"; rc=$?
judge "ask headless: improve_description stops, nothing started" "3 0" "$rc $(grep -c '^ARGV' "$CLAUDE_LOG")"
: > "$CLAUDE_LOG"
out="$(STUB_MODE=ask sc no_tty python3 -m scripts.run_loop --eval-set "$TMP/evalset.json" --skill-path "$SKILLDIR" \
        --model test-model --max-iterations 1 --report none 2>&1)"; rc=$?
judge "ask headless: run_loop stops before the first spawn" "3 0" "$rc $(grep -c '^ARGV' "$CLAUDE_LOG")"
judge "run_loop's gate names the loop's size" yes "$(has "$out" 'blocked: process.spawn.agent_host')"

# ==============================================================================
section "skill-creator eval viewer stops only a viewer it started"

WS="$TMP/ws/iteration-1/eval-1/with_skill"; mkdir -p "$WS/outputs"
printf 'out\n' > "$WS/outputs/a.txt"
VTMP="$TMP/vtmp"; mkdir -p "$VTMP"
viewer() { TMPDIR="$VTMP" python3 -u "$SC/eval-viewer/generate_review.py" "$TMP/ws/iteration-1" --port "$1" >"$2" 2>&1 & }
wait_for() { local i; for i in $(seq 1 50); do grep -q "$2" "$1" 2>/dev/null && return 0; sleep 0.2; done; return 1; }

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
judge "in a private 0700 directory" 700 "$(stat -f '%Lp' "$(dirname "$PIDFILE")" 2>/dev/null || stat -c '%a' "$(dirname "$PIDFILE")")"
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
