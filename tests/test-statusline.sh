#!/usr/bin/env bash
# Tests for scripts/statusline.sh.
#
# WHY THE NO-STDIN CASE IS THE POINT
#   The defect being pinned is a hang, not a wrong string. `input=$(cat)` with
#   no writer waits forever, and a statusline that never returns is a session
#   that never paints. A test that merely asserts on output would pass while
#   hanging the suite, so every case here runs under a hard wall-clock timeout
#   and a case that exceeds it is a FAILURE, not a stall.
#
#   Three stdin shapes are exercised, because they fail differently:
#     - piped JSON        the normal path
#     - </dev/null        EOF immediately; the "caller remembered" path
#     - an open fifo      no writer, no EOF: the actual hang

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SL="$ROOT/scripts/statusline.sh"

PASS=0
FAIL=0
FAILED_NAMES=()

[ -f "$SL" ] || { echo "FATAL: statusline not found at $SL"; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "FATAL: jq is required"; exit 1; }

TMPROOT="$(mktemp -d)"

# WHY THERE IS A SENTINEL AND A SNAPSHOT HERE
#   $TMPROOT has vanished mid-run on four CI jobs (2026-09-02): run 33595749097
#   on aeb42caf — which is master — and both jobs of run 33597009636 attempt 1
#   on 9a7c916, which ran on two SEPARATE runner VMs, and run 33599695141 on a
#   branch whose entire diff was .claude/memory/*.md. Re-runs of the same commit
#   unchanged have gone green, and greens and reds interleave within the same
#   hour, so it is neither deterministic nor cleanly transient.
#
#   THE CAUSE IS UNKNOWN. Two explanations have already been written down here
#   as fact and both were wrong: an inherited `trap ... EXIT` in the backgrounded
#   watcher subshell (disproven by repro on bash 3.2.57 and 5.3.15 — bash does
#   not run an inherited EXIT trap in a subshell), and "the directory sits empty
#   and unreferenced for ~2s, so something reaps it" (disproven when the run on
#   the memory-only branch vanished a $TMPROOT that had a .keep file in it).
#   Do not write a third explanation here without a repro to back it.
#
#   What an audit does establish: nothing in this repo can delete a bare
#   mktemp root. Every destructive path is anchored to $WORKTREE_ROOT, itself
#   recomputed as "${HOME}/.claude/worktrees" (hooks/lib/worktree-common.sh:4);
#   the retirement `find` requires depth 2 plus a .git entry; the only
#   `find -delete` is -type f. So this instrumentation exists to tell us which
#   way to look next, not to fix anything:
#
#     SENTINEL is created and never touched. If it dies alongside $TMPROOT the
#     sweeper is external and this repo is exonerated; if only $TMPROOT dies,
#     something targets this suite specifically and the snapshot diff names
#     every other casualty.
SENTINEL="$(mktemp -d)"
# macOS sets TMPDIR with a trailing slash; strip it so the listings below are
# comparable strings rather than differing only by a "//".
TMPDIR_BASE="${TMPDIR:-/tmp}"; TMPDIR_BASE="${TMPDIR_BASE%/}"
TMPDIR_SNAPSHOT="$(ls -1d "$TMPDIR_BASE"/tmp.* 2>/dev/null | sort)"
TMPROOT_VANISHED=0
trap 'rm -rf "$TMPROOT" "$SENTINEL"' EXIT

