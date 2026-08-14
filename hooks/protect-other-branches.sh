#!/usr/bin/env bash
# PreToolUse (Bash|Shell) — concurrency guard for shared work artifacts.
#
# WHAT THIS GUARDS
#   Mutating operations on a GitHub PR, a GitHub issue, or a repo branch are
#   only allowed when no OTHER agent is *currently* working on that same
#   artifact. "Currently" is established by a live claim under the shared,
#   tool-neutral claim directory (see lib/agent-claim.sh) — Claude Code, Cursor
#   and Codex all read and write the same files, so they can see each other.
#
# WHAT IT DELIBERATELY NO LONGER GUARDS
#   Authorship. The previous version of this hook blocked `gh pr close` whenever
#   the PR's author differed from the current GitHub login. That is a proxy
#   question: authorship is permanent and immutable, so the guard could never
#   release — an artifact created by another agent or a bot (e.g. app/cursor)
#   stayed blocked forever even when nothing was working on it. Concurrency is
#   the real question, and it is transient. Authorship checks are removed.
#
# FAILURE POSTURE
#   If the guard cannot determine the answer — no jq, unusable claim directory,
#   corrupt claim file, an unidentifiable target artifact — it DENIES with an
#   explicit reason. It never returns a value that is indistinguishable from
#   "nobody is working on it".

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hook-output.sh
source "${SCRIPT_DIR}/lib/hook-output.sh"
# shellcheck source=lib/agent-claim.sh
source "${SCRIPT_DIR}/lib/agent-claim.sh"

INPUT=$(cat)
hook_detect_platform "$INPUT"

# jq is required by hook-output.sh itself, but check explicitly so the failure
# is a spoken denial rather than a malformed hook response.
if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"CONCURRENCY GUARD CANNOT RUN: jq is not installed, so agent work-claims cannot be evaluated. Refusing to assume the artifact is free."}}'
  exit 0
fi

COMMAND=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // ""')
CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // (.workspace_roots[0]? // "") // ""')
SESSION=$(printf '%s' "$INPUT" | jq -r '.session_id // .conversation_id // ""')
[ -n "$CWD" ] && [ -d "$CWD" ] || CWD="$PWD"

ME="$(claim_agent_id "$SESSION")"

# ---------------------------------------------------------------- helpers ---

deny_cannot_run() {
  hook_deny "CONCURRENCY GUARD CANNOT RUN: $1
The guard refuses to report 'free' when it could not check. Resolve the cause, or set AGENT_CLAIM_DIR to a usable location."
}

# repo_slug — owner/name for the command, from --repo/-R or the git remote.
repo_slug() {
  local slug
  slug=$(printf '%s' "$COMMAND" | grep -oE -- '(--repo|-R)[= ]+[^ ]+' | head -1 | sed -E 's/^(--repo|-R)[= ]+//' | tr -d '"'"'"'')
  if [ -n "$slug" ]; then
    printf '%s' "$slug" | sed -E 's#^https?://[^/]+/##; s#\.git$##'
    return 0
  fi
  local url
  url=$(git -C "$CWD" remote get-url origin 2>/dev/null) || return 1
  printf '%s' "$url" | sed -E 's#^git@[^:]+:##; s#^https?://[^/]+/##; s#\.git$##'
}

current_branch() {
  git -C "$CWD" rev-parse --abbrev-ref HEAD 2>/dev/null
}

