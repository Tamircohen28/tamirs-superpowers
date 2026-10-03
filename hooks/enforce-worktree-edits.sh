#!/usr/bin/env bash
set -euo pipefail

# PreToolUse — block repo file edits outside ~/.claude/worktrees/<repo>/<task-slug>.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/worktree-common.sh
source "${SCRIPT_DIR}/lib/worktree-common.sh"
# shellcheck source=lib/objective-common.sh
source "${SCRIPT_DIR}/lib/objective-common.sh"
# shellcheck source=lib/hook-output.sh
source "${SCRIPT_DIR}/lib/hook-output.sh"
# shellcheck source=lib/platform-tools.sh
source "${SCRIPT_DIR}/lib/platform-tools.sh"

input="$(hook_read_stdin)"
hook_detect_platform "$input"
tool_name="$(echo "$input" | jq -r '.tool_name // empty')"
session_id="$(echo "$input" | jq -r '.session_id // .conversation_id // empty')"
cwd="$(echo "$input" | jq -r '.cwd // empty')"
if [[ -z "$cwd" ]]; then
  cwd="$(echo "$input" | jq -r '.workspace_roots[0] // empty')"
fi

# Dispatch decision only — normalize a platform's own tool name (e.g. Codex's
# apply_patch) onto this repo's canonical Claude-shaped vocabulary so the case
# arm below matches. $input itself is left untouched: nothing downstream that
# still reads raw tool_name (there is none in this script) should ever see a
# rewritten value.
canonical_tool_name="$(normalize_tool_name "$tool_name")"

case "$canonical_tool_name" in
  Edit|Write|MultiEdit|NotebookEdit|StrReplace) ;;
  *) hook_allow ;;
esac

# The Claude config directory is version-controlled for backup, not a project
# checkout. Editing settings, memory, or agent definitions there is machine
# housekeeping, so it must never be forced through a worktree.
claude_config_root() {
  local root="${CLAUDE_CONFIG_DIR:-${HOME}/.claude}"
  printf '%s' "${root%/}"
}

is_claude_config_path() {
  local path="${1%/}" root
  root="$(claude_config_root)"
  [[ -n "$root" && ( "$path" == "$root" || "$path" == "${root}/"* ) ]]
}

# Walk up to the nearest directory that exists — a Write may target a file in a
# directory that has not been created yet.
nearest_existing_dir() {
  local d="$1"
  while [[ -n "$d" && "$d" != "/" && "$d" != "." && ! -d "$d" ]]; do
    d="$(dirname "$d")"
  done
  printf '%s' "$d"
}

