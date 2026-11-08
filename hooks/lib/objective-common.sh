#!/usr/bin/env bash
# Objective-model helpers — shared by the worktree-lifecycle hooks.
#
# WHY THIS FILE EXISTS SEPARATELY FROM worktree-common.sh
#   worktree-common.sh encodes the single-task model: one prompt, one slug, one
#   worktree under <session worktree root>/<repo>/<slug> (default
#   ~/.session-worktrees; ~/.claude/worktrees before issue #404). That model is still the
#   default and must keep working untouched. The objective model adds a second,
#   orchestrated shape on top of it:
#
#     .agent-worktrees/<objective>/{integration,task-NNN}
#     branches: objective/<slug>, worker/<slug>/NNN
#
#   Keeping the new vocabulary here means the protected worktree-common.sh only
#   grows the few hooks it genuinely needs, and a hook that has no objective
#   awareness keeps behaving exactly as it did.
#
# PROVIDER IS METADATA
#   Nothing here encodes claude/cursor/codex/gemini into a path or a branch. The
#   legacy platform-shaped paths (.claude/.worktrees, .cursor/.worktrees,
#   .codex/.worktrees) are RECOGNIZED so existing work is never orphaned, but
#   they are never GENERATED.

# _hook_put <text> writes <text> to stdout exactly as given: no trailing newline,
# no option or backslash processing. _hook_putln adds one newline. They stand in
# for format-string prints, so this file holds no printf conversion: the plugin
# directory's scan reads every printf carrying a % conversion as an answer it
# cannot prove harmless (objective hook-answer-proof). A bare echo would read a
# value that starts with "-" (say "-n") as its own option, so leading dashes go
# out one at a time first. Kept identical in command-tokens.sh,
# objective-common.sh and worktree-common.sh: whichever file loads last
# redefines the same body.
_hook_put() {
  local s="${1-}"
  while [[ "$s" == -* ]]; do echo -nE -; s="${s#-}"; done
  echo -nE "$s"
}
_hook_putln() { _hook_put "${1-}"; echo; }

# ------------------------------------------------------------------ layout ---

# Directory (relative to the repo root) that holds objective worktrees.
AGENT_WORKTREE_DIRNAME="${SUPERPOWERS_AGENT_WORKTREE_DIRNAME:-.agent-worktrees}"
# Directory (relative to the repo root) that holds objective state.
OBJECTIVE_STATE_DIRNAME="${SUPERPOWERS_OBJECTIVE_STATE_DIRNAME:-.dev-files/objectives}"

# agent_worktree_root <repo_root>
# Where objective worktrees live. SUPERPOWERS_AGENT_WORKTREE_ROOT relocates them
# outside the repository entirely (the "user-level equivalent" of the layout).
agent_worktree_root() {
  local repo_root="${1:-}"
  if [[ -n "${SUPERPOWERS_AGENT_WORKTREE_ROOT:-}" ]]; then
    _hook_put "${SUPERPOWERS_AGENT_WORKTREE_ROOT%/}"
    return 0
  fi
  [[ -n "$repo_root" ]] || return 1
  _hook_put "${repo_root%/}/${AGENT_WORKTREE_DIRNAME}"
}

objective_state_dir() {
  local repo_root="${1:-}" objective_id="${2:-}"
  [[ -n "$repo_root" ]] || return 1
  if [[ -n "$objective_id" ]]; then
    _hook_put "${repo_root%/}/${OBJECTIVE_STATE_DIRNAME}/${objective_id}"
  else
    _hook_put "${repo_root%/}/${OBJECTIVE_STATE_DIRNAME}"
  fi
}

# objective_worktree_path <repo_root> <objective_id> <unit>
# unit is "integration" or "task-NNN".
objective_worktree_path() {
  local repo_root="$1" objective_id="$2" unit="$3" base
  base="$(agent_worktree_root "$repo_root")" || return 1
  _hook_put "${base}/${objective_id}/${unit}"
}

objective_branch_for() {
  _hook_put "objective/${1-}"
}

