#!/usr/bin/env bash
# test-apply-patch-heredoc-bypass.sh — hooks/lib/write-targets.py against the
# apply_patch shell-heredoc bypass task-007 (c959b11) closed, and the marker
# constants task-002/task-007's apply_patch parser is written against.
#
# WHY THIS SUITE EXISTS
#   Codex's editing tool is `apply_patch`. Every OTHER guard suite in
#   tests/hooks/ sends it the way Codex's own tool call arrives:
#   `tool_name: "apply_patch"`, `tool_input: {command: "<patch envelope>"}`.
#   But apply_patch ALSO reaches this repo through a plain `Bash` tool call —
#   `apply_patch <<'PATCH' … PATCH` — because Codex, like any agent with shell
#   access, can invoke its own CLI tool as a shell command instead of through
#   the structured tool-call path. Before task-007, `analyze_command()` had no
#   branch for `argv0 == "apply_patch"`: the heredoc body was stripped as an
#   opaque data blob (same treatment as `cat > f <<EOF`) and never read as a
#   patch envelope, so a protected-file write shaped exactly like every other
#   suite's BLOCKS case sailed through as long as it arrived over Bash instead
#   of the apply_patch tool call. task-007 fixed the parser
#   (hooks/lib/write-targets.py); task-007's own handoff recorded that fix as
#   shipping with NO regression test and filed it as a BLOCKING followup for
#   test-engineer. This suite discharges that followup.
#
#   Matched-pair discipline, same reasoning tests/test-write-target-guard.sh
#   and every other tests/hooks/ suite already uses: a guard that treats
#   "the command contains apply_patch" as "deny everything" would pass a
#   BLOCKS-only suite just as well as one that actually parsed the heredoc
#   body. The negatives section exists to rule that out.
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
WT="$ROOT/hooks/lib/write-targets.py"
OBJ="grapes"
REPO="$(setup_apply_patch_repo "$TMP" "$OBJ")"

# run_guard <tool> <tool_input-json> <cwd> -> deny | warn | allow
run_guard() {
  local tool="$1" ti="$2" cwd="${3:-$REPO}"
  jq -n --arg t "$tool" --argjson ti "$ti" --arg cwd "$cwd" '{tool_name:$t, cwd:$cwd, tool_input:$ti}' \
  | bash "$GUARD" 2>/dev/null \
  | jq -r 'if .hookSpecificOutput.permissionDecision=="deny" then "deny"
           elif .hookSpecificOutput.additionalContext then "warn"
           else "allow" end' 2>/dev/null
}

# raw_targets <tool> <tool_input-json> <cwd> -> write-targets.py's own
# TARGET/DELETE/UNSURE lines, verbatim. Used where the property under test is
# "identical targets", not just a deny/allow verdict — a guard-level verdict
# can agree by coincidence (both DENY, for different reasons); the raw
# parser output cannot.
raw_targets() {
  local tool="$1" ti="$2" cwd="${3:-$REPO}"
  jq -n --arg t "$tool" --argjson ti "$ti" --arg cwd "$cwd" '{tool_name:$t, cwd:$cwd, tool_input:$ti}' \
  | python3 "$WT" 2>/dev/null
}

# tool_call_input <patch-text> -> the tool_input JSON for tool_name=apply_patch
tool_call_input() { jq -n --arg cmd "$1" '{command:$cmd}'; }

# heredoc_input <patch-text> [quoted=1] [delim=PATCH] -> the tool_input JSON
# for tool_name=Bash, patch fed via `apply_patch <<[']DELIM[']`.
heredoc_input() {
  local patch="$1" quoted="${2:-1}" delim="${3:-PATCH}"
  jq -n --arg cmd "$(apply_patch_heredoc "$patch" "$quoted" "$delim")" '{command:$cmd}'
}

# ===========================================================================
section "agreement: tool-call and Bash-heredoc forms of the SAME envelope report IDENTICAL targets"
# ===========================================================================
# The core property task-007's followup asked for: not "both non-empty", but
# byte-identical write-targets.py output (kind, resolved path, and fragment)
# regardless of which shape apply_patch arrived in.

single="$(patch_envelope "Update File: yarn.lock")"
judge "single-target envelope: tool-call and heredoc agree" \
  "$(raw_targets apply_patch "$(tool_call_input "$single")")" \
  "$(raw_targets Bash "$(heredoc_input "$single")")"

