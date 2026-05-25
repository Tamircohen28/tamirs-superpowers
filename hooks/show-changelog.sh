#!/bin/bash

CHANGELOG="$HOME/.claude/cache/changelog.md"
VERSION_FILE="$HOME/.claude/cache/last_changelog_version"
CURRENT_VERSION=$(claude --version 2>/dev/null | awk '{print $1}')

if [ -z "$CURRENT_VERSION" ]; then
  echo '{"suppressOutput":true}'
  exit 0
fi

LAST_VERSION=""
if [ -f "$VERSION_FILE" ]; then
  LAST_VERSION=$(cat "$VERSION_FILE")
fi

if [ "$CURRENT_VERSION" = "$LAST_VERSION" ]; then
  echo '{"suppressOutput":true}'
  exit 0
fi

if [ ! -f "$CHANGELOG" ]; then
  echo '{"suppressOutput":true}'
  exit 0
fi

if [ -n "$LAST_VERSION" ] && grep -q "^## $LAST_VERSION$" "$CHANGELOG"; then
  SECTION=$(sed -n "/^## $CURRENT_VERSION$/,/^## $LAST_VERSION$/p" "$CHANGELOG" | sed '$d')
else
  SECTION=$(sed -n "/^## $CURRENT_VERSION$/,/^## [0-9]/p" "$CHANGELOG" | sed '$d')
fi

if [ -n "$SECTION" ]; then
  VERSION_COUNT=$(echo "$SECTION" | grep -c "^## ")

  if [ "$VERSION_COUNT" -le 1 ]; then
    BULLETS=$(echo "$SECTION" | grep "^- ")
    MSG=$(printf "━━━ Claude Code %s ━━━\n%s\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" "$CURRENT_VERSION" "$BULLETS")
  else
    BODY=$(echo "$SECTION" | awk '/^## /{if(NR>1)print ""; printf "▸ %s\n", $2; next} /^- /{print}')
    MSG=$(printf "━━━ Claude Code updates ━━━\n%s\n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" "$BODY")
  fi

  MSG_ESCAPED=$(echo "$MSG" | jq -Rs .)
  echo "$CURRENT_VERSION" > "$VERSION_FILE"
  echo "{\"suppressOutput\":true,\"systemMessage\":$MSG_ESCAPED}"
else
  echo "$CURRENT_VERSION" > "$VERSION_FILE"
  echo '{"suppressOutput":true}'
fi
