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
section "primary extraction is gated on tool_name — task-009 (654f4da)"
# ===========================================================================
# Was a KNOWN GAP: skill-creator-guard.sh's FIRST extraction step (the inline
# python block) read tool_input.file_path/.path unconditionally — it did not
# gate on tool_name at all, unlike its own write-targets.py FALLBACK, which
# did gate on the normalized tool name. So a Read whose tool_input happened to
# carry a SKILL.md file_path fired the same "about to write/edit" reminder a
# real write would, even though nothing was being written. The script itself
# had no such guard, and every test in this repo (this suite included) invokes
# the script directly, bypassing hooks.json's own matcher — so this was a real,
# reproducible false positive, not merely a theoretical one.
#
# task-009 (654f4da) fixed this: raw_tool_name/canonical_tool_name are now
# computed once up front, and BOTH the primary flat-key extraction and the
# write-targets.py apply_patch fallback are gated on the same
# Edit|Write|MultiEdit|NotebookEdit|StrReplace case arm. A Read or Grep
# carrying a SKILL.md-shaped file_path/path must now stay silent.
judge "Read of a SKILL.md path no longer fires the reminder" no \
  "$(reminder_fired Read "$(jq -n --arg p "$REPO/skills/foo/SKILL.md" '{file_path:$p}')" "$REPO")"
judge "Grep of a SKILL.md path no longer fires the reminder" no \
  "$(reminder_fired Grep "$(jq -n --arg p "$REPO/skills/foo/SKILL.md" '{path:$p}')" "$REPO")"

harness_summary
