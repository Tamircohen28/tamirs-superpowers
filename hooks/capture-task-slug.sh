#!/usr/bin/env bash
set -euo pipefail

# UserPromptSubmit — derive task slug from the first user prompt of the session.
# Creates or reuses a global worktree for git repos before edits begin.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/worktree-common.sh
source "${SCRIPT_DIR}/lib/worktree-common.sh"
# shellcheck source=lib/objective-common.sh
source "${SCRIPT_DIR}/lib/objective-common.sh"
# shellcheck source=lib/hook-output.sh
source "${SCRIPT_DIR}/lib/hook-output.sh"

# A minimal, valid UserPromptSubmit response and nothing else. Used for every
# "I have no usable information" exit: the harness must not be disrupted (so
# exit 0, valid JSON), but no worktree, branch, or state may be created.
emit_noop_and_exit() {
  local title="${1:-}"
  if [[ -n "$title" ]]; then
    cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "sessionTitle": "${title}"
  }
}
EOF
  else
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit"}}'
  fi
  exit 0
}

input="$(hook_read_stdin)"

# An empty or unparseable payload carries no instruction. Every field below
# would be empty, and the code downstream would then invent values for them —
# so stop here rather than letting jq fail mid-script (which exited non-zero
# and disrupted the harness for no benefit).
if [[ -z "$input" ]] || ! printf '%s' "$input" | jq -e . >/dev/null 2>&1; then
  emit_noop_and_exit
fi

session_id="$(echo "$input" | jq -r '.session_id // empty')"
prompt="$(echo "$input" | jq -r '.prompt // empty')"
cwd="$(echo "$input" | jq -r '.cwd // empty')"

state="$(load_session_state "$session_id")"
prompt_count="$(echo "$state" | jq -r '.prompt_count // 0')"
# Re-slugify on read so a state file poisoned with a multi-line slug (written
# before slugify_text stripped newlines) self-heals instead of mangling paths.
task_slug="$(slugify_text "$(echo "$state" | jq -r '.task_slug // empty')" 48)"
now_iso="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

if [[ "$prompt_count" == "0" || -z "$task_slug" || "$task_slug" == "null" ]]; then
  task_slug="$(slugify_text "$prompt" 48)"
  if [[ -z "$task_slug" ]]; then
    # The prompt yielded nothing sluggable (absent, or whitespace/punctuation
    # only). The session id is a legitimate fallback because it still IDENTIFIES
    # this session — but only when there IS one. With both empty the old code
    # produced the literal slug "session-", and that placeholder is precisely
    # what turns "no information" into a real branch and worktree: `wt/session-`
    # on the first call, then `wt/session` once the self-heal re-slugify strips
    # the trailing hyphen. One content-free invocation, two junk branches.
    #
    # So the fallback is guarded, not defaulted: no identity, no slug, no
    # worktree.
    short_id="${session_id:0:8}"
    if [[ -z "$short_id" ]]; then
      emit_noop_and_exit
    fi
    task_slug="session-${short_id}"
  fi

  state="$(echo "$state" | jq \
    --arg task_slug "$task_slug" \
    --arg initial_prompt "$prompt" \
    --arg now "$now_iso" \
    --argjson prompt_count 1 \
    '. + {
      task_slug: $task_slug,
      initial_prompt: $initial_prompt,
      prompt_count: $prompt_count,
      created_at: (if .created_at == null then $now else .created_at end),
      updated_at: $now
    }')"
  save_session_state "$session_id" "$state"
else
  # Write the sanitized slug back so later readers see a clean value too.
  state="$(echo "$state" | jq --arg task_slug "$task_slug" --argjson prompt_count $((prompt_count + 1)) --arg now "$now_iso" \
    '. + {task_slug: $task_slug, prompt_count: $prompt_count, updated_at: $now}')"
  save_session_state "$session_id" "$state"
fi

context_lines=()
session_title="$(echo "$state" | jq -r '.task_slug // empty')"

# jq renders a missing key as the STRING "null", which is non-empty and would
# sail through every downstream check to produce a `wt/null` branch. Same
# family as `wt/session-`: a placeholder standing in for information nobody
# had.
if [[ -z "$session_title" || "$session_title" == "null" ]]; then
  emit_noop_and_exit
fi

# A payload with no cwd is malformed, not an invitation to guess. Falling back
# to the process's working directory made this hook create a `wt/<slug>` branch
# and a worktree in whatever repo it happened to be launched from — including
# the developer's real checkout, from a test harness that only meant to check
# the hook returned promptly. There is nothing useful to do without a cwd, so
# do nothing.
if [[ -z "$cwd" ]]; then
  emit_noop_and_exit "$session_title"
fi

