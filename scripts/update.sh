#!/usr/bin/env bash
# update.sh — refresh the installed plugin and the machine artifacts it renders.
#
# THIS IS A SHIM over `scripts/setup.sh apply`, plus the two marketplace commands
# that only the Claude Code CLI can perform.
#
# Usage:
#   make update
#   bash scripts/update.sh [--dry-run] [--verbose] [--help]
#
# Scope is deliberately narrower than install.sh: it refreshes the artifacts that
# go stale as the repo moves (agents/, the statusline wiring) and leaves your
# settings alone. Run `make install` — or `bash scripts/setup.sh apply` — when you
# want the full canonical profile re-applied.
#
# Exit codes: 0 success, 1 failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${1:-}" in
  -h|--help) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
esac

if command -v claude >/dev/null 2>&1; then
  claude plugin marketplace update tamirs-marketplace 2>/dev/null || true
  if claude plugin update tamirs-superpowers@tamirs-marketplace 2>/dev/null; then
    printf 'Updated tamirs-superpowers via claude CLI\n'
  else
    printf 'Run inside Claude Code: /plugin update tamirs-superpowers@tamirs-marketplace\n'
  fi
else
  printf 'claude CLI not found — run /plugin update tamirs-superpowers@tamirs-marketplace in Claude Code\n'
fi

bash "${SCRIPT_DIR}/setup.sh" apply --yes --targets claude --only agents,statusline "$@"

printf '\nDone. Restart Claude Code or run /reload-plugins to pick up changes.\n'