# tmproot_check <where> — report and RECOVER, never abort.
#
#   This suite asserts statusline behavior, not /tmp durability, and every case
#   below works fine against a recreated directory. Hard-failing here would
#   red-gate unrelated PRs to buy evidence the block below already captures, so
#   it recreates and carries on — loudly, and again in the final summary, so the
#   signal cannot scroll past.
tmproot_check() {
  [ -d "$TMPROOT" ] && return 0
  TMPROOT_VANISHED=1
  echo
  echo "  WARN: TMPROOT vanished ($TMPROOT) — detected at: $1"
  if [ -d "$SENTINEL" ]; then
    echo "  WARN:   sentinel SURVIVED ($SENTINEL) -> something targeted this suite's dir"
  else
    echo "  WARN:   sentinel ALSO GONE ($SENTINEL) -> external sweeper, repo exonerated"
  fi
  echo "  WARN:   other mktemp roots that disappeared since startup:"
  comm -23 <(printf '%s\n' "$TMPDIR_SNAPSHOT") \
           <(ls -1d "$TMPDIR_BASE"/tmp.* 2>/dev/null | sort) | sed 's/^/  WARN:     /'
  echo "  WARN:   ls -ld $TMPDIR_BASE: $(ls -ld "$TMPDIR_BASE" 2>&1)"
  echo "  WARN:   processes alive (an earlier suite disowns rm -rf workers):"
  # Truncated hard: an agent harness command line can run to several KB and
  # would bury the four lines above it that actually carry the signal.
  ps -eo pid,ppid,lstart,args 2>/dev/null | grep -E 'rm -rf|worktree|statusline' \
    | grep -v grep | cut -c1-160 | sed 's/^/  WARN:     /' | head -20
  mkdir -p "$TMPROOT"
  echo "  WARN:   recreated $TMPROOT; continuing"
  echo
}

ok()   { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); printf '  FAIL %s — %s\n' "$1" "$2"; }

# run_with_timeout <seconds> <command...>
#
# NO EXTERNAL `timeout` BINARY IS USED ANYWHERE IN THIS FILE.
#   `timeout(1)` ships with GNU coreutils, which a stock macOS does not have —
#   and this repo's primary development platform IS macOS. A test that shells
#   out to a missing binary does not "fail safe": `command not found` is a
#   non-zero exit that reads as "the case failed", or worse, gets skipped and
#   reported green. Since the whole point of this file is catching a HANG, a
#   watchdog that silently isn't there is the one failure it cannot afford.
#
#   So the wall clock is enforced with bash built-ins only: background the
#   command, poll it with `kill -0`, `kill -9` on expiry. Nothing here is
#   optional on any POSIX shell.
#
# Returns the command's own exit status, or 124 for "timed out" — the same code
# timeout(1) uses, so callers read the same either way.
run_with_timeout() {
  local secs="$1"; shift
  "$@" &
  local pid=$!
  (
    local waited=0
    while kill -0 "$pid" 2>/dev/null; do
      if [ "$waited" -ge "$secs" ]; then kill -9 "$pid" 2>/dev/null; exit 0; fi
      sleep 1
      waited=$((waited + 1))
    done
  ) &
  local watcher=$!
  wait "$pid" 2>/dev/null
  local rc=$?
  kill "$watcher" 2>/dev/null
  wait "$watcher" 2>/dev/null
  # A process killed by SIGKILL reports 137; report it as a timeout.
  [ "$rc" = 137 ] && rc=124
  return "$rc"
}

# expect_ok <name> <seconds> <command...>
# Runs under the watchdog and distinguishes the two ways a case can fail:
# TIMED OUT (the hang regressed) versus a plain non-zero exit (something else
# broke). The original version reported both as "timed out", which would have
# sent the next reader hunting a hang that was not there.
expect_ok() {
  local name="$1" secs="$2"; shift 2
  local rc
  run_with_timeout "$secs" "$@"
  rc=$?
  case "$rc" in
    0)   return 0 ;;
    124) bad "$name" "TIMED OUT after ${secs}s — the no-stdin hang has regressed"; return 1 ;;
    *)   bad "$name" "exited $rc (not a timeout)"; return 1 ;;
  esac
}

# ---------------------------------------------------------------------------
# THE WATCHDOG MUST BE PROVEN BEFORE IT IS TRUSTED.
#
# Every hang assertion below is only as good as run_with_timeout. If it were
# broken into a no-op — an early return, a watcher that never fires, a bash
# without job control — every case would exit 0 and the suite would report a
# confident green while testing nothing at all. That is precisely the silent
# pass this file exists to prevent, so the mechanism is tested first, against a
# command that is guaranteed to outlive its deadline. If this fails, nothing
# after it means anything, and the run stops.
# ---------------------------------------------------------------------------
echo "--- watchdog self-test (the tests below are worthless without it) ---"

