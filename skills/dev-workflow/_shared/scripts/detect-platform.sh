#!/usr/bin/env bash
# detect-platform.sh — return current agent platform.
#
# Usage:
#   detect-platform.sh            # print platform id
#   detect-platform.sh --list     # print every id this script can return
#   detect-platform.sh -h | --help
#
# Ids: claude, codex, cursor, gemini, opencode.
# Detection order: CODEX_*, CURSOR_*, GEMINI_*, OPENCODE_*, CLAUDE_*, fallback claude.
# Validation tier: 0 (edit-time; no side effects, never blocks on stdin).
set -euo pipefail

usage() {
  sed -n '2,10p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

case "${1:-}" in
  -h|--help) usage 0 ;;
  --list)    printf '%s\n' claude codex cursor gemini opencode; exit 0 ;;
  "")        ;;
  *)         echo "detect-platform.sh: unknown argument '$1'" >&2; usage 2 ;;
esac

if [[ -n "${CODEX_HOME:-}" || -n "${CODEX_SESSION_ID:-}" ]]; then
  echo "codex"
  exit 0
fi

if [[ -n "${CURSOR_TRACE_ID:-}" || -n "${CURSOR_AGENT:-}" || "${TERM_PROGRAM:-}" == "cursor" ]]; then
  echo "cursor"
  exit 0
fi

# Gemini CLI. GEMINI_API_KEY alone is not sufficient — it is commonly exported
# in shells that are not Gemini sessions — so it only counts alongside a
# Gemini-CLI-specific marker.
if [[ -n "${GEMINI_CLI:-}" || -n "${GEMINI_CLI_VERSION:-}" || -n "${GEMINI_SANDBOX:-}" \
   || -n "${GEMINI_EXTENSION_PATH:-}" \
   || ( -n "${GEMINI_API_KEY:-}" && -n "${GEMINI_CONFIG_DIR:-}" ) ]]; then
  echo "gemini"
  exit 0
fi

if [[ -n "${OPENCODE:-}" || -n "${OPENCODE_BIN:-}" || -n "${OPENCODE_CONFIG:-}" \
   || -n "${OPENCODE_SESSION_ID:-}" ]]; then
  echo "opencode"
  exit 0
fi

if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" || -n "${CLAUDE_CODE_ENTRYPOINT:-}" || -n "${CLAUDE_SESSION_ID:-}" ]]; then
  echo "claude"
  exit 0
fi

# Default for ambiguous environments (e.g. plain terminal with plugin skills).
echo "claude"