# worker_branch_for <objective_id> <index>
# The index is zero-padded to three digits so branch order matches task order;
# an index of 1000 or more prints in full, as a %03d conversion would.
worker_branch_for() {
  local objective_id="$1" index="$2" n padded sign width
  index="${index##task-}"
  n=$((10#${index:-0}))
  sign="" width=3
  if [[ $n -lt 0 ]]; then sign="-" width=2 n=$((0 - n)); fi
  padded="$n"
  while [[ ${#padded} -lt $width ]]; do padded="0${padded}"; done
  _hook_put "worker/${objective_id}/${sign}${padded}"
}

# ------------------------------------------------------------ recognition ---

is_objective_worktree_path() {
  local path="${1%/}"
  [[ -n "$path" ]] || return 1
  case "$path" in
    */"${AGENT_WORKTREE_DIRNAME}"/*) return 0 ;;
  esac
  if [[ -n "${SUPERPOWERS_AGENT_WORKTREE_ROOT:-}" ]]; then
    local root="${SUPERPOWERS_AGENT_WORKTREE_ROOT%/}"
    [[ "$path" == "$root"/* ]] && return 0
  fi
  return 1
}

# Legacy platform-shaped worktrees. Recognized, never created.
is_platform_worktree_path() {
  local path="${1%/}"
  case "$path" in
    */.claude/.worktrees/*|*/.cursor/.worktrees/*|*/.codex/.worktrees/*) return 0 ;;
    *) return 1 ;;
  esac
}

is_objective_branch() {
  case "${1:-}" in objective/?*) return 0 ;; *) return 1 ;; esac
}

is_worker_branch() {
  case "${1:-}" in worker/*/?*) return 0 ;; *) return 1 ;; esac
}

# objective_id_from_branch <branch> — the objective slug carried by an
# objective/* or worker/* branch. Empty for anything else.
objective_id_from_branch() {
  local branch="${1:-}"
  case "$branch" in
    objective/*) _hook_put "${branch#objective/}" ;;
    worker/*/*)  branch="${branch#worker/}"; _hook_put "${branch%/*}" ;;
  esac
}

# classify_worktree_path <dir>
# One of: objective-integration | objective-worker | objective-other |
#         session-global | legacy-global | legacy-platform | native-claude |
#         main-checkout | not-a-repo
#
#   session-global  <configured session root>/<repo>/<slug>  (worktree-common.sh)
#   legacy-global   ~/.claude/worktrees/<repo>/<slug>         (recognised, never created)
#
# ORDER MATTERS where layouts could overlap. An EXPLICIT objective root
# (SUPERPOWERS_AGENT_WORKTREE_ROOT) is checked first: whoever set it said what
# lives there. The configured session root comes next, ahead of the
# `/.agent-worktrees/` name match, so a user who points worktree_root at a path
# that happens to contain that name still gets session worktrees there. The
# default roots never overlap (~/.session-worktrees vs .agent-worktrees).
# Path shape decides the objective classification; branch name refines it. The
# two can disagree (a worker directory checked out on some other branch), and
# when they do the DIRECTORY wins for "is this an agent workspace" while the
# branch only chooses between integration and worker.
classify_worktree_path() {
  local dir="${1:-}" top branch
  [[ -n "$dir" ]] || { printf 'not-a-repo'; return 0; }
  top="$(git -C "$dir" rev-parse --show-toplevel 2>/dev/null)" || { printf 'not-a-repo'; return 0; }
  branch="$(git -C "$dir" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"

  local session_kind=""
  if declare -F session_root_kind >/dev/null 2>/dev/null; then
    session_kind="$(session_root_kind "$top" || true)"
  fi

  if _is_explicit_objective_root_path "$top" \
     || { [[ -z "$session_kind" ]] && is_objective_worktree_path "$top"; }; then
    case "${top##*/}" in
      integration) printf 'objective-integration'; return 0 ;;
      task-*)      printf 'objective-worker'; return 0 ;;
    esac
    if is_objective_branch "$branch"; then printf 'objective-integration'; return 0; fi
    if is_worker_branch "$branch"; then printf 'objective-worker'; return 0; fi
    printf 'objective-other'; return 0
  fi

  if [[ -n "$session_kind" ]]; then _hook_put "$session_kind"; return 0; fi

  if is_platform_worktree_path "$top"; then printf 'legacy-platform'; return 0; fi

  # Without worktree-common.sh (no session_root_kind), fall back to the legacy
  # root. git reports the PHYSICAL path (/private/var/... on macOS) while the
  # root is built from $HOME (/var/... there), so both sides are matched.
  if [[ -z "$session_kind" ]] && ! declare -F session_root_kind >/dev/null 2>/dev/null; then
    local global_root="$HOME/.claude/worktrees" global_root_phys
    global_root_phys="$global_root"
    [[ -d "$global_root" ]] && global_root_phys="$(cd "$global_root" && pwd -P)"
    case "$top" in
      "${global_root}"/*|"${global_root_phys}"/*) printf 'legacy-global'; return 0 ;;
    esac
  fi

  case "$top" in
    */.claude/worktrees/*) printf 'native-claude'; return 0 ;;
  esac
  printf 'main-checkout'
}

# _is_explicit_objective_root_path <path> — under SUPERPOWERS_AGENT_WORKTREE_ROOT,
# in either its logical or its physical spelling (git reports physical paths).
_is_explicit_objective_root_path() {
  local path="${1%/}" root="${SUPERPOWERS_AGENT_WORKTREE_ROOT:-}" root_phys
  [[ -n "$path" && -n "$root" ]] || return 1
  root="${root%/}"
  [[ "$path" == "$root"/* ]] && return 0
  [[ -d "$root" ]] || return 1
  root_phys="$(cd "$root" 2>/dev/null && pwd -P)" || return 1
  [[ "$root_phys" != "$root" && "$path" == "$root_phys"/* ]]
}

# is_agent_workspace <dir> — true for any layout in which repo edits are
# legitimate: the new objective shapes and every legacy shape. Registration is
# checked where it can be (a linked worktree has a .git FILE), but an
# unregistered objective directory still counts: the orchestrator may create the
# directory before `git worktree add` completes, and denying an edit there would
# strand work rather than protect anything.
is_agent_workspace() {
  local dir="${1:-}" kind
  kind="$(classify_worktree_path "$dir")"
  case "$kind" in
    objective-integration|objective-worker|objective-other) return 0 ;;
    session-global|legacy-platform|legacy-global|native-claude) return 0 ;;
    *) return 1 ;;
  esac
}

# ------------------------------------------------------- active objective ---

# active_objective_id <cwd>
# An objective is "active" when the orchestrator says so via
# SUPERPOWERS_OBJECTIVE_ID, or when a checked-in/local objective.json with
# status "active" exists under .dev-files/objectives/. Prints the id; returns 1
# when no objective is active.
active_objective_id() {
  local cwd="${1:-$PWD}" repo_root state_dir f id status

  if [[ -n "${SUPERPOWERS_OBJECTIVE_ID:-}" ]]; then
    _hook_put "$SUPERPOWERS_OBJECTIVE_ID"
    return 0
  fi

  repo_root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || return 1
  # Inside an objective worktree, the objective state lives in the MAIN
  # checkout, not in the linked worktree's own tree.
  local common_root
  common_root="$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [[ -n "$common_root" ]]; then
    common_root="$(dirname "$common_root")"
    [[ -d "$common_root" ]] && repo_root="$common_root"
  fi

  state_dir="$(objective_state_dir "$repo_root")" || return 1
  [[ -d "$state_dir" ]] || return 1

  for f in "$state_dir"/*/objective.json; do
    [[ -f "$f" ]] || continue
    status="$(jq -r '.status // empty' "$f" 2>/dev/null || true)"
    [[ "$status" == "active" ]] || continue
    id="$(jq -r '.id // empty' "$f" 2>/dev/null || true)"
    [[ -n "$id" ]] || id="$(basename "$(dirname "$f")")"
    _hook_put "$id"
    return 0
  done
  return 1
}

