#!/usr/bin/env bash
# extract-error-paths.sh — extract file paths from stack traces and error
# messages, deterministically.
#
# Usage:
#   extract-error-paths.sh "<input>"          # input as arg
#   echo "<input>" | extract-error-paths.sh   # input on stdin
#   extract-error-paths.sh -h | --help
#
# Output (to stdout): one file path per line, sorted, deduplicated. Paths
# are emitted as found in the input — relative or absolute, exactly as
# they appeared. The caller (the targeted-debug skill) is responsible for
# resolving them against the repo if needed.
#
# Recognized stack-trace shapes:
#   - Java/Scala:     at com.example.Foo.bar(Foo.scala:42)
#   - JavaScript:     at Object.<anonymous> (/path/to/file.js:42:7)
#   - Python:         File "/path/to/file.py", line 42, in foo
#   - Bash:           script.sh: line 42:
#   - Generic:        path/to/file.ext:42  (Vim-style)
#
# Why this script exists:
#   The targeted-debug skill's hard rule is "read only files named in the
#   stack trace." That rule is only enforceable if path extraction is
#   deterministic — every interpretation has to come from this script,
#   not from the LLM eyeballing the trace. If the user disagrees with what
#   the script extracted, they edit the input and re-run.
set -uo pipefail

usage() {
  sed -n '2,18p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage 0; fi

if [[ -n "${1:-}" && "$1" != "-" ]]; then
  INPUT="$1"
else
  INPUT=$(cat)
fi

if [[ -z "$INPUT" ]]; then
  echo "ERROR: empty input — pass a stack trace as arg or stdin" >&2
  exit 1
fi

# Pattern 1: parens-wrapped paths e.g. "(Foo.scala:42)" or "(/path/file.js:42:7)"
# Pattern 2: Python File "..." form
# Pattern 3: Vim-style path:line at start of word
# Pattern 4: bash "script.sh: line"
# Combine into a single emission stream, then sort/dedupe.

{
  # Parens-wrapped (Java/Scala/JS): capture content of (...:NN) or (...:NN:CC)
  printf '%s\n' "$INPUT" | grep -oE '\([^()]+\.[a-zA-Z0-9]+:[0-9]+(:[0-9]+)?\)' \
    | sed -E 's/^\(//; s/\)$//; s/:[0-9]+(:[0-9]+)?$//'

  # Python: File "..."
  printf '%s\n' "$INPUT" | grep -oE 'File "[^"]+"' \
    | sed -E 's/^File "//; s/"$//'

  # Vim-style: path:line  (only when path looks file-like — contains a slash or dot-extension)
  printf '%s\n' "$INPUT" | grep -oE '[A-Za-z0-9_./-]+\.[a-zA-Z0-9]+:[0-9]+' \
    | sed -E 's/:[0-9]+$//'

  # Bash: script.sh: line N
  printf '%s\n' "$INPUT" | grep -oE '[A-Za-z0-9_./-]+\.sh: line [0-9]+' \
    | sed -E 's/: line [0-9]+$//'
} | grep -v '^$' | sort -u
