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
# What is never deleted, even with --yes:
#   - a branch GitHub reports protected (its `protected` flag, or a ruleset
#     deletion/update/non-fast-forward rule), or whose protection cannot be read
#   - a branch sitting at the default branch's tip (no commits of its own yet)
#   - a branch with an open PR, or whose PRs cannot be listed
#   - a worktree that is dirty, holds gitignored content, holds commits no
#     remote ref contains (also when origin/<branch> does not exist), holds a
#     live agent claim, or belongs to an objective task that is not finished
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
    -h|--help)     awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"; exit 0 ;;
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

# The repository as owner/name: what the GitHub API calls and the claim keys name.
SLUG=""
if [[ $HAVE_GH -eq 1 ]]; then
  SLUG=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
fi
if [[ -z "$SLUG" ]]; then
  SLUG=$(git remote get-url origin 2>/dev/null | sed -E 's#^git@[^:]+:##; s#^[a-z]+://[^/]+/##; s#\.git$##')
  case "$SLUG" in */*/*|/*|"") SLUG="" ;; esac
fi

# gh_protected <branch> — true | false | unknown, from GitHub, never a name:
# the branch's `protected` flag (classic protection) and the rulesets that
# apply to it. A ruleset that restricts deletion, updates or force pushes
# protects it; any read that fails is unknown.
gh_protected() {
  local b="$1" flag rules
  [[ -n "$SLUG" ]] || { echo unknown; return; }
  flag=$(gh api "repos/$SLUG/branches/$b" --jq '.protected' 2>/dev/null) || flag=""
  rules=$(gh api "repos/$SLUG/rules/branches/$b" --jq '[.[].type] | join(",")' 2>/dev/null) || rules="?"
  if [[ "$flag" == true ]] || [[ ",$rules," =~ ,(deletion|update|non_fast_forward), ]]; then
    echo true
  elif [[ "$flag" == false && "$rules" != "?" ]]; then
    echo false
  else
    echo unknown
  fi
}

# in_flight <worktree-path> <branch> — prints a reason and returns 0 when the
# worktree belongs to work still running: a live agent claim on its branch
# (hooks/lib/agent-claim.sh's liveness: heartbeat within
# AGENT_CLAIM_STALE_SECONDS and, on this host, the holder pid alive), or an
# objective task (or integration branch) that is not finished. State that
# cannot be read counts as in flight.
in_flight() {
  local roots=() common
  common=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)
  roots+=("$ROOT/.dev-files/objectives")
  [[ -n "$common" ]] && roots+=("$(dirname "$common")/.dev-files/objectives")
  [[ -n "${OBJECTIVES_ROOT:-}" ]] && roots+=("$OBJECTIVES_ROOT")
  if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is missing, so claims and objective state cannot be read"; return 0
  fi
  python3 -I -S - "$1" "$2" "$SLUG" "${AGENT_CLAIM_DIR:-$HOME/.agent-work-claims}" \
    "${AGENT_CLAIM_STALE_SECONDS:-900}" "$(hostname 2>/dev/null)" "${roots[@]}" <<'PY'
import glob, json, os, sys, time
path, branch, slug, claims, stale, host = sys.argv[1:7]
roots = sys.argv[7:]
real = os.path.realpath(path)
def alive(pid):
    try:
        os.kill(int(pid), 0)
        return True
    except PermissionError:
        return True
    except Exception:
        return False
if branch and os.path.isdir(claims):
    for f in sorted(glob.glob(os.path.join(claims, "*.json"))):
        try:
            c = json.load(open(f))
            res = c["resource"]
        except Exception:
            if branch in os.path.basename(f):
                print("claim file %s cannot be read" % f); sys.exit(0)
            continue
        if not isinstance(res, str) or not res.endswith("@" + branch):
            continue
        if slug and res != "git:%s@%s" % (slug, branch):
            continue
        try:
            age = time.time() - int(c["heartbeat_at"])
        except Exception:
            print("claim %s has no readable heartbeat" % res); sys.exit(0)
        if age > int(stale):
            continue
        if c.get("host") == host and str(c.get("pid", "")).isdigit() and not alive(c["pid"]):
            continue
        print("live agent claim on %s (%s, heartbeat %ds ago)" % (res, c.get("tool", "?"), max(age, 0))); sys.exit(0)
OPEN_TASK = {"pending", "ready", "running", "blocked"}
OPEN_OBJ = {"draft", "active", "integrating", "reviewing", "delivering", "blocked"}
seen = set()
for r in roots:
    r = os.path.realpath(r)
    if r in seen or not os.path.isdir(r):
        continue
    seen.add(r)
    for od in sorted(glob.glob(os.path.join(r, "*"))):
        of = os.path.join(od, "objective.json")
        if not os.path.isfile(of):
            continue
        try:
            o = json.load(open(of))
        except Exception:
            print("objective state %s cannot be read" % of); sys.exit(0)
        oid = o.get("id") or os.path.basename(od)
        if o.get("status") in OPEN_OBJ:
            if branch and branch == o.get("integration_branch"):
                print("integration branch of objective %s (%s)" % (oid, o.get("status"))); sys.exit(0)
            if ("/.agent-worktrees/%s/" % oid) in real + "/":
                print("worktree of objective %s (%s)" % (oid, o.get("status"))); sys.exit(0)
        for tf in sorted(glob.glob(os.path.join(od, "tasks", "*.json"))):
            try:
                t = json.load(open(tf))
            except Exception:
                print("task state %s cannot be read" % tf); sys.exit(0)
            if t.get("status") not in OPEN_TASK:
                continue
            wt = t.get("worktree")
            if (wt and os.path.realpath(wt) == real) or (branch and t.get("branch") == branch):
                print("objective %s %s is %s" % (oid, t.get("id", os.path.basename(tf)), t.get("status"))); sys.exit(0)
sys.exit(1)
PY
}

MODE_LABEL=$([[ $DRY_RUN -eq 1 ]] && echo "DRY-RUN (no changes)" || echo "EXECUTE")
say "repo-cleanup (safe subset) — $ROOT"
say "default branch: $DEFAULT | scope: $SCOPE | mode: $MODE_LABEL"
say ""

# Never-delete names. The resolved default branch is excluded by name (it may be
# 'trunk' or anything else); the literals are an additional conventional
# superset — over-protecting a branch is safe, under-protecting one is not. This
# is NOT the protection check: that is gh_protected(), GitHub's own answer, and a
# protected branch named anything else is kept by it.
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

  local br has_pr tip default_tip prot
  default_tip=$(git rev-parse --verify --quiet "refs/remotes/origin/$DEFAULT" 2>/dev/null)
  while IFS= read -r br; do
    [[ -z "$br" ]] && continue
    # A branch at the default tip has no commits of its own: just created, not merged.
    tip=$(git rev-parse --verify --quiet "refs/remotes/origin/$br" 2>/dev/null)
    if [[ -z "$tip" || -z "$default_tip" || "$tip" == "$default_tip" ]]; then
      say "  keep (at the $DEFAULT tip — no commits of its own): $br"
      continue
    fi
    # Never delete a branch that still has an open PR, or whose PRs cannot be listed.
    if ! has_pr=$(gh pr list --head "$br" --state open --json number -q '.[].number' 2>/dev/null); then
      say "  keep (its open PRs could not be listed): $br"
      continue
    fi
    if [[ -n "$has_pr" ]]; then
      say "  keep (open PR #$has_pr): $br"
      continue
    fi
    # Protection is GitHub's answer, not a name pattern.
    prot=$(gh_protected "$br")
    if [[ "$prot" != false ]]; then
      say "  keep (protected on GitHub, or its protection could not be read: $prot): $br"
      continue
    fi
    act "delete merged branch: $br" git push origin --delete "refs/heads/$br"
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
  # `git status --porcelain` is empty for gitignored-but-present content by design —
  # that is not the same as "nothing here". A repo can deliberately route session or
  # scratch output into a gitignored directory, which is then invisible to the check
  # above while still holding real, irreplaceable work. Treat any such content the
  # same as a dirty worktree: never force-remove it unattended.
  local ignored_count
  ignored_count=$(git -C "$path" ls-files --others --ignored --exclude-standard 2>/dev/null | wc -l | tr -d ' ')
  if [[ "${ignored_count:-0}" -gt 0 ]]; then
    say "  keep (gitignored content present, $ignored_count file(s) — git status reports clean, this does not): $path"
    return 1
  fi
  # Unpushed = reachable from HEAD and from no remote-tracking ref. Measured
  # against every remote ref, not origin/<branch>: when that ref does not exist,
  # `git log origin/<b>..HEAD` errors to an empty answer and local-only commits
  # read as "nothing unpushed".
  local unpushed
  if ! unpushed=$(git -C "$path" rev-list --count HEAD --not --remotes 2>/dev/null); then
    say "  keep (its commits could not be compared with the remote): $path"; return 1
  fi
  if [[ "$unpushed" != 0 ]]; then
    say "  keep (unpushed commits: $unpushed): $path"; return 1
  fi
  local why
  if why=$(in_flight "$path" "$branch"); then
    say "  keep (in flight — $why): $path"; return 1
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
  # Clean, nothing ignored, nothing unpushed: --force here discards nothing.
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
