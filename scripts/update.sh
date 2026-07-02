#!/usr/bin/env bash
# update.sh — refresh installed plugin artifacts (agents, statusline wiring).
# Marketplace plugin update still requires Claude Code: /plugin update tamirs-superpowers@tamirs-plugins
#
# Usage: make update  |  bash scripts/update.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
AGENTS_SRC="${PLUGIN_DIR}/agents"
AGENTS_DEST="${HOME}/.claude/agents"

if command -v claude >/dev/null 2>&1; then
  claude plugin marketplace update tamirs-plugins 2>/dev/null || true
  if claude plugin update tamirs-superpowers@tamirs-plugins 2>/dev/null; then
    printf 'Updated tamirs-superpowers via claude CLI\n'
  else
    printf 'Run inside Claude Code: /plugin update tamirs-superpowers@tamirs-plugins\n'
  fi
else
  printf 'claude CLI not found — run /plugin update tamirs-superpowers@tamirs-plugins in Claude Code\n'
fi

if [[ -d "$AGENTS_SRC" ]]; then
  mkdir -p "$AGENTS_DEST"
  cp "${AGENTS_SRC}"/*.md "$AGENTS_DEST/"
  printf 'Refreshed %d agent(s) in %s\n' \
    "$(find "${AGENTS_SRC}" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')" "$AGENTS_DEST"
fi

printf 'Done. Restart Claude Code or run /reload-plugins to pick up changes.\n'
