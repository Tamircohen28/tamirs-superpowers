#!/usr/bin/env bash
# uninstall.sh — remove plugin-installed artifacts from ~/.claude (does not remove marketplace entry).
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AGENTS_SRC="${PLUGIN_DIR}/agents"
AGENTS_DEST="${HOME}/.claude/agents"

if [[ -d "$AGENTS_SRC" ]]; then
  for agent in "${AGENTS_SRC}"/*.md; do
    [[ -f "$agent" ]] || continue
    dest="${AGENTS_DEST}/$(basename "$agent")"
    if [[ -f "$dest" ]]; then
      rm -f "$dest"
      printf 'Removed %s\n' "$dest"
    fi
  done
fi

if command -v claude >/dev/null 2>&1; then
  claude plugin uninstall tamirs-superpowers@tamirs-plugins 2>/dev/null \
    && printf 'Uninstalled tamirs-superpowers via claude CLI\n' \
    || printf 'Run inside Claude Code: /plugin uninstall tamirs-superpowers@tamirs-plugins\n'
else
  printf 'Run inside Claude Code: /plugin uninstall tamirs-superpowers@tamirs-plugins\n'
fi

printf 'Cursor/Codex: disable the plugin in IDE settings if enabled from this repo path.\n'
