#!/usr/bin/env bash
# test-doctor-deadline.sh — doctor's external probes run under a deadline (#412).
#
# A harness CLI that never answers `--version` must not hang doctor: the probe is killed
# at DOCTOR_PROBE_SECONDS (at most 3 s) with every process it started, reported as
# "version unknown (probe timed out)", and doctor still reaches its dependency report and
# summary. A hung `gh auth status` is bounded the same way (5 s).
#
# HERMETIC
#   Every run is `env -i` with PATH = a directory of fake CLIs + links to the system tools
#   doctor needs, so no real claude, codex, cursor-agent, gemini, opencode or gh is found.
#   HOME and TMPDIR are temp dirs. No network.
#
# Bash 3.2 compatible.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$ROOT/tests/lib/harness.sh"

T="$(harness_tmpdir)"
DOCTOR="$ROOT/scripts/doctor.sh"
PLAIN="$T/plain"
mkdir -p "$PLAIN" "$T/home" "$T/tmp" "$T/bin" "$T/sys"
printf '# an ordinary repo\n' > "$PLAIN/README.md"

for tool in bash sh env jq awk sed grep head tail find sort tr cat dirname basename git date mkdir rm \
  wc cut uname id ls mktemp readlink python3 tput sleep kill ps; do
  p="$(command -v "$tool" 2>/dev/null || true)"
  case "$p" in /*) ln -sf "$p" "$T/sys/$tool" ;; esac
done
for host in claude codex cursor-agent gemini opencode gh timeout gtimeout; do
  [ -e "$T/sys/$host" ] && rm -f "$T/sys/$host"
done

# hang <name> — a fake CLI that logs its pid and sleeps far past any deadline, in a child.
hang() {
  printf '#!/bin/sh\necho $$ >> "%s"\nsleep 6011 &\necho $! >> "%s"\nwait\n' \
    "$T/pids" "$T/pids" > "$T/bin/$1"
  chmod +x "$T/bin/$1"
}
: > "$T/pids"
hang claude
hang gh
printf '#!/bin/sh\necho "codex-cli 9.9.9"\n' > "$T/bin/codex"; chmod +x "$T/bin/codex"

section "a hung --version and a hung gh auth status are bounded"
start=$(date +%s)
env -i PATH="$T/bin:$T/sys" HOME="$T/home" TMPDIR="$T/tmp" LANG=C DOCTOR_PROBE_SECONDS=1 \
  bash "$DOCTOR" "$PLAIN" </dev/null > "$T/doctor.out" 2>&1
end=$(date +%s)
elapsed=$((end - start))
OUT="$(cat "$T/doctor.out")"
has() { printf '%s\n' "$1" | grep -qF -- "$2" && echo yes || echo no; }

judge "doctor finishes well before the hung CLIs would (elapsed ${elapsed}s < 30s)" yes \
  "$([ "$elapsed" -lt 30 ] && echo yes || echo no)"
judge "the hung claude is reported as a timed-out probe" yes \
  "$(has "$OUT" "claude_code (CLI: version unknown (probe timed out))")"
judge "a healthy CLI still reports its version" yes "$(has "$OUT" "codex (CLI: codex-cli 9.9.9)")"
judge "doctor still reaches the optional-features report" yes "$(has "$OUT" "GitHub automation")"
judge "a hung gh auth status reads as not authenticated" yes \
  "$(has "$OUT" "GitHub automation — PR/issue steps will print output for manual filing instead")"

sleep 2
left=""
while read -r pid; do
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && left="$left $pid"
done < "$T/pids"
judge "no process a killed probe started is still running" "" "${left# }"
for pid in $left; do kill -KILL "$pid" 2>/dev/null || true; done

section "DOCTOR_PROBE_SECONDS is clamped to 1..3"
# shellcheck disable=SC2016 # the literal source line is what is being matched
judge "out-of-range values fall back to 3" yes \
  "$(grep -qF 'case "$PROBE_SECS" in 1|2|3) ;; *) PROBE_SECS=3 ;; esac' "$DOCTOR" && echo yes || echo no)"

harness_summary
