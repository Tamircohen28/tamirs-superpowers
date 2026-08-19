#!/usr/bin/env bash
#
# cleanup.sh — non-interactive, provably-safe subset of the repo-cleanup sweep.
#
# Purpose: give headless callers (sub-agents fanning out over many repos,
# Workflow stages, CI) a scriptable cleanup path that CANNOT destroy work.
# It performs ONLY deletions that are safe without human judgment:
#   - remote branches fully merged into the default branch
#   - auxiliary worktrees that are clean AND whose branch is merged/gone
#   - git-ignored build/cache directories
#   - a fast-forward-only sync of the default branch to origin
#
# Anything requiring judgment — dirty worktrees, unpushed commits, unmerged
# branches, non-ignored files, a diverged default branch — is REPORTED and
# left untouched. For the full interactive sweep (per-item confirmation,
# rescuing uncommitted work, driving open PRs via pr-dev), use the `cleanup`
# skill instead; this script is the safe deterministic core of it.
#
# Usage:
#   cleanup.sh [--dry-run] [--remote-only | --local-only] [--yes] [REPO_PATH]
#
# Flags:
#   --dry-run       Print the plan; change nothing. (Default when --yes absent.)
#   --yes           Actually execute the safe deletions. Without it, dry-run.
#   --remote-only   Only the remote merged-branch phase.
#   --local-only    Only the worktree + build-file + ff-sync phases.
#   -h, --help      Show this help.
#   REPO_PATH       Repo to operate on (default: current directory).
#
# Exit codes: 0 success (incl. dry-run), 1 usage/precondition error.

set -uo pipefail

DRY_RUN=1        # safe by default; --yes flips to 0
SCOPE="all"      # all | remote | local
REPO_PATH="."

die()  { printf 'cleanup.sh: %s\n' "$1" >&2; exit 1; }
say()  { printf '%s\n' "$1"; }
# act "<human description>" cmd args... — always prints its line to real stdout;
# in execute mode it runs the command with the command's own output suppressed.
act()  {
  local desc="$1"; shift
  if [[ $DRY_RUN -eq 1 ]]; then
    say "  [dry-run] would $desc"
  else
    say "  $desc"
    "$@" >/dev/null 2>&1 || say "    (failed: $desc)"
  fi
}
# verb used in summary lines: "would delete"/"deleted" etc.
did() { [[ $DRY_RUN -eq 1 ]] && printf 'would %s' "$1" || printf '%s' "$2"; }

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)     DRY_RUN=1 ;;
    --yes)         DRY_RUN=0 ;;
    --remote-only) SCOPE="remote" ;;
    --local-only)  SCOPE="local" ;;
    -h|--help)     grep '^#' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*)            die "unknown flag: $1" ;;
    *)             REPO_PATH="$1" ;;
  esac
  shift
done

command -v git >/dev/null 2>&1 || die "git not found"
cd "$REPO_PATH" 2>/dev/null || die "not a directory: $REPO_PATH"
ROOT=$(git rev-parse --show-toplevel 2>/dev/null) || die "not a git repo: $REPO_PATH"
cd "$ROOT" || die "cannot cd to repo root: $ROOT"

HAVE_GH=0
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  HAVE_GH=1
fi

DEFAULT=""
if [[ $HAVE_GH -eq 1 ]]; then
  DEFAULT=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null)
fi
# Fall back to the local guess if gh is unavailable.
if [[ -z "$DEFAULT" ]]; then
  DEFAULT=$(git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||')
fi
if [[ -z "$DEFAULT" ]]; then
  die "cannot resolve the default branch (gh unavailable and origin/HEAD unset). Run 'git remote set-head origin --auto'. Refusing to guess a name — every deletion below is measured against 'origin/<default>', and a wrong name makes 'git branch --merged' return nothing or, worse, the wrong set."
fi

MODE_LABEL=$([[ $DRY_RUN -eq 1 ]] && echo "DRY-RUN (no changes)" || echo "EXECUTE")
say "repo-cleanup (safe subset) — $ROOT"
say "default branch: $DEFAULT | scope: $SCOPE | mode: $MODE_LABEL"
say ""

# Never-delete list. The resolved default branch is protected by name (it may be
# 'trunk' or anything else); the literals are an additional conventional
# superset — over-protecting a branch is safe, under-protecting one is not. This
# is a deny-list, not a default-branch guess.
PROTECTED_RE="^(${DEFAULT}|main|master|develop|HEAD)\$|^(release|hotfix)/"

# ---------------------------------------------------------------------------
# Phase 1 — remote branches fully merged into the default branch
# ---------------------------------------------------------------------------
remote_phase() {
  say "[remote] merged-branch cleanup"
  git fetch --prune origin >/dev/null 2>&1 || say "  (warning: git fetch failed)"

  local merged deleted=0
  merged=$(git branch -r --merged "origin/$DEFAULT" 2>/dev/null \
    | grep -v ' -> ' \
    | sed 's|^[* ]*origin/||' \
    | grep -Ev "$PROTECTED_RE" \
    | grep -Ev '^origin/' \
    | sort -u)

  if [[ -z "$merged" ]]; then
    say "  no merged branches to delete"
    say ""
    return
  fi

  local br has_pr
  while IFS= read -r br; do
    [[ -z "$br" ]] && continue
    # Never delete a branch that still has an open PR.
    has_pr=""
    if [[ $HAVE_GH -eq 1 ]]; then
      has_pr=$(gh pr list --head "$br" --state open --json number -q '.[].number' 2>/dev/null)
    fi
    if [[ -n "$has_pr" ]]; then
      say "  keep (open PR #$has_pr): $br"
      continue
    fi
    act "delete merged branch: $br" git push origin --delete "$br"
    deleted=$((deleted + 1))
  done <<< "$merged"

  say "  merged branches $(did delete deleted): $deleted"
  say ""
}

# ---------------------------------------------------------------------------
# Phase 2 — auxiliary worktrees that are clean AND merged/gone
# ---------------------------------------------------------------------------
worktree_phase() {
  say "[local] stale-clean worktree cleanup"
  local first=1 removed=0 path="" branch=""

  # Walk `git worktree list --porcelain`; first record = main worktree, skip it.
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      worktree\ *)
        path="${line#worktree }"; branch="" ;;
      branch\ *)
        branch="${line#branch refs/heads/}" ;;
      "")
        if [[ $first -eq 1 ]]; then first=0; path=""; continue; fi
        [[ -z "$path" ]] && continue
        classify_worktree "$path" "$branch" && removed=$((removed + 1))
        path=""; branch="" ;;
    esac
  done < <(git worktree list --porcelain 2>/dev/null; printf '\n')

  say "  stale-clean worktrees $(did remove removed): $removed"
  say ""
}

