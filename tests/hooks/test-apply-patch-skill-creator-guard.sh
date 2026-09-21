#!/usr/bin/env bash
# test-apply-patch-skill-creator-guard.sh — hooks/skill-creator-guard.sh
# against an apply_patch envelope touching SKILL.md.
#
# skill-creator-guard.sh has NO tool_name case statement to bypass — its gap
# was file-PATH extraction failing for the apply_patch shape, not a case
# fallthrough (task-003's own framing). So the matched-pair discipline here is
# about the PATH, not the tool: a SKILL.md write must surface the reminder
# and an ordinary file write must not, for both apply_patch and Edit.
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

GUARD="$ROOT/hooks/skill-creator-guard.sh"
OBJ="pears"
REPO="$(setup_apply_patch_repo "$TMP" "$OBJ")"

# reminder_fired <tool> <tool_input-json> <cwd> -> yes | no
reminder_fired() {
  local tool="$1" ti="$2" cwd="$3" out
  out="$(jq -n --arg t "$tool" --argjson ti "$ti" --arg cwd "$cwd" '{tool_name:$t, cwd:$cwd, tool_input:$ti}' \
         | bash "$GUARD" 2>/dev/null)"
  printf '%s' "$out" | jq -e '.hookSpecificOutput.additionalContext | test("SKILL QUALITY GATE")' \
    >/dev/null 2>&1 && echo yes || echo no
}

# ===========================================================================
section "apply_patch adding a SKILL.md surfaces the reminder"
# ===========================================================================

judge "Add File: skills/foo/SKILL.md" yes \
  "$(reminder_fired apply_patch "$(jq -n --arg cmd "$(patch_envelope "Add File: skills/foo/SKILL.md")" '{command:$cmd}')" "$REPO")"
judge "Update File: an existing skills/foo/SKILL.md" yes \
  "$(reminder_fired apply_patch "$(jq -n --arg cmd "$(patch_envelope "Update File: skills/foo/SKILL.md")" '{command:$cmd}')" "$REPO")"
judge "SKILL.md target reached via multi-file envelope, not the first target" yes \
  "$(reminder_fired apply_patch "$(jq -n --arg cmd "$(patch_envelope "Add File: skills/foo/reference.md" "Add File: skills/foo/SKILL.md")" '{command:$cmd}')" "$REPO")"

section "the matched sibling: apply_patch touching an ordinary file does NOT fire"

judge "Add File: an ordinary skill reference doc" no \
  "$(reminder_fired apply_patch "$(jq -n --arg cmd "$(patch_envelope "Add File: skills/foo/reference.md")" '{command:$cmd}')" "$REPO")"
judge "Update File: an ordinary source file" no \
  "$(reminder_fired apply_patch "$(jq -n --arg cmd "$(patch_envelope "Update File: src/app.ts")" '{command:$cmd}')" "$REPO")"
judge "a path that merely CONTAINS the substring SKILL.md-ish text but isn't one" no \
  "$(reminder_fired apply_patch "$(jq -n --arg cmd "$(patch_envelope "Add File: skills/foo/NOT_A_SKILL.md")" '{command:$cmd}')" "$REPO")"

# ===========================================================================
section "parity: the canonical Claude Edit/Write path is unchanged"
# ===========================================================================

judge "Write: skills/foo/SKILL.md" yes \
  "$(reminder_fired Write "$(jq -n --arg p "$REPO/skills/foo/SKILL.md" '{file_path:$p}')" "$REPO")"
judge "Edit: an ordinary file" no \
  "$(reminder_fired Edit "$(jq -n --arg p "$REPO/src/app.ts" '{file_path:$p}')" "$REPO")"

# ===========================================================================
section "negative / no-false-positive cases"
# ===========================================================================

judge "apply_patch command with no *** Begin Patch envelope" no \
  "$(reminder_fired apply_patch "$(jq -n '{command:"echo hi"}')" "$REPO")"
judge "a Bash command that merely mentions SKILL.md in prose" no \
  "$(reminder_fired Bash "$(jq -n '{command:"echo do not hand-write SKILL.md"}')" "$REPO")"

# ===========================================================================
section "KNOWN GAP found while writing this suite — pre-existing, NOT introduced by codex-guard-fix"
# ===========================================================================
# skill-creator-guard.sh's FIRST extraction step (the inline python block)
# reads tool_input.file_path/.path unconditionally — it does not gate on
# tool_name at all, unlike its own write-targets.py FALLBACK, which does gate
# on the normalized tool name. So a Read whose tool_input happens to carry a
# SKILL.md file_path fires the same "about to write/edit" reminder a real
# write would, even though nothing is being written. This suite's own first
# attempt at this case asserted "Read must ALLOW" on the assumption that
# hooks.json's own matcher (Edit|Write|MultiEdit|NotebookEdit|StrReplace)
# would keep a Read from ever reaching this script — true for how Claude Code
# dispatches it, but the SCRIPT ITSELF has no such guard, and every test in
# this repo (this suite included) invokes the script directly, bypassing that
# matcher. warn(), not judge(): the script's behavior here is real and
# reproducible, but fixing it is a skill-creator-guard.sh change, outside
# this task's tests/hooks/** scope.
read_reminder="$(reminder_fired Read "$(jq -n --arg p "$REPO/skills/foo/SKILL.md" '{file_path:$p}')" "$REPO")"
if [ "$read_reminder" = "yes" ]; then
  warn "skill-creator-guard.sh's primary file_path/path extraction is not gated on tool_name — a Read of a SKILL.md path fires the write reminder exactly as an Edit would. Not a codex-guard-fix regression (pre-existing before this objective); the hooks.json matcher (Edit-family only) is the only thing preventing this from firing on a real Read in production. Recorded as a followup."
  ok "known gap characterized (see warning above)"
else
  bad "known gap characterization" "expected the reminder to fire for a Read of a SKILL.md path (matching the script's unconditional primary extraction); got '$read_reminder' — the gap may have been fixed, re-verify this section"
fi

harness_summary
