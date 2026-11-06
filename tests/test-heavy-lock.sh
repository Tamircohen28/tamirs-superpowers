#!/usr/bin/env bash
# test-heavy-lock.sh — tests/lib/heavy-lock.sh lets one heavy suite run at a time.
#
# Holds: a second taker waits while the first runs and names it; it proceeds once the first
# exits (no trap needed: a dead holder pid is a stale lock); a stale lock is taken over at once;
# HEAVY_LOCK=0 skips the lock; HEAVY_LOCK_WAIT bounds the wait and says so.
set -uo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$REPO_ROOT/tests/lib/harness.sh"
T="$(harness_tmpdir)"
LIB="$REPO_ROOT/tests/lib/heavy-lock.sh"
LOCK="$T/tamirs-superpowers-heavy-suite.lock"

section "one holder at a time"
HEAVY_LOCK_DIR="$T" bash -c "source '$LIB'; heavy_lock_take first; sleep 3" &
holder=$!
for _ in 1 2 3 4 5 6 7 8 9 10; do [ -f "$LOCK/pid" ] && break; sleep 0.2; done
judge "the first taker holds the lock under its own pid" "$holder" "$(cat "$LOCK/pid" 2>/dev/null)"
start=$(date +%s)
out="$(HEAVY_LOCK_DIR="$T" bash -c "source '$LIB'; heavy_lock_take second; echo got" 2>&1)"
took=$(( $(date +%s) - start ))
judge "the second taker names the holder while it waits" yes "$(case "$out" in *"waits for first"*) echo yes;; *) echo no;; esac)"
judge "the second taker runs once the first has exited" yes "$(case "$out" in *got*) echo yes;; *) echo no;; esac)"
judge "it waited rather than running alongside" yes "$([ "$took" -ge 2 ] && echo yes || echo no)"
wait "$holder" 2>/dev/null

section "stale lock, opt-out, bounded wait"
rm -rf "$LOCK"; mkdir -p "$LOCK"; echo 999999 > "$LOCK/pid"; echo ghost > "$LOCK/name"
out="$(HEAVY_LOCK_DIR="$T" bash -c "source '$LIB'; heavy_lock_take third; echo got" 2>&1)"
judge "a lock whose pid is gone is taken over at once" yes "$(case "$out" in *"stale lock from ghost"*got*) echo yes;; *) echo no;; esac)"
# #388 review: two waiters that see the same dead pid must not both take the lock.
rm -rf "$LOCK"; mkdir -p "$LOCK"; echo 999998 > "$LOCK/pid"; echo ghost > "$LOCK/name"
for w in a b c d; do
  HEAVY_LOCK_DIR="$T" bash -c "source '$LIB'; heavy_lock_take race-$w; echo \"\$(python3 -c \"import time; print(repr(time.time()))\") start $w\" >> '$T/race.log'; sleep 2; echo \"\$(python3 -c \"import time; print(repr(time.time()))\") end $w\" >> '$T/race.log'" 2>/dev/null &
done
wait
overlap="$(sort -g "$T/race.log" | awk '$2 == "start" { n++; if (n > 1) bad = 1 } $2 == "end" { n-- } END { print bad ? "overlap" : "serial" }')"
judge "four waiters on one stale lock run one at a time" serial "$overlap"
rm -rf "$LOCK" "$T/race.log"
rm -rf "$LOCK"; mkdir -p "$LOCK"; echo $$ > "$LOCK/pid"; echo me > "$LOCK/name"
out="$(HEAVY_LOCK=0 HEAVY_LOCK_DIR="$T" bash -c "source '$LIB'; heavy_lock_take fourth; echo got" 2>&1)"
judge "HEAVY_LOCK=0 skips the lock" got "$out"
out="$(HEAVY_LOCK_WAIT=5 HEAVY_LOCK_DIR="$T" bash -c "source '$LIB'; heavy_lock_take fifth; echo got" 2>&1)"
judge "HEAVY_LOCK_WAIT bounds the wait and says so" yes "$(case "$out" in *"running fifth anyway"*got*) echo yes;; *) echo no;; esac)"
rm -rf "$LOCK"

harness_summary
