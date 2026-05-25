#!/usr/bin/env bash
set -euo pipefail

input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id')
cwd=$(echo "$input" | jq -r '.cwd')

short_id="${session_id:0:8}"
date_stamp=$(date +%Y-%m-%d)
cwd_slug=$(basename "$cwd" | tr -c 'A-Za-z0-9' '-' | sed 's/-\+/-/g; s/^-//; s/-$//')
slug="${date_stamp}_${cwd_slug}_${short_id}"

output_dir="$HOME/.claude/outputs/$slug"
mkdir -p "$output_dir"

cat > "$output_dir/.session.json" <<EOF
{
  "session_id": "$session_id",
  "cwd": "$cwd",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

ln -sfn "$output_dir" "$HOME/.claude/outputs/_latest"

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export CLAUDE_OUTPUT_DIR=\"$output_dir\"" >> "$CLAUDE_ENV_FILE"
  echo "export CLAUDE_SESSION_SLUG=\"$slug\"" >> "$CLAUDE_ENV_FILE"
fi

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "additionalContext": "Session output directory: $output_dir (available as \$CLAUDE_OUTPUT_DIR in Bash). Use this for files that don't belong in the current repo."
  }
}
EOF
