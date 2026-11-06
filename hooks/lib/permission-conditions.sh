#!/usr/bin/env bash
# permission-conditions.sh — the GitHub-backed conditions of the permission guard
# (ADR 004 D1, D4, D8), each behind a hard deadline.
#
# WHAT IT ANSWERS
#   default-branch <dir> <remote>
#       The default branch of <remote>: refs/remotes/<remote>/HEAD when it
#       resolves, else GitHub's answer for the repository the remote's push URL
#       names (`gh repo view HOST/OWNER/REPO --json defaultBranchRef`; the push
#       URL is read with `git remote get-url --push`, so insteadOf rewrites are
#       the ones git itself would push to). Prints the branch name, or nothing.
#   required-checks <dir> <pr|-> <owner/repo|->
#       Whether a required status check on the PR is failing or pending (D1
#       `pr.merge.admin`, safety invariant 2), from `gh pr checks --required` run
#       in <dir> on the same selector (`-` = the current branch's PR) and -R repo
#       the merge names. Prints one line:
#         true <counts>     at least one required check fails, is cancelled or pending
#         false <counts>    every reported required check passes (or was skipped)
#         unknown <why>     anything else: no required check reported, no PR, no
#                           access, no gh, a timeout, output PG cannot read
#       Counts only: check names are text a PR author controls.
#
# DEADLINE
#   --deadline <seconds> (0.1-3, default 3) bounds the lookup: coreutils
#   `timeout`/`gtimeout` when installed, else a background job and a watchdog
#   that kills it (macOS ships no timeout). The caller (hooks/permission-guard.sh)
#   spends ONE 3 s budget over every lookup of a call and kills this script's
#   process group if it overruns. An error or a timeout never answers true or
#   false: PG reads unknown, and unknown never holds (D4; SR S-12), so the raise
#   or deny applies exactly as with no lookup at all.
#
# WHY UNKNOWN WHEN NO REQUIRED CHECK IS REPORTED
#   GitHub reports a required check only once it has started. "No required check
#   reported" therefore cannot tell a repository with none from a check that has
#   not started yet, which is pending; it stays unknown and --admin stays denied.
#
# One file, two roles: sourced, it defines the pc_* functions; executed, it runs
# one subcommand and exits 0 (2 on a usage error). gh never prompts (stdin is
# /dev/null, GH_PROMPT_DISABLED) and never pages. Bash 3.2 compatible; needs git,
# gh and jq, and each one missing is an unknown, never a pass.

PC_SAFE_REF='^[A-Za-z0-9._/@+-]+$'

# HOW A LINE IS PRINTED (the plugin directory's hook-permission rule): with echo, never a printf
# format, and stderr is never merged into stdout. Every echo below prints a value that cannot be
# one of echo's own options (it starts with a fixed word, holds a slash, or was checked not to
# start with -) and holds no backslash; pc_line is for the one value that is not so constrained.

# pc_line <text> — <text> and a newline, byte for byte: a here-string where echo would read the
# text as its option (-n, -e, -E and their clusters), echo otherwise.
pc_line() {
  case "$1" in
    -*) cat <<<"$1" ;;
    *) echo "$1" ;;
  esac
}

# pc_with_deadline <seconds> <command...> — run it, killed after <seconds>.
# Returns its exit status, or 124/143 when the deadline killed it.
pc_with_deadline() {
  local secs="$1" pid wd rc mon
  shift
  if command -v timeout >/dev/null 2>/dev/null; then
    timeout -k 1 "$secs" "$@"
    return $?
  fi
  if command -v gtimeout >/dev/null 2>/dev/null; then
    gtimeout -k 1 "$secs" "$@"
    return $?
  fi
  # Job control puts the command in a process group of its own, so the watchdog
  # kills it with its children: a child left holding stdout would keep a $(...)
  # caller waiting past the deadline. The watchdog's own output goes nowhere.
  case "$-" in *m*) mon=1 ;; *) mon=0 ;; esac
  set -m
  "$@" &
  pid=$!
  [ "$mon" = 1 ] || set +m
  ( sleep "$secs"; kill -TERM -- "-$pid" 2>/dev/null; sleep 1; kill -KILL -- "-$pid" 2>/dev/null ) </dev/null >/dev/null 2>/dev/null &
  wd=$!
  wait "$pid"
  rc=$?
  kill "$wd" 2>/dev/null
  wait "$wd" 2>/dev/null
  return "$rc"
}

# pc_gh <seconds> <dir> <args...> — gh in <dir>, non-interactive, under the deadline.
pc_gh() {
  local secs="$1" dir="$2"
  shift 2
  command -v gh >/dev/null 2>/dev/null || return 127
  ( CDPATH='' cd -- "$dir" 2>/dev/null || exit 1
    pc_with_deadline "$secs" env GH_PROMPT_DISABLED=1 GH_NO_UPDATE_NOTIFIER=1 GH_SPINNER_DISABLED=1 \
      GH_PAGER=cat PAGER=cat NO_COLOR=1 CLICOLOR=0 GIT_TERMINAL_PROMPT=0 gh "$@" </dev/null 2>/dev/null )
}

# pc_git <dir> <args...> — a local git read (no network, no optional locks).
pc_git() {
  local dir="$1"
  shift
  GIT_OPTIONAL_LOCKS=0 GIT_TERMINAL_PROMPT=0 LC_ALL=C git -C "$dir" "$@" 2>/dev/null
}

