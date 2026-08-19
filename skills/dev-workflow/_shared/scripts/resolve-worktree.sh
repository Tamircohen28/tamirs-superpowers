#!/usr/bin/env bash
# resolve-worktree.sh — resolve, list and migrate agent git worktrees.
#
# Worktree identity is the objective and the task, never the harness that runs
# them (rules/dev/git-worktree-agent-workflow.md). The objective layout is:
#
#   .agent-worktrees/<slug>/integration   ->  objective/<slug>
#   .agent-worktrees/<slug>/task-NNN      ->  worker/<slug>/NNN
#
# Legacy platform layouts (.claude/.worktrees/, .cursor/.worktrees/,
# .codex/.worktrees/) stay valid and are never orphaned: when one already holds
# the branch being resolved, that worktree is returned instead of a parallel
# new-layout one being created.
#
# Validation tier: 0 (edit-time). This script never runs project tests.
#
# Usage:
#   resolve-worktree.sh --objective <slug> --task NNN [--base <branch>] [--root <dir>]
#   resolve-worktree.sh --objective <slug> --integration [--base <branch>] [--root <dir>]
#   resolve-worktree.sh --list [--root <dir>] [--table]
#   resolve-worktree.sh --migrate <path> [--confirm-dirty] [--dry-run]
#   resolve-worktree.sh <repo_root> <branch_name> [worktree_slug]   # legacy, still supported
#   resolve-worktree.sh -h | --help
#
# Output: one JSON object on stdout (a JSON array for --list; a table with
#   --table). Diagnostics go to stderr.
#
#   { objective, task, layout, platform, worktree_path, branch, base,
#     created, resumed }
#
# Requires git. Does NOT require jq. gh is optional — the default branch comes
# from git symbolic-ref, and gh is only consulted when origin/HEAD is unset
# (rules/dev/gh-cli-preference.md). No branch name is ever assumed.
#
# Exit codes: 0 ok · 1 usage/argument error · 2 not found · 4 refused (dirty tree)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() {
  sed -n '2,33p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

die() { printf 'ERROR: %s\n' "$1" >&2; exit "${2:-1}"; }
note() { printf '%s\n' "$1" >&2; }

