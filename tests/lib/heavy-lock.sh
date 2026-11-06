#!/usr/bin/env bash
# heavy-lock.sh — one heavy test suite at a time on this machine.
#
# Source it, then call `heavy_lock_take <name>` near the top of a suite that runs thousands of
# hook processes (the permission fuzz and guard suites). A second heavy suite started meanwhile
# waits for the first and says who holds the lock; it never runs alongside it.
#
# WHY (retro 2026-11-06): several agents ran the fuzz and guard suites at once on one laptop. A
# 2-minute suite took 18, and the core-safety hooks, which fail closed after a 5-second timeout,
# blocked every shell command on the machine for about 20 minutes, twice. CI is unaffected:
# every shard runs on its own runner and never contends.
#
# The lock is a directory (mkdir is atomic on every filesystem we run on) holding the holder's
# pid and suite name. A lock whose pid no longer runs is stale and is taken over, so a suite that
# ends, crashes or is killed frees the lock without any trap (the suites keep their own EXIT
# traps for their temp dirs, and this file never replaces them). heavy_lock_release frees it early.
#
# Environment:
#   HEAVY_LOCK=0             skip the lock (a dedicated machine, or a deliberate parallel run)
#   HEAVY_LOCK_DIR=<dir>     where the lock lives (default: ${TMPDIR:-/tmp})
#   HEAVY_LOCK_WAIT=<sec>    give up waiting after this long and run anyway, saying so (default 1800)

HEAVY_LOCK_PATH=""

heavy_lock_release() {
  [ -n "$HEAVY_LOCK_PATH" ] || return 0
  if [ "$(cat "$HEAVY_LOCK_PATH/pid" 2>/dev/null)" = "$$" ]; then
    rm -rf "$HEAVY_LOCK_PATH"
  fi
  HEAVY_LOCK_PATH=""
}

heavy_lock_take() {
  local name="${1:-$(basename "$0")}" dir waited=0 limit holder hpid
  [ "${HEAVY_LOCK:-1}" = 0 ] && return 0
  dir="${HEAVY_LOCK_DIR:-${TMPDIR:-/tmp}}"
  dir="${dir%/}/tamirs-superpowers-heavy-suite.lock"
  limit="${HEAVY_LOCK_WAIT:-1800}"
  while ! mkdir "$dir" 2>/dev/null; do
    hpid="$(cat "$dir/pid" 2>/dev/null)"
    holder="$(cat "$dir/name" 2>/dev/null)"
    if [ -n "$hpid" ] && ! kill -0 "$hpid" 2>/dev/null; then
      echo "heavy-lock: taking over a stale lock from $holder (pid $hpid is gone)" >&2
      rm -rf "$dir"
      continue
    fi
    if [ "$waited" -eq 0 ]; then
      echo "heavy-lock: $name waits for ${holder:-another heavy suite} (pid ${hpid:-?}) to finish; HEAVY_LOCK=0 skips the wait" >&2
    fi
    if [ "$waited" -ge "$limit" ]; then
      echo "heavy-lock: waited ${limit}s for ${holder:-another heavy suite}; running $name anyway" >&2
      return 0
    fi
    sleep 5
    waited=$((waited + 5))
  done
  echo "$$" > "$dir/pid"
  echo "$name" > "$dir/name"
  HEAVY_LOCK_PATH="$dir"
}
