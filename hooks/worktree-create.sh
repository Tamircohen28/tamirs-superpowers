#!/usr/bin/env bash
set -euo pipefail

# WorktreeCreate hook — and, when invoked with arguments, the worktree CLI.
#
# TWO CALLERS, ONE FILE
#   With no arguments it is a hook: it reads the WorktreeCreate JSON payload on
#   stdin and behaves exactly as before. With arguments it is a command an agent
#   or a human can run — `--list`, `--migrate`, or an explicit objective/unit
#   create. The argument form NEVER reads stdin, so it cannot hang when invoked
#   from a script, a CI step, or a non-tty context.
#
# TWO LAYOUTS, NEITHER DESTROYED
#   Legacy:    ~/.claude/worktrees/<repo>/<task-slug>        branch wt/<slug>
#   Objective: <repo>/.agent-worktrees/<objective>/<unit>    branch objective/<slug>
#                                                            or worker/<slug>/NNN
#   The objective layout is used when an objective is active or explicitly
#   named; otherwise the legacy layout is used unchanged. Nothing migrates
#   automatically — `--migrate` prints the commands and does not run them,
#   because moving a worktree out from under a running agent is exactly the
#   destructive directory migration this refactor forbids.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/worktree-common.sh
source "${SCRIPT_DIR}/lib/worktree-common.sh"
# shellcheck source=lib/objective-common.sh
source "${SCRIPT_DIR}/lib/objective-common.sh"
# shellcheck source=lib/hook-output.sh
source "${SCRIPT_DIR}/lib/hook-output.sh"

usage() {
  cat <<'EOF'
worktree-create.sh — create or inventory agent worktrees

  (no arguments)                 WorktreeCreate hook; reads JSON on stdin
  --list [--repo <dir>]          list every agent worktree, both layouts
  --migrate [--repo <dir>]       print (do NOT run) commands to move legacy
                                 worktrees into the objective layout
  --objective <id> --unit <u>    create <repo>/.agent-worktrees/<id>/<u>
                                 <u> is "integration" or "task-NNN"
  --repo <dir>                   repository to act on (default: cwd)
  -h, --help                     this text

Environment:
  SUPERPOWERS_OBJECTIVE_ID              active objective; makes the hook path
                                        create objective worktrees
  SUPERPOWERS_AGENT_WORKTREE_ROOT       relocate .agent-worktrees elsewhere
  SUPERPOWERS_WORKTREE_INSTALL_DEPS     0/false to skip dependency installs
  SUPERPOWERS_MAX_CONCURRENT_INSTALLS   cap on simultaneous installers (default 2)
EOF
}

# create_objective_worktree <repo_root> <objective_id> <unit>
# Prints the created (or already-existing) path.
create_objective_worktree() {
  local repo_root="$1" objective_id="$2" unit="$3" path branch

  path="$(objective_worktree_path "$repo_root" "$objective_id" "$unit")"
  case "$unit" in
    integration) branch="$(objective_branch_for "$objective_id")" ;;
    task-*)      branch="$(worker_branch_for "$objective_id" "${unit#task-}")" ;;
    *)
      echo "worktree-create: unit must be 'integration' or 'task-NNN' (got '${unit}')" >&2
      return 1
      ;;
  esac

  mkdir -p "$(dirname "$path")"

  # A worker branches off the objective's integration branch when it exists, so
  # workers compose against each other's base rather than against stale main.
  local base
  if [[ "$unit" == integration ]]; then
    base="$(resolve_worktree_base_ref "$repo_root")"
  elif git -C "$repo_root" rev-parse --verify --quiet "refs/heads/$(objective_branch_for "$objective_id")" >/dev/null 2>&1; then
    base="$(objective_branch_for "$objective_id")"
  else
    base="$(resolve_worktree_base_ref "$repo_root")"
  fi

  if [[ -d "$path" ]]; then
    if ! git -C "$repo_root" worktree list --porcelain \
         | awk -v p="$path" '/^worktree /{if($2==p) found=1} END{exit !found}'; then
      rm -rf "$path"
      git -C "$repo_root" worktree add -B "$branch" "$path" "$base" >&2
    fi
  else
    git -C "$repo_root" worktree add -B "$branch" "$path" "$base" >&2
  fi

  copy_worktreeinclude_files "$repo_root" "$path"
  write_worktree_env_local "$path" "$branch" 2>/dev/null || true
  ( run_worktree_post_setup "$path" >/dev/null 2>&1 & )

  printf '%s' "$path"
}

