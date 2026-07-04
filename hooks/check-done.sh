#!/usr/bin/env bash
# Stop hook (ADVISORY — never blocks, always exit 0).
# Reminds to verify a definition-of-done when there are uncommitted code changes.
set -uo pipefail

root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0
changed=$(git -C "$root" status --porcelain 2>/dev/null \
  | grep -cE '\.(ts|tsx|js|jsx|mjs|cjs|py|go|rs|sh)$' || true)

if [ "${changed:-0}" -gt 0 ]; then
  printf '⚠ DoD reminder: %s changed code file(s) in '"'"'%s'"'"'. Before claiming done, confirm lint/typecheck/tests pass AND that CI is green (e.g. '"'"'gh run list'"'"' / '"'"'gh pr checks'"'"') if the change is pushed — cite the result. Do not assert success without evidence.\n' \
    "$changed" "$(basename "$root")" >&2
fi
exit 0
