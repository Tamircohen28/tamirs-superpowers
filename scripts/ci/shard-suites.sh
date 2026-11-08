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
#   -v, --verbose  report the shard's size and expected seconds on stderr
#
# Example:
#   scripts/ci/shard-suites.sh 2/6          # the suites the greedy partition gives shard 2
#   make test-hooks SHARD=2/6               # runs exactly that list
#
# THE PARTITION (duration-weighted greedy)
#   The suite list is `find tests -maxdepth 2 -name 'test-*.sh'`, sorted under LC_ALL=C
#   so that a macOS shell in en_US.UTF-8 and a Linux runner in C.UTF-8 agree on the
#   order. Each suite weighs its seconds in <repo-root>/scripts/ci/suite-timings.tsv
#   (`<suite> <tab> <seconds>`, from a CI run's per-suite durations); a suite the file
#   does not name weighs the median of the named ones (1 when it names none). Suites
#   are taken heaviest first (ties by name) and each goes to the shard with the least
#   total so far (ties to the lowest shard number). Every step is deterministic, so a
#   shard is the same list on every machine. With no timings file every weight is
#   equal and the result is round-robin by sorted name.
#
#   This script is the ONLY source of the partition: the Makefile's `test-hooks`
#   target consumes its output, so a shard run on CI and the same `SHARD=i/n` on a
#   laptop run the same suites. Change the partition here, nowhere else. Refresh the
#   timings when a suite's cost moves a lot (testing-matrix.md says how).
#
# Output: one path per line on stdout, relative to repo-root (`tests/...`), in sorted
# order, nothing else. An empty shard (n larger than the suite count) prints nothing and
# exits 0.
#
# Exit: 0 ok · 2 usage error (malformed or out-of-range <i>/<n>, unknown flag, bad root)
set -euo pipefail

usage() { sed -n '2,40p' "$0" | sed -E 's/^# ?//'; }

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

export LC_ALL=C
LIST="$(find tests -maxdepth 2 -name 'test-*.sh' | sort)"
TIMINGS="scripts/ci/suite-timings.tsv"
[ -f "$TIMINGS" ] || TIMINGS=/dev/null

# weighted: "<suite> <tab> <weight>" for every listed suite, heaviest first, ties by name.
# A weight is the timings file's seconds, else the median of the listed suites it names.
weighted="$(printf '%s\n' "$LIST" | awk -F'\t' -v tf="$TIMINGS" '
  FILENAME == tf { if (NF >= 2 && $2 ~ /^[0-9]+([.][0-9]+)?$/) t[$1] = $2 + 0; next }
  NF { s[++n] = $1 }
  END {
    k = 0
    for (j = 1; j <= n; j++) if (s[j] in t) v[++k] = t[s[j]]
    # median by insertion sort (k is ~100)
    for (a = 2; a <= k; a++) { x = v[a]; b = a - 1; while (b >= 1 && v[b] > x) { v[b + 1] = v[b]; b-- } v[b + 1] = x }
    med = (k == 0) ? 1 : ((k % 2) ? v[(k + 1) / 2] : (v[k / 2] + v[k / 2 + 1]) / 2)
    for (j = 1; j <= n; j++) printf "%s\t%.3f\n", s[j], ((s[j] in t) ? t[s[j]] : med)
  }' "$TIMINGS" - | sort -t "$(printf '\t')" -k2,2gr -k1,1)"

# Greedy: each suite to the shard with the least total so far, ties to the lowest index.
SHARD_LIST="$(printf '%s\n' "$weighted" | awk -F'\t' -v i="$I" -v n="$N" -v verbose="$VERBOSE" '
  BEGIN { for (q = 1; q <= n; q++) load[q] = 0 }
  NF {
    best = 1
    for (q = 2; q <= n; q++) if (load[q] < load[best]) best = q
    load[best] += $2
    if (best == i) { print $1; mine += $2; count++ }
    total++
  }
  END { if (verbose) printf "shard %d/%d: %d of %d suites, ~%.0f s expected\n", i, n, count, total, mine > "/dev/stderr" }' | sort)"

[ -z "$SHARD_LIST" ] || printf '%s\n' "$SHARD_LIST"
