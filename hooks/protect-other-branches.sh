#!/bin/bash
# PreToolUse (Bash) — block closing PRs that belong to other authors.
#
# Prevents Claude from accidentally closing PRs opened by someone else.
# Set GITHUB_OWNER_LOGIN in your environment or ~/.claude/settings.json
# to your GitHub handle. Falls back to `gh api user` if not set.

INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // ""')

block() {
  echo "{\"hookSpecificOutput\": {\"hookEventName\": \"PreToolUse\", \"permissionDecision\": \"deny\", \"permissionDecisionReason\": \"$1\"}}"
  exit 0
}

# Resolve the owner's GitHub login
GITHUB_LOGIN="${GITHUB_OWNER_LOGIN:-}"
if [ -z "$GITHUB_LOGIN" ]; then
  GITHUB_LOGIN=$(gh api user --jq '.login' 2>/dev/null || true)
fi
if [ -z "$GITHUB_LOGIN" ]; then
  exit 0  # Cannot verify — allow and let gh handle it
fi

# Block gh pr close — check PR author before allowing
if echo "$COMMAND" | grep -qE '^\s*gh pr close'; then
  PR_NUM=$(echo "$COMMAND" | grep -oE 'gh pr close [0-9]+' | grep -oE '[0-9]+$')
  REPO_FLAG=$(echo "$COMMAND" | grep -oE -- '--repo [^ ]+' | head -1)

  if [ -n "$PR_NUM" ]; then
    AUTHOR=$(gh pr view "$PR_NUM" $REPO_FLAG --json author --jq '.author.login' 2>/dev/null)
    if [ -z "$AUTHOR" ]; then
      block "HARD BLOCK: Cannot verify author of PR #$PR_NUM before closing. Check manually."
    fi
    if [ "$AUTHOR" != "$GITHUB_LOGIN" ]; then
      block "HARD BLOCK: PR #$PR_NUM belongs to $AUTHOR (not $GITHUB_LOGIN). Closing other people's PRs is blocked."
    fi
  else
    block "HARD BLOCK: 'gh pr close' without a determinable PR number — cannot verify ownership. Blocked."
  fi
fi

# Block gh api PATCH/POST to close PRs belonging to others
if echo "$COMMAND" | grep -qE 'gh api.*(PATCH|POST).*pulls/[0-9]+' && echo "$COMMAND" | grep -q '"closed"'; then
  PR_NUM=$(echo "$COMMAND" | grep -oE 'pulls/[0-9]+' | grep -oE '[0-9]+$' | head -1)
  REPO=$(echo "$COMMAND" | grep -oE 'repos/[^/]+/[^/]+' | head -1 | sed 's|repos/||')
  if [ -n "$PR_NUM" ] && [ -n "$REPO" ]; then
    AUTHOR=$(gh api "repos/$REPO/pulls/$PR_NUM" --jq '.user.login' 2>/dev/null)
    if [ -n "$AUTHOR" ] && [ "$AUTHOR" != "$GITHUB_LOGIN" ]; then
      block "HARD BLOCK: PR #$PR_NUM belongs to $AUTHOR (not $GITHUB_LOGIN). Closing via API blocked."
    fi
  fi
fi

exit 0
