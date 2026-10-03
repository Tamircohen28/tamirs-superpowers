#!/usr/bin/env bash
# Cross-platform tool-name normalizer.
#
# Every hook in this repo that gates on `tool_name` (enforce-worktree-edits.sh,
# guard-sensitive-files.sh, ...) was written against Claude Code's tool
# vocabulary: Edit, Write, MultiEdit, NotebookEdit, StrReplace, Bash, Read,
# Grep, Glob. A hook payload from a non-Claude platform carries that
# platform's own tool name instead, so a Claude-shaped `case` statement
# silently no-ops for every other platform (see enforce-worktree-edits.sh's
# Codex gap: `apply_patch` matched none of its Edit|Write|... arms).
#
# normalize_tool_name maps a platform's raw tool name onto this repo's
# canonical Claude-shaped name so callers can keep one `case` statement.
# Unknown input is passed through unchanged — never invent a mapping without
# evidence; passthrough keeps an unmapped name visibly distinct rather than
# silently coercing it into a canonical bucket it may not belong in.
#
# Canonical vocabulary (targets of this map): Edit, Write, MultiEdit,
# NotebookEdit, StrReplace, Bash, Read, Grep, Glob.
#
# Mapped so far:
#   apply_patch (Codex CLI's single file create/update/delete tool) -> Edit
#     Codex has no separate create-vs-modify tool the way Claude splits
#     Edit/Write/MultiEdit; apply_patch covers all three. It maps to Edit
#     because every canonical case arm in this repo that guards Edit also
#     guards Write/MultiEdit/NotebookEdit/StrReplace as one group (see
#     enforce-worktree-edits.sh), so a single representative name is enough
#     for a caller matching that group.
#
# Usage:
#   source "$(dirname "$0")/lib/platform-tools.sh"
#   canonical="$(normalize_tool_name "$tool_name")"
normalize_tool_name() {
  local raw="$1"
  case "$raw" in
    apply_patch) printf '%s' "Edit" ;;
    *)           printf '%s' "$raw" ;;
  esac
}
