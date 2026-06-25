#!/usr/bin/env bash
# UserPromptSubmit hook — reminds to run /compact before /goal or /login.
# These commands reset context and destroy cache warmth; compacting first is cheaper.
set -euo pipefail

input="$(cat)"
prompt="$(echo "$input" | jq -r '.prompt // empty')"

if echo "$prompt" | grep -qE '^\s*/(goal|login)\b'; then
  cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "⚠ Cache warmth reminder: the user is about to reset context with /goal or /login. Remind them to run /compact FIRST if they want to preserve cache warmth and avoid a costly cache break — unless they explicitly want a fresh start."
  }
}
EOF
fi
