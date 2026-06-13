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

# Copy gitignored files matching a pattern from the repo into the worktree.
# Tracked files already exist in the worktree via git; .worktreeinclude exists
# to bring across gitignored files (.env.local, credentials, build caches).
# Supports a trailing-slash directory pattern, a single file, or a glob.
copy_pattern_if_gitignored() {
  local repo_root="$1"
  local worktree_path="$2"
  local pattern="$3"
  local rel

  if [[ "$pattern" == */ ]]; then
    pattern="${pattern%/}"
    while IFS= read -r rel; do
      [[ -z "$rel" ]] && continue
      mkdir -p "$(dirname "${worktree_path}/${rel}")"
      cp -f "${repo_root}/${rel}" "${worktree_path}/${rel}" 2>/dev/null || true
    done < <(git -C "$repo_root" ls-files -oi --exclude-standard -- "${pattern}" "${pattern}/**" 2>/dev/null || true)
    return 0
  fi

  if [[ -f "${repo_root}/${pattern}" ]] && git -C "$repo_root" check-ignore -q "$pattern" 2>/dev/null; then
    mkdir -p "$(dirname "${worktree_path}/${pattern}")"
    cp -f "${repo_root}/${pattern}" "${worktree_path}/${pattern}" 2>/dev/null || true
    return 0
  fi

  while IFS= read -r rel; do
    [[ -z "$rel" ]] && continue
    mkdir -p "$(dirname "${worktree_path}/${rel}")"
    cp -f "${repo_root}/${rel}" "${worktree_path}/${rel}" 2>/dev/null || true
  done < <(git -C "$repo_root" ls-files -oi --exclude-standard -- "$pattern" 2>/dev/null || true)
}

# Apply .worktreeinclude patterns. Reads global defaults first
# (~/.claude/defaults/worktreeinclude), then the repo-level .worktreeinclude,
# so a repo can extend the global set.
copy_worktreeinclude_files() {
  local repo_root="$1"
  local worktree_path="$2"
  local include_file

  for include_file in "${HOME}/.claude/defaults/worktreeinclude" "${repo_root}/.worktreeinclude"; do
    [[ -f "$include_file" ]] || continue
    while IFS= read -r pattern || [[ -n "$pattern" ]]; do
      [[ -z "$pattern" || "$pattern" =~ ^[[:space:]]*# ]] && continue
      pattern="${pattern%%#*}"
      pattern="$(echo "$pattern" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
      [[ -z "$pattern" ]] && continue
      copy_pattern_if_gitignored "$repo_root" "$worktree_path" "$pattern"
    done < "$include_file"
  done
}

# Deterministic dev-server port (3100-9999) derived from the branch name, so
# parallel worktrees don't collide on the same port.
hash_port_for_branch() {
  local branch="$1"
  local hash
  hash="$(printf '%s' "$branch" | md5 2>/dev/null | tr -dc '0-9' | head -c 5)"
  if [[ -z "$hash" ]]; then
    hash="$(printf '%s' "$branch" | cksum | tr -dc '0-9' | head -c 5)"
  fi
  echo $(( (10#${hash:-12345} % 6900) + 3100 ))
}

# Write a per-worktree DEV_PORT into .env.local (without clobbering an existing one).
# Only writes when .env.local is gitignored or already exists — avoids leaving an
# untracked file that would block cleanup_stale_worktrees' porcelain check.
write_worktree_env_local() {
  local worktree_path="$1"
  local branch_name="$2"
  local port
  port="$(hash_port_for_branch "$branch_name")"

  local env_local="${worktree_path}/.env.local"
  if [[ -f "$env_local" ]]; then
    grep -q '^DEV_PORT=' "$env_local" 2>/dev/null || echo "DEV_PORT=${port}" >> "$env_local"
  elif git -C "$worktree_path" check-ignore -q .env.local 2>/dev/null; then
    echo "DEV_PORT=${port}" > "$env_local"
  fi
}

# Install dependencies in a freshly created worktree, matching the project's
# package manager. Skips when node_modules is already present (e.g. symlinked).
# Logs to .session-files/worktree-setup.log; never fatal to the caller.
run_worktree_post_setup() {
  local worktree_path="$1"
  local logfile="${worktree_path}/.session-files/worktree-setup.log"
  mkdir -p "$(dirname "$logfile")"
  local stamp errors=()
  stamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  if [[ -L "${worktree_path}/node_modules" || -d "${worktree_path}/node_modules" ]]; then
    echo "${stamp} node_modules present (native symlink or existing install)" >> "$logfile"
    return 0
  fi

  if [[ -f "${worktree_path}/package.json" ]]; then
    if [[ -f "${worktree_path}/yarn.lock" ]]; then
      echo "${stamp} yarn install" >> "$logfile"
      (cd "$worktree_path" && yarn install --immutable >> "$logfile" 2>&1) || errors+=("yarn install")
    elif [[ -f "${worktree_path}/package-lock.json" ]]; then
      echo "${stamp} npm ci" >> "$logfile"
      (cd "$worktree_path" && npm ci >> "$logfile" 2>&1) || errors+=("npm ci")
    elif [[ -f "${worktree_path}/pnpm-lock.yaml" ]]; then
      echo "${stamp} pnpm install" >> "$logfile"
      (cd "$worktree_path" && pnpm install --frozen-lockfile >> "$logfile" 2>&1) || errors+=("pnpm install")
    fi
  fi

  if [[ -f "${worktree_path}/pyproject.toml" && ! -d "${worktree_path}/.venv" ]] && command -v poetry >/dev/null 2>&1; then
    echo "${stamp} poetry install" >> "$logfile"
    (cd "$worktree_path" && poetry install >> "$logfile" 2>&1) || errors+=("poetry install")
  fi

  if ((${#errors[@]})); then
    echo "setup errors: ${errors[*]}" >> "$logfile"
    return 1
  fi
  return 0
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
    mtime="$(stat -c %Y "$wt_dir" 2>/dev/null || stat -f %m "$wt_dir" 2>/dev/null || echo 0)"
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

# Prune archived session-files older than WORKTREE_RETENTION_DAYS.
prune_session_files_archive() {
  [[ -d "$SESSION_FILES_ARCHIVE" ]] || return 0

  local cutoff_epoch
  cutoff_epoch="$(date -v-"${WORKTREE_RETENTION_DAYS}"d +%s 2>/dev/null || date -d "${WORKTREE_RETENTION_DAYS} days ago" +%s)"

  find "$SESSION_FILES_ARCHIVE" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | while read -r dir; do
    local mtime
    mtime="$(stat -c %Y "$dir" 2>/dev/null || stat -f %m "$dir" 2>/dev/null || echo 0)"
    [[ "$mtime" -lt "$cutoff_epoch" ]] && rm -rf "$dir"
  done
}