if is_git_repo "$cwd"; then
  repo_root="$(repo_root_for "$cwd")"
  repo_name="$(repo_name_for "$cwd")"
  worktree_path="$(worktree_path_for "$repo_name" "$session_title")"
  worktree_created_at="$(echo "$state" | jq -r '.worktree_created_at // empty')"
  worktree_retired_at="$(echo "$state" | jq -r '.worktree_retired_at // empty')"
  worktree_live=no

  # STAND DOWN WHEN AN ORCHESTRATOR OWNS THIS REPO.
  #
  # This hook's original contract was "one prompt creates one task worktree".
  # Under the objective model that contract is actively harmful: the
  # orchestrator has already laid out .agent-worktrees/<objective>/{integration,
  # task-NNN} and assigned each worker its own directory and branch. A hook that
  # then derives a slug from the prompt and calls `git worktree add` creates a
  # SECOND, unrelated worktree on a `wt/*` branch for work that already has a
  # home — splitting the objective across two trees.
  #
  # So when an objective is active, or the session is already sitting inside an
  # agent workspace of any layout, do not create anything. Record state, point
  # at the existing workspace, and let the orchestrator own placement.
  objective_id="$(active_objective_id "$cwd" 2>/dev/null || true)"

  if is_global_worktree_path "$cwd"; then
    worktree_live=yes
    worktree_retired_at=""
    session_files_dir="$(ensure_session_files_dir "${cwd}/session-files")"
  elif is_agent_workspace "$cwd"; then
    # Already inside an objective / legacy-platform / native worktree.
    worktree_path="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || echo "$cwd")"
    worktree_live=yes
    worktree_retired_at=""
    session_files_dir="$(ensure_session_files_dir "${worktree_path}/session-files")"
  elif [[ -n "$objective_id" ]]; then
    # An objective is active but this session is in the main checkout. Creating
    # a competing worktree here is the exact conflict this branch exists to
    # avoid — name the objective's workspaces instead.
    worktree_path=""
    session_files_dir="$(ensure_session_files_dir "$(objective_state_dir "$repo_root" "$objective_id")")"

  # CREATE ONCE. A REMOVAL IS A DECISION, NOT A GAP TO CLOSE.
  #
  # This used to be a bare `[[ ! -d "$worktree_path" ]] && git worktree add`,
  # re-evaluated on EVERY prompt for the life of the session. Read as "keep the
  # worktree present" it looks harmless. What it actually does is undo every
  # removal: `git worktree remove`, the repo-cleanup skill's worktree phase,
  # even this plugin's own stale-worktree retention pass — each is reversed by
  # the next prompt, and `-B` restores the `wt/*` branch along with it. Someone
  # who cleans a repo watches the worktree return minutes later with no actor
  # named, which reads as a bug in git rather than a hook doing as it was told.
  #
  # So creation happens once and is recorded. If the path is gone afterwards,
  # somebody removed it deliberately: retire it rather than rebuild it, and put
  # session files somewhere that needs no checkout.
  #
  # Retirement suppresses creation HERE, where the only evidence is that a
  # prompt arrived — which is no evidence at all that this session will touch
  # the repo. An actual Edit is real evidence, so enforce-worktree-edits.sh
  # rebuilds the worktree at that moment instead.
  elif is_live_worktree "$worktree_path"; then
    worktree_live=yes
    worktree_retired_at=""
    # Backfill for a session that predates this hook. Its state has no
    # worktree_created_at, and without one a later removal leaves BOTH
    # lifecycle fields empty — which reads as "never created" and sends the
    # next prompt straight back to create_session_worktree. That is the
    # resurrection this file exists to stop, arriving by the upgrade path.
    worktree_created_at="${worktree_created_at:-$now_iso}"
    session_files_dir="$(ensure_session_files_dir "${worktree_path}/session-files")"
  elif [[ -n "$worktree_retired_at" || -n "$worktree_created_at" ]]; then
    worktree_retired_at="${worktree_retired_at:-$now_iso}"
    session_files_dir="$(ensure_session_files_dir "${HOME}/.claude/outputs/${session_title}/session-files")"
  elif create_session_worktree "$repo_root" "$worktree_path" "$session_title"; then
    worktree_created_at="$now_iso"
    worktree_live=yes
    session_files_dir="$(ensure_session_files_dir "${worktree_path}/session-files")"
  else
    # Creation was attempted and failed — a locked worktree, a `wt/*` branch
    # already checked out elsewhere. Do not describe a directory that is not
    # there; the edit guard will try again when an edit actually needs one.
    session_files_dir="$(ensure_session_files_dir "${HOME}/.claude/outputs/${session_title}/session-files")"
  fi

  state="$(echo "$state" | jq \
    --arg repo_root "$repo_root" \
    --arg repo_name "$repo_name" \
    --arg worktree_path "$worktree_path" \
    --arg session_files_dir "$session_files_dir" \
    --arg objective_id "$objective_id" \
    --arg worktree_created_at "$worktree_created_at" \
    --arg worktree_retired_at "$worktree_retired_at" \
  '. + {
    repo_root: $repo_root,
    repo_name: $repo_name,
    worktree_path: $worktree_path,
    session_files_dir: $session_files_dir,
    objective_id: (if ($objective_id | length) > 0 then $objective_id else null end)
  }
  | if ($worktree_created_at | length) > 0 then .worktree_created_at = $worktree_created_at else . end
  | if ($worktree_retired_at | length) > 0 then .worktree_retired_at = $worktree_retired_at else del(.worktree_retired_at) end')"
  save_session_state "$session_id" "$state"

  if [[ -n "${CLAUDE_ENV_FILE:-}" ]]; then
    append_env_exports "$CLAUDE_ENV_FILE" \
      "CLAUDE_TASK_SLUG=\"${session_title}\"" \
      "CLAUDE_SESSION_FILES_DIR=\"${session_files_dir}\"" \
      "CLAUDE_REPO_ROOT=\"${repo_root}\""
    if [[ -n "$worktree_path" && "$worktree_live" == "yes" ]]; then
      append_env_exports "$CLAUDE_ENV_FILE" "CLAUDE_WORKTREE_PATH=\"${worktree_path}\""
    else
      # The env file only ever accumulates, so skipping the export is not the
      # same as clearing it: an earlier prompt's value would still point at the
      # worktree this prompt just reported as removed. Overwrite it.
      append_env_exports "$CLAUDE_ENV_FILE" "CLAUDE_WORKTREE_PATH=\"\""
    fi
    if [[ -n "$objective_id" ]]; then
      append_env_exports "$CLAUDE_ENV_FILE" "SUPERPOWERS_OBJECTIVE_ID=\"${objective_id}\""
    fi
  fi

  if [[ -n "$objective_id" && -z "$worktree_path" ]]; then
    context_lines+=("Objective '${objective_id}' is active and orchestrator-managed. No session worktree was created.")
    context_lines+=("Worker and integration worktrees live under: $(agent_worktree_root "$repo_root")/${objective_id}/")
    context_lines+=("Ask the orchestrator for your task worktree (task-NNN) — do not create one.")
    context_lines+=("Objective state: $(objective_state_dir "$repo_root" "$objective_id")")
  elif [[ -n "$worktree_retired_at" ]]; then
    context_lines+=("This session's worktree (${worktree_path}) was removed and has NOT been recreated.")
    context_lines+=("Working in ${cwd}. An Edit/Write to repo files is still refused in the main checkout — the edit guard will rebuild the worktree then and name it.")
    context_lines+=("Session artifacts (plans, reviews, investigations) go in: ${session_files_dir}")
  elif [[ "$worktree_live" != "yes" ]]; then
    context_lines+=("No session worktree could be created for ${repo_name}; working in ${cwd}.")
    context_lines+=("Session artifacts (plans, reviews, investigations) go in: ${session_files_dir}")
  elif ! is_global_worktree_path "$cwd" && ! is_agent_workspace "$cwd"; then
    context_lines+=("Git repo task detected. Dedicated worktree: ${worktree_path}")
    context_lines+=("Before Edit/Write, run: cd \"${worktree_path}\" or use EnterWorktree.")
    context_lines+=("Session artifacts (plans, reviews, investigations) go in: ${session_files_dir}")
    context_lines+=("Do NOT use repo .dev-files/ — use \$CLAUDE_SESSION_FILES_DIR instead.")
  fi
