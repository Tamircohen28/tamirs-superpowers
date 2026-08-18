#!/usr/bin/env bash
# PreToolUse guard: block edits to protected/generated files.
# Override for an intentional edit: set PM_ALLOW_PROTECTED=1 in the environment.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hook-output.sh
source "${SCRIPT_DIR}/lib/hook-output.sh"

input="$(hook_read_stdin)"
hook_detect_platform "$input"
file=$(printf '%s' "$input" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input', {}) or {}
    print(ti.get('file_path', '') or ti.get('path', '') or '')
except Exception:
    print('')
" 2>/dev/null)

[ -z "$file" ] && hook_allow
[ "${PM_ALLOW_PROTECTED:-0}" = "1" ] && hook_allow

case "$file" in
  *.lock|*/.yarn/releases/*|*/dist/*|*/build/*|*/src/components/ui/*|*/.github/workflows/*)
    reason="BLOCKED: '$file' is a protected/generated file (lockfile, build output, generated shadcn UI, .yarn binary, or GitHub workflow). Don't hand-edit it — regenerate via the package manager / shadcn CLI, or edit workflows via the GitHub MCP. If this edit is genuinely intended and the user asked for it, set PM_ALLOW_PROTECTED=1 in the environment and retry."
    echo "$reason" >&2
    hook_deny "$reason"
    ;;
esac
hook_allow
