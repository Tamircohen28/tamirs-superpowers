#!/usr/bin/env bash
# shard-suites.sh — print the test suites that belong to one shard of `make test-hooks`.
#
# Usage:
#   scripts/ci/shard-suites.sh [-v|--verbose] <i>/<n> [repo-root]
#   scripts/ci/shard-suites.sh -h | --help
#
# Arguments:
#   <i>/<n>     shard i of n, 1-based (1/1 is the whole list, in order)
#   repo-root   the tree to list; default: the repository this script lives in
#
# Flags:
#   -h, --help     print this usage and exit 0
#   -v, --verbose  report the shard's size on stderr
#
# Example:
#   scripts/ci/shard-suites.sh 2/4          # every suite k (0-based) with k mod 4 == 1
#   make test-hooks SHARD=2/4               # runs exactly that list
#
# THE PARTITION
#   The suite list is `find tests -maxdepth 2 -name 'test-*.sh'`, sorted under LC_ALL=C
#   so that a macOS shell in en_US.UTF-8 and a Linux runner in C.UTF-8 agree on the
#   order. Suite k (0-based) goes to shard (k mod n) + 1. Round-robin by sorted name is
#   deterministic and needs no timing data; the expensive suites (test-permission-fuzz,
#   test-permission-guard, test-security-regressions, test-toolkit-gates, test-static,
#   test-dist, test-hook-stdin) spread across shards because their names do.
#
#   This script is the ONLY source of the partition: the Makefile's `test-hooks`
#   target consumes its output, so a shard run on CI and the same `SHARD=i/n` on a
#   laptop run the same suites. Change the partition here, nowhere else.
#
# Output: one path per line on stdout, relative to repo-root (`tests/...`), nothing
# else. An empty shard (n larger than the suite count) prints nothing and exits 0.
#
# Exit: 0 ok · 2 usage error (malformed or out-of-range <i>/<n>, unknown flag, bad root)
set -euo pipefail

usage() { sed -n '2,34p' "$0" | sed -E 's/^# ?//'; }

VERBOSE=0
SPEC=""
ROOT=""
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage; exit 0 ;;
    -v|--verbose) VERBOSE=1 ;;
    -*) printf 'shard-suites.sh: unknown flag %s\n' "$arg" >&2; usage >&2; exit 2 ;;
    *)
      if [ -z "$SPEC" ]; then SPEC="$arg"
      elif [ -z "$ROOT" ]; then ROOT="$arg"
      else printf 'shard-suites.sh: too many arguments\n' >&2; usage >&2; exit 2
      fi ;;
  esac
done

[ -n "$SPEC" ] || { printf 'shard-suites.sh: missing <i>/<n>\n' >&2; usage >&2; exit 2; }

# Strict shape: digits, one slash, digits. Anything else (0/4, 5/4, 1/0, a/b, 1, 1/4/2,
# -1/4) is a configuration error and must fail loudly — a silently empty shard in CI
# is a green job that ran nothing.
if ! [[ "$SPEC" =~ ^([0-9]+)/([0-9]+)$ ]]; then
  printf 'shard-suites.sh: SHARD must be <i>/<n> with 1 <= i <= n, got %s\n' "$SPEC" >&2
  exit 2
fi
I=$((10#${BASH_REMATCH[1]}))
N=$((10#${BASH_REMATCH[2]}))
if [ "$N" -lt 1 ] || [ "$I" -lt 1 ] || [ "$I" -gt "$N" ]; then
  printf 'shard-suites.sh: SHARD must be <i>/<n> with 1 <= i <= n, got %s\n' "$SPEC" >&2
  exit 2
fi

if [ -z "$ROOT" ]; then
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi
cd "$ROOT" 2>/dev/null || { printf 'shard-suites.sh: no such directory: %s\n' "$ROOT" >&2; exit 2; }
[ -d tests ] || { printf 'shard-suites.sh: no tests/ under %s\n' "$ROOT" >&2; exit 2; }

# NR is 1-based, so suite k = NR-1; it belongs to shard i when (NR-1) mod n == i-1.
LIST="$(find tests -maxdepth 2 -name 'test-*.sh' | LC_ALL=C sort)"
SHARD_LIST="$(printf '%s\n' "$LIST" | awk -v i="$I" -v n="$N" 'NF && (NR-1) % n == i-1')"

if [ "$VERBOSE" -eq 1 ]; then
  total="$(printf '%s\n' "$LIST" | grep -c . || true)"
  count="$(printf '%s\n' "$SHARD_LIST" | grep -c . || true)"
  printf 'shard %s/%s: %s of %s suites\n' "$I" "$N" "$count" "$total" >&2
fi

[ -z "$SHARD_LIST" ] || printf '%s\n' "$SHARD_LIST"