# Returns 0 if the worktree was (or would be) removed, 1 otherwise.
classify_worktree() {
  local path="$1" branch="$2"
  [[ -d "$path" ]] || return 1

  if [[ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]]; then
    say "  keep (dirty — has uncommitted changes): $path"; return 1
  fi
  local cur unpushed
  cur=$(git -C "$path" branch --show-current 2>/dev/null)
  if [[ -n "$cur" ]]; then
    unpushed=$(git -C "$path" log --oneline "origin/$cur..HEAD" 2>/dev/null)
    if [[ -n "$unpushed" ]]; then
      say "  keep (unpushed commits): $path"; return 1
    fi
  fi
  # Safe only when the branch is merged into default or already gone from remote.
  local merged=0
  if [[ -z "$branch" ]]; then
    merged=1  # detached/gone → nothing to lose
  elif git branch --merged "origin/$DEFAULT" 2>/dev/null | sed 's|^[* ]*||' | grep -qx "$branch"; then
    merged=1
  elif ! git show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    merged=1  # remote branch gone
  fi
  if [[ $merged -eq 0 ]]; then
    say "  keep (branch not merged): $path"; return 1
  fi
  act "remove stale-clean worktree: $path" git worktree remove --force "$path"
  return 0
}

# ---------------------------------------------------------------------------
# Phase 3a — git-ignored build/cache directories
# ---------------------------------------------------------------------------
buildfiles_phase() {
  say "[local] git-ignored build artifacts"
  local names=(node_modules .next dist build .cache __pycache__ .tox target .gradle)
  local expr=() n
  for n in "${names[@]}"; do expr+=(-name "$n" -o); done
  unset 'expr[${#expr[@]}-1]'  # drop trailing -o

  local removed=0 d
  while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    # Only remove paths git actually ignores — never a tracked/source dir.
    if git check-ignore -q "$d" 2>/dev/null; then
      act "delete ignored build dir: $d" rm -rf "$d"
      removed=$((removed + 1))
    fi
  done < <(find . -maxdepth 3 -type d \( "${expr[@]}" \) -not -path './.git/*' 2>/dev/null)

  say "  ignored build dirs $(did delete removed): $removed"
  say ""
}

# ---------------------------------------------------------------------------
# Phase 3b — fast-forward-only sync of the default branch
# ---------------------------------------------------------------------------
sync_phase() {
  say "[local] fast-forward sync of $DEFAULT"
  local cur
  cur=$(git branch --show-current 2>/dev/null)
  if [[ -n "$(git status --porcelain 2>/dev/null)" ]]; then
    say "  skip (working tree not clean)"; say ""; return
  fi
  git fetch --prune origin >/dev/null 2>&1 || true
  if ! git show-ref --verify --quiet "refs/remotes/origin/$DEFAULT"; then
    say "  skip (no origin/$DEFAULT)"; say ""; return
  fi
  local ahead
  ahead=$(git rev-list --count "origin/$DEFAULT..$DEFAULT" 2>/dev/null || echo 0)
  if [[ "$ahead" != "0" ]]; then
    say "  skip ($DEFAULT is ahead of origin by $ahead commit(s) — diverged, needs a human)"
    say ""; return
  fi
  act "checkout $DEFAULT" git checkout "$DEFAULT"
  act "fast-forward $DEFAULT to origin/$DEFAULT" git merge --ff-only "origin/$DEFAULT"
  [[ -n "$cur" && "$cur" != "$DEFAULT" && $DRY_RUN -eq 1 ]] && say "  (would return to $cur)"
  say ""
}

# ---------------------------------------------------------------------------
if [[ "$SCOPE" == "remote" || "$SCOPE" == "all" ]]; then
  if [[ $HAVE_GH -eq 1 ]]; then remote_phase; else say "[remote] skipped — gh unavailable/unauthenticated"; say ""; fi
fi
if [[ "$SCOPE" == "local" || "$SCOPE" == "all" ]]; then
  worktree_phase
  buildfiles_phase
  sync_phase
fi

if [[ $DRY_RUN -eq 1 ]]; then
  say "Dry-run complete — no changes made. Re-run with --yes to apply the safe subset."
else
  say "Done — safe subset applied."
fi
