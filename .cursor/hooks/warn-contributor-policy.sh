#!/usr/bin/env bash
# Cursor project hook (cloud agents + local Agent): soft-warn on contributor
# policy risks for this plugin repo. Observes only — never blocks.
# Reads JSON on stdin; writes JSON on stdout. See https://cursor.com/docs/hooks
set -euo pipefail

input=$(cat || true)
command=$(printf '%s' "$input" | jq -r '.command // empty' 2>/dev/null || true)

if [ -z "$command" ]; then
  jq -n '{continue: true, permission: "allow"}'
  exit 0
fi

msg=""

if printf '%s' "$command" | grep -qiE 'git[[:space:]]+push[[:space:]]+.*(--force|-f)([[:space:]]|$)|git[[:space:]]+push[[:space:]]+--force-with-lease'; then
  if printf '%s' "$command" | grep -qiE 'master|main'; then
    msg="Do not force-push to master/main in this repo — open a PR instead (AGENTS.md)."
  fi
fi

if [ -z "$msg" ] && printf '%s' "$command" | grep -qiE 'runs-on:[[:space:]]*(\[.*)?self-hosted|runs-on:[[:space:]]*\[self-hosted|self-hosted.*linux|\[self-hosted'; then
  msg="Hard constraint: never add runs-on self-hosted — this public/plugin repo stays on ubuntu-latest."
fi

if [ -z "$msg" ] && printf '%s' "$command" | grep -qiE 'gh[[:space:]]+pr[[:space:]]+merge.*(--admin)?.*master|git[[:space:]]+push[[:space:]]+.*HEAD:master'; then
  msg="Never commit or push directly to master — use a feature branch + PR."
fi

if [ -n "$msg" ]; then
  jq -n --arg m "$msg" '{
    continue: true,
    permission: "ask",
    user_message: $m,
    agent_message: $m
  }'
  exit 0
fi

jq -n '{continue: true, permission: "allow"}'
