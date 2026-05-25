#!/usr/bin/env bash
# Shared helpers for Make-worktree-in-~/.claude/worktrees session workflow.

WORKTREE_ROOT="${HOME}/.claude/worktrees"
SESSION_STATE_DIR="${HOME}/.claude/session-state"
SESSION_FILES_ARCHIVE="${HOME}/.claude/session-files"
WORKTREE_RETENTION_DAYS="${WORKTREE_RETENTION_DAYS:-3}"

slugify_text() {
  local text="$1"
  local max_len="${2:-48}"
  echo "$text" \
    | tr '[:upper:]' '[:lower:]' \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
    | sed -E 's/[^a-z0-9]+/-/g; s/-+/-/g; s/^-//; s/-$//' \
    | cut -c1-"$max_len" \
    | sed -E 's/-+$//'
}

session_state_path() {
  local session_id="$1"
  echo "${SESSION_STATE_DIR}/${session_id}.json"
}

load_session_state() {
  local session_id="$1"
  local path
  path="$(session_state_path "$session_id")"
  if [[ -f "$path" ]]; then
    cat "$path"
  else
    echo '{}'
  fi
}

save_session_state() {
  local session_id="$1"
  local json="$2"
  mkdir -p "$SESSION_STATE_DIR"
  echo "$json" > "$(session_state_path "$session_id")"
}

is_git_repo() {
  local dir="${1:-.}"
  git -C "$dir" rev-parse --git-dir >/dev/null 2>&1
}

repo_root_for() {
  local dir="$1"
  git -C "$dir" rev-parse --show-toplevel 2>/dev/null
}

repo_name_for() {
  basename "$(repo_root_for "$1")"
}

is_global_worktree_path() {
  local path="$1"
  [[ "$path" == "${WORKTREE_ROOT}/"* ]]
}

worktree_path_for() {
  local repo_name="$1"
  local task_slug="$2"
  echo "${WORKTREE_ROOT}/${repo_name}/${task_slug}"
}

branch_name_for() {
  local task_slug="$1"
  echo "wt/${task_slug}"
}

resolve_worktree_base_ref() {
  local repo_root="$1"
  local base_ref="${CLAUDE_WORKTREE_BASE_REF:-fresh}"

  if [[ "$base_ref" == "head" ]]; then
    git -C "$repo_root" rev-parse HEAD
    return
  fi

  local default_branch
  default_branch="$(git -C "$repo_root" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null | sed 's|^refs/remotes/origin/||')"
  if [[ -n "$default_branch" ]] && git -C "$repo_root" rev-parse "origin/${default_branch}" >/dev/null 2>&1; then
    echo "origin/${default_branch}"
    return
  fi

  git -C "$repo_root" rev-parse HEAD
}

copy_worktreeinclude_files() {
  local repo_root="$1"
  local worktree_path="$2"
  local include_file="${repo_root}/.worktreeinclude"

  [[ -f "$include_file" ]] || return 0

  while IFS= read -r pattern || [[ -n "$pattern" ]]; do
    [[ -z "$pattern" || "$pattern" =~ ^[[:space:]]*# ]] && continue
    pattern="${pattern%%#*}"
    pattern="$(echo "$pattern" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
    [[ -z "$pattern" ]] && continue

    local src="${repo_root}/${pattern}"
    if [[ -f "$src" ]]; then
      mkdir -p "$(dirname "${worktree_path}/${pattern}")"
      cp -f "$src" "${worktree_path}/${pattern}" 2>/dev/null || true
    fi
  done < "$include_file"
}

ensure_session_files_dir() {
  local target_dir="$1"
  mkdir -p "$target_dir"
  echo "$target_dir"
}

sync_session_files_archive() {
  local source_dir="$1"
  local session_name="$2"
  local archive_dir="${SESSION_FILES_ARCHIVE}/${session_name}"

  [[ -d "$source_dir" ]] || return 0
  mkdir -p "$archive_dir"
  rsync -a --delete "${source_dir}/" "${archive_dir}/" 2>/dev/null \
    || cp -R "${source_dir}/." "${archive_dir}/" 2>/dev/null \
    || true
}

read_session_files_context() {
  local session_files_dir="$1"
  local max_files="${2:-20}"

  [[ -d "$session_files_dir" ]] || return 0

  local count=0
  while IFS= read -r file; do
    [[ -f "$file" ]] || continue
    count=$((count + 1))
    [[ "$count" -gt "$max_files" ]] && break
    echo ""
    echo "### ${file}"
    echo '```'
    head -n 200 "$file"
    local lines
    lines="$(wc -l < "$file" | tr -d ' ')"
    if [[ "$lines" -gt 200 ]]; then
      echo ""
      echo "... truncated ($(("$lines" - 200)) more lines) ..."
    fi
    echo '```'
  done < <(find "$session_files_dir" -type f \( -name '*.md' -o -name '*.txt' \) | sort)
}

append_env_exports() {
  local env_file="$1"
  shift
  [[ -n "$env_file" ]] || return 0
  while (($#)); do
    echo "export $1" >> "$env_file"
    shift
  done
}

cleanup_stale_worktrees() {
  local cutoff_epoch
  cutoff_epoch="$(date -v-"${WORKTREE_RETENTION_DAYS}"d +%s 2>/dev/null || date -d "${WORKTREE_RETENTION_DAYS} days ago" +%s)"

  find "$WORKTREE_ROOT" -mindepth 2 -maxdepth 2 -type d 2>/dev/null | while read -r wt_dir; do
    [[ -d "$wt_dir/.git" || -f "$wt_dir/.git" ]] || continue

    local mtime
    mtime="$(stat -f %m "$wt_dir" 2>/dev/null || stat -c %Y "$wt_dir" 2>/dev/null || echo 0)"
    [[ "$mtime" -lt "$cutoff_epoch" ]] || continue

    if [[ -n "$(git -C "$wt_dir" status --porcelain 2>/dev/null)" ]]; then
      continue
    fi

    local repo_root
    repo_root="$(git -C "$wt_dir" rev-parse --show-toplevel 2>/dev/null || true)"
    if [[ -n "$repo_root" && "$repo_root" != "$wt_dir" ]]; then
      git -C "$(dirname "$repo_root")" worktree remove "$wt_dir" --force 2>/dev/null \
        || rm -rf "$wt_dir"
    else
      rm -rf "$wt_dir"
    fi
  done
}
