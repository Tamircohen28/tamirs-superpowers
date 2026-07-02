#!/usr/bin/env bash
# detect-platform.sh — return current agent platform: claude, cursor, or codex.
#
# Usage:
#   detect-platform.sh
#   detect-platform.sh -h | --help
#
# Detection order: CODEX_* env, CURSOR_* env, CLAUDE_* env, fallback claude.
set -euo pipefail

usage() {
  sed -n '2,8p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage 0
fi

if [[ -n "${CODEX_HOME:-}" || -n "${CODEX_SESSION_ID:-}" ]]; then
  echo "codex"
  exit 0
fi

if [[ -n "${CURSOR_TRACE_ID:-}" || -n "${CURSOR_AGENT:-}" || "${TERM_PROGRAM:-}" == "cursor" ]]; then
  echo "cursor"
  exit 0
fi

if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" || -n "${CLAUDE_CODE_ENTRYPOINT:-}" || -n "${CLAUDE_SESSION_ID:-}" ]]; then
  echo "claude"
  exit 0
fi

# Default for ambiguous environments (e.g. plain terminal with plugin skills).
echo "claude"