_probe_start="$(date +%s)"
run_with_timeout 2 sleep 30
_probe_rc=$?
_probe_elapsed=$(( $(date +%s) - _probe_start ))

# Halves the unknown window. Without this probe the only check is ~2.01s after
# the mktemp, so a report could say no more than "it went sometime in there".
tmproot_check "immediately after the 2s watchdog kill"

if [ "$_probe_rc" != 124 ]; then
  echo "  FATAL: the pure-bash watchdog did not time out a 30s sleep (rc=$_probe_rc)."
  echo "         Every hang assertion in this file would pass vacuously."
  echo "         SKIPPING LOUDLY rather than reporting a false green."
  exit 1
fi
if [ "$_probe_elapsed" -gt 10 ]; then
  echo "  FATAL: the watchdog took ${_probe_elapsed}s to enforce a 2s deadline."
  exit 1
fi
ok "watchdog kills an over-running command and reports 124 (${_probe_elapsed}s)"

run_with_timeout 5 true
[ $? = 0 ] && ok "watchdog passes through a fast success" \
           || bad "watchdog passes through a fast success" "got non-zero"

run_with_timeout 5 sh -c 'exit 3'
[ $? = 3 ] && ok "watchdog preserves a real exit code (not mislabelled as timeout)" \
           || bad "watchdog preserves a real exit code (not mislabelled as timeout)" "code was lost"

SAMPLE_JSON="$(jq -n --argjson resets "$(( $(date +%s) + 5400 ))" '{
  model: {display_name: "Opus 5 (1M context)"},
  workspace: {current_dir: "/tmp"},
  effort: {level: "high"},
  context_window: {used_percentage: 42.3},
  rate_limits: {
    five_hour: {used_percentage: 71, resets_at: $resets},
    seven_day: {used_percentage: 12, resets_at: $resets}
  },
  cost: {total_duration_ms: 3723000, total_cost_usd: 12.345},
  version: "2.1.233"
}')"

# Same payload plus rate_limits.spend_limit (Claude Code 2.1.251+, gateway-only).
SAMPLE_JSON_SPEND="$(echo "$SAMPLE_JSON" | jq --argjson resets "$(( $(date +%s) + 5400 ))" \
  '.rate_limits.spend_limit = {used_percentage: 55, resets_at: $resets}')"

echo "--- statusline: piped JSON ---"

tmproot_check "before first use"

out="$TMPROOT/piped.out"
if run_with_timeout 5 bash -c 'printf "%s" "$1" | bash "$2" > "$3" 2>&1' _ "$SAMPLE_JSON" "$SL" "$out"; then
  rendered="$(cat "$out")"
  case "$rendered" in
    *"Opus 5 (1M)"*) ok "renders the model name" ;;
    *) bad "renders the model name" "got: ${rendered%%$'\n'*}" ;;
  esac
  case "$rendered" in
    *"ctx:42%"*) ok "renders context percentage" ;;
    *) bad "renders context percentage" "got: ${rendered%%$'\n'*}" ;;
  esac
  case "$rendered" in
    *'$12.35'*) ok "renders cost" ;;
    *) bad "renders cost" "got: $rendered" ;;
  esac
  # 5h and 7d lines both present => three lines.
  lines="$(printf '%s\n' "$rendered" | grep -c .)"
  if [ "$lines" -eq 3 ]; then ok "renders 5h and 7d limit lines"; else bad "renders 5h and 7d limit lines" "expected 3 lines, got $lines"; fi
  case "$rendered" in
    *"spend:"*) bad "omits spend line when rate_limits.spend_limit is absent" "got: $rendered" ;;
    *) ok "omits spend line when rate_limits.spend_limit is absent" ;;
  esac
