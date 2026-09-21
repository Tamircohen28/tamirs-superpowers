#!/usr/bin/env bash
# test-apply-patch-sensitive-files-guard.sh — hooks/guard-sensitive-files.sh
# against an apply_patch envelope, matching the BLOCKS/ALLOWS-pair discipline
# tests/test-write-target-guard.sh already established for Bash.
#
# The cheap wrong way to write this suite is to assert only the BLOCKS half:
# a guard that treats "tool_name == apply_patch" as "deny everything" passes
# that half just as well as a guard that actually parsed the patch envelope.
# Every BLOCKS case here therefore has a matched ALLOWS sibling that differs
# only in the one fact that should change the verdict.
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
unset GH_TOKEN GITHUB_TOKEN PM_ALLOW_PROTECTED 2>/dev/null || true

GUARD="$ROOT/hooks/guard-sensitive-files.sh"
OBJ="oranges"
REPO="$(setup_apply_patch_repo "$TMP" "$OBJ")"
git -C "$REPO" remote add origin https://github.com/example/x.git 2>/dev/null || true

# run_guard <tool> <tool_input-json> <cwd> -> deny | warn | allow
run_guard() {
  local tool="$1" ti="$2" cwd="${3:-$REPO}"
  jq -n --arg t "$tool" --argjson ti "$ti" --arg cwd "$cwd" '{tool_name:$t, cwd:$cwd, tool_input:$ti}' \
  | bash "$GUARD" 2>/dev/null \
  | jq -r 'if .hookSpecificOutput.permissionDecision=="deny" then "deny"
           elif .hookSpecificOutput.additionalContext then "warn"
           else "allow" end' 2>/dev/null
}
# verdict <command-text> [cwd] -> deny | warn | allow, for an apply_patch call
verdict() {
  local cmd="$1" cwd="${2:-$REPO}"
  run_guard apply_patch "$(jq -n --arg cmd "$cmd" '{command:$cmd}')" "$cwd"
}
patch() { patch_envelope "$@"; }

# ===========================================================================
section "apply_patch writing a protected path is BLOCKED"
# ===========================================================================

judge "Update File: package-lock.json"        deny "$(verdict "$(patch "Update File: package-lock.json")")"
judge "Update File: yarn.lock"                 deny "$(verdict "$(patch "Update File: yarn.lock")")"
judge "Add File: a NEW lockfile"               deny "$(verdict "$(patch "Add File: pnpm-lock.yaml")")"
judge "Update File: a workflow"                deny "$(verdict "$(patch "Update File: .github/workflows/ci.yml")")"
judge "Add File: a new workflow"               deny "$(verdict "$(patch "Add File: .github/workflows/new.yml")")"
judge "Delete File: a workflow"                deny "$(verdict "$(patch "Delete File: .github/workflows/ci.yml")")"
judge "Add File: generated shadcn ui"          deny "$(verdict "$(patch "Add File: src/components/ui/button.tsx")")"
judge "absolute-path Update File: a lockfile"  deny "$(verdict "$(patch "Update File: $REPO/yarn.lock")")"

section "the matched ALLOWS sibling for each — same shape, an unprotected path"

judge "Update File: an ordinary source file"   allow "$(verdict "$(patch "Update File: src/app.ts")")"
judge "Add File: an ordinary source file"      allow "$(verdict "$(patch "Add File: src/new.ts")")"
judge "Delete File: an ordinary source file"   allow "$(verdict "$(patch "Delete File: src/app.ts")")"
judge "Add File: ordinary ui, no shadcn"       allow "$(verdict "$(patch "Add File: src/widgets/thing.tsx")")"

# ===========================================================================
section "the RENAME case — the fact task-002 added beyond the three literal markers"
# ===========================================================================
# *** Update File: scratch.py   (unprotected source path)
# *** Move to: yarn.lock        (protected DESTINATION)
# A parser that reports only the Update File path sees "scratch.py" — an
# ordinary file — and misses that the write actually LANDS on the lockfile.

judge "Update File: scratch.py, Move to: yarn.lock -> the DESTINATION is caught" deny \
  "$(verdict "$(patch_envelope "Update File: scratch.py" "Move to: yarn.lock")")"
judge "  ... and the matched sibling: renaming to an ordinary path is allowed" allow \
  "$(verdict "$(patch_envelope "Update File: scratch.py" "Move to: renamed.py")")"
judge "Update File: yarn.lock, Move to: scratch.py -> the SOURCE is still caught too" deny \
  "$(verdict "$(patch_envelope "Update File: yarn.lock" "Move to: scratch.py")")"