if [[ $# -eq 0 || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage 0
fi

# --- JSON output without a jq dependency ------------------------------------

json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  printf '%s' "$s"
}

# emit_json key value [key value ...] — values "true"/"false" are emitted raw.
emit_json() {
  local out="{" first=1 k v
  while [[ $# -gt 0 ]]; do
    k="$1"; v="${2:-}"; shift 2
    [[ $first -eq 1 ]] || out+=","
    first=0
    if [[ "$v" == "true" || "$v" == "false" || "$v" == "null" ]]; then
      out+="\"$(json_escape "$k")\":$v"
    else
      out+="\"$(json_escape "$k")\":\"$(json_escape "$v")\""
    fi
  done
  printf '%s}\n' "$out"
}

# --- repo helpers -----------------------------------------------------------

REPO_ROOT=""

# The MAIN checkout, never a linked worktree: `git rev-parse --show-toplevel`
# run inside a worktree returns that worktree, which would nest
# .agent-worktrees/ inside it. The first entry of `worktree list` is the
# primary working tree, so resolution is stable from anywhere in the repo.
resolve_repo_root() {
  local want="${1:-}" here
  if [[ -n "$want" ]]; then
    [[ -e "$want" ]] || die "no such path: $want" 2
    [[ -d "$want" ]] || want="$(dirname "$want")"
    here="$want"
  else
    here="$PWD"
  fi
  git -C "$here" rev-parse --git-dir >/dev/null 2>&1 \
    || die "$here is not inside a git repository — pass --root <dir>" 2
  REPO_ROOT="$(git -C "$here" worktree list --porcelain 2>/dev/null | sed -n '1s/^worktree //p')"
  [[ -n "$REPO_ROOT" ]] || REPO_ROOT="$(git -C "$here" rev-parse --show-toplevel)"
}

# Default branch: the shared resolver (origin/HEAD, then gh). It refuses to
# guess a literal, and so does this — a base branch invented here becomes the
# start point of every worker branch on the objective.
# shellcheck source=./default-branch.sh
. "$SCRIPT_DIR/default-branch.sh"
default_branch() {
  local d
  d="$(resolve_default_branch "$REPO_ROOT")" \
    || die "cannot resolve the default branch to base this worktree on — pass --base <branch>" 1
  printf '%s\n' "$d"
}

# The commit-ish a new branch starts from, preferring the remote copy.
start_point() {
  local branch="$1"
  if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    printf 'origin/%s\n' "$branch"
  elif git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$branch"; then
    printf '%s\n' "$branch"
  else
    printf 'HEAD\n'
  fi
}

# Path of the worktree that currently has <branch> checked out, if any.
worktree_for_branch() {
  local branch="$1" path="" line
  while IFS= read -r line; do
    case "$line" in
      worktree\ *) path="${line#worktree }" ;;
      branch\ refs/heads/*)
        if [[ "${line#branch refs/heads/}" == "$branch" ]]; then
          printf '%s\n' "$path"
          return 0
        fi ;;
    esac
  done < <(git -C "$REPO_ROOT" worktree list --porcelain 2>/dev/null)
  return 1
}

LEGACY_PLATFORMS="claude cursor codex gemini opencode"

# First legacy worktree directory matching a slug-ish name, if one exists.
legacy_worktree_for() {
  local name="$1" p candidate
  for p in $LEGACY_PLATFORMS; do
    candidate="${REPO_ROOT}/.${p}/.worktrees/${name}"
    if [[ -d "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}

classify_layout() {
  case "$1" in
    */.agent-worktrees/*)                     printf 'objective\n' ;;
    */.claude/.worktrees/*|*/.cursor/.worktrees/*|*/.codex/.worktrees/*|*/.gemini/.worktrees/*|*/.opencode/.worktrees/*)
                                              printf 'legacy-platform\n' ;;
    */.claude/worktrees/*|*/worktrees/*)      printf 'legacy-external\n' ;;
    *)                                        printf 'other\n' ;;
  esac
}

platform_of_path() {
  case "$1" in
    */.claude/*)   printf 'claude\n' ;;
    */.cursor/*)   printf 'cursor\n' ;;
    */.codex/*)    printf 'codex\n' ;;
    */.gemini/*)   printf 'gemini\n' ;;
    */.opencode/*) printf 'opencode\n' ;;
    *)             printf '\n' ;;
  esac
}

objective_of() {
  local path="$1" branch="$2"
  case "$branch" in
    objective/*) printf '%s\n' "${branch#objective/}"; return 0 ;;
    worker/*)    local rest="${branch#worker/}"; printf '%s\n' "${rest%%/*}"; return 0 ;;
  esac
  case "$path" in
    */.agent-worktrees/*)
      local rest="${path#*/.agent-worktrees/}"
      printf '%s\n' "${rest%%/*}" ;;
    *) printf '\n' ;;
  esac
}

is_dirty() {
  [[ -n "$(git -C "$1" status --porcelain 2>/dev/null)" ]]
}

# Attach a worktree at <path> for <branch>, creating the branch if needed.
# Echoes "created" or "resumed".
add_worktree() {
  local path="$1" branch="$2" base="$3"
  mkdir -p "$(dirname "$path")"
  if git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/$branch"; then
    git -C "$REPO_ROOT" worktree add "$path" "$branch" >&2
    printf 'resumed\n'
  elif git -C "$REPO_ROOT" show-ref --verify --quiet "refs/remotes/origin/$branch"; then
    git -C "$REPO_ROOT" worktree add "$path" --track -b "$branch" "origin/$branch" >&2
    printf 'created\n'
  else
    git -C "$REPO_ROOT" worktree add "$path" -b "$branch" "$base" >&2
    printf 'created\n'
  fi
}

# --- objective / task resolution --------------------------------------------