# ------------------------------------------------------------- CLI form ---

if (($#)); then
  mode=""
  repo_arg="$PWD"
  objective_id=""
  unit=""
  while (($#)); do
    case "$1" in
      --list)      mode=list ;;
      --migrate)   mode=migrate ;;
      --objective) objective_id="${2:-}"; shift ;;
      --unit)      unit="${2:-}"; shift ;;
      --repo)      repo_arg="${2:-}"; shift ;;
      -h|--help)   usage; exit 0 ;;
      *) echo "worktree-create: unknown argument '$1'" >&2; usage >&2; exit 2 ;;
    esac
    shift
  done

  if ! is_git_repo "$repo_arg"; then
    echo "worktree-create: not a git repository: ${repo_arg}" >&2
    exit 1
  fi
  repo_root="$(repo_root_for "$repo_arg")"

  case "$mode" in
    list)
      printf '%-22s %-60s %s\n' LAYOUT PATH BRANCH
      list_agent_worktrees "$repo_root" | while IFS=$'\t' read -r kind path branch; do
        printf '%-22s %-60s %s\n' "$kind" "$path" "${branch:-(none)}"
      done
      exit 0
      ;;
    migrate)
      # Printed, never executed. A legacy worktree may have a live agent in it
      # and uncommitted work in its tree; only a human (or the orchestrator that
      # owns the objective) can decide when moving it is safe.
      target_objective="${objective_id:-$(active_objective_id "$repo_root" 2>/dev/null || echo '<objective-id>')}"
      echo "# Migration plan for ${repo_root}"
      echo "# Review each line before running it. Nothing below has been executed."
      echo "# A worktree with uncommitted changes is listed but must be committed first."
      n=0
      list_agent_worktrees "$repo_root" | while IFS=$'\t' read -r kind path branch; do
        case "$kind" in
          legacy-global|legacy-platform|native-claude) ;;
          *) continue ;;
        esac
        n=$((n + 1))
        dirty=""
        [[ -n "$(git -C "$path" status --porcelain 2>/dev/null || true)" ]] && dirty="   # DIRTY — commit or stash first"
        printf '\n# %s (%s) on %s%s\n' "$path" "$kind" "${branch:-detached}" "$dirty"
        printf 'git -C %q worktree move %q %q\n' "$repo_root" "$path" \
          "$(objective_worktree_path "$repo_root" "$target_objective" "task-$(printf '%03d' "$n")")"
        printf 'git -C %q branch -m %q %q\n' "$repo_root" "${branch:-HEAD}" \
          "$(worker_branch_for "$target_objective" "$n")"
      done
      exit 0
      ;;
    "")
      if [[ -z "$objective_id" || -z "$unit" ]]; then
        echo "worktree-create: --objective and --unit are both required" >&2
        usage >&2
        exit 2
      fi
      create_objective_worktree "$repo_root" "$objective_id" "$unit"
      echo
      exit 0
      ;;
  esac
fi

# ------------------------------------------------------------ hook form ---

input="$(hook_read_stdin)"
session_id="$(echo "$input" | jq -r '.session_id // empty')"
requested_name="$(echo "$input" | jq -r '.name // empty')"
cwd="$(echo "$input" | jq -r '.cwd // empty')"

if [[ -z "$cwd" ]]; then
  echo "WorktreeCreate: missing cwd" >&2
  exit 1
fi
if ! is_git_repo "$cwd"; then
  echo "WorktreeCreate: not a git repository: ${cwd}" >&2
  exit 1
fi

