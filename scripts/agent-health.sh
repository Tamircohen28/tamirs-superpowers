#!/usr/bin/env bash
# agent-health.sh — per-worktree health report for parallel coding agents.
#
# Usage:
#   agent-health.sh [--repo PATH] [--idle-min N] [--pile N] [--json]
#   agent-health.sh -h | --help
#
# For every `git worktree` of the repo (default: current directory) prints the
# branch, commits ahead of the default branch, the uncommitted file count, the
# minutes since the last file write and since the last commit, and a verdict.
#
# Why: an agent once sat on 171 uncommitted files and 0 commits for hours, and
# agents kept showing "running" after a network drop had killed them. Both are
# visible from the filesystem and git alone, with no help from the agent.
#
# Verdicts (first match wins, in this precedence):
#   uncommitted-pile  uncommitted files >= --pile (default 25)
#   idle              (uncommitted > 0 or ahead > 0) and the newest file write is
#                     older than --idle-min minutes (default 20): work exists but
#                     nothing has touched it, so the agent is probably dead
#   no-commits        zero commits ahead of the default branch AND (uncommitted > 0
#                     or the branch is not the default branch, incl. detached HEAD)
#   ok                anything else
#
# Default branch: origin/HEAD if set, else main, else master. If none exists,
# ahead is reported as 0 and every non-empty worktree counts as "not default".
# Last write ignores .git, node_modules and dist. Bare and missing (prunable)
# worktrees are listed with a note and no file statistics.
#
# Portable: bash 3.2 and BSD/GNU userlands (find -mmin, git plumbing, date +%s).
# Exit 0 always, except 2 on a usage error or when PATH is not a git repository.
set -uo pipefail

usage() { sed -n '2,29p' "$0" | sed -E 's/^# ?//'; }
die() { printf 'agent-health: %s\n' "$1" >&2; exit 2; }

REPO="."
IDLE_MIN=20
PILE=25
JSON=0

is_uint() { case "$1" in ''|*[!0-9]*) return 1 ;; *) return 0 ;; esac; }

while [ "$#" -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --json) JSON=1 ;;
    --repo) [ "$#" -ge 2 ] || die "--repo needs a path"; REPO="$2"; shift ;;
    --idle-min) [ "$#" -ge 2 ] || die "--idle-min needs a number"; IDLE_MIN="$2"; shift ;;
    --pile) [ "$#" -ge 2 ] || die "--pile needs a number"; PILE="$2"; shift ;;
    *) printf 'agent-health: unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done
is_uint "$IDLE_MIN" || die "--idle-min must be a non-negative integer"
is_uint "$PILE" || die "--pile must be a non-negative integer"
command -v git >/dev/null 2>&1 || die "git not found"
[ -d "$REPO" ] || die "not a directory: $REPO"
git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || die "not a git repository: $REPO"
REPO="$(cd "$REPO" && pwd)"

NOW="$(date +%s)"

# json_escape STRING — escape for use inside a JSON string, no jq needed.
json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e "s/$(printf '\t')/\\\\t/g" | tr -d '\000-\037'
}

# Default branch: origin/HEAD, else main, else master.
DEF_NAME=""
DEF_REF=""
oh="$(git -C "$REPO" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
if [ -n "$oh" ]; then
  DEF_NAME="${oh#origin/}"
  DEF_REF="refs/remotes/$oh"
  # Compare against the remote-tracking ref, never a local branch of the same
  # name: a stale local default would count upstream commits as the worker's own.
else
  for b in main master; do
    if git -C "$REPO" show-ref --verify -q "refs/heads/$b"; then DEF_NAME="$b"; DEF_REF="refs/heads/$b"; break; fi
  done
fi

# newest_write_min DIR — minutes since the newest file write under DIR (ignoring
# .git, node_modules, dist, nested worktrees). Prints nothing when there are no files. Doubles an
# upper bound with find -mmin, then bisects; each probe stops at the first hit.
newest_write_min() {
  local dir="$1" hi=1 lo=0 mid
  # Also prune nested worktree dirs and any directory holding a .git FILE (a
  # nested worktree root), so one checkout's age is not driven by its workers.
  local -a prune=( -name .git -o -name node_modules -o -name dist -o -path ./.agent-worktrees -o -path ./.claude/.worktrees )
  local nested
  while IFS= read -r nested; do
    [ -n "$nested" ] && prune+=( -o -path "${nested%/.git}" )
  done < <(cd "$dir" && find . -mindepth 2 \( -name node_modules -o -name dist \) -prune -o -type f -name .git -print 2>/dev/null)
  has_newer() {
    [ -n "$(cd "$dir" && find . \( "${prune[@]}" \) -prune -o -type f -mmin "-$1" -print 2>/dev/null | head -n 1)" ]
  }
  while ! has_newer "$hi"; do
    [ "$hi" -ge 5256000 ] && return 0
    lo="$hi"; hi=$((hi * 2))
  done
  # Invariant: nothing newer than lo minutes, something newer than hi.
  while [ $((hi - lo)) -gt 1 ]; do
    mid=$(((lo + hi) / 2))
    if has_newer "$mid"; then hi="$mid"; else lo="$mid"; fi
  done
  printf '%s' "$lo"
}

