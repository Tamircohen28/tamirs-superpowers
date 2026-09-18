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
  # claude plugin update --json (Claude Code 2.1.268+) prints one machine-readable
  # result line — {command, outcome, plugin, scope, message, failureCode} — instead
  # of the human message. On failure this gives a specific reason ("Plugin ... not
  # found", "restart required", etc.) instead of only the generic fallback below.
  # Degrades to that same generic fallback on an older CLI (no --json support, so
  # stdout won't parse as the JSON shape we expect) or with neither jq nor python3
  # available to read it.
  set +e
  update_json="$(claude plugin update tamirs-superpowers@tamirs-marketplace --json 2>/dev/null)"
  update_status=$?
  set -e
  if [[ $update_status -eq 0 ]]; then
    printf 'Updated tamirs-superpowers via claude CLI\n'
  else
    detail=""
    if command -v jq >/dev/null 2>&1; then
      detail="$(printf '%s' "$update_json" | jq -r 'if .message then (.message + (if .failureCode then " (" + .failureCode + ")" else "" end)) else empty end' 2>/dev/null || true)"
    elif command -v python3 >/dev/null 2>&1; then
      detail="$(printf '%s' "$update_json" | python3 -c '
import sys, json
try:
    d = json.load(sys.stdin)
    msg = d.get("message")
    code = d.get("failureCode")
    if msg:
        print(msg + (f" ({code})" if code else ""))
except Exception:
    pass
' 2>/dev/null || true)"
    fi
    [[ -n "$detail" ]] && printf '%s\n' "$detail"
    printf 'Run inside Claude Code: /plugin update tamirs-superpowers@tamirs-marketplace\n'
  fi
else
  printf 'claude CLI not found — run /plugin update tamirs-superpowers@tamirs-marketplace in Claude Code\n'
fi

bash "${SCRIPT_DIR}/setup.sh" apply --yes --targets claude --only agents,statusline "$@"

printf '\nDone. Restart Claude Code or run /reload-plugins to pick up changes.\n'
