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
#   - the Pushover Notification hook an older install (< 4.11.0) wrote into
#     settings.json, leaving any other Notification hooks alone; since 4.11.0 the
#     hook lives in the plugin's own hooks.json and needs no unwiring
#
# What it deliberately KEEPS:
#   - ~/.claude/pushover.env, if an install older than 4.11.0 left one. Nothing
#     reads it any more (credentials are plugin options now); delete it by hand.
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

# An install older than 4.11.0 wired the Pushover hook into ~/.claude/settings.json
# (the plugin's own hooks.json carries it now). Strip that one entry, leave every
# other Notification hook alone, and touch nothing when there is none.
SETTINGS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/settings.json"
if [ -f "$SETTINGS" ] && command -v jq >/dev/null 2>&1 \
   && jq -e '[.hooks.Notification // [] | .[] | .hooks // [] | .[] | .command // ""] | any(test("notify-pushover"))' "$SETTINGS" >/dev/null 2>&1; then
  case " $* " in *" --dry-run "*) echo "would remove the legacy Pushover Notification hook from $SETTINGS" ;;
  *)
    tmp="$(mktemp)"
    jq '.hooks.Notification = ((.hooks.Notification // [])
          | map(select([(.hooks // [])[] | .command // "" | test("notify-pushover")] | any | not)))
        | if (.hooks.Notification | length) == 0 then del(.hooks.Notification) else . end
        | if (.hooks | length) == 0 then del(.hooks) else . end' "$SETTINGS" > "$tmp" && mv "$tmp" "$SETTINGS"
    echo "removed the legacy Pushover Notification hook from $SETTINGS"
    ;;
  esac
fi

if command -v claude >/dev/null 2>&1; then
  # claude plugin uninstall --json (Claude Code 2.1.268+) prints one machine-readable
  # result line — {command, outcome, plugin, scope, message, failureCode} — instead
  # of the human message, so a failure ("not found in installed plugins", etc.) can
  # be surfaced specifically rather than only via the generic fallback below.
  # Degrades to that fallback on an older CLI or with neither jq nor python3 present.
  set +e
  uninstall_json="$(claude plugin uninstall tamirs-superpowers@tamirs-marketplace --json 2>/dev/null)"
  uninstall_status=$?
  set -e
  if [[ $uninstall_status -eq 0 ]]; then
    printf 'Uninstalled tamirs-superpowers via claude CLI\n'
  else
    detail=""
    if command -v jq >/dev/null 2>&1; then
      detail="$(printf '%s' "$uninstall_json" | jq -r 'if .message then (.message + (if .failureCode then " (" + .failureCode + ")" else "" end)) else empty end' 2>/dev/null || true)"
    elif command -v python3 >/dev/null 2>&1; then
      detail="$(printf '%s' "$uninstall_json" | python3 -c '
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
    printf 'Run inside Claude Code: /plugin uninstall tamirs-superpowers@tamirs-marketplace\n'
  fi
else
  printf 'Run inside Claude Code: /plugin uninstall tamirs-superpowers@tamirs-marketplace\n'
fi

printf 'Cursor/Codex: disable the plugin in IDE settings if enabled from this repo path.\n'
