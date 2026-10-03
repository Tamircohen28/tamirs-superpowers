#!/usr/bin/env bash
set -euo pipefail

# SessionEnd — archive session files and prune stale worktrees.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/worktree-common.sh
source "${SCRIPT_DIR}/lib/worktree-common.sh"
# shellcheck source=lib/hook-output.sh
source "${SCRIPT_DIR}/lib/hook-output.sh"

input="$(hook_read_stdin)"
session_id="$(echo "$input" | jq -r '.session_id // empty')"

# Archive session files to persistent store
state="$(load_session_state "$session_id")"
session_files_dir="$(echo "$state" | jq -r '.session_files_dir // empty')"
session_slug="$(echo "$state" | jq -r '.session_slug // empty')"

# Claude Code cancels SessionEnd hooks after 1.5 s regardless of the `timeout`
# declared in hooks.json, and every SessionEnd hook runs concurrently at the
# moment the machine is busiest (the session tearing down). None of the work
# below produces output anyone reads, so it runs detached: the hook answers in
# milliseconds and the rsync/prune finish on their own time. Same pattern, and
# same reason for closing the inherited descriptors, as cleanup_stale_worktrees.
(
  if [[ -n "$session_files_dir" && -d "$session_files_dir" && -n "$session_slug" ]]; then
    sync_session_files_archive "$session_files_dir" "$session_slug" || true
  fi

  # Prune stale worktrees (older than WORKTREE_RETENTION_DAYS, no uncommitted changes)
  cleanup_stale_worktrees || true

  # Prune archived session-files past retention
  prune_session_files_archive || true
) </dev/null >/dev/null 2>&1 &
disown 2>/dev/null || true

echo '{"suppressOutput": true}'
