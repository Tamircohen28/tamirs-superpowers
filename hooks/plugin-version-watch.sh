#!/bin/bash
# Stop hook — lightweight 24h cache check for plugin repos.
# If this repo has at least one platform plugin manifest AND 24h have elapsed
# since the last check, emits a systemMessage nudging the user to run /platform-sync.
# No web fetches here — those stay inside the platform-sync skill.

set -euo pipefail

CACHE_FILE="${HOME}/.claude/cache/platform-sync-last-check.json"
PLUGIN_MARKERS=(".claude-plugin" ".codex-plugin" ".cursor-plugin")

# Read cwd from hook input (Stop hook provides JSON on stdin)
input="$(cat)"
CWD="$(echo "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
if [ -z "$CWD" ]; then
  CWD="$(pwd)"
fi

# Early exit: only run in repos with at least one plugin manifest
IS_PLUGIN_REPO=false
for marker in "${PLUGIN_MARKERS[@]}"; do
  if [ -d "${CWD}/${marker}" ]; then
    IS_PLUGIN_REPO=true
    break
  fi
done

if [ "$IS_PLUGIN_REPO" = "false" ]; then
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

# Exit silently if cache is still fresh (< 24h)
if [ "$HOURS_SINCE" -lt 24 ]; then
  echo '{"suppressOutput":true}'
  exit 0
fi

# Cache is stale — update it and emit a nudge for the next turn
mkdir -p "$(dirname "$CACHE_FILE")"
printf '{"ts":%d,"cwd":"%s"}\n' "$NOW" "$CWD" > "$CACHE_FILE"

MSG="Platform docs check: it has been ${HOURS_SINCE}h since the last /platform-sync run in this plugin repo. Run /platform-sync to verify your plugin configs against the latest Claude Code, Codex, and Cursor docs."
MSG_ESCAPED=$(printf '%s' "$MSG" | jq -Rs .)
printf '{"suppressOutput":true,"systemMessage":%s}\n' "$MSG_ESCAPED"
