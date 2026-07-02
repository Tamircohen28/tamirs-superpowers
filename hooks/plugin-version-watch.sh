#!/usr/bin/env bash
# plugin-version-watch.sh — Stop hook: 24h nudge to run /platform-sync when repo uses any AI target.
set -euo pipefail

CACHE_FILE="${HOME}/.claude/cache/platform-sync-last-check.json"

# Read cwd from hook input (Stop hook provides JSON on stdin)
input="$(cat)"
CWD="$(echo "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
if [ -z "$CWD" ]; then
  CWD="$(pwd)"
fi

# Early exit: only run when repo uses at least one AI coding assistant target
uses_ai_target() {
  local root="$1"
  [[ -f "${root}/.claude-plugin/plugin.json" ]] && return 0
  [[ -f "${root}/.cursor-plugin/plugin.json" ]] && return 0
  [[ -f "${root}/.codex-plugin/plugin.json" ]] && return 0
  [[ -f "${root}/CLAUDE.md" ]] && return 0
  [[ -f "${root}/AGENTS.md" ]] && return 0
  [[ -d "${root}/.cursor/rules" ]] && return 0
  [[ -f "${root}/.cursorrules" ]] && return 0
  [[ -d "${root}/.claude/rules" ]] && return 0
  if [[ -f "${root}/hooks/hooks.json" ]]; then return 0; fi
  return 1
}

if ! uses_ai_target "$CWD"; then
  echo '{"suppressOutput":true}'
  exit 0
fi

# Check cache age
NOW=$(date +%s)
LAST_CHECK=0
HOURS_SINCE=999

if [ -f "$CACHE_FILE" ]; then
  LAST_CHECK=$(jq -r '.ts // 0' "$CACHE_FILE" 2>/dev/null || echo 0)
  if [ "$LAST_CHECK" -gt 0 ]; then
    DIFF=$(( NOW - LAST_CHECK ))
    HOURS_SINCE=$(( DIFF / 3600 ))
  fi
fi

if [ "$HOURS_SINCE" -lt 24 ]; then
  echo '{"suppressOutput":true}'
  exit 0
fi

mkdir -p "$(dirname "$CACHE_FILE")"
printf '{"ts":%d,"cwd":"%s"}\n' "$NOW" "$CWD" > "$CACHE_FILE"

MSG="Platform docs check: it has been ${HOURS_SINCE}h since the last /platform-sync run. Run /platform-sync to compare this repo against the latest Claude Code, Codex, and Cursor docs."
MSG_ESCAPED=$(printf '%s' "$MSG" | jq -Rs .)
printf '{"suppressOutput":true,"systemMessage":%s}\n' "$MSG_ESCAPED"
