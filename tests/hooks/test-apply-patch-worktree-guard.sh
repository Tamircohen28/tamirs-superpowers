#!/usr/bin/env bash
# test-apply-patch-worktree-guard.sh — hooks/enforce-worktree-edits.sh against
# every platform's editing-tool payload shape, not just Claude's.
#
# WHAT THIS SUITE IS FOR
#   This objective (codex-guard-fix) exists because a probe recorded as
#   [pass] during task-003 could not fail for the right reason: it fed an
#   apply_patch payload with `cwd` in the MAIN repo, so the guard denied on
#   the "cwd is not a worktree" check alone — passing identically whether or
#   not the patch TARGET was ever parsed at all.
#
#   So every case below varies cwd and target INDEPENDENTLY. The matrix:
#
#     cwd              target            expected
#     inside worktree   inside worktree   ALLOW
#     inside worktree   OUTSIDE           DENY   <- the case that was broken
#     main repo          outside           DENY  (denies on cwd alone; NOT
#                                                  proof the target was parsed
#                                                  — see the note at that case)
#
#   Run once for apply_patch and once for each canonical Claude tool
#   (Edit, Write, MultiEdit, NotebookEdit, StrReplace) so a regression in the
#   normalizer shows up as a diff between the two, not as a suite that only
#   ever exercised one shape.
#
# Hermetic: temp fixtures only, no network, no gh.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$ROOT/tests/lib/harness.sh"
# shellcheck source=tests/hooks/lib/apply-patch-fixtures.sh
source "$ROOT/tests/hooks/lib/apply-patch-fixtures.sh"

harness_require git jq python3

TMP="$(harness_tmpdir)"
export HOME="$TMP/home"
mkdir -p "$HOME"
export GIT_CONFIG_NOSYSTEM=1
# The detached cleanup sweep every worktree hook kicks off cannot reach this
# suite's tmpdir, but it does leave a live ownerless `rm -rf` in the run
# (Makefile's own test-hooks target disables it for the same reason).
export SUPERPOWERS_WORKTREE_CLEANUP=0
unset SUPERPOWERS_OBJECTIVE_ID 2>/dev/null || true

ENFORCE="$ROOT/hooks/enforce-worktree-edits.sh"
OBJ="apples"

REPO="$(setup_apply_patch_repo "$TMP" "$OBJ")"
WORKTREE="$REPO/.agent-worktrees/$OBJ/task-001"

# run_enforce <tool_input-json> <cwd> -> ALLOW | DENY:<reason>
run_enforce() {
  local ti="$1" cwd="$2" out decision tool
  tool="$3"
  out="$(jq -n --argjson ti "$ti" --arg cwd "$cwd" --arg t "$tool" --arg sid "enforce-matrix" \
           '{tool_name:$t, tool_input:$ti, cwd:$cwd, session_id:$sid}' \
         | bash "$ENFORCE" 2>/dev/null)"
  decision="$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // "allow"' 2>/dev/null)"
  if [ "$decision" = "deny" ]; then
    printf 'DENY:%s' "$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // ""' 2>/dev/null)"
  else
    printf 'ALLOW'
  fi
}
verdict() { case "$1" in ALLOW) printf ALLOW ;; DENY:*) printf DENY ;; *) printf 'MALFORMED:%s' "$1" ;; esac; }

apply_patch_ti() { jq -n --arg cmd "$(patch_envelope "$1")" '{command:$cmd}'; }

# ===========================================================================
section "apply_patch: cwd × target matrix (the composition task-004 exists to pin)"
# ===========================================================================

judge "cwd in worktree, target in worktree -> ALLOW" ALLOW \
  "$(verdict "$(run_enforce "$(apply_patch_ti "Update File: $WORKTREE/src/app.ts")" "$WORKTREE" apply_patch)")"

judge "cwd in worktree, target OUTSIDE (main checkout) -> DENY — the case that silently allowed before 23c020e" DENY \
  "$(verdict "$(run_enforce "$(apply_patch_ti "Update File: $REPO/src/app.ts")" "$WORKTREE" apply_patch)")"

judge "cwd in main repo, target outside -> DENY (on cwd alone — NOT proof the target was parsed; see PROBE B note below)" DENY \
  "$(verdict "$(run_enforce "$(apply_patch_ti "Update File: $REPO/src/app.ts")" "$REPO" apply_patch)")"
# PROBE B's own shape: main-repo cwd denies regardless of whether the target
# resolver ever ran — a relative target with no absolute path to disambiguate
# would deny identically on a completely broken parser. It is included only
# to keep the three-row matrix complete, never read as evidence on its own.

judge "cwd in main repo, target ALSO in main repo (relative target) -> DENY" DENY \
  "$(verdict "$(run_enforce "$(jq -n --arg cmd "$(patch_envelope "Update File: src/app.ts")" '{command:$cmd}')" "$REPO" apply_patch)")"

# ===========================================================================
section "the same matrix for every canonical Claude tool — one normalizer regression shows up as a DIVERGENCE from apply_patch, not a silent pass"
# ===========================================================================

for tool_key in "Edit:file_path" "Write:file_path" "MultiEdit:file_path" "StrReplace:path"; do
  tool="${tool_key%%:*}"; key="${tool_key##*:}"
  judge "$tool: cwd+target in worktree -> ALLOW" ALLOW \
    "$(verdict "$(run_enforce "$(claude_tool_input "$tool" "$key" "$WORKTREE/src/app.ts" "$WORKTREE" | jq '.tool_input')" "$WORKTREE" "$tool")")"
  judge "$tool: cwd in worktree, target outside -> DENY" DENY \
    "$(verdict "$(run_enforce "$(claude_tool_input "$tool" "$key" "$REPO/src/app.ts" "$WORKTREE" | jq '.tool_input')" "$WORKTREE" "$tool")")"