# pc_url_slug <url> — HOST/OWNER/REPO for an https, ssh or scp-form remote URL; 1 if it is none of them.
pc_url_slug() {
  local u="$1" host owner repo
  local re_url='^(https|http|ssh|git)://([^@/]+@)?([A-Za-z0-9.-]+)/([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+)/?$'
  local re_scp='^([A-Za-z0-9._-]+@)?([A-Za-z0-9.-]+):([A-Za-z0-9._-]+)/([A-Za-z0-9._-]+)/?$'
  if [[ "$u" =~ $re_url ]]; then
    host="${BASH_REMATCH[3]}" owner="${BASH_REMATCH[4]}" repo="${BASH_REMATCH[5]}"
  elif [[ "$u" =~ $re_scp ]]; then
    host="${BASH_REMATCH[2]}" owner="${BASH_REMATCH[3]}" repo="${BASH_REMATCH[4]}"
  else
    return 1
  fi
  repo="${repo%.git}"
  case "$host$owner$repo" in *..*) return 1 ;; esac
  [ -n "$repo" ] && [ "$owner" != . ] && [ "$repo" != . ] || return 1
  echo "$host/$owner/$repo"
}

# pc_default_branch <dir> <remote> <seconds>
pc_default_branch() {
  local dir="$1" remote="$2" secs="$3" ref url slug out
  case "$remote" in ''|-*|*/*|*..*) return 0 ;; esac
  [[ "$remote" =~ $PC_SAFE_REF ]] || return 0
  ref="$(pc_git "$dir" symbolic-ref --quiet "refs/remotes/$remote/HEAD")"
  if [ -n "$ref" ] && [ "${ref#refs/remotes/"$remote"/}" != "$ref" ]; then
    pc_line "${ref#refs/remotes/"$remote"/}"
    return 0
  fi
  url="$(pc_git "$dir" remote get-url --push "$remote")" || return 0
  slug="$(pc_url_slug "$url")" || return 0
  out="$(pc_gh "$secs" "$dir" repo view "$slug" --json defaultBranchRef --jq .defaultBranchRef.name)" || return 0
  out="${out%%$'\n'*}"
  case "$out" in ''|-*|*..*|refs/*) return 0 ;; esac
  [[ "$out" =~ $PC_SAFE_REF ]] || return 0
  echo "$out"
}

# pc_required_checks <dir> <pr|-> <owner/repo|-> <seconds>
pc_required_checks() {
  local dir="$1" sel="$2" repo="$3" secs="$4" out rc verdict
  set -- pr checks
  [ "$sel" = - ] || set -- "$@" "$sel"
  [ "$repo" = - ] || set -- "$@" -R "$repo"
  set -- "$@" --required --json bucket
  out="$(pc_gh "$secs" "$dir" "$@")"
  rc=$?
  case "$rc" in
    0|8) : ;;   # 8 is gh's documented "checks pending"
    124|137|143) echo "unknown no answer within ${secs}s"; return 0 ;;
    127) echo "unknown gh is not installed"; return 0 ;;
    *) echo "unknown gh exited $rc (no required check reported yet, no such PR, or no access)"; return 0 ;;
  esac
  command -v jq >/dev/null 2>/dev/null || { echo "unknown jq is not installed"; return 0; }
  verdict="$(jq -r '
    if type == "array" and length > 0 and all(.[]; type == "object" and (.bucket | type) == "string") then
      ([.[] | select(.bucket == "fail" or .bucket == "cancel")] | length) as $f
      | ([.[] | select(.bucket == "pending")] | length) as $p
      | ([.[] | select(.bucket == "pass" or .bucket == "skipping")] | length) as $ok
      | if $f + $p > 0 then "true \(length) required: \($f) failing or cancelled, \($p) pending"
        elif $ok == length then "false \(length) required, all passing"
        else "unknown a required check is in a state gh does not name" end
    else "unknown gh printed no required checks" end' <<<"$out" 2>/dev/null)" || verdict=""
  case "$verdict" in
    true\ *) echo "$verdict" ;;
    false\ *) if [ "$rc" = 0 ]; then echo "$verdict"; else echo "unknown gh said pending, its list did not"; fi ;;
    unknown\ *) echo "$verdict" ;;
    *) echo "unknown gh printed no JSON" ;;
  esac
}

pc_usage() {
  echo "usage: permission-conditions.sh default-branch [--deadline s] <dir> <remote>" >&2
  echo "       permission-conditions.sh required-checks [--deadline s] <dir> <pr|-> <owner/repo|->" >&2
  return 2
}

pc_main() {
  local cmd="${1:-}" secs=3
  [ "$#" -gt 0 ] && shift
  if [ "${1:-}" = --deadline ]; then
    [ "$#" -ge 2 ] || { pc_usage; return 2; }
    secs="$2"
    shift 2
  fi
  # 0.1 to 3 seconds; anything else is 3 (a 0 would mean no deadline to timeout(1)).
  [[ "$secs" =~ ^([0-2](\.[0-9]+)?|3(\.0+)?)$ ]] || secs=3
  [[ "$secs" =~ ^0(\.0+)?$ ]] && secs=0.1
  case "$cmd" in
    default-branch)
      [ "$#" -eq 2 ] || { pc_usage; return 2; }
      pc_default_branch "$1" "$2" "$secs" ;;
    required-checks)
      [ "$#" -eq 3 ] || { pc_usage; return 2; }
      pc_required_checks "$1" "$2" "$3" "$secs" ;;
    *) pc_usage; return 2 ;;
  esac
  return 0
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  pc_main "$@"
  exit $?
fi