# active_objective_dir <cwd> — the state directory of the active objective, resolved
# the way active_objective_id resolves it: from the MAIN checkout even when <cwd> is a
# linked worker worktree (where .dev-files/objectives does not exist), honouring
# SUPERPOWERS_OBJECTIVE_ID, and never "the first directory find happens to list".
# Prints nothing and returns 1 when no objective is active.
active_objective_dir() {
  local cwd="${1:-$PWD}" id repo_root common_root
  id="$(active_objective_id "$cwd")" || return 1
  repo_root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || repo_root="$cwd"
  common_root="$(git -C "$cwd" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  if [[ -n "$common_root" ]]; then
    common_root="$(dirname "$common_root")"
    [[ -d "$common_root" ]] && repo_root="$common_root"
  fi
  objective_state_dir "$repo_root" "$id"
}

objective_is_active() {
  active_objective_id "${1:-$PWD}" >/dev/null 2>/dev/null
}

# ---------------------------------------------------------------- listing ---

# list_agent_worktrees <repo_root>
# Emits "layout<TAB>path<TAB>branch" for every git worktree of this repo that
# belongs to any agent layout, old or new. This is the migration/inventory
# surface: it answers "what exists" across both models without moving anything.
list_agent_worktrees() {
  local repo_root="${1:-$PWD}" path="" branch="" kind
  git -C "$repo_root" worktree list --porcelain 2>/dev/null | while IFS= read -r line; do
    case "$line" in
      "worktree "*) path="${line#worktree }" ;;
      "branch "*)   branch="${line#branch }"; branch="${branch#refs/heads/}" ;;
      "detached")   branch="(detached)" ;;
      "")
        if [[ -n "$path" ]]; then
          kind="$(classify_worktree_path "$path")"
          [[ "$kind" != "main-checkout" && "$kind" != "not-a-repo" ]] \
            && _hook_putln "${kind}"$'\t'"${path}"$'\t'"${branch}"
        fi
        path=""; branch=""
        ;;
    esac
  done
  # `git worktree list --porcelain` ends with a blank line, so the final record
  # is flushed by the loop above; nothing to drain here.
}
