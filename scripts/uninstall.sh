#!/usr/bin/env bash
# uninstall.sh — remove plugin-installed artifacts from ~/.claude (does not remove marketplace entry).
#
# Usage: make uninstall  |  bash scripts/uninstall.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
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

# Unwire the Pushover Notification hook, leaving any other Notification hooks
# in place. Credentials are NOT deleted — they are user secrets, and a reinstall
# should not need them re-entered. Remove ~/.claude/pushover.env by hand to purge.
SETTINGS_FILE="${HOME}/.claude/settings.json"
if [[ -f "$SETTINGS_FILE" ]] && command -v jq > /dev/null 2>&1; then
  if jq -e '[(.hooks.Notification // [])[].hooks[]?.command // "" | select(test("notify-pushover"))] | length > 0' \
    "$SETTINGS_FILE" > /dev/null 2>&1; then
    jq '
      .hooks.Notification = ((.hooks.Notification // [])
        | map(select([(.hooks // [])[] | .command // "" | test("notify-pushover")] | any | not)))
      | if (.hooks.Notification | length) == 0 then del(.hooks.Notification) else . end
    ' "$SETTINGS_FILE" > "${SETTINGS_FILE}.tmp" && mv "${SETTINGS_FILE}.tmp" "$SETTINGS_FILE"
    printf 'Unwired Pushover Notification hook from %s\n' "$SETTINGS_FILE"
    if [[ -f "${HOME}/.claude/pushover.env" ]]; then
      printf 'Kept credentials at %s — delete manually to purge.\n' "${HOME}/.claude/pushover.env"
    fi
  fi
fi

if command -v claude >/dev/null 2>&1; then
  claude plugin uninstall tamirs-superpowers@tamirs-marketplace 2>/dev/null \
    && printf 'Uninstalled tamirs-superpowers via claude CLI\n' \
    || printf 'Run inside Claude Code: /plugin uninstall tamirs-superpowers@tamirs-marketplace\n'
else
  printf 'Run inside Claude Code: /plugin uninstall tamirs-superpowers@tamirs-marketplace\n'
fi

printf 'Cursor/Codex: disable the plugin in IDE settings if enabled from this repo path.\n'
