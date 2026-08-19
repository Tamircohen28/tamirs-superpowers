#!/usr/bin/env bash
# uninstall.sh — remove what install.sh wrote into ~/.claude.
#
# THIS IS A SHIM over `scripts/setup.sh remove`, which is symmetric with apply by
# construction: both go through the same render/compare/confirm/write path.
#
# Usage:
#   make uninstall
#   bash scripts/uninstall.sh [--dry-run] [--verbose] [--help]
#
# What it removes:
#   - ~/.claude/settings.json  restored from ~/.claude/settings.json.pre-tamirs-superpowers,
#     the copy taken before this repo ever wrote to it. A dated backup of the
#     current file is rotated first, so this undo is itself undoable.
#   - the agents this repo installed into ~/.claude/agents/
#   - ~/.claude/CLAUDE.md, only when it is byte-identical to the template we wrote
#   - the Pushover Notification hook, leaving any other Notification hooks alone
#
# What it deliberately KEEPS:
#   - ~/.claude/pushover.env — those are your credentials, and a reinstall should
#     not need them re-entered. Delete it by hand to purge.
#   - the marketplace entry, and every plugin other than this one.
#
# Preview first:
#   bash scripts/uninstall.sh --dry-run
#
# Exit codes: 0 success, 1 failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "${1:-}" in
  -h|--help) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
esac

bash "${SCRIPT_DIR}/setup.sh" remove --yes --targets claude "$@"

if command -v claude >/dev/null 2>&1; then
  claude plugin uninstall tamirs-superpowers@tamirs-marketplace 2>/dev/null \
    && printf 'Uninstalled tamirs-superpowers via claude CLI\n' \
    || printf 'Run inside Claude Code: /plugin uninstall tamirs-superpowers@tamirs-marketplace\n'
else
  printf 'Run inside Claude Code: /plugin uninstall tamirs-superpowers@tamirs-marketplace\n'
fi

printf 'Cursor/Codex: disable the plugin in IDE settings if enabled from this repo path.\n'