repo_root="$(repo_root_for "$cwd")"
repo_name="$(repo_name_for "$cwd")"

state="$(load_session_state "$session_id")"
# Re-slugify on read — state files poisoned with multi-line slugs self-heal.
task_slug="$(slugify_text "$(echo "$state" | jq -r '.task_slug // empty')" 48)"

if [[ -z "$task_slug" || "$task_slug" == "null" ]]; then
  task_slug="$(slugify_text "$requested_name" 48)"
fi

if [[ -z "$task_slug" ]]; then
  echo "WorktreeCreate: could not derive task slug" >&2
  exit 1
fi

# When an objective is active, an explicit WorktreeCreate still means "give me a
# workspace" — but it must be a workspace of the objective, not a competing
# wt/<slug> tree beside it. SUPERPOWERS_TASK_UNIT names the unit when the
# orchestrator knows it; otherwise the next free task-NNN is taken.
objective_id="$(active_objective_id "$cwd" 2>/dev/null || true)"

if [[ -n "$objective_id" ]]; then
  unit="${SUPERPOWERS_TASK_UNIT:-}"
  if [[ -z "$unit" ]]; then
    base_dir="$(agent_worktree_root "$repo_root")/${objective_id}"
    idx=1
    while [[ -d "${base_dir}/$(printf 'task-%03d' "$idx")" ]]; do
      idx=$((idx + 1))
    done
    unit="$(printf 'task-%03d' "$idx")"
  fi
  worktree_path="$(create_objective_worktree "$repo_root" "$objective_id" "$unit")"
  case "$unit" in
    integration) branch_name="$(objective_branch_for "$objective_id")" ;;
    *)           branch_name="$(worker_branch_for "$objective_id" "${unit#task-}")" ;;
  esac
  session_files_dir="$(ensure_session_files_dir "${worktree_path}/session-files")"
else
  worktree_path="$(worktree_path_for "$repo_name" "$task_slug")"
  branch_name="$(branch_name_for "$task_slug")"
  session_files_dir="$(ensure_session_files_dir "${worktree_path}/session-files")"

  mkdir -p "${WORKTREE_ROOT}/${repo_name}"

  if [[ -d "$worktree_path" ]]; then
    if ! git -C "$repo_root" worktree list --porcelain | awk -v p="$worktree_path" '/^worktree /{if($2==p) found=1} END{exit !found}'; then
      rm -rf "$worktree_path"
      git -C "$repo_root" worktree add -B "$branch_name" "$worktree_path" "$(resolve_worktree_base_ref "$repo_root")" >&2
    fi
  else
    git -C "$repo_root" worktree add -B "$branch_name" "$worktree_path" "$(resolve_worktree_base_ref "$repo_root")" >&2
  fi

  copy_worktreeinclude_files "$repo_root" "$worktree_path"
  write_worktree_env_local "$worktree_path" "$branch_name" 2>/dev/null || true
  # Install deps in the background so a slow npm/yarn install never blocks the hook timeout.
  ( run_worktree_post_setup "$worktree_path" >/dev/null 2>&1 & )
fi

now_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
state="$(echo "$state" | jq \
  --arg session_id "$session_id" \
  --arg repo_root "$repo_root" \
  --arg repo_name "$repo_name" \
  --arg task_slug "$task_slug" \
  --arg worktree_path "$worktree_path" \
  --arg session_files_dir "$session_files_dir" \
  --arg branch_name "$branch_name" \
  --arg objective_id "$objective_id" \
  --arg now "$now_iso" \
  '. + {
    session_id: $session_id,
    repo_root: $repo_root,
    repo_name: $repo_name,
    task_slug: $task_slug,
    worktree_path: $worktree_path,
    session_files_dir: $session_files_dir,
    branch_name: $branch_name,
    objective_id: (if ($objective_id | length) > 0 then $objective_id else null end),
    updated_at: $now
  } | if .created_at == null then .created_at = $now else . end')"

save_session_state "$session_id" "$state"
echo "$worktree_path"
