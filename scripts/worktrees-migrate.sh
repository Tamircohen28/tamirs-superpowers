#!/usr/bin/env bash
# worktrees-migrate.sh — move idle session worktrees out of ~/.claude/worktrees.
#
# Usage:
#   worktrees-migrate.sh [--yes] [--to <root>] [--from <root>] [--idle-minutes <n>] [-v]
#   worktrees-migrate.sh -h | --help
#
# Session worktrees used to live under ~/.claude/worktrees/<repo>/<slug>. Claude Code
# treats every .claude directory as a protected path, so outside bypassPermissions
# mode each edit there prompts (issue #404). New worktrees go to the configured root
# (SUPERPOWERS_WORKTREE_ROOT, the worktree_root plugin option, default
# ~/.session-worktrees); this script moves the old ones there, to <root>/<repo>/<slug>.
#
# DRY RUN BY DEFAULT. Without --yes it prints the plan and changes nothing.
#
# Only IDLE worktrees move. A worktree is skipped, with the reason printed, when:
#   - it has uncommitted changes (git status --porcelain shows anything besides the
#     plugin's own session-files/ and .env.local, which move with the directory);
#   - a live agent claim (~/.agent-work-claims, hooks/lib/agent-claim.sh) holds its branch;
#   - an unfinished objective task, or an open objective's integration branch, owns it;
#   - a running process has its working directory inside it (lsof, or /proc on Linux;
#     when neither can answer, every worktree is skipped);
#   - anything in it changed in the last --idle-minutes (default 60; 0 turns this off);
#   - the destination already exists.
#
# Each move is `git worktree move` (never --force), so git updates its own metadata.
# Afterwards every session-state record (~/.claude/session-state/*.json) that names the
# old path, or a path inside it, is rewritten to the new one.
#
# Options:
#   --yes               perform the moves (default: dry run)
#   --to <root>         destination root (default: the configured worktree root). The
#                       worktree_root plugin option reaches hooks only, so pass it here
#                       if you set it there.
#   --from <root>       source root (default: ~/.claude/worktrees)
#   --idle-minutes <n>  skip worktrees modified in the last n minutes (default 60)
#   -v, --verbose       print every check
#   -h, --help          this text
#
# Example:
#   scripts/worktrees-migrate.sh                 # see what would move
#   scripts/worktrees-migrate.sh --yes           # move the idle ones
#   scripts/worktrees-migrate.sh --yes --to ~/wt
#
# Exit 0 when every planned move succeeded (or in a dry run); 1 when a move failed;
# 2 on a usage error.
set -euo pipefail

usage() { sed -n '2,46p' "$0" | sed -E 's/^# ?//'; exit "${1:-0}"; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../hooks/lib/worktree-common.sh
source "${SCRIPT_DIR}/../hooks/lib/worktree-common.sh"

APPLY=0
VERBOSE=0
TO=""
FROM=""
IDLE_MINUTES=60

while [[ $# -gt 0 ]]; do
  case "$1" in
    --yes) APPLY=1 ;;
    --to) [[ $# -ge 2 ]] || { echo "worktrees-migrate: --to needs a path" >&2; exit 2; }; TO="$2"; shift ;;
    --from) [[ $# -ge 2 ]] || { echo "worktrees-migrate: --from needs a path" >&2; exit 2; }; FROM="$2"; shift ;;
    --idle-minutes)
      [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]] || { echo "worktrees-migrate: --idle-minutes needs a whole number" >&2; exit 2; }
      IDLE_MINUTES="$2"; shift ;;
    -v|--verbose) VERBOSE=1 ;;
    -h|--help) usage 0 ;;
    *) echo "worktrees-migrate: unknown argument '$1' (try --help)" >&2; exit 2 ;;
  esac
  shift
done

resolve_root_arg() {
  local raw="$1" what="$2"
  if ! _normalize_worktree_root "$raw"; then
    echo "worktrees-migrate: ${what} '${raw}' is not an absolute path" >&2
    exit 2
  fi
  printf '%s' "$_WT_ROOT_OUT"
}

if [[ -n "$TO" ]]; then TO="$(resolve_root_arg "$TO" --to)"; else TO="$WORKTREE_ROOT"; fi
if [[ -n "$FROM" ]]; then FROM="$(resolve_root_arg "$FROM" --from)"; else FROM="$LEGACY_WORKTREE_ROOT"; fi

log() { [[ $VERBOSE -eq 1 ]] && printf '  . %s\n' "$1"; return 0; }

mode="DRY RUN (nothing is changed; pass --yes to move)"
[[ $APPLY -eq 1 ]] && mode="APPLY"
printf 'worktrees-migrate — %s\n' "$mode"
to_note=""
[[ "$TO" == "$WORKTREE_ROOT" ]] && to_note=" (configured root, from ${WORKTREE_ROOT_SOURCE})"
printf '  from: %s\n  to:   %s%s\n' "$FROM" "$TO" "$to_note"

