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

# The payload's `.cwd` is the SESSION's directory, not the command's. An agent
# working in a worktree writes `cd <worktree> && git push`, and resolving the
# remote from the session directory then attributes the push to a different
# repository entirely: every pm-marketing-site branch was claimed against
# ProductionMasterAI/dev, blocking the repo nobody was editing while protecting
# nothing in the one they were. Honour a leading `cd` before resolving anything
# from CWD. (`git -C` is handled per-invocation inside repo_slug.)
effective_cwd() {
  local seg dir
  local -a ctoks=()
  while IFS= read -r seg; do
    [ -n "$seg" ] || continue
    IFS="$_CLAIM_TOKSEP" read -ra ctoks <<< "$seg"
    [ "${#ctoks[@]}" -ge 2 ] || continue
    dir=""
    if [ "${ctoks[0]}" = "cd" ]; then
      dir="${ctoks[1]}"
    elif [ "${ctoks[0]##*/}" = "git" ]; then
      # `git -C <dir>` relocates the invocation as surely as a cd does, and
      # detect_git_push resolves the slug without access to the segment tokens.
      local gi=1
      while [ "$gi" -lt "${#ctoks[@]}" ]; do
        if [ "${ctoks[$gi]}" = "-C" ] && [ $((gi + 1)) -lt "${#ctoks[@]}" ]; then
          dir="${ctoks[$((gi + 1))]}"; break
        fi
        gi=$((gi + 1))
      done
    fi
    [ -n "$dir" ] || continue
    case "$dir" in
      -|--) continue ;;
      "~") dir="$HOME" ;;
      "~/"*) dir="$HOME/${dir#\~/}" ;;
    esac
    case "$dir" in /*) : ;; *) dir="$CWD/$dir" ;; esac
    [ -d "$dir" ] || continue
    printf '%s' "$dir"
    return 0
  done <<< "$(claim_effective_segments "$COMMAND")"
  return 1
}
_eff=$(effective_cwd) && [ -n "$_eff" ] && CWD="$_eff"

ME="$(claim_agent_id "$SESSION")"

# ---------------------------------------------------------------- helpers ---

deny_cannot_run() {
  hook_deny "CONCURRENCY GUARD CANNOT RUN: $1
The guard refuses to report 'free' when it could not check. Resolve the cause, or set AGENT_CLAIM_DIR to a usable location."
}

# repo_slug [tokens...] — owner/name for the invocation being examined.
# An explicit --repo/-R among the given tokens wins; otherwise the git remote of
# CWD. Only the tokens of the segment actually being guarded are consulted — a
# `--repo` sitting in some other segment (or inside a quoted message) names a
# different command's target.
repo_slug() {
  local slug="" url dir="$CWD"
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --repo=*|-R=*) slug="${1#*=}" ;;
      --repo|-R) [ "$#" -ge 2 ] && slug="$2" ;;
      # `git -C <dir>` moves the invocation, so it moves the repo it targets.
      -C) [ "$#" -ge 2 ] && [ -d "$2" ] && dir="$2" ;;
    esac
    shift
  done
  if [ -n "$slug" ]; then
    printf '%s' "$slug" | sed -E 's#^https?://[^/]+/##; s#\.git$##'
    return 0
  fi
  url=$(git -C "$dir" remote get-url origin 2>/dev/null) || return 1
  [ -n "$url" ] || return 1
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
#
# Detection is STRUCTURE-aware, never substring-aware. The command string is
# tokenized by claim_effective_segments (hooks/lib/agent-claim.sh), so a
# `git push` or `gh issue comment` appearing inside a quoted argument, a `-m`
# message or a heredoc body is what it actually is — text — and only the first
# word of a real segment can name a guarded command. Matching the raw string
# instead reads phantom targets out of ordinary commit messages (and, having no
# idea where a command starts, mis-attributes real ones just as easily).

GH_PR_VERBS='close|merge|edit|reopen|ready|comment|review|lock|unlock|update-branch'
GH_ISSUE_VERBS='close|edit|reopen|comment|delete|lock|unlock|pin|unpin|transfer'

# The detect_* helpers below read the current segment from the caller's `toks`
# and `ntoks` (bash is dynamically scoped); detect_targets is their only caller.

# first_number_arg <from-index> — the first bare integer argument of the
# segment. gh takes the PR/issue number positionally, but flags may precede it
# (`gh pr comment --repo o/r 123`), so position alone cannot find it.
first_number_arg() {
  local i="$1"
  while [ "$i" -lt "$ntoks" ]; do
    case "${toks[$i]}" in
      [0-9]*) case "${toks[$i]}" in *[!0-9]*) : ;; *) printf '%s' "${toks[$i]}"; return 0 ;; esac ;;
    esac
    i=$((i + 1))
  done
  return 1
}

detect_gh_numbered() {
  local kind="$1" verbs="$2" verb num slug
  verb="${toks[2]:-}"
  [ -n "$verb" ] || return 0
  case "|${verbs}|" in
    *"|${verb}|"*) : ;;
    *) return 0 ;;
  esac

  slug=$(repo_slug "${toks[@]}") || slug=""
  if [ -z "$slug" ]; then
    deny_cannot_run "'gh ${kind} ${verb}' targets a repository that could not be identified (no --repo flag and no git remote in '$CWD'), so the guard cannot tell which artifact is being touched."
  fi

  num=$(first_number_arg 3) || num=""
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
  local i=2 t nxt mutating=0 path="" hit slug kind num
  while [ "$i" -lt "$ntoks" ]; do
    t="${toks[$i]}"
    case "$t" in
      # Mutating only: an explicit method, or field flags (which make gh POST).
      -X|--method)
        nxt="${toks[$((i + 1))]:-}"
        case "$nxt" in PATCH|POST|PUT|DELETE) mutating=1 ;; esac ;;
      -X=*|--method=*)
        case "${t#*=}" in PATCH|POST|PUT|DELETE) mutating=1 ;; esac ;;
      -f|-F|--field|--raw-field|-f=*|-F=*|--field=*|--raw-field=*) mutating=1 ;;
      *)
        hit=$(printf '%s' "$t" | grep -oE 'repos/[^/]+/[^/]+/(pulls|issues)/[0-9]+' | head -1)
        [ -n "$hit" ] && path="$hit" ;;
    esac
    i=$((i + 1))
  done
  [ "$mutating" -eq 1 ] || return 0
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

# git push is parsed whole-command (one invocation can name many destinations,
# and several segments can each push), so it is detected outside the per-segment
# loop — claim_push_destinations does its own segment-aware anchoring.
detect_git_push() {
  local slug parsed rc kind value
  parsed=$(claim_push_destinations "$COMMAND" "$(push_fallback_branch)")
  rc=$?
  [ "$rc" -eq 2 ] && return 0

  slug=$(repo_slug) || slug=""
  # A push outside a git repository has no artifact to protect; git will fail
  # on its own. Only guard when there IS a repository.
  [ -n "$slug" ] || return 0

  if [ "$rc" -ne 0 ]; then
    value="$(printf '%s' "$parsed" | head -1 | cut -f2)"
    deny_cannot_run "'git push' in '$CWD': ${value:-the destination branch could not be determined}. The guard will not fall back to a default branch — that would answer a question about a branch the command never named."
  fi

  # Every destination is claim-checked, not just the first: one `git push` can
  # write several branches, and a collision on any of them is a collision.
  while IFS=$'\t' read -r kind value; do
    [ "$kind" = "DEST" ] || continue
    add_target "git:${slug}@${value}" "branch '${value}' in ${slug}"
  done <<< "$parsed"
}

detect_targets() {
  local seg base
  local -a toks=()
  local ntoks
  while IFS= read -r seg; do
    [ -n "$seg" ] || continue
    IFS="$_CLAIM_TOKSEP" read -ra toks <<< "$seg"
    ntoks=${#toks[@]}
    [ "$ntoks" -gt 0 ] || continue
    base="${toks[0]##*/}"
    [ "$base" = "gh" ] || continue
    case "${toks[1]:-}" in
      pr)    detect_gh_numbered "pr" "$GH_PR_VERBS" ;;
      issue) detect_gh_numbered "issue" "$GH_ISSUE_VERBS" ;;
      api)   detect_gh_api ;;
    esac
  done <<< "$(claim_effective_segments "$COMMAND")"
}

detect_targets
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
