#!/usr/bin/env bash
# harness.sh — shared assertion and fixture helpers for the tests/ suite.
#
# Sourced, never executed. It deliberately mirrors the ok/bad/judge/has idiom
# already used by tests/test-worktree-objective.sh and friends so that a reader
# moving between the hook tests and these newer suites sees one style.
#
# WHAT THIS ADDS OVER COPY-PASTE
#   1. One summary/exit convention, so `make test-hooks` treats every suite the
#      same way.
#   2. `harness_tmpdir`, which registers its own trap-based cleanup. A test that
#      forgets cleanup leaves git worktrees behind, and stale worktrees are the
#      single nastiest failure mode in this repo's own tooling.
#   3. `harness_new_repo`, a hermetic git repo with committer identity and hooks
#      disabled — the user's global git config must never change a result.
#
# Contract for callers: `set -uo pipefail` (NOT -e; the assertions ARE the
# control flow), source this file, assert, then call `harness_summary`.

# shellcheck shell=bash

# Cross-platform shims (portable_timeout, portable_xargs0, ...). Sourced here so
# every suite gets them without repeating the source line.
# shellcheck source=tests/lib/portable.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/portable.sh"

PASS=0
FAIL=0
SKIP=0
FAILED_NAMES=()
WARNINGS=()

ok()   { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); FAILED_NAMES+=("$1"); printf '  FAIL %s — %s\n' "$1" "$2"; }
skip() { SKIP=$((SKIP + 1)); printf '  skip %s — %s\n' "$1" "$2"; }
warn() { WARNINGS+=("$1"); printf '  warn %s\n' "$1"; }

# judge <name> <expected> <actual>
judge() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected '$2', got '$3'"; fi; }

# has <haystack> <needle> -> yes|no. A `case` cannot be written inline inside
# $( ) because its `)` would close the substitution, hence the function.
has() { case "$1" in *"$2"*) echo yes ;; *) echo no ;; esac; }

# read_lines <array-name> — populate an array from stdin, one element per line.
# macOS ships bash 3.2, which has no `mapfile`/`readarray`; a test suite that only
# runs on a Homebrew bash is a test suite that does not run on the machine where
# the bug will be found.
read_lines() {
  local __name="$1" __line
  eval "$__name=()"
  while IFS= read -r __line; do
    eval "$__name+=(\"\$__line\")"
  done
}

# exists <path> -> yes|no
exists() { if [ -e "$1" ]; then echo yes; else echo no; fi; }

# section <title>
section() { printf '\n--- %s ---\n' "$1"; }

# harness_require <cmd>... — hard prerequisite; a suite that cannot run at all
# must say so rather than reporting a vacuous pass.
harness_require() {
  local c
  for c in "$@"; do
    command -v "$c" >/dev/null 2>&1 || { echo "FATAL: $c is required"; exit 1; }
  done
}

# harness_have <cmd> — soft prerequisite for a skippable case.
harness_have() { command -v "$1" >/dev/null 2>&1; }

# WHY A FILE AND NOT AN ARRAY
#   Every one of the 33 callers uses `d="$(harness_tmpdir)"`, and a command
#   substitution runs in a subshell: a `_HARNESS_TMPDIRS+=(...)` inside the
#   function mutated the subshell's copy and was discarded on return. The array
#   was therefore always empty at exit and this trap deleted nothing — measured
#   as ~140 leaked /tmp/tmp.* directories after a single `make test-hooks`.
#   A file survives the subshell because the write is a syscall, not a variable.
#
#     bash -c 'A=(); f(){ A+=(x); echo /tmp/z; }; d="$(f)"; echo ${#A[@]}'  ->  0
_HARNESS_TMPDIR_LIST="$(mktemp)"
_harness_cleanup() {
  local d
  while IFS= read -r d; do
    # Worktrees inside the temp tree can hold .git files pointing outward; rm -rf
    # is still correct because every repo involved is itself inside the tree.
    [ -n "$d" ] || continue
    chmod -R u+w "$d" 2>/dev/null || true
    rm -rf "$d"
  done < "$_HARNESS_TMPDIR_LIST"
  rm -f "$_HARNESS_TMPDIR_LIST"
}
trap _harness_cleanup EXIT

# harness_tmpdir — mktemp -d that is cleaned up on exit.
harness_tmpdir() {
  local d
  d="$(mktemp -d)"
  printf '%s\n' "$d" >> "$_HARNESS_TMPDIR_LIST"
  printf '%s\n' "$d"
}

# harness_new_repo <dir> [initial-branch] — hermetic git repo, one empty commit.
harness_new_repo() {
  local dir="$1" branch="${2:-main}"
  mkdir -p "$dir"
  git -C "$dir" init -q -b "$branch"
  git -C "$dir" config user.email test@example.invalid
  git -C "$dir" config user.name "Test Harness"
  git -C "$dir" config commit.gpgsign false
  git -C "$dir" config core.hooksPath /dev/null
  git -C "$dir" commit -q --allow-empty -m "init"
}

# canon <path> — macOS /var is a symlink to /private/var; normalize both sides
# before comparing a path the test built with a path git reported.
canon() { (cd "$1" 2>/dev/null && pwd -P) || printf '%s' "$1"; }

# harness_summary — prints the tally and exits non-zero when anything failed.
harness_summary() {
  printf '\n'
  if [ "${#WARNINGS[@]}" -gt 0 ]; then
    printf 'warnings (%d):\n' "${#WARNINGS[@]}"
    printf '  - %s\n' "${WARNINGS[@]}"
  fi
  printf 'passed: %s   failed: %s   skipped: %s\n' "$PASS" "$FAIL" "$SKIP"
  if [ "$FAIL" -ne 0 ]; then
    printf 'failing: %s\n' "${FAILED_NAMES[*]}"
    exit 1
  fi
  exit 0
}