if [[ ! -d "$FROM" ]]; then
  printf 'Nothing to migrate: %s does not exist.\n' "$FROM"
  exit 0
fi
if [[ "$(_physical_dir "$FROM")" == "$(_physical_dir "$TO")" ]]; then
  printf 'Nothing to migrate: the source and destination roots are the same directory.\n'
  exit 0
fi
if path_under_root "$TO" "$FROM"; then
  echo "worktrees-migrate: the destination root is inside the source root" >&2
  exit 2
fi

# ---------------------------------------------------------------- processes ---
# Every running process's working directory, physical, one per line. Collected
# once. PROC_CHECK=unknown when nothing on this machine can answer.
PROC_CWDS=""
PROC_CHECK=ok
if command -v lsof >/dev/null 2>&1; then
  PROC_CWDS="$(lsof -n -w -d cwd -Fn 2>/dev/null </dev/null | sed -n 's/^n//p' || true)"
elif [[ -d /proc/self ]]; then
  for link in /proc/[0-9]*/cwd; do
    target="$(readlink "$link" 2>/dev/null || true)"
    [[ -n "$target" ]] && PROC_CWDS="${PROC_CWDS}${target}"$'\n'
  done
else
  PROC_CHECK=unknown
fi

# in_use <dir> — prints the first process cwd inside <dir>.
in_use() {
  local dir="$1" phys cwd
  phys="$(_physical_dir "$dir")"
  while IFS= read -r cwd; do
    [[ -n "$cwd" ]] || continue
    case "$cwd" in
      "$dir"|"$dir"/*|"$phys"|"$phys"/*) printf '%s' "$cwd"; return 0 ;;
    esac
  done <<<"$PROC_CWDS"
  return 1
}

# ---------------------------------------------------------------- recency ---
# recently_modified <dir> <gitdir> — prints one path changed in the last
# IDLE_MINUTES (node_modules skipped: an install there is not the user's work),
# plus the worktree's own HEAD and reflog in git's metadata, which a commit or a
# checkout touches.
recently_modified() {
  local dir="$1" gitdir="$2" hit
  [[ "$IDLE_MINUTES" -gt 0 ]] || return 1
  hit="$(find "$dir" -name node_modules -prune -o -mmin "-${IDLE_MINUTES}" -print 2>/dev/null | head -n 1)"
  if [[ -z "$hit" && -n "$gitdir" && -d "$gitdir" ]]; then
    hit="$(find "$gitdir/HEAD" "$gitdir/logs" -maxdepth 1 -mmin "-${IDLE_MINUTES}" -print 2>/dev/null | head -n 1)"
  fi
  [[ -n "$hit" ]] || return 1
  printf '%s' "$hit"
}

# ------------------------------------------------------------- in flight ---
# in_flight <worktree> <branch> <main-root> — prints a reason and returns 0 when a
# live agent claim or an unfinished objective owns the worktree. The same reading
# as skills/repo/cleanup/scripts/cleanup.sh's in_flight. State that cannot be read
# counts as in flight.
in_flight() {
  if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 is missing, so claims and objective state cannot be read"; return 0
  fi
  local roots=("$3/.dev-files/objectives")
  [[ -n "${OBJECTIVES_ROOT:-}" ]] && roots+=("$OBJECTIVES_ROOT")
  python3 -I -S - "$1" "$2" "${AGENT_CLAIM_DIR:-$HOME/.agent-work-claims}" \
    "${AGENT_CLAIM_STALE_SECONDS:-900}" "$(hostname 2>/dev/null || true)" "${roots[@]}" <<'PY'
import glob, json, os, sys, time
path, branch, claims, stale, host = sys.argv[1:6]
roots = sys.argv[6:]
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
            if branch.replace("/", "-") in os.path.basename(f) or branch in os.path.basename(f):
                print("claim file %s cannot be read" % f); sys.exit(0)
            continue
        if not isinstance(res, str) or not res.endswith("@" + branch):
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
        if o.get("status") in OPEN_OBJ and branch and branch == o.get("integration_branch"):
            print("integration branch of objective %s (%s)" % (oid, o.get("status"))); sys.exit(0)
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

# ---------------------------------------------------------------- dirty ---
# dirty_entries <porcelain> — porcelain lines other than the plugin's own files.
dirty_entries() {
  printf '%s\n' "$1" | grep -v -E '^(\?\? (session-files/|\.env\.local)$|$)' || true
}

# ------------------------------------------------------------ state update ---
# rewrite_session_state <old> <new> — every string in every session-state record
# equal to <old>, or starting with "<old>/", now names <new>. Prints how many
# records changed.
rewrite_session_state() {
  local old="$1" new="$2" f tmp changed=0 out
  [[ -d "$SESSION_STATE_DIR" ]] || { printf '0'; return 0; }
  for f in "$SESSION_STATE_DIR"/*.json; do
    [[ -f "$f" ]] || continue
    grep -qF "$old" "$f" 2>/dev/null || continue
    out="$(jq --arg old "$old" --arg new "$new" '
      def rw: if type == "string" then
                (if . == $old then $new
                 elif startswith($old + "/") then $new + .[($old | length):]
                 else . end)
              elif type == "object" then map_values(rw)
              elif type == "array" then map(rw)
              else . end;
      rw' "$f" 2>/dev/null)" || continue
    tmp="${f}.migrate.$$"
    printf '%s\n' "$out" > "$tmp" && mv "$tmp" "$f" && changed=$((changed + 1))
  done
  printf '%s' "$changed"
}

# ------------------------------------------------------------------ plan ---
moved=0 planned=0 skipped=0 failed=0
skip() { skipped=$((skipped + 1)); printf 'SKIP  %s\n      %s\n' "$1" "$2"; }

while IFS= read -r wt; do
  [[ -n "$wt" ]] || continue
  repo="$(basename "$(dirname "$wt")")"
  slug="$(basename "$wt")"
  dest="${TO}/${repo}/${slug}"

  if [[ ! -f "$wt/.git" ]]; then
    log "$wt: no .git file, not a linked worktree"
    continue
  fi
  common="$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  gitdir="$(git -C "$wt" rev-parse --path-format=absolute --git-dir 2>/dev/null || true)"
  if [[ -z "$common" || ! -d "$common" ]]; then
    skip "$wt" "its repository cannot be found (a pruned or broken worktree)"
    continue
  fi
  main_root="$(dirname "$common")"
  # Canonical comparison with git's own list: a worktree reached through a
  # symlinked root is still recognised, and nothing unregistered is touched.
  if ! is_linked_worktree_of "$main_root" "$wt"; then
    skip "$wt" "not a registered linked worktree of ${main_root}"
    continue
  fi
  branch="$(git -C "$wt" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
  log "$wt: repo ${main_root}, branch ${branch:-(detached)}"

  if [[ -e "$dest" ]]; then
    skip "$wt" "destination ${dest} already exists"; continue
  fi
  # Recency first: the git status below refreshes git's index, which is not the
  # worktree being used.
  if hit="$(recently_modified "$wt" "$gitdir")"; then
    skip "$wt" "modified in the last ${IDLE_MINUTES} min (${hit})"; continue
  fi
  if [[ "$PROC_CHECK" != ok ]]; then
    skip "$wt" "running processes cannot be checked (neither lsof nor /proc is available)"; continue
  fi
  if user="$(in_use "$wt")"; then
    skip "$wt" "a running process has its working directory inside (${user})"; continue
  fi
  if reason="$(in_flight "$wt" "$branch" "$main_root")"; then
    skip "$wt" "$reason"; continue
  fi
  # A status that fails is not "clean" — it is unknown, and unknown stays put.
  if ! porcelain="$(git -C "$wt" status --porcelain 2>/dev/null)"; then
    skip "$wt" "git status failed, so its changes cannot be checked"
    continue
  fi
  dirty="$(dirty_entries "$porcelain")"
  if [[ -n "$dirty" ]]; then
    skip "$wt" "uncommitted changes ($(printf '%s\n' "$dirty" | wc -l | tr -d ' ') entries) — commit or discard them first"
    continue
  fi

  planned=$((planned + 1))
  printf 'MOVE  %s\n   -> %s\n' "$wt" "$dest"
  [[ $APPLY -eq 1 ]] || continue

  # State may record either spelling of the old path; resolve it while it exists.
  wt_phys="$(_physical_dir "$wt")"
  mkdir -p "$(dirname "$dest")"
  if git -C "$main_root" worktree move "$wt" "$dest" </dev/null; then
    moved=$((moved + 1))
    n="$(rewrite_session_state "$wt" "$dest")"
    if [[ "$wt_phys" != "$wt" ]]; then
      n=$((n + $(rewrite_session_state "$wt_phys" "$dest")))
    fi
    printf '      moved; %s session-state record(s) updated\n' "$n"
    rmdir "$(dirname "$wt")" 2>/dev/null || true
  else
    failed=$((failed + 1))
    printf '      FAILED: git worktree move refused (see above); nothing else was changed\n'
  fi
done < <(find -H "$FROM" -mindepth 2 -maxdepth 2 -type d ! -name '.cleanup.lock' 2>/dev/null | sort)

echo
if [[ $APPLY -eq 1 ]]; then
  printf 'Moved %s, skipped %s, failed %s.\n' "$moved" "$skipped" "$failed"
  if [[ $moved -gt 0 ]]; then
    echo "Running sessions keep their old paths until they restart: run /plugin update and"
    echo "/reload-plugins in each, or start a new session."
  fi
else
  printf 'Would move %s, skip %s. Re-run with --yes to move them.\n' "$planned" "$skipped"
fi
[[ $failed -eq 0 ]]