done

# NotebookEdit carries no file_path/path key at all in its real payload shape
# — only notebook_path — so this is a distinct code path from the four above:
# the flat jq extraction in enforce-worktree-edits.sh reads ONLY
# tool_input.file_path // .tool_input.path, which is empty for a real
# NotebookEdit call, so this exercises the write-targets.py EDIT_PATH_KEYS
# fallback exclusively. This independently verifies task-003's own
# non-blocking followup ("NotebookEdit's notebook_path key may have had the
# same cwd-fallback gap for unrelated reasons — unverified").
judge "NotebookEdit: cwd+target(notebook_path) in worktree -> ALLOW" ALLOW \
  "$(verdict "$(run_enforce "$(claude_tool_input NotebookEdit notebook_path "$WORKTREE/nb.ipynb" "$WORKTREE" | jq '.tool_input')" "$WORKTREE" NotebookEdit)")"
judge "NotebookEdit: cwd in worktree, notebook_path outside -> DENY" DENY \
  "$(verdict "$(run_enforce "$(claude_tool_input NotebookEdit notebook_path "$REPO/nb.ipynb" "$WORKTREE" | jq '.tool_input')" "$WORKTREE" NotebookEdit)")"

# ===========================================================================
section "multi-target apply_patch — proves the judge loop, not a stop-at-first-clean-target bug"
# ===========================================================================
# One apply_patch call naming TWO files: the first inside the worktree, the
# second outside it. hook_allow/hook_deny both exit(0) immediately, so an
# implementation that only inspected the FIRST candidate target could allow
# the whole call on the strength of the clean one and never reach the second.

MULTI_CMD="$(patch_envelope "Update File: $WORKTREE/src/app.ts" "Update File: $REPO/src/app.ts")"
judge "target #1 in worktree, target #2 outside -> DENY (loop keeps going past a clean first target)" DENY \
  "$(verdict "$(run_enforce "$(jq -n --arg cmd "$MULTI_CMD" '{command:$cmd}')" "$WORKTREE" apply_patch)")"

MULTI_CMD_REVERSED="$(patch_envelope "Update File: $REPO/src/app.ts" "Update File: $WORKTREE/src/app.ts")"
judge "target #1 outside, target #2 in worktree -> DENY (order does not matter)" DENY \
  "$(verdict "$(run_enforce "$(jq -n --arg cmd "$MULTI_CMD_REVERSED" '{command:$cmd}')" "$WORKTREE" apply_patch)")"

MULTI_CLEAN="$(patch_envelope "Add File: $WORKTREE/src/new.ts" "Update File: $WORKTREE/src/app.ts")"
judge "both targets in worktree -> ALLOW" ALLOW \
  "$(verdict "$(run_enforce "$(jq -n --arg cmd "$MULTI_CLEAN" '{command:$cmd}')" "$WORKTREE" apply_patch)")"

# ===========================================================================
section "regression: existing in-worktree behavior is unchanged"
# ===========================================================================

judge "in-worktree Claude Edit still allowed" ALLOW \
  "$(verdict "$(run_enforce "$(jq -n --arg p "$WORKTREE/src/app.ts" '{file_path:$p}')" "$WORKTREE" Edit)")"
judge "in-worktree single-target apply_patch still allowed" ALLOW \
  "$(verdict "$(run_enforce "$(apply_patch_ti "Update File: $WORKTREE/src/app.ts")" "$WORKTREE" apply_patch)")"
judge "an unrelated Read tool is never even case-dispatched — allowed" ALLOW \
  "$(verdict "$(run_enforce "$(jq -n --arg p "$REPO/yarn.lock" '{file_path:$p}')" "$REPO" Read)")"

# ===========================================================================
section "no-envelope apply_patch is not silently forced through a false deny"
# ===========================================================================
# A command with no "*** Begin Patch" marker at all (malformed, or a
# different Codex action reusing the same tool_name) resolves no candidate
# path, so the guard falls back to judging cwd — exactly like any other
# path-less edit. From inside the worktree that is ALLOW; this is not a
# universal allow regardless of cwd, so the case is anchored at cwd=worktree
# to test the real fallback, not a vacuous truth.
judge "apply_patch command with no patch envelope, cwd in worktree -> ALLOW (falls back to judging cwd)" ALLOW \
  "$(verdict "$(run_enforce "$(jq -n '{command:"echo hi"}')" "$WORKTREE" apply_patch)")"

# ===========================================================================
section "the ~/.claude config-path exemption still applies to apply_patch"
# ===========================================================================
# hooks/enforce-worktree-edits.sh's own header: the Claude config directory is
# machine housekeeping, never forced through a worktree. This exemption is
# checked before the tool-name case dispatch even matters for the FILE being
# edited, so it must hold for apply_patch exactly as it does for Edit.
CLAUDE_CFG="$HOME/.claude"
mkdir -p "$CLAUDE_CFG"
judge "apply_patch targeting \$HOME/.claude/CLAUDE.md from the main repo cwd -> ALLOW" ALLOW \
  "$(verdict "$(run_enforce "$(apply_patch_ti "Update File: $CLAUDE_CFG/CLAUDE.md")" "$REPO" apply_patch)")"
judge "Edit targeting \$HOME/.claude/CLAUDE.md from the main repo cwd -> ALLOW (parity check)" ALLOW \
  "$(verdict "$(run_enforce "$(jq -n --arg p "$CLAUDE_CFG/CLAUDE.md" '{file_path:$p}')" "$REPO" Edit)")"

harness_summary
