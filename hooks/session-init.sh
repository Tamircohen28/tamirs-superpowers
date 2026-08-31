#!/usr/bin/env bash
set -euo pipefail

# SessionStart — initialize session dirs, load prior session-files, prune stale worktrees.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/worktree-common.sh
source "${SCRIPT_DIR}/lib/worktree-common.sh"
# shellcheck source=lib/hook-output.sh
source "${SCRIPT_DIR}/lib/hook-output.sh"

input="$(hook_read_stdin)"
session_id="$(echo "$input" | jq -r '.session_id // empty')"
cwd="$(echo "$input" | jq -r '.cwd // empty')"
source_kind="$(echo "$input" | jq -r '.source // "startup"')"
# Claude Code 2.1.251+: resume/fork payloads add these four fields describing
# how stale the resumed transcript's prompt cache is. Absent on every other
# source (startup, clear, compact) and on pre-2.1.251 hosts, where the `//
# empty` fallback leaves them blank and the staleness note below never fires.
prompt_cache_likely_expired="$(echo "$input" | jq -r '.prompt_cache_likely_expired // empty')"
context_tokens="$(echo "$input" | jq -r '.context_tokens // empty')"
estimated_cache_write_usd="$(echo "$input" | jq -r '.estimated_cache_write_usd // empty')"

cleanup_stale_worktrees >/dev/null 2>&1 || true

state="$(load_session_state "$session_id")"
# Sanitize values read back from state: files written before slugify_text
# stripped newlines can carry multi-line slugs/paths — re-slugify the slug and
# discard any path with an embedded newline so it gets recomputed cleanly.
task_slug="$(slugify_text "$(echo "$state" | jq -r '.task_slug // empty')" 48)"
worktree_path="$(echo "$state" | jq -r '.worktree_path // empty')"
case "$worktree_path" in *$'\n'*) worktree_path="" ;; esac
session_files_dir="$(echo "$state" | jq -r '.session_files_dir // empty')"
case "$session_files_dir" in *$'\n'*) session_files_dir="" ;; esac
session_slug="$(echo "$state" | jq -r '.session_slug // empty')"
case "$session_slug" in *$'\n'*) session_slug="" ;; esac

short_id="${session_id:0:8}"
date_stamp="$(date +%Y-%m-%d)"

if [[ -n "$task_slug" && "$task_slug" != "null" ]]; then
  slug="${task_slug}"
elif [[ -n "$session_slug" && "$session_slug" != "null" ]]; then
  slug="${session_slug}"
else
  # Compose from the parts that actually carry information, rather than
  # interpolating every slot unconditionally. `basename ""` is empty and
  # `${session_id:0:8}` is empty without a session, so the unconditional form
  # yielded names like "2026-08-19__" — a directory, and a repointed `_latest`
  # symlink, standing for nothing. Same shape as the `wt/session-` leak: a
  # placeholder assembled around missing values. Degrading to just the date is
  # coarse but honest; it never invents an identity that was not supplied.
  cwd_slug="$(basename "$cwd" | tr -c 'A-Za-z0-9' '-' | sed 's/-\+/-/g; s/^-//; s/-$//')"
  slug="${date_stamp}"
  if [[ -n "$cwd_slug" ]]; then
    slug="${slug}_${cwd_slug}"
  fi
  if [[ -n "$short_id" ]]; then
    slug="${slug}_${short_id}"
  fi
fi

output_dir="${HOME}/.claude/outputs/${slug}"
mkdir -p "$output_dir"

if is_git_repo "$cwd"; then
  repo_root="$(repo_root_for "$cwd")"
  repo_name="$(repo_name_for "$cwd")"

  if is_global_worktree_path "$cwd"; then
    session_files_dir="$(ensure_session_files_dir "${cwd}/session-files")"
    worktree_path="$cwd"
  elif [[ -n "$worktree_path" && "$worktree_path" != "null" && -d "$worktree_path" ]]; then
    session_files_dir="$(ensure_session_files_dir "${worktree_path}/session-files")"
  elif [[ -n "$task_slug" && "$task_slug" != "null" ]]; then
    worktree_path="$(worktree_path_for "$repo_name" "$task_slug")"
    session_files_dir="$(ensure_session_files_dir "${worktree_path}/session-files")"
  else
    session_files_dir="$(ensure_session_files_dir "${output_dir}/session-files")"
    sync_session_files_archive "$session_files_dir" "$slug"
  fi
else
  session_files_dir="$(ensure_session_files_dir "${output_dir}/session-files")"
  sync_session_files_archive "$session_files_dir" "$slug"
fi

