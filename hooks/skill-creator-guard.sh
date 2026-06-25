#!/usr/bin/env bash
# Fire on any Write/Edit targeting a SKILL.md — inject a hard reminder to use /skill-creator.
INPUT=$(cat)
FILE=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    print(d.get('tool_input', {}).get('file_path', ''))
except Exception:
    print('')
" 2>/dev/null)

if [[ "$FILE" == *"/SKILL.md" ]] || [[ "$FILE" == "SKILL.md" ]]; then
  python3 -c "
import json
print(json.dumps({
  'hookSpecificOutput': {
    'hookEventName': 'PreToolUse',
    'additionalContext': (
      'SKILL QUALITY GATE — action required before proceeding:\n'
      'You are about to write/edit a SKILL.md file directly. '
      'This is ONLY acceptable if you are already executing INSIDE the skill-creator skill. '
      'Otherwise you MUST stop and invoke /skill-creator '
      '(Skill tool, skill=\"tamirs-superpowers:skill-creator\") with the skill requirements. '
      'Hand-crafted SKILL.md files miss evals, reference docs, scripts, and the quality bar '
      'that skill-creator enforces. Do not proceed with this Write/Edit — delegate to /skill-creator.'
    )
  },
  'systemMessage': 'SKILL.md gate: use /skill-creator, not direct file writes, for skill creation/edits.'
}))
"
fi