else
  # session_title is guaranteed non-empty here: the guard above exits before
  # this point when it is empty or the string "null". The old
  # `${session_title:-session-${short_id}}` default was therefore unreachable —
  # but it was also the exact placeholder shape that produced `wt/session-`,
  # and a dead default is one moved guard away from being live again. Stating
  # the invariant beats re-arming the bug.
  session_slug="$session_title"
  session_dir="${HOME}/.claude/outputs/${session_slug}"
  session_files_dir="$(ensure_session_files_dir "${session_dir}/session-files")"
  sync_session_files_archive "$session_files_dir" "$session_slug"

  state="$(echo "$state" | jq \
    --arg session_slug "$session_slug" \
    --arg session_dir "$session_dir" \
    --arg session_files_dir "$session_files_dir" \
  '. + {
    session_slug: $session_slug,
    session_dir: $session_dir,
    session_files_dir: $session_files_dir
  }')"
  save_session_state "$session_id" "$state"

  if [[ -n "${CLAUDE_ENV_FILE:-}" ]]; then
    append_env_exports "$CLAUDE_ENV_FILE" \
      "CLAUDE_SESSION_SLUG=\"${session_slug}\"" \
      "CLAUDE_OUTPUT_DIR=\"${session_dir}\"" \
      "CLAUDE_SESSION_FILES_DIR=\"${session_files_dir}\""
  fi

  context_lines+=("Non-repo session. Session files: ${session_files_dir}")
  context_lines+=("Archive copy: ${SESSION_FILES_ARCHIVE}/${session_slug}/")
fi

if ((${#context_lines[@]})); then
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "sessionTitle": "${session_title}",
    "additionalContext": "$(printf '%s\n' "${context_lines[@]}" | sed 's/"/\\"/g' | awk '{printf "%s\\n", $0}' | sed 's/\\n$//')"
  }
}
EOF
else
  cat <<EOF
{
  "hookSpecificOutput": {
    "hookEventName": "UserPromptSubmit",
    "sessionTitle": "${session_title}"
  }
}
EOF
fi