multi="$(patch_envelope "Add File: src/a.ts" "Update File: src/b.ts" "Update File: yarn.lock")"
judge "multi-target envelope: tool-call and heredoc agree" \
  "$(raw_targets apply_patch "$(tool_call_input "$multi")")" \
  "$(raw_targets Bash "$(heredoc_input "$multi")")"

rename="$(patch_envelope "Update File: scratch.py" "Move to: yarn.lock")"
judge "rename (Move to) envelope: tool-call and heredoc agree" \
  "$(raw_targets apply_patch "$(tool_call_input "$rename")")" \
  "$(raw_targets Bash "$(heredoc_input "$rename")")"

clean="$(patch_envelope "Add File: src/new.ts")"
judge "clean (no protected target) envelope: tool-call and heredoc agree" \
  "$(raw_targets apply_patch "$(tool_call_input "$clean")")" \
  "$(raw_targets Bash "$(heredoc_input "$clean")")"

# ===========================================================================
section "the actual bypass: apply_patch via a Bash heredoc is BLOCKED, matching the tool-call path"
# ===========================================================================

judge "Bash: apply_patch <<'PATCH' updating yarn.lock is DENIED" deny \
  "$(run_guard Bash "$(heredoc_input "$(patch_envelope "Update File: yarn.lock")")")"
judge "Bash: apply_patch <<'PATCH' adding a workflow is DENIED" deny \
  "$(run_guard Bash "$(heredoc_input "$(patch_envelope "Add File: .github/workflows/new.yml")")")"
judge "Bash: apply_patch <<'PATCH' renaming onto a lockfile (Move to) is DENIED" deny \
  "$(run_guard Bash "$(heredoc_input "$(patch_envelope "Update File: scratch.py" "Move to: yarn.lock")")")"

section "the matched ALLOWS sibling — same heredoc shape, an unprotected path"

judge "Bash: apply_patch <<'PATCH' updating an ordinary source file is ALLOWED" allow \
  "$(run_guard Bash "$(heredoc_input "$(patch_envelope "Update File: src/app.ts")")")"

# ===========================================================================
section "quoted vs unquoted heredoc delimiter — both forms are equivalent"
# ===========================================================================

lockfile_patch="$(patch_envelope "Update File: yarn.lock")"
judge "quoted <<'PATCH'   heredoc is DENIED"  deny "$(run_guard Bash "$(heredoc_input "$lockfile_patch" 1 PATCH)")"
judge "unquoted <<PATCH heredoc is DENIED"    deny "$(run_guard Bash "$(heredoc_input "$lockfile_patch" 0 PATCH)")"
judge "quoted and unquoted delimiters report identical targets" \
  "$(raw_targets Bash "$(heredoc_input "$lockfile_patch" 1 PATCH)")" \
  "$(raw_targets Bash "$(heredoc_input "$lockfile_patch" 0 PATCH)")"

# ===========================================================================
section "composition: apply_patch heredoc combined with other shell constructs"
# ===========================================================================

judge "apply_patch heredoc after && is still DENIED" deny \
  "$(run_guard Bash "$(jq -n --arg c "true && $(apply_patch_heredoc "$lockfile_patch")" '{command:$c}')")"

# Two heredocs on one command line: a decoy `cat <<'EOF'` whose BODY merely
# LOOKS like a patch envelope for a DIFFERENT protected file (yarn.lock),
# immediately followed by the REAL `apply_patch <<'PATCH'` targeting a
# DIFFERENT protected file (package-lock.json). strip_heredocs collects both
# bodies in source order; _segment_records must hand each segment its OWN
# body off the shared iterator, or the apply_patch segment would read the
# cat segment's body instead of its own and report the wrong target (or the
# decoy's) — proving the shared-iterator ordering task-007's docstring
# describes, not just "some heredoc got parsed".
decoy_body="$(patch_envelope "Update File: yarn.lock")"
real_patch="$(patch_envelope "Update File: package-lock.json")"
two_heredocs="$(printf 'cat <<%s\n%s\n%s\n%s' "'EOF'" "$decoy_body" "EOF" "$(apply_patch_heredoc "$real_patch")")"

