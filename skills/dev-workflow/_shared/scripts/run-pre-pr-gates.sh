#!/usr/bin/env bash
# run-pre-pr-gates.sh — mandatory agent-kit / multi-platform pre-PR validation.
#
# Wired into start-dev (before push/PR), pr-dev (before every push + readiness gate),
# and detect-stack.sh (emitted after make validate when applicable).
#
# Usage:
#   bash skills/dev-workflow/_shared/scripts/run-pre-pr-gates.sh [repo-root]
#
# Exit 0 when all applicable gates pass; 1 on failure; 0 when no gates apply.
set -euo pipefail

ROOT="${1:-.}"
ROOT="$(cd "$ROOT" && pwd)"
MAKEFILE="$ROOT/Makefile"

if [[ ! -f "$MAKEFILE" ]]; then
  echo "pre-pr-gates: no Makefile — skipping"
  exit 0
fi

run_make() {
  local target="$1"
  echo "=== pre-pr-gates: make $target ==="
  make -C "$ROOT" "$target"
}

# Prefer the full repo-standards polish exit gate when defined.
if grep -qE '^repo-standards-gate:' "$MAKEFILE" 2>/dev/null; then
  run_make repo-standards-gate
  echo "pre-pr-gates: passed (repo-standards-gate)"
  exit 0
fi

if grep -qE '^agent-polish-gate:' "$MAKEFILE" 2>/dev/null; then
  run_make agent-polish-gate
  echo "pre-pr-gates: passed (agent-polish-gate)"
  exit 0
fi

if grep -qE '^agent\\:check:' "$MAKEFILE" 2>/dev/null; then
  run_make 'agent:check'
  echo "pre-pr-gates: passed (agent:check)"
  exit 0
fi

echo "pre-pr-gates: no agent targets in Makefile — skipping"
exit 0