FIRST=1
emit() { # path branch head note
  local path="$1" branch="$2" head="$3" note="$4"
  local ahead=0 unc=0 wmin="" cmin="" ct verdict nb out

  if [ -n "$head" ] && [ -n "$DEF_REF" ]; then
    ahead="$(git -C "$REPO" rev-list --count "$DEF_REF..$head" 2>/dev/null || echo 0)"
  fi
  if [ -n "$head" ]; then
    ct="$(git -C "$REPO" log -1 --format=%ct "$head" 2>/dev/null || true)"
    if is_uint "${ct:-x}"; then cmin=$(((NOW - ct) / 60)); [ "$cmin" -lt 0 ] && cmin=0; fi
  fi
  if [ -z "$note" ]; then
    out="$(git -C "$path" status --porcelain 2>/dev/null || true)"
    if [ -n "$out" ]; then unc="$(printf '%s\n' "$out" | wc -l | tr -d ' ')"; fi
    wmin="$(newest_write_min "$path")"
  fi

  nb=1
  if [ -n "$DEF_NAME" ] && [ "$branch" = "$DEF_NAME" ]; then nb=0; fi
  if [ "$unc" -ge "$PILE" ]; then
    verdict="uncommitted-pile"
  elif { [ "$unc" -gt 0 ] || [ "$ahead" -gt 0 ]; } && [ -n "$wmin" ] && [ "$wmin" -gt "$IDLE_MIN" ]; then
    verdict="idle"
  elif [ -z "$note" ] && [ "$ahead" -eq 0 ] && { [ "$unc" -gt 0 ] || [ "$nb" -eq 1 ]; }; then
    verdict="no-commits"
  else
    verdict="ok"
  fi

  if [ "$JSON" -eq 1 ]; then
    [ "$FIRST" -eq 1 ] || printf ',\n'
    printf '    {"path":"%s","branch":"%s","ahead":%s,"uncommitted":%s,"last_write_min":%s,"last_commit_min":%s,"verdict":"%s","note":"%s"}' \
      "$(json_escape "$path")" "$(json_escape "$branch")" "$ahead" "$unc" \
      "${wmin:-null}" "${cmin:-null}" "$verdict" "$note"
  else
    printf '%-17s %-24s %5s %7s %9s %9s  %s%s\n' "$verdict" "$branch" "$ahead" "$unc" \
      "${wmin:--}" "${cmin:--}" "$path" "${note:+  ($note)}"
  fi
  FIRST=0
}

if [ "$JSON" -eq 1 ]; then
  printf '{\n  "repo":"%s","default_branch":"%s","idle_min":%s,"pile":%s,\n  "worktrees":[\n' \
    "$(json_escape "$REPO")" "$(json_escape "$DEF_NAME")" "$IDLE_MIN" "$PILE"
else
  printf 'repo: %s   default: %s   idle-min: %s   pile: %s\n' "$REPO" "${DEF_NAME:-(none)}" "$IDLE_MIN" "$PILE"
  printf '%-17s %-24s %5s %7s %9s %9s  %s\n' VERDICT BRANCH AHEAD UNCOMM WRITE-MIN COMMIT-MIN PATH
fi

p_path=""; p_head=""; p_branch=""; p_bare=0; p_prune=0; have=0
flush() {
  [ "$have" -eq 1 ] || return 0
  local note=""
  if [ "$p_bare" -eq 1 ]; then note="bare"
  elif [ ! -d "$p_path" ]; then note="missing"
  elif [ "$p_prune" -eq 1 ]; then note="prunable"; fi
  [ -n "$p_branch" ] || p_branch="(detached)"
  emit "$p_path" "$p_branch" "$p_head" "$note"
  p_path=""; p_head=""; p_branch=""; p_bare=0; p_prune=0; have=0
}
while IFS= read -r line; do
  case "$line" in
    "worktree "*) flush; p_path="${line#worktree }"; have=1 ;;
    "HEAD "*) p_head="${line#HEAD }" ;;
    "branch "*) p_branch="${line#branch refs/heads/}" ;;
    bare) p_bare=1 ;;
    prunable*) p_prune=1 ;;
  esac
done <<EOT
$(git -C "$REPO" worktree list --porcelain 2>/dev/null)
EOT
flush

if [ "$JSON" -eq 1 ]; then printf '\n  ]\n}\n'; fi
exit 0