cmd_resolve_objective() {
  local slug="$1" kind="$2" task="$3" base="$4"

  [[ "$slug" =~ ^[a-z0-9][a-z0-9-]*$ ]] \
    || die "objective slug must be kebab-case and carry no provider name (got '$slug')"

  local branch subdir
  if [[ "$kind" == "task" ]]; then
    [[ "$task" =~ ^[0-9]{1,3}$ ]] || die "--task takes 1-3 digits (got '$task')"
    task="$(printf '%03d' "$((10#$task))")"
    branch="worker/${slug}/${task}"
    subdir="task-${task}"
  else
    task=""
    branch="objective/${slug}"
    subdir="integration"
  fi

  # 1. The branch is already checked out somewhere — new layout or legacy.
  #    Resuming beats creating; a parallel worktree would split the work.
  local existing=""
  if existing="$(worktree_for_branch "$branch")"; then
    emit_json objective "$slug" task "$task" layout "$(classify_layout "$existing")" \
      platform "$(platform_of_path "$existing")" worktree_path "$existing" \
      branch "$branch" base "" created false resumed true
    return 0
  fi

  # 2. A legacy platform worktree named for this slug/branch — adopt it rather
  #    than creating a parallel new-layout one (core/policies/git.md).
  local legacy=""
  if legacy="$(legacy_worktree_for "$slug")" \
     || legacy="$(legacy_worktree_for "${branch//\//-}")" \
     || legacy="$(legacy_worktree_for "${slug}-${subdir}")"; then
    note "adopting existing legacy worktree: $legacy (not creating a parallel .agent-worktrees path)"
    emit_json objective "$slug" task "$task" layout "legacy-platform" \
      platform "$(platform_of_path "$legacy")" worktree_path "$legacy" \
      branch "$(git -C "$legacy" branch --show-current 2>/dev/null || printf '%s' "$branch")" \
      base "" created false resumed true
    return 0
  fi

  # 3. Create in the objective layout.
  if [[ -z "$base" ]]; then
    if [[ "$kind" == "task" ]] && git -C "$REPO_ROOT" show-ref --verify --quiet "refs/heads/objective/${slug}"; then
      # Worker branches come off the integration branch, not off origin.
      base="objective/${slug}"
    else
      base="$(start_point "$(default_branch)")"
    fi
  fi

  local path="${REPO_ROOT}/.agent-worktrees/${slug}/${subdir}"
  local state
  state="$(add_worktree "$path" "$branch" "$base")"
  emit_json objective "$slug" task "$task" layout "objective" platform "" \
    worktree_path "$path" branch "$branch" base "$base" \
    created "$([[ "$state" == created ]] && echo true || echo false)" \
    resumed "$([[ "$state" == resumed ]] && echo true || echo false)"
}

# --- legacy positional interface --------------------------------------------
#
# start-dev and switch-dev still call `resolve-worktree.sh <root> <branch>`.
# Kept working deliberately: the refactor adds interfaces, it does not break
# callers. It now also adopts an existing worktree for the branch in either
# layout instead of creating a second one, and no longer needs gh.

cmd_resolve_positional() {
  local root="$1" branch="$2" slug="${3:-}"
  [[ -n "$branch" ]] || die "usage: resolve-worktree.sh <repo_root> <branch_name> [worktree_slug]"
  resolve_repo_root "$root"

  local existing=""
  if existing="$(worktree_for_branch "$branch")"; then
    emit_json objective "$(objective_of "$existing" "$branch")" task "" \
      layout "$(classify_layout "$existing")" platform "$(platform_of_path "$existing")" \
      worktree_path "$existing" branch "$branch" base "" created false resumed true
    return 0
  fi

  # An objective-shaped branch gets the objective layout even by this route.
  case "$branch" in
    objective/*)
      cmd_resolve_objective "${branch#objective/}" integration "" ""
      return 0 ;;
    worker/*/[0-9][0-9][0-9])
      local rest="${branch#worker/}"
      cmd_resolve_objective "${rest%%/*}" task "${branch##*/}" ""
      return 0 ;;
  esac

  [[ -n "$slug" ]] || slug="${branch//\//-}"
  local platform
  platform="$(bash "${SCRIPT_DIR}/detect-platform.sh" 2>/dev/null || echo unknown)"
  local path="${REPO_ROOT}/.${platform}/.worktrees/${slug}"

  if [[ -d "$path" ]]; then
    emit_json objective "" task "" layout "legacy-platform" platform "$platform" \
      worktree_path "$path" branch "$branch" base "" created false resumed true
    return 0
  fi

  local base state
  base="$(start_point "$(default_branch)")"
  state="$(add_worktree "$path" "$branch" "$base")"
  emit_json objective "" task "" layout "legacy-platform" platform "$platform" \
    worktree_path "$path" branch "$branch" base "$base" \
    created "$([[ "$state" == created ]] && echo true || echo false)" \
    resumed "$([[ "$state" == resumed ]] && echo true || echo false)"
}

# --- list -------------------------------------------------------------------

cmd_list() {
  local as_table="$1"
  local primary path branch line rows=0 out="["
  primary="$REPO_ROOT"

  local -a paths=() branches=()
  path=""; branch=""
  while IFS= read -r line; do
    case "$line" in
      worktree\ *)
        if [[ -n "$path" ]]; then paths+=("$path"); branches+=("$branch"); fi
        path="${line#worktree }"; branch="" ;;
      branch\ refs/heads/*) branch="${line#branch refs/heads/}" ;;
      detached) branch="(detached)" ;;
    esac
  done < <(git -C "$REPO_ROOT" worktree list --porcelain 2>/dev/null)
  if [[ -n "$path" ]]; then paths+=("$path"); branches+=("$branch"); fi

  if [[ "$as_table" == "true" ]]; then
    printf '%-52s %-30s %-16s %-7s %s\n' PATH BRANCH OBJECTIVE DIRTY LAST-COMMIT
  fi

  local i layout obj dirty last
  for i in "${!paths[@]}"; do
    path="${paths[$i]}"; branch="${branches[$i]}"
    if [[ "$path" == "$primary" ]]; then continue; fi   # the human's checkout, not an agent worktree
    layout="$(classify_layout "$path")"
    obj="$(objective_of "$path" "$branch")"
    dirty=false
    if is_dirty "$path"; then dirty=true; fi
    last="$(git -C "$path" log -1 --format=%cI 2>/dev/null || true)"
    if [[ "$as_table" == "true" ]]; then
      printf '%-52s %-30s %-16s %-7s %s\n' "${path/#$HOME/~}" "$branch" "${obj:--}" "$dirty" "${last:--}"
    else
      [[ $rows -eq 0 ]] || out+=","
      out+="$(emit_json path "$path" branch "$branch" objective "$obj" \
              layout "$layout" platform "$(platform_of_path "$path")" \
              dirty "$dirty" last_commit "$last" | tr -d '\n')"
    fi
    rows=$((rows + 1))
  done

  if [[ "$as_table" == "true" ]]; then
    if [[ $rows -eq 0 ]]; then printf 'no agent worktrees\n'; fi
  else
    printf '%s]\n' "$out"
  fi
}

# --- migrate ----------------------------------------------------------------

cmd_migrate() {
  local src="$1" confirm_dirty="$2" dry_run="$3"
  [[ -d "$src" ]] || die "no such worktree: $src" 2
  src="$(cd "$src" && pwd)"

  local layout; layout="$(classify_layout "$src")"
  [[ "$layout" != "objective" ]] || die "$src is already in the objective layout — nothing to migrate"

  local branch; branch="$(git -C "$src" branch --show-current 2>/dev/null || true)"
  [[ -n "$branch" ]] || die "$src has a detached HEAD — check out a branch there first, or migrate it by hand" 4

  local slug subdir
  case "$branch" in
    objective/*) slug="${branch#objective/}"; subdir="integration" ;;
    worker/*/[0-9]*)
      local rest="${branch#worker/}"
      slug="${rest%%/*}"; subdir="task-$(printf '%03d' "$((10#${branch##*/}))")" ;;
    *)
      slug="$(printf '%s' "$branch" | tr '/_' '--' | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]//g; s/^-*//; s/-*$//')"
      subdir="integration"
      note "branch '$branch' is not objective-shaped; migrating to objective slug '$slug'" ;;
  esac
  [[ -n "$slug" ]] || die "could not derive an objective slug from branch '$branch'"

  local dest="${REPO_ROOT}/.agent-worktrees/${slug}/${subdir}"
  [[ ! -e "$dest" ]] || die "destination already exists: $dest" 4

  local dirty=false
  if is_dirty "$src"; then dirty=true; fi
  local blocked=false
  if [[ "$dirty" == "true" && "$confirm_dirty" != "true" ]]; then blocked=true; fi

  # A dry run inspects; it never refuses. It reports what a real run would do,
  # including that a dirty tree would block it.
  if [[ "$dry_run" == "true" ]]; then
    if [[ "$blocked" == "true" ]]; then
      note "$src has uncommitted changes — a real run would refuse without --confirm-dirty:"
      git -C "$src" status --short >&2
    fi
    emit_json action "migrate" dry_run true from "$src" to "$dest" branch "$branch" \
      objective "$slug" dirty "$dirty" would_block "$blocked" moved false
    return 0
  fi

  if [[ "$blocked" == "true" ]]; then
    note "$src has uncommitted changes:"
    git -C "$src" status --short >&2
    die "refusing to migrate a dirty worktree. Commit the work, or re-run with --confirm-dirty (the move preserves uncommitted changes)." 4
  fi

  mkdir -p "$(dirname "$dest")"
  # git worktree move relocates the checkout and rewrites its admin files;
  # uncommitted changes travel with it.
  git -C "$REPO_ROOT" worktree move "$src" "$dest" >&2
  emit_json action "migrate" dry_run false from "$src" to "$dest" branch "$branch" \
    objective "$slug" dirty "$dirty" moved true
}

# --- argument parsing -------------------------------------------------------

MODE="" SLUG="" KIND="" TASK="" BASE="" ROOT="" TABLE=false MIGRATE_PATH=""
CONFIRM_DIRTY=false DRY_RUN=false
POSITIONAL=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --objective)    MODE=objective; SLUG="${2:-}"; shift 2 ;;
    --task)         KIND=task; TASK="${2:-}"; shift 2 ;;
    --integration)  KIND=integration; shift ;;
    --base)         BASE="${2:-}"; shift 2 ;;
    --root)         ROOT="${2:-}"; shift 2 ;;
    --list)         MODE=list; shift ;;
    --table)        TABLE=true; shift ;;
    --migrate)      MODE=migrate; MIGRATE_PATH="${2:-}"; shift 2 ;;
    --confirm-dirty) CONFIRM_DIRTY=true; shift ;;
    --dry-run)      DRY_RUN=true; shift ;;
    -h|--help)      usage 0 ;;
    --*)            die "unknown option '$1' (try --help)" ;;
    *)              POSITIONAL+=("$1"); shift ;;
  esac
done

case "$MODE" in
  objective)
    [[ -n "$SLUG" ]] || die "--objective requires a slug"
    [[ -n "$KIND" ]] || die "--objective needs --task NNN or --integration"
    resolve_repo_root "$ROOT"
    cmd_resolve_objective "$SLUG" "$KIND" "$TASK" "$BASE"
    ;;
  list)
    resolve_repo_root "$ROOT"
    cmd_list "$TABLE"
    ;;
  migrate)
    [[ -n "$MIGRATE_PATH" ]] || die "--migrate requires a worktree path"
    resolve_repo_root "${ROOT:-$MIGRATE_PATH}"
    cmd_migrate "$MIGRATE_PATH" "$CONFIRM_DIRTY" "$DRY_RUN"
    ;;
  *)
    [[ ${#POSITIONAL[@]} -ge 2 ]] \
      || die "usage: resolve-worktree.sh --objective <slug> --task NNN | --integration | --list | --migrate <path> | <repo_root> <branch>"
    cmd_resolve_positional "${POSITIONAL[0]}" "${POSITIONAL[1]}" "${POSITIONAL[2]:-}"
    ;;
esac