two_heredoc_targets="$(raw_targets Bash "$(jq -n --arg c "$two_heredocs" '{command:$c}')")"
judge "two heredocs on one command line: only the apply_patch segment's OWN body is a target" \
  "$(raw_targets apply_patch "$(tool_call_input "$real_patch")")" "$two_heredoc_targets"
judge "two heredocs on one command line: the decoy's file (yarn.lock) is NOT reported" no \
  "$(printf '%s' "$two_heredoc_targets" | grep -q 'yarn\.lock' && echo yes || echo no)"
judge "two heredocs on one command line: apply_patch's real target (package-lock.json) is DENIED" deny \
  "$(run_guard Bash "$(jq -n --arg c "$two_heredocs" '{command:$c}')")"

# ===========================================================================
section "negatives — must ALLOW and report no targets"
# ===========================================================================

judge "a plain cat <<'EOF' heredoc whose body merely CONTAINS patch-marker text is ALLOWED" allow \
  "$(run_guard Bash "$(jq -n --arg c "cat <<'EOF'
$(patch_envelope "Update File: yarn.lock")
EOF" '{command:$c}')")"
judge "…and reports no write targets at all" "" \
  "$(raw_targets Bash "$(jq -n --arg c "cat <<'EOF'
$(patch_envelope "Update File: yarn.lock")
EOF" '{command:$c}')")"

judge "a git commit -m mentioning a protected filename in prose is ALLOWED" allow \
  "$(run_guard Bash "$(jq -n '{command:"git commit -m \"regenerate yarn.lock and fix ci.yml\""}')")"
judge "a grep for a patch-marker-shaped pattern is ALLOWED" allow \
  "$(run_guard Bash "$(jq -n '{command:"grep -rn \"*** Update File: yarn.lock\" src/"}')")"

# ===========================================================================
section "authoritative marker constants (codex-rs/apply-patch/src/parser.rs:37-45) — pinned"
# ===========================================================================
# Exact literal markers, including the trailing space after the colon that
# distinguishes a marker prefix from an ordinary line of patch context:
#   "*** Begin Patch"  "*** End Patch"  "*** Add File: "  "*** Delete File: "
#   "*** Update File: "  "*** Move to: "  "*** End of File"
# Verified against the current parser so a future change to
# hooks/lib/write-targets.py or hooks/lib/apply-patch-fixtures.sh cannot
# silently regress any of these without a red test.

# The real fixture from codex-rs/core/src/tools/events.rs.
real_fixture=$'*** Begin Patch\n*** Add File: out/dest.txt\n+after\n*** End Patch'
judge "the real codex-rs events.rs fixture (Add File: out/dest.txt) is a TARGET" yes \
  "$(printf '%s' "$(raw_targets apply_patch "$(tool_call_input "$real_fixture")")" | grep -q $'^TARGET\t.*/out/dest\\.txt\t' && echo yes || echo no)"

# Leading whitespace before "***" and trailing whitespace at line-end, around
# an otherwise ordinary marker line, are tolerated.
padded=$'*** Begin Patch\n  *** Update File: yarn.lock  \n@@\n-old\n+new\n*** End Patch'
judge "leading/trailing whitespace around a marker line is tolerated" deny \
  "$(run_guard apply_patch "$(tool_call_input "$padded")")"

# Filenames are greedy to end-of-line and may contain spaces.
spaced=$'*** Begin Patch\n*** Add File: src/components/ui/my file.tsx\n+x\n*** End Patch'
judge "a filename containing spaces is captured whole, not truncated at the first space" yes \
  "$(printf '%s' "$(raw_targets apply_patch "$(tool_call_input "$spaced")")" | grep -q $'my file\\.tsx\t' && echo yes || echo no)"

# An optional "*** Environment ID: <id>" line may follow Begin Patch and is
# NOT a file target — only the real Update File line after it is.
with_env_id=$'*** Begin Patch\n*** Environment ID: abc-123\n*** Update File: yarn.lock\n@@\n-old\n+new\n*** End Patch'
env_id_targets="$(raw_targets apply_patch "$(tool_call_input "$with_env_id")")"
judge "an Environment ID line is not itself reported as a target" no \
  "$(printf '%s' "$env_id_targets" | grep -q -i 'environment' && echo yes || echo no)"
judge "…and the real Update File line after it is still reported" deny \
  "$(run_guard apply_patch "$(tool_call_input "$with_env_id")")"

harness_summary
