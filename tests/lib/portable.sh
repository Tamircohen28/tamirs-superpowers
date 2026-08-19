#!/usr/bin/env bash
# portable.sh — cross-platform shims for the tests/ suite.
#
# This repo develops on macOS (bash 3.2, BSD userland) and runs CI on
# ubuntu-latest (bash 5, GNU userland). A helper that exists on only one of those
# produces the worst possible failure mode: green in CI, broken for the
# maintainer — or, as happened while writing this suite, a GNU-only `xargs -a`
# that failed silently on macOS and made three security scanners report "clean"
# because their `|| true` swallowed the error.
#
# Rules encoded here (see rules/dev/user-facing-script-standards.md §3):
#   - `timeout` is NOT present on the development machine, and neither is
#     `gtimeout`. Never call either directly.
#   - `xargs -a` is GNU-only. Redirect stdin instead.
#   - bash is 3.2: no mapfile, no declare -A, no ${var^^}, no `wait -n`.
#
# Sourced by tests/lib/harness.sh, so every suite gets these for free.
# shellcheck shell=bash

# ---------------------------------------------------------------------------
# portable_timeout <seconds> <command> [args...]
#
# Runs the command under a watchdog. Exit status is the command's own, or 124 on
# expiry (matching GNU `timeout`, so callers can branch on it portably).
#
# Three implementations, in preference order:
#   1. `timeout`   — GNU coreutils, present on ubuntu-latest.
#   2. `gtimeout`  — the Homebrew coreutils spelling.
#   3. pure bash   — background the command, poll for liveness with a bounded
#                    sleep loop, TERM then KILL on expiry, propagate the status.
#
# Stdin is redirected from /dev/null: a watchdog around a command that then
# blocks reading an inherited terminal descriptor is not a watchdog.
portable_timeout() {
  local secs="$1"; shift
  [ "$#" -gt 0 ] || { printf 'portable_timeout: no command given\n' >&2; return 2; }

  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@" </dev/null
    return $?
  fi
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@" </dev/null
    return $?
  fi
  _portable_timeout_bash "$secs" "$@"
}

# Does this sleep accept fractional seconds? Both BSD and GNU sleep do, but POSIX
# only requires integers, so it is detected once rather than assumed.
_PORTABLE_SLEEP_TICK=""
_portable_sleep_tick() {
  if [ -z "$_PORTABLE_SLEEP_TICK" ]; then
    if sleep 0.1 >/dev/null 2>&1; then _PORTABLE_SLEEP_TICK="0.1"; else _PORTABLE_SLEEP_TICK="1"; fi
  fi
  printf '%s\n' "$_PORTABLE_SLEEP_TICK"
}

_portable_timeout_bash() {
  local secs="$1"; shift
  local tick ticks waited=0 pid rc

  tick="$(_portable_sleep_tick)"
  if [ "$tick" = "0.1" ]; then ticks=$((secs * 10)); else ticks="$secs"; fi

  "$@" </dev/null &
  pid=$!

  while kill -0 "$pid" 2>/dev/null; do
    if [ "$waited" -ge "$ticks" ]; then
      kill -TERM "$pid" 2>/dev/null
      # Give it a moment to die politely, then insist.
      sleep "$tick"
      kill -KILL "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      return 124
    fi
    sleep "$tick"
    waited=$((waited + 1))
  done

  # The loop exited because the process is gone; `wait` yields its real status.
  wait "$pid"
  rc=$?
  return "$rc"
}

# portable_timeout_impl — which implementation is in play. For reporting, so a
# skip or a failure can name the reason rather than leaving it to guesswork.
portable_timeout_impl() {
  if command -v timeout  >/dev/null 2>&1; then printf 'timeout\n';  return 0; fi
  if command -v gtimeout >/dev/null 2>&1; then printf 'gtimeout\n'; return 0; fi
  printf 'bash-watchdog\n'
}

# ---------------------------------------------------------------------------
# portable_xargs0 <nul-separated-file-list> <command> [args...]
#
# `xargs -a FILE` is GNU-only — BSD xargs rejects it with "invalid option -- a",
# and a caller that appends `|| true` turns that into a silent empty result.
# Redirecting stdin works identically on both.
portable_xargs0() {
  local list="$1"; shift
  [ -s "$list" ] || return 0
  xargs -0 "$@" < "$list"
}

# ---------------------------------------------------------------------------
# portable_realpath <path> — `readlink -f` is GNU-only.
portable_realpath() {
  if [ -d "$1" ]; then (cd "$1" 2>/dev/null && pwd -P); else
    printf '%s/%s\n' "$(cd "$(dirname "$1")" 2>/dev/null && pwd -P)" "$(basename "$1")"
  fi
}

# portable_utc_now — `date -d` / `date --iso-8601` are GNU-only; this spelling
# works on both.
portable_utc_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }
