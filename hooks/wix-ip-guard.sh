#!/usr/bin/env bash
# PostToolUse hook — warn if a Wix IP reference is introduced in an edited file.
# Wix IP (internal registries, APIs, credentials) must not appear in personal projects.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hook-output.sh
source "${SCRIPT_DIR}/lib/hook-output.sh"

input="$(hook_read_stdin)"
file="$(echo "$input" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('file_path', '') or '')
except Exception:
    print('')
" 2>/dev/null)"

[ -z "$file" ] && exit 0
[ ! -f "$file" ] && exit 0

if grep -qiE 'registry\.wix|wixapis\.com|wix-sk-|@wix/' "$file" 2>/dev/null; then
  python3 -c "
import json, sys
file = sys.argv[1]
print(json.dumps({
    'hookSpecificOutput': {
        'hookEventName': 'PostToolUse',
        'additionalContext': f'⚠ Wix IP reference detected in {file}. Personal projects must not reference Wix internal registries (registry.wix), APIs (wixapis.com), credentials (wix-sk-*), or scoped packages (@wix/*). Remove before committing.'
    }
}))
" "$file"
fi
exit 0
