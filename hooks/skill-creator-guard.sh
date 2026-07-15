#!/usr/bin/env bash
# Fire on any Write/Edit targeting a SKILL.md — inject a hard reminder to use /skill-creator.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hook-output.sh
source "${SCRIPT_DIR}/lib/hook-output.sh"

INPUT=$(cat)
hook_detect_platform "$INPUT"
FILE=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input', {}) or {}
    print(ti.get('file_path', '') or ti.get('path', '') or '')
except Exception:
    print('')
" 2>/dev/null)

if [[ "$FILE" == *"/SKILL.md" ]] || [[ "$FILE" == "SKILL.md" ]]; then
  hook_additional_context "$(cat <<'EOF'
SKILL QUALITY GATE — action required before proceeding:
You are about to write/edit a SKILL.md file directly. This is ONLY acceptable if you are already executing INSIDE the skill-creator skill. Otherwise you MUST stop and invoke /skill-creator (Skill tool, skill="tamirs-superpowers:skill-creator") with the skill requirements. Hand-crafted SKILL.md files miss evals, reference docs, scripts, and the quality bar that skill-creator enforces. Do not proceed with this Write/Edit — delegate to /skill-creator.
EOF
)"
fi

hook_allow
