#!/usr/bin/env bash
# test-apply-patch-matcher-dispatch.sh — does the HOST-LEVEL dispatch in
# hooks.json ever hand an apply_patch call to these hooks in the first place?
#
# WHY THIS SUITE EXISTS
#   Every other suite in tests/hooks/ (and every existing probe in this
#   objective's task-002/task-003 handoffs) tests ONE layer: pipe a payload
#   directly into `bash hooks/<guard>.sh` and read its verdict. That proves
#   the SCRIPT decides correctly once it runs. It proves nothing about
#   whether the script ever gets invoked for a real apply_patch tool call —
#   that decision happens one layer up, in whichever host reads
#   hooks/hooks.json's own "matcher" field, BEFORE the script's stdin is even
#   written.
#
#   hooks/hooks.json wires all three guards this objective touches under a
#   matcher of literally "Edit|Write|MultiEdit|NotebookEdit|StrReplace" (the
#   Edit-family block) or "Bash|Shell" (the Bash-family block):
#
#     matcher                                    guards routed through it
#     Edit|Write|MultiEdit|NotebookEdit|StrReplace  enforce-worktree-edits.sh
#                                                    guard-sensitive-files.sh
#                                                    skill-creator-guard.sh
#     Bash|Shell                                    guard-sensitive-files.sh
#
#   Nowhere does any matcher name "apply_patch". If a host tests this field
#   as a regex against the RAW, un-normalized tool_name it received — which
#   is exactly how Claude Code itself uses this same field, per this repo's
#   own docs/user/configuration.md — then an apply_patch call would never
#   reach any of these three scripts AT ALL, regardless of what
#   normalize_tool_name does once inside them. task-001/002/003's fix would
#   be entirely correct and entirely unreachable in production.
#
#   THIS IS NOT ESTABLISHED. Whether Codex's own hook runner uses `matcher`
#   this way — or uses a different field, or ignores it, or the file "does
#   not port" to Codex at all as docs/user/install/codex.md:164 separately
#   claims (itself in tension with .codex-plugin/plugin.json's
#   `"hooks": "./hooks/hooks.json"` and CLAUDE.md's "loaded by Claude Code
#   and the Codex CLI") — is NOT VERIFIED anywhere in this repo against a
#   live Codex binary. That contradiction predates this task and is bigger
#   than tests/hooks/** can resolve; it is recorded in the handoff as a
#   followup, not adjudicated here.
#
#   What CAN be established with no live Codex run at all: the plain
#   regex fact. This suite computes it and WARNS — it does not fail the
#   suite, because "correct" depends on host semantics this repo has not
#   verified, and asserting a pass/fail here would manufacture false
#   confidence in exactly the direction this whole objective's caveat
#   ("F1/F2 are proven from Codex source and tests, NOT a live run") warns
#   against.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$ROOT/tests/lib/harness.sh"

harness_require jq

HOOKS_JSON="$ROOT/hooks/hooks.json"

# matcher_for <script-name> -> every distinct matcher regex a PreToolUse block
# invoking that script declares, one per line.
matcher_for() {
  jq -r --arg s "$1" \
    '.hooks.PreToolUse[] | select(any(.hooks[]; .command | test($s))) | .matcher' \
    "$HOOKS_JSON" 2>/dev/null | sort -u
}

# ere_matches <regex> <string> -> yes|no, via the same POSIX ERE engine a
# matcher field would plausibly be tested with (grep -E).
ere_matches() {
  if printf '%s' "$2" | grep -Eq "^($1)$"; then echo yes; else echo no; fi
}

section "the plain regex fact: does any matcher gating these guards match the literal string apply_patch?"

for script in enforce-worktree-edits guard-sensitive-files skill-creator-guard; do
  matchers="$(matcher_for "$script")"
  any_match=no
  while IFS= read -r m; do
    [ -n "$m" ] || continue
    [ "$(ere_matches "$m" apply_patch)" = "yes" ] && any_match=yes
  done <<< "$matchers"
  if [ "$any_match" = "yes" ]; then
    ok "$script.sh: a matcher already matches apply_patch"
  else
    warn "$script.sh: none of its hooks.json matcher(s) [$(printf '%s' "$matchers" | tr '\n' ' ')] match the literal string 'apply_patch'. IF the host that dispatches this hook tests 'matcher' as a regex against the raw tool_name (as Claude Code itself does per docs/user/configuration.md) BEFORE the script runs, this script is never invoked for an apply_patch call regardless of normalize_tool_name inside it. NOT verified against a live Codex run either way — see this file's header."
  fi
done

section "sanity: the SAME matchers DO match every canonical Claude tool name this objective's fix preserves"

for script in enforce-worktree-edits guard-sensitive-files skill-creator-guard; do
  matchers="$(matcher_for "$script")"
  [ -n "$matchers" ] || { skip "$script.sh has any Edit-family/Bash-family matcher at all" "not wired to any PreToolUse block"; continue; }
  for tool in Edit Write; do
    any_match=no
    while IFS= read -r m; do
      [ -n "$m" ] || continue
      [ "$(ere_matches "$m" "$tool")" = "yes" ] && any_match=yes
    done <<< "$matchers"
    judge "$script.sh matcher matches $tool" yes "$any_match"
  done
done

harness_summary