cat > "${output_dir}/.session.json" <<EOF
{
  "session_id": "${session_id}",
  "cwd": "${cwd}",
  "source": "${source_kind}",
  "task_slug": "${task_slug}",
  "worktree_path": "${worktree_path}",
  "session_files_dir": "${session_files_dir}",
  "started_at": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF

ln -sfn "$output_dir" "${HOME}/.claude/outputs/_latest"

state="$(echo "$state" | jq \
  --arg session_id "$session_id" \
  --arg slug "$slug" \
  --arg output_dir "$output_dir" \
  --arg session_files_dir "$session_files_dir" \
  --arg worktree_path "$worktree_path" \
  --arg source_kind "$source_kind" \
  --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '. + {
    session_id: $session_id,
    session_slug: $slug,
    output_dir: $output_dir,
    session_files_dir: $session_files_dir,
    worktree_path: (if ($worktree_path | length) > 0 then $worktree_path else .worktree_path // "" end),
    last_source: $source_kind,
    updated_at: $now
  } | if .created_at == null then .created_at = $now else . end')"

save_session_state "$session_id" "$state"

if [[ -n "${CLAUDE_ENV_FILE:-}" ]]; then
  append_env_exports "$CLAUDE_ENV_FILE" \
    "CLAUDE_OUTPUT_DIR=\"${output_dir}\"" \
    "CLAUDE_SESSION_SLUG=\"${slug}\"" \
    "CLAUDE_SESSION_FILES_DIR=\"${session_files_dir}\"" \
    "CLAUDE_WORKTREE_ROOT=\"${WORKTREE_ROOT}\"" \
    "CLAUDE_WORKTREE_RETENTION_DAYS=\"${WORKTREE_RETENTION_DAYS}\""

  if [[ -n "$worktree_path" && "$worktree_path" != "null" ]]; then
    echo "export CLAUDE_WORKTREE_PATH=\"${worktree_path}\"" >> "$CLAUDE_ENV_FILE"
  fi

  if [[ -n "$task_slug" && "$task_slug" != "null" ]]; then
    echo "export CLAUDE_TASK_SLUG=\"${task_slug}\"" >> "$CLAUDE_ENV_FILE"
  fi
fi

context_parts=()
context_parts+=("Session output dir: ${output_dir}")
context_parts+=("Session files dir: ${session_files_dir} — use CLAUDE_SESSION_FILES_DIR for plans, reviews, investigations")

if is_git_repo "$cwd"; then
  context_parts+=("Worktree policy: every repo task runs in ~/.claude/worktrees/<repo>/<task-slug>. Never edit the main checkout.")
  if [[ -n "$worktree_path" && "$worktree_path" != "null" && -d "$worktree_path" ]]; then
    if [[ "$cwd" != "$worktree_path" ]]; then
      context_parts+=("Resumed session worktree exists at: ${worktree_path}. cd there or use EnterWorktree before editing.")
    else
      context_parts+=("Working in worktree: ${worktree_path}")
    fi
  fi
fi

# Claude Code 2.1.214+: forked sessions report source "fork" (previously
# "resume"), so treat both as continuations that should reload session-files.
if [[ -d "$session_files_dir" ]] && { [[ "$source_kind" == "resume" || "$source_kind" == "fork" ]] || [[ -n "$task_slug" && "$task_slug" != "null" ]]; }; then
  files_context="$(read_session_files_context "$session_files_dir")"
  if [[ -n "$files_context" ]]; then
    context_parts+=("Prior session files from ${session_files_dir}:")
    context_parts+=("$files_context")
  fi
fi

# Claude Code 2.1.251+: surface the re-cache warning up front rather than
# leaving it to be inferred from an unexplained cost/latency spike on the
# first turn back. `prompt_cache_likely_expired` is the host's own judgment
# (seconds_since_last_response measured against the model's cache TTL); the
# token count and cost estimate are best-effort detail, not required to warn.
if [[ "$prompt_cache_likely_expired" == "true" ]]; then
  staleness_note="Resumed session's prompt cache has likely expired — the next request re-caches context from scratch"
  detail=""
  if [[ -n "$context_tokens" && "$context_tokens" != "null" ]]; then
    detail="~${context_tokens} tokens"
  fi
  if [[ -n "$estimated_cache_write_usd" && "$estimated_cache_write_usd" != "null" ]]; then
    detail="${detail}${detail:+, }est. \$${estimated_cache_write_usd}"
  fi
  if [[ -n "$detail" ]]; then
    staleness_note="${staleness_note} (${detail})"
  fi
  context_parts+=("${staleness_note}.")
fi

additional_context="$(printf '%s\n' "${context_parts[@]}")"

cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "SessionStart",
    "sessionTitle": $(echo "$slug" | jq -Rs .),
    "additionalContext": $(echo "$additional_context" | jq -Rs .)
  }
}
EOF
