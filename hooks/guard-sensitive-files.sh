#!/usr/bin/env bash
# PreToolUse guard: block edits to protected/generated files.
# Override for an intentional edit: set PM_ALLOW_PROTECTED=1 in the environment.
set -uo pipefail

input=$(cat)
file=$(printf '%s' "$input" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('file_path', '') or '')
except Exception:
    print('')
" 2>/dev/null)

[ -z "$file" ] && exit 0
[ "${PM_ALLOW_PROTECTED:-0}" = "1" ] && exit 0

case "$file" in
  *.lock|*/.yarn/releases/*|*/dist/*|*/build/*|*/src/components/ui/*|*/.github/workflows/*)
    echo "BLOCKED: '$file' is a protected/generated file (lockfile, build output, generated shadcn UI, .yarn binary, or GitHub workflow). Don't hand-edit it — regenerate via the package manager / shadcn CLI, or edit workflows via the GitHub MCP. If this edit is genuinely intended and the user asked for it, set PM_ALLOW_PROTECTED=1 in the environment and retry." >&2
    exit 2
    ;;
esac
exit 0
