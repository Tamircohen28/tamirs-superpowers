#!/bin/bash
# PostToolUse hook: validates URLs in report.md files after Write operations.
# Returns feedback to Claude if broken link patterns are detected.


SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hook-output.sh
source "${SCRIPT_DIR}/lib/hook-output.sh"
INPUT="$(hook_read_stdin)"
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only check report.md files
if [[ "$FILE_PATH" != *"report.md" ]]; then
  exit 0
fi

if [ ! -f "$FILE_PATH" ]; then
  exit 0
fi

ISSUES=""
ISSUE_COUNT=0

URLS=$(grep -oE 'https?://[^ )">]+' "$FILE_PATH" 2>/dev/null)

if [ -z "$URLS" ]; then
  exit 0
fi

while IFS= read -r url; do
  [ -z "$url" ] && continue

  if echo "$url" | grep -q "grafana\|app-analytics"; then
    if ! echo "$url" | grep -qE '(from=|to=|fromTime=|toTime=|orgId=)'; then
      ISSUES="${ISSUES}\n- Grafana URL missing time range parameters: ${url:0:120}..."
      ISSUE_COUNT=$((ISSUE_COUNT + 1))
    fi
    if ! echo "$url" | grep -qE '(artifact|service|datasource|query|panelId)'; then
      ISSUES="${ISSUES}\n- Grafana URL missing artifact/service identifier: ${url:0:120}..."
      ISSUE_COUNT=$((ISSUE_COUNT + 1))
    fi
  fi

  if echo "$url" | grep -q "github.com"; then
    if echo "$url" | grep -q "/pull" && ! echo "$url" | grep -qE '/pull/[0-9]+'; then
      ISSUES="${ISSUES}\n- GitHub PR URL malformed (missing PR number): ${url:0:120}"
      ISSUE_COUNT=$((ISSUE_COUNT + 1))
    fi
    if echo "$url" | grep -q "/blob/" && ! echo "$url" | grep -qE '/blob/[a-zA-Z0-9]+/'; then
      ISSUES="${ISSUES}\n- GitHub file URL malformed (missing branch/commit): ${url:0:120}"
      ISSUE_COUNT=$((ISSUE_COUNT + 1))
    fi
  fi

  if echo "$url" | grep -q "slack.com"; then
    if echo "$url" | grep -q "/archives/" && ! echo "$url" | grep -qE '/archives/C[A-Z0-9]+'; then
      ISSUES="${ISSUES}\n- Slack archive URL has invalid channel ID: ${url:0:120}"
      ISSUE_COUNT=$((ISSUE_COUNT + 1))
    fi
  fi

  if echo "$url" | grep -qiE '(example\.com|placeholder|TODO|FIXME|xxx|your-|INSERT)'; then
    ISSUES="${ISSUES}\n- Placeholder/template URL detected: ${url:0:120}"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
  fi

  if echo "$url" | grep -qE '\.\.\.$'; then
    ISSUES="${ISSUES}\n- Truncated URL detected: ${url:0:120}"
    ISSUE_COUNT=$((ISSUE_COUNT + 1))
  fi

done <<< "$URLS"

if [ "$ISSUE_COUNT" -gt 0 ]; then
  jq -n \
    --arg reason "Link validation found $ISSUE_COUNT issue(s) in $FILE_PATH:$(echo -e "$ISSUES")" \
    --arg context "Fix these links before publishing. For Grafana URLs: ensure time range params and artifact_id are present. For GitHub PRs: ensure /pull/<number> format. For Slack: verify channel IDs. Remove any placeholder or truncated URLs." \
    '{
      "decision": "block",
      "reason": $reason,
      "hookSpecificOutput": {
        "hookEventName": "PostToolUse",
        "additionalContext": $context
      }
    }'
  exit 0
fi

exit 0