# judge_target_dir TARGET_DIR — decide whether TARGET_DIR is a legitimate
# place to write. Returns 0 (allowed) for every early-out case this hook has
# always recognized; returns 1 and sets JUDGE_DENY_REASON otherwise (and, as
# a real side effect on the way to a genuine deny, may recreate a removed
# session worktree — see the AN EDIT IS THE DEMAND SIGNAL comment below).
#
# A function, not the old inline block, because one tool call can now name
# MORE THAN ONE write target: Codex's apply_patch can touch several files in
# a single envelope. hook_allow/hook_deny both exit(0) immediately, so an
# inline version could only ever answer for the FIRST target it looked at —
# a patch with one in-worktree target and one outside it would have been
# allowed on the strength of the first. See the candidate loop below, which
# calls this once per target and denies on the first one that fails.
# is_throwaway_root DIR — true when DIR sits under a system temp root.
#
# The degraded path below fails OPEN, so it must only ever engage where the
# checkout is provably disposable: an eval sandbox, a CI scratch dir, a test
# fixture. A person's real project never lives under /tmp or $TMPDIR, so this
# is the narrowest signal that separates "isolation is unavailable here" from
# "one `git worktree add` happened to fail" — which is an ordinary condition
# (branch already checked out elsewhere, stale session state, a permissions
# blip) and must still be denied in the main checkout.
is_throwaway_root() {
  local dir="$1" tmp
  [[ -z "$dir" ]] && return 1
  case "$dir" in
    /tmp/*|/private/tmp/*|/var/folders/*|/private/var/folders/*) return 0 ;;
  esac
  tmp="${TMPDIR:-}"
  if [[ -n "$tmp" ]]; then
    tmp="${tmp%/}"
    [[ -n "$tmp" && "$dir" == "$tmp"/* ]] && return 0
  fi
  return 1
}

judge_target_dir() {
  local target_dir="$1"
  local repo_root repo_name state task_slug worktree_path objective_id reason workspace_kind

  if [[ -z "$target_dir" ]]; then
    return 0
  fi

  if is_claude_config_path "$target_dir"; then
    return 0
  fi

  if ! is_git_repo "$target_dir"; then
    return 0
  fi

  if is_global_worktree_path "$target_dir"; then
    return 0
  fi

  # Any registered session worktree is compliant — including Claude Code's native
  # <repo>/.claude/worktrees/<name> layout on a claude/* branch. Never deny based
  # on a path rebuilt from session state; the state slug can be stale or mangled.
  if is_registered_claude_worktree "$target_dir"; then
    return 0
  fi

  # Every agent workspace shape is compliant, old and new alike:
  #
  #   objective-integration  .agent-worktrees/<objective>/integration
  #   objective-worker       .agent-worktrees/<objective>/task-NNN
  #   legacy-platform        .claude/.worktrees, .cursor/.worktrees, .codex/.worktrees
  #   legacy-global          ~/.claude/worktrees/<repo>/<slug>
  #   native-claude          <repo>/.claude/worktrees/<name>
  #
  # The legacy shapes are listed deliberately. This hook predates the objective
  # model, and a worker or integrator whose worktree it did not recognize would be
  # denied every Edit — the work would have nowhere legal to go. Recognizing a
  # layout is not endorsing it: nothing here CREATES a platform-shaped path.
  workspace_kind="$(classify_worktree_path "$target_dir")"
  case "$workspace_kind" in
    objective-integration|objective-worker|objective-other|legacy-platform|legacy-global|native-claude)
      return 0
      ;;
  esac

  repo_root="$(repo_root_for "$target_dir")"
  repo_name="$(repo_name_for "$target_dir")"
  state="$(load_session_state "$session_id")"
  # Re-slugify on read: state files written before slugify_text stripped newlines
  # can carry multi-line slugs/paths that would mangle the suggested worktree.
  task_slug="$(slugify_text "$(echo "$state" | jq -r '.task_slug // empty')" 48)"
  worktree_path="$(echo "$state" | jq -r '.worktree_path // empty')"
  case "$worktree_path" in *$'\n'*) worktree_path="" ;; esac

  if [[ -z "$worktree_path" || "$worktree_path" == "null" ]]; then
    if [[ -n "$task_slug" && "$task_slug" != "null" ]]; then
      worktree_path="$(worktree_path_for "$repo_name" "$task_slug")"
    fi
  fi

  # The recorded path belongs to whichever repo the session started in. A session
  # that edits a second repo would otherwise be told to cd into the FIRST repo's
  # worktree — and, below, would have that worktree rebuilt for it. Recompute
  # whenever the recorded path is not this repo's.
  if [[ -n "$worktree_path" && "$worktree_path" != "null" \
        && "$worktree_path" != "${WORKTREE_ROOT}/${repo_name}/"* ]]; then
    if [[ -n "$task_slug" && "$task_slug" != "null" ]]; then
      worktree_path="$(worktree_path_for "$repo_name" "$task_slug")"
    else
      worktree_path=""
    fi
  fi

  # An active objective changes the remedy, not the verdict: the main checkout is
  # still off limits, but the correct destination is a worker/integration worktree
  # the orchestrator already owns — NOT a fresh session worktree.
  objective_id="$(active_objective_id "$target_dir" 2>/dev/null || true)"

  if [[ -n "$objective_id" ]]; then
    reason="Repo edits must happen in an objective worktree, not the main checkout (${repo_root}). Objective '${objective_id}' is active: work in $(agent_worktree_root "$repo_root")/${objective_id}/task-NNN (worker) or .../integration (integrator). Ask the orchestrator which one is yours — do not create a new worktree."
  else
    reason="Repo edits must happen in a dedicated worktree under ~/.claude/worktrees/${repo_name}/<task-slug>, not the main checkout (${repo_root})."
    if [[ -z "$worktree_path" || "$worktree_path" == "null" ]]; then
      reason="${reason} Submit your task prompt first so the worktree slug is derived from it, then cd into the worktree."
    elif is_live_worktree "$worktree_path"; then
      reason="${reason} Use: cd \"${worktree_path}\" or EnterWorktree before editing."

    # AN EDIT IS THE DEMAND SIGNAL.
    #
    # capture-task-slug.sh deliberately stopped rebuilding a worktree somebody
    # removed, because a prompt arriving proves nothing about whether this session
    # will ever touch the repo — and rebuilding on that basis is what made a
    # cleaned-up worktree keep coming back. An Edit is the first hard evidence
    # that a workspace is actually needed, so the rebuild belongs here.
    #
    # The edit is still denied: the tool call names a path in the main checkout
    # and cannot be silently redirected. It is denied with a destination that
    # exists, which is the part that was broken — the old message pointed at a
    # removed directory and the retry failed the same way.
    elif create_session_worktree "$repo_root" "$worktree_path" "$task_slug"; then
      clear_worktree_retirement "$session_id"
      reason="${reason} This session's worktree had been removed; it has been recreated at \"${worktree_path}\". cd there (or use EnterWorktree) and retry."
    elif [[ "${TAMIRS_ALLOW_DEGRADED_WRITES:-}" == "1" ]] || is_throwaway_root "$repo_root"; then
      # DEGRADED PATH — no remedy exists, so denying is a dead end, not a guard.
      #
      # Every other branch above denies with a destination the agent can act on:
      # a live worktree to cd into, one just recreated for it, or an objective
      # worktree the orchestrator owns. This branch is the one where the worktree
      # is missing AND could not be recreated — there is nowhere to send the
      # work, and nothing the agent can do to make one. A deny here does not
      # protect the repo, it strands the session.
      #
      # Measured in a `claude plugin eval` sandbox, where the harness makes the
      # run's home a git repo but refuses worktree isolation: every Write was
      # denied and a one-word file-creation task scored 1.00 WITHOUT the plugin
      # and 0.00 WITH it. The same shape occurs anywhere `git worktree add`
      # cannot run or its target is unwritable — a CI checkout, a container, a
      # read-only mount.
      #
      # So: allow the write, loudly. The invariant that matters is preserved,
      # because this degrades only where a worktree is provably unobtainable;
      # wherever one CAN exist, the branches above still deny.
      #
      # GATED, because this fails open. It engages only where the checkout is
      # provably disposable (is_throwaway_root) or an operator opted in with
      # TAMIRS_ALLOW_DEGRADED_WRITES=1. A failed `git worktree add` in a real
      # checkout — branch already checked out in another worktree, stale
      # session state, a permissions blip — is an ORDINARY condition and still
      # falls through to the deny below. Without that gate this branch would
      # disable the guard in the user's own repo on a transient git error.
      JUDGE_DEGRADED_REASON="Worktree policy DEGRADED: repo edits belong in a dedicated worktree (${worktree_path}), but it is missing and could not be recreated, and this checkout (${repo_root}) is a disposable one. Allowing this write so the session is not dead-locked. This never engages in a normal checkout."
      return 0
    else
      reason="${reason} This session's worktree (${worktree_path}) is missing and could not be recreated — use EnterWorktree, or edit inside an objective worktree."
    fi
  fi

  JUDGE_DENY_REASON="$reason"
  return 1
}

# Judge the FILE(S) being edited, not the session cwd. An incidental `cd` into
# an unrelated repo — reading a config file, inspecting a checkout — used to
# arm the guard for every subsequent edit, including edits outside that repo.
#
# A single Claude tool call carries its target at tool_input.file_path/.path.
# apply_patch carries neither — the target(s) live inside the patch body,
# possibly several of them in one envelope — so when the flat-key read comes
# up empty, ask write-targets.py's own apply_patch parser (already proven
# against 73 cases in tests/test-write-target-guard.sh) for every TARGET/
# DELETE path instead of re-deriving the marker format a second time here.
# $input is passed through UNCHANGED — never rewrite tool_name before this
# call, or write-targets.py's apply_patch branch (keyed on the raw literal)
# stops firing and the extraction goes silent again.
file_path="$(echo "$input" | jq -r '.tool_input.file_path // .tool_input.path // empty')"
declare -a candidate_paths=()
if [[ -n "$file_path" && "$file_path" != "null" ]]; then
  candidate_paths+=("$file_path")
else
  while IFS=$'\t' read -r kind detail _fragment; do
    case "$kind" in
      TARGET|DELETE) candidate_paths+=("$detail") ;;
    esac
  done < <(printf '%s' "$input" | python3 "${SCRIPT_DIR}/lib/write-targets.py" 2>/dev/null)
fi
# Nothing resolved a path at all (an unparseable payload, or a genuinely
# path-less call that still matched the case above) — same as before, judge
# the session cwd. The array is never left empty: an empty "${arr[@]}"
# expansion under `set -u` is only safe on bash >= 4.4, and this sentinel
# sidesteps the question entirely.
if [[ ${#candidate_paths[@]} -eq 0 ]]; then
  candidate_paths+=("")
fi

for path in "${candidate_paths[@]}"; do
  target_dir=""
  if [[ -n "$path" && "$path" != "null" ]]; then
    target_dir="$(nearest_existing_dir "$(dirname "$path")")"
  fi
  if [[ -z "$target_dir" || ! -d "$target_dir" ]]; then
    target_dir="$cwd"
  fi
  if [[ -z "$target_dir" ]]; then
    continue
  fi
  if ! judge_target_dir "$target_dir"; then
    hook_deny "$JUDGE_DENY_REASON"
  fi
done

# A degraded allow is still an allow, but it must never be silent: the write
# landed somewhere the policy would normally refuse, and the session should say
# so. Emitted once, after every target passed, so a multi-target apply_patch
# does not answer for its first path alone.
if [[ -n "${JUDGE_DEGRADED_REASON:-}" ]]; then
  hook_additional_context "$JUDGE_DEGRADED_REASON"
fi

hook_allow