# Newline-separated list of "resource<TAB>description" this command touches.
TARGETS=""
add_target() { TARGETS="${TARGETS}${1}	${2}
"; }

# ------------------------------------------------------- target detection ---

GH_PR_VERBS='close|merge|edit|reopen|ready|comment|review|lock|unlock|update-branch'
GH_ISSUE_VERBS='close|edit|reopen|comment|delete|lock|unlock|pin|unpin|transfer'

detect_gh_numbered() {
  local kind="$1" verbs="$2" verb num slug
  printf '%s' "$COMMAND" | grep -qE "(^|[;&|[:space:]])gh[[:space:]]+${kind}[[:space:]]+(${verbs})([[:space:]]|$)" || return 0

  verb=$(printf '%s' "$COMMAND" | grep -oE "gh[[:space:]]+${kind}[[:space:]]+(${verbs})" | head -1 | awk '{print $3}')
  num=$(printf '%s' "$COMMAND" | grep -oE "gh[[:space:]]+${kind}[[:space:]]+(${verbs})[[:space:]]+[0-9]+" | head -1 | grep -oE '[0-9]+$')

  slug=$(repo_slug) || slug=""
  if [ -z "$slug" ]; then
    deny_cannot_run "'gh ${kind} ${verb}' targets a repository that could not be identified (no --repo flag and no git remote in '$CWD'), so the guard cannot tell which artifact is being touched."
  fi

  if [ -z "$num" ]; then
    # No explicit number: gh resolves it from the current branch. Do the same,
    # so the claim key matches what other agents would compute.
    if [ "$kind" = "pr" ]; then
      num=$(gh pr view --repo "$slug" --json number --jq '.number' 2>/dev/null)
    fi
    if [ -z "$num" ]; then
      deny_cannot_run "'gh ${kind} ${verb}' has no determinable ${kind} number (and it could not be resolved from the current branch), so the guard cannot identify the artifact being modified."
    fi
  fi

  add_target "github:${slug}#${kind}-${num}" "${kind} #${num} in ${slug}"
}

detect_gh_api() {
  local path slug kind num
  printf '%s' "$COMMAND" | grep -qE '(^|[;&|[:space:]])gh[[:space:]]+api' || return 0
  # Mutating only: explicit method, or field flags (which make gh default to POST).
  printf '%s' "$COMMAND" | grep -qE -- '(-X|--method)[= ]+(PATCH|POST|PUT|DELETE)|(-f|-F|--field|--raw-field)[= ]' || return 0

  path=$(printf '%s' "$COMMAND" | grep -oE 'repos/[^/ "'"'"']+/[^/ "'"'"']+/(pulls|issues)/[0-9]+' | head -1)
  [ -n "$path" ] || return 0

  slug=$(printf '%s' "$path" | sed -E 's#^repos/([^/]+/[^/]+)/.*#\1#')
  kind=$(printf '%s' "$path" | sed -E 's#.*/(pulls|issues)/[0-9]+$#\1#')
  num=$(printf '%s' "$path" | grep -oE '[0-9]+$')
  [ "$kind" = "pulls" ] && kind="pr" || kind="issue"

  add_target "github:${slug}#${kind}-${num}" "${kind} #${num} in ${slug} (via gh api)"
}

# push_fallback_branch — what git itself would push to when no refspec is given:
# the current branch's upstream, else the current branch. Empty when neither is
# resolvable — the caller then fails loud rather than guessing a default branch.
push_fallback_branch() {
  local up b
  up=$(git -C "$CWD" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)
  if [ -n "$up" ] && [ "$up" != "@{upstream}" ]; then
    printf '%s' "${up#*/}"
    return 0
  fi
  b=$(current_branch)
  if [ -n "$b" ] && [ "$b" != "HEAD" ]; then printf '%s' "$b"; fi
}

detect_git_push() {
  local slug parsed rc kind value
  printf '%s' "$COMMAND" | grep -qE '(^|[;&|[:space:]])git[[:space:]]+([^ ]+[[:space:]]+)*push([[:space:]]|$)' || return 0

  slug=$(repo_slug) || slug=""
  # A push outside a git repository has no artifact to protect; git will fail
  # on its own. Only guard when there IS a repository.
  [ -n "$slug" ] || return 0

  # Every destination is claim-checked, not just the first: one `git push` can
  # write several branches, and a collision on any of them is a collision.
  parsed=$(claim_push_destinations "$COMMAND" "$(push_fallback_branch)")
  rc=$?
  [ "$rc" -eq 2 ] && return 0
  if [ "$rc" -ne 0 ]; then
    value="$(printf '%s' "$parsed" | head -1 | cut -f2)"
    deny_cannot_run "'git push' in '$CWD': ${value:-the destination branch could not be determined}. The guard will not fall back to a default branch — that would answer a question about a branch the command never named."
  fi

  while IFS=$'\t' read -r kind value; do
    [ "$kind" = "DEST" ] || continue
    add_target "git:${slug}@${value}" "branch '${value}' in ${slug}"
  done <<< "$parsed"
}

detect_gh_numbered "pr" "$GH_PR_VERBS"
detect_gh_numbered "issue" "$GH_ISSUE_VERBS"
detect_gh_api
detect_git_push

# Nothing this guard is responsible for.
[ -n "$TARGETS" ] || hook_allow

# ------------------------------------------------------------ evaluation ---

claim_require_deps || deny_cannot_run "$CLAIM_ERROR"
claim_ensure_dir   || deny_cannot_run "$CLAIM_ERROR"

OLD_IFS="$IFS"
IFS='
'
for line in $TARGETS; do
  [ -n "$line" ] || continue
  RESOURCE="${line%%	*}"
  DESC="${line#*	}"

  RESULT="$(claim_inspect "$RESOURCE" "$ME")"
  RC=$?
  STATUS="$(printf '%s' "$RESULT" | cut -f1)"
  HOLDER="$(printf '%s' "$RESULT" | cut -f2)"
  TOOL="$(printf '%s' "$RESULT" | cut -f3)"
  AGE="$(printf '%s' "$RESULT" | cut -f4)"
  DETAIL="$(printf '%s' "$RESULT" | cut -f5)"

  # claim_inspect runs in a command substitution, so CLAIM_ERROR cannot
  # propagate out of it — the reason is carried in the DETAIL field instead.
  if [ "$RC" -ne 0 ] || [ "$STATUS" = "ERROR" ]; then
    IFS="$OLD_IFS"
    deny_cannot_run "${DETAIL:-claim state for $RESOURCE could not be evaluated}"
  fi

  if [ "$STATUS" = "LIVE" ]; then
    IFS="$OLD_IFS"
    hook_deny "BLOCKED — another agent is actively working on ${DESC}.
  resource : ${RESOURCE}
  held by  : ${HOLDER} (tool: ${TOOL})
  liveness : ${DETAIL}
This is a live claim, not an authorship check: it expires ${AGENT_CLAIM_STALE_SECONDS}s after the holder's last touch, or immediately if the holder's process dies on this host. Coordinate with that agent, or wait for the claim to go stale.
Claim file: $(claim_path "$RESOURCE")"
  fi
done
IFS="$OLD_IFS"

# Free / stale / already-mine: take (or refresh) the claim, then allow.
IFS='
'
for line in $TARGETS; do
  [ -n "$line" ] || continue
  RESOURCE="${line%%	*}"
  DESC="${line#*	}"
  if ! claim_write "$RESOURCE" "$ME" "$DESC"; then
    IFS="$OLD_IFS"
    deny_cannot_run "$CLAIM_ERROR"
  fi
done
IFS="$OLD_IFS"

hook_allow
