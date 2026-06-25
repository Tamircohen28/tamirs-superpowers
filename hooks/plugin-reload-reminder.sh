#!/usr/bin/env bash
# PostToolUse hook — reminds to /reload-plugins after editing plugin files.
set -euo pipefail

input="$(cat)"
file="$(echo "$input" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('file_path', '') or '')
except Exception:
    print('')
" 2>/dev/null)"

[ -z "$file" ] && exit 0

if echo "$file" | grep -qE '(plugin\.json|SKILL\.md|hooks\.json|marketplace\.json|\.claude-plugin/)'; then
  printf '🔄  Plugin file changed: %s. Run /reload-plugins to apply.\n' "$(basename "$file")" >&2
fi
exit 0