# ===========================================================================
section "multi-file envelope: ONE protected target among several clean ones is still caught"
# ===========================================================================

MIXED="$(patch_envelope "Add File: src/a.ts" "Update File: src/b.ts" "Update File: yarn.lock")"
judge "protected target buried after two clean ones" deny "$(verdict "$MIXED")"

MIXED_CLEAN="$(patch_envelope "Add File: src/a.ts" "Update File: src/b.ts" "Delete File: src/c.ts")"
judge "all-clean multi-file envelope is allowed" allow "$(verdict "$MIXED_CLEAN")"

# ===========================================================================
section "negative / no-false-positive cases — must ALLOW"
# ===========================================================================

judge "a command with no *** Begin Patch envelope at all" allow \
  "$(verdict "echo not a patch")"
judge "apply_patch tool_name but a stray marker-shaped line with no envelope" allow \
  "$(verdict "*** Update File: yarn.lock")"
judge "a Bash command that merely GREPS for a patch marker" allow \
  "$(run_guard Bash "$(jq -n --arg c "grep -rn '*** Update File: yarn.lock' src/" '{command:$c}')" "$REPO")"
judge "a git commit -m mentioning a protected filename in prose" allow \
  "$(run_guard Bash "$(jq -n '{command:"git commit -m \"regenerate yarn.lock and fix ci.yml\""}')" "$REPO")"
judge "an unrelated Read of an ordinary file" allow \
  "$(run_guard Read "$(jq -n --arg p "$REPO/src/app.ts" '{file_path:$p}')" "$REPO")"

# ===========================================================================
section "PM_ALLOW_PROTECTED is still the only override, and still honored for apply_patch"
# ===========================================================================

judge "PM_ALLOW_PROTECTED=1 allows an apply_patch write to a lockfile" allow \
  "$(PM_ALLOW_PROTECTED=1 verdict "$(patch "Update File: yarn.lock")")"

# ===========================================================================
section "KNOWN GAP found while writing this suite — pre-existing, NOT introduced by codex-guard-fix, out of this task's scope to fix"
# ===========================================================================
# guard-sensitive-files.sh:88 resolves repo_root via
# `git -C "$(dirname "$file")" rev-parse --show-toplevel`. `git -C` on a
# directory that does not exist on disk fails silently, so repo_root comes
# back empty — and every repo_root-gated rule (shadcn ui, gitignored build
# output, the workflow-remote lookup) then no-ops instead of denying.
#
# "Add File" into a directory that does not exist yet is apply_patch's own
# normal shape for a brand-new component, so this composes badly with Codex
# in particular — but the same jq -n --arg | bash probe below shows it is
# NOT apply_patch-specific: the canonical Claude Write tool hits the exact
# same silent no-op. This is a pre-existing defect in guard-sensitive-
# files.sh's own repo_root resolution that predates this objective and this
# task's scope is tests/hooks/** only, so it is recorded here rather than
# fixed. warn(), not judge(), because failing THIS suite over an unrelated,
# out-of-scope defect would misrepresent it as a codex-guard-fix regression.
NEWDIR_REPO="$TMP/newdir-repo"
harness_new_repo "$NEWDIR_REPO" main
printf '{"style":"x"}\n' > "$NEWDIR_REPO/components.json"
git -C "$NEWDIR_REPO" add -A && git -C "$NEWDIR_REPO" commit -q -m fixtures

apply_patch_verdict="$(run_guard apply_patch \
  "$(jq -n --arg cmd "$(patch_envelope "Add File: src/components/ui/new.tsx")" '{command:$cmd}')" \
  "$NEWDIR_REPO")"
write_verdict="$(run_guard Write \
  "$(jq -n --arg p "$NEWDIR_REPO/src/components/ui/new.tsx" '{file_path:$p}')" \
  "$NEWDIR_REPO")"

if [ "$apply_patch_verdict" = "allow" ] && [ "$write_verdict" = "allow" ]; then
  warn "guard-sensitive-files.sh: shadcn/build-output/workflow rules silently no-op when dirname(file) does not yet exist on disk — confirmed for BOTH apply_patch Add File ($apply_patch_verdict) and Claude Write ($write_verdict) into src/components/ui/new.tsx with no pre-existing components/ui dir; not a codex-guard-fix regression, recorded as a followup"
  ok "known gap characterized (see warning above) — apply_patch and Write agree, so it is not a cross-platform regression"
else
  bad "known gap characterization" "expected BOTH apply_patch and Write to silently allow (confirming this is general, not apply_patch-specific); got apply_patch=$apply_patch_verdict write=$write_verdict — the gap may have been fixed or changed shape, re-verify this section"
fi

harness_summary