else
  bad "piped JSON completes" "timed out or exited non-zero"
fi

echo "--- statusline: rate_limits.spend_limit present (Claude Code 2.1.251+, gateway-only) ---"

out="$TMPROOT/spend.out"
if run_with_timeout 5 bash -c 'printf "%s" "$1" | bash "$2" > "$3" 2>&1' _ "$SAMPLE_JSON_SPEND" "$SL" "$out"; then
  rendered="$(cat "$out")"
  case "$rendered" in
    *"spend: "*"55%"*) ok "renders the spend limit line" ;;
    *) bad "renders the spend limit line" "got: $rendered" ;;
  esac
  # 5h, 7d, and spend lines all present => four lines.
  lines="$(printf '%s\n' "$rendered" | grep -c .)"
  if [ "$lines" -eq 4 ]; then ok "renders 5h, 7d, and spend limit lines"; else bad "renders 5h, 7d, and spend limit lines" "expected 4 lines, got $lines"; fi
else
  bad "piped JSON with spend_limit completes" "timed out or exited non-zero"
fi

echo "--- statusline: stdin absent (must not hang) ---"

out="$TMPROOT/null.out"
start="$(date +%s)"
if expect_ok "</dev/null returns promptly" 5 bash -c 'bash "$1" </dev/null > "$2" 2>&1' _ "$SL" "$out"; then
  elapsed=$(( $(date +%s) - start ))
  ok "</dev/null returns (${elapsed}s)"
  rendered="$(cat "$out")"
  if [ -n "$rendered" ]; then ok "</dev/null still renders a line"; else bad "</dev/null still renders a line" "empty output"; fi
  case "$rendered" in
    *"ctx:--"*) ok "</dev/null degrades context to --" ;;
    *) bad "</dev/null degrades context to --" "got: ${rendered%%$'\n'*}" ;;
  esac
  case "$rendered" in
    *error*|*parse*) bad "</dev/null emits no jq error text" "got: $rendered" ;;
    *) ok "</dev/null emits no jq error text" ;;
  esac
fi

echo "--- statusline: stdin is an open pipe with no writer (the real hang) ---"

FIFO="$TMPROOT/fifo"
mkfifo "$FIFO"
# Hold the write end open without ever writing: no data, and no EOF either.
sleep 20 > "$FIFO" &
holder=$!
out="$TMPROOT/fifo.out"
start="$(date +%s)"
if expect_ok "open-pipe stdin returns via read timeout" 8 bash -c 'bash "$1" < "$2" > "$3" 2>&1' _ "$SL" "$FIFO" "$out"; then
  elapsed=$(( $(date +%s) - start ))
  ok "open-pipe stdin returns via read timeout (${elapsed}s)"
  if [ -n "$(cat "$out")" ]; then ok "open-pipe stdin still renders a line"; else bad "open-pipe stdin still renders a line" "empty output"; fi
fi
kill "$holder" 2>/dev/null
wait "$holder" 2>/dev/null

echo "--- statusline: malformed payload ---"

out="$TMPROOT/junk.out"
if run_with_timeout 5 bash -c 'printf "not json at all" | bash "$1" > "$2" 2>&1' _ "$SL" "$out"; then
  rendered="$(cat "$out")"
  case "$rendered" in
    *"ctx:--"*) ok "non-JSON payload degrades instead of erroring" ;;
    *) bad "non-JSON payload degrades instead of erroring" "got: ${rendered%%$'\n'*}" ;;
  esac
else
  bad "non-JSON payload completes" "timed out"
fi

echo
echo "passed: $PASS   failed: $FAIL"
if [ "$TMPROOT_VANISHED" -eq 1 ]; then
  echo "WARN: TMPROOT vanished during this run and was recreated — see the WARN block above."
fi
if [ "$FAIL" -ne 0 ]; then
  printf 'failing: %s\n' "${FAILED_NAMES[*]}"
  exit 1
fi
exit 0
