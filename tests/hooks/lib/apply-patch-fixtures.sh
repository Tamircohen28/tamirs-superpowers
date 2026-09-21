#!/usr/bin/env bash
# apply-patch-fixtures.sh — shared helpers for the tests/hooks/ apply_patch
# regression suites.
#
# Sourced, never executed. Depends on tests/lib/harness.sh already being
# sourced by the caller (for harness_tmpdir/harness_new_repo/canon).
#
# WHY A SEPARATE FIXTURE FILE
#   Every suite in tests/hooks/ needs the same two things: a repo shaped like
#   a real objective (main checkout + a worker worktree under
#   .agent-worktrees/<obj>/task-NNN) and a way to build a syntactically valid
#   apply_patch envelope with one or more targets. Keeping both in one place
#   means a fixture bug gets fixed once, not per-suite.

# shellcheck shell=bash

# patch_envelope <marker-line>... — a "*** Begin/End Patch" envelope with one
# synthesized hunk per marker line. Each argument is the text that follows
# "*** ", e.g. "Update File: src/app.ts" or "Add File: skills/foo/SKILL.md".
# A body line is emitted after every marker except "Delete File" (which takes
# none) and "Move to" (a continuation of the preceding Update File, not its
# own hunk) — this mirrors the real V4A shape task-002 was written against.
patch_envelope() {
  printf '*** Begin Patch\n'
  for marker in "$@"; do
    printf '*** %s\n' "$marker"
    case "$marker" in
      "Delete File:"*|"Move to:"*) ;;
      *) printf '@@\n-old\n+new\n' ;;
    esac
  done
  printf '*** End Patch\n'
}

# apply_patch_heredoc <patch-text> [quoted=1] [delim=PATCH] — a Bash command
# STRING that feeds a patch envelope to `apply_patch` via a heredoc, the shape
# a real Codex Bash-mediated apply_patch call takes (as opposed to Codex's own
# `tool_name: "apply_patch"` tool call). quoted=1 (the default) produces
# `<<'PATCH'` (delimiter quoted, no expansion inside the body); quoted=0
# produces the unquoted `<<PATCH` form. Callers wrap the result in a Bash
# tool_input themselves (`{command: "..."}`) — this only builds the text.
apply_patch_heredoc() {
  local patch_text="$1" quoted="${2:-1}" delim="${3:-PATCH}" open
  if [ "$quoted" = "1" ]; then
    open="<<'$delim'"
  else
    open="<<$delim"
  fi
  printf 'apply_patch %s\n%s\n%s' "$open" "$patch_text" "$delim"
}

# apply_patch_input <command> <cwd> [session_id] — the JSON payload a Codex
# apply_patch tool call produces, as this repo's hooks read it.
apply_patch_input() {
  local command="$1" cwd="$2" session_id="${3:-apply-patch-test-session}"
  jq -n --arg cmd "$command" --arg cwd "$cwd" --arg sid "$session_id" \
    '{tool_name:"apply_patch", tool_input:{command:$cmd}, cwd:$cwd, session_id:$sid}'
}

# claude_tool_input <tool_name> <key> <value> <cwd> [session_id] — the JSON
# payload shape Claude's own canonical editing tools send, so the same matrix
# can be run against apply_patch and against the tools these guards were
# originally written for.
claude_tool_input() {
  local tool="$1" key="$2" value="$3" cwd="$4" session_id="${5:-claude-tool-test-session}"
  jq -n --arg t "$tool" --arg k "$key" --arg v "$value" --arg cwd "$cwd" --arg sid "$session_id" \
    '{tool_name:$t, tool_input:({} | .[$k]=$v), cwd:$cwd, session_id:$sid}'
}

# setup_apply_patch_repo <root> <objective-id> — a repo shaped exactly like a
# real objective: a main checkout at <root>/repo, and one worker worktree at
# <root>/repo/.agent-worktrees/<objective-id>/task-001 on a worker/* branch.
# Prints the main checkout's canonical (symlink-resolved) path.
setup_apply_patch_repo() {
  local root="$1" objective_id="$2" repo worker_dir
  repo="$root/repo"
  harness_new_repo "$repo" main
  # src/components/ui must pre-exist for the shadcn check: guard-sensitive-
  # files.sh resolves repo_root via `git -C "$(dirname "$file")"`, which is
  # itself empty when the directory does not yet exist — see
  # test-apply-patch-sensitive-files-guard.sh's "pre-existing, out-of-scope
  # gap" section for the case where that matters.
  mkdir -p "$repo/src/components/ui" "$repo/skills" "$repo/.github/workflows"
  printf '{"style":"x"}\n' > "$repo/components.json"
  printf 'x\n'             > "$repo/yarn.lock"
  printf 'x\n'              > "$repo/package-lock.json"
  printf 'name: CI\n'       > "$repo/.github/workflows/ci.yml"
  printf 'x\n'              > "$repo/src/app.ts"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "fixtures"

  worker_dir="$repo/.agent-worktrees/$objective_id/task-001"
  git -C "$repo" worktree add -q -B "worker/$objective_id/001" "$worker_dir" main
  mkdir -p "$worker_dir/src"

  canon "$repo"
}
