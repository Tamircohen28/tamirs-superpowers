#!/usr/bin/env bash
# UserPromptSubmit hook — nudges decomposition when a prompt is a sweeping mandate.
# Sweeping "do everything at once" prompts are the top cause of context/token-limit
# failures (output-token max, "prompt too long"). Advisory only — never blocks.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hook-output.sh
source "${SCRIPT_DIR}/lib/hook-output.sh"

input="$(hook_read_stdin)"
prompt="$(echo "$input" | jq -r '.prompt // empty')"

if echo "$prompt" | grep -qiE 'complete everything|transform .* (into|to)|all open .*(pr|pull request)|portfolio-grade|merge all|do everything|entire (repo|codebase|roadmap)'; then
  cat <<'EOF'
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "additionalContext": "⚠ Large-scope mandate detected. To avoid context/token-limit failures: decompose into bounded sub-tasks, write large outputs incrementally to separate files (outline first, then <400-line sections), and delegate heavy reads to scoped sub-agents rather than reading whole repos in the main thread."
  }
}
EOF
fi
