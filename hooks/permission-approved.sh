#!/usr/bin/env bash
# permission-approved.sh — phase 2 of the two-phase confirm on Claude Code
# (ADR 004 D5, D6; the second adversarial pass, F1).
#
# WHY IT EXISTS
#   The permission guard (hooks/permission-guard.sh) answers `ask` on a Bash call
#   `plugin-config.sh confirm <nonce>` and stamps <state>/asked/<nonce>.json with
#   that call's tool_use_id. The stamp proves the dialog was SHOWN, not that the
#   user approved it: a declined dialog leaves it behind. So `confirm`, running
#   inside the approved call, only STAGES its result (<state>/staged/<nonce>.json,
#   bound to the stamp's tool_use_id, session and agent), and nothing the resolver
#   reads changes. Claude Code runs PostToolUse only after a tool call actually
#   ran, which after an `ask` means only after the user approved it. This hook, on
#   that PostToolUse, asks the writer to promote the staged record of THIS call:
#   scripts/plugin-config.sh promote, with the payload on stdin, which writes the
#   user file and its lock, or the raise ticket as active, only when the payload's
#   tool_use_id, session_id and agent equal the staged record's and its command is
#   exactly the plain `[bash] <path>/plugin-config.sh confirm <nonce> [--json]`.
#   A declined dialog never runs the call: nothing is promoted. A confirm re-run
#   later through a form the guard cannot see has another tool_use_id and is not
#   the plain form: never promoted. A staged record lapses with the stamp (15 min).
#
# EVENT
#   Claude Code PostToolUse, matcher Bash (hooks/hooks.json). Claude Code only:
#   the Codex and Gemini generators drop it (no confirm channel stages anything
#   there; scripts/build-codex-hooks.sh, scripts/build-gemini-hooks.sh), and the
#   Cursor bundle does not wire it (Cursor has no confirm channel, D5).
#
# FAILURE
#   Advisory in the hook sense (no onFailure): it runs after the call, so it
#   cannot block anything, and every failure promotes nothing, which is the
#   strict outcome (the change stays unwritten). It always exits 0. Output: none
#   for an unrelated call; otherwise hookSpecificOutput.additionalContext (and a
#   systemMessage for the user) saying whether the change is now active.
#
# FAST PATH
#   A Bash call whose payload does not name plugin-config.sh and confirm is left
#   alone with no process spawned.
set -uo pipefail

case "${BASH_SOURCE[0]}" in
  */*) _pa_here="${BASH_SOURCE[0]%/*}" ;;
  *) _pa_here=. ;;
esac
PA_ROOT="$(CDPATH='' cd -- "$_pa_here/.." 2>/dev/null && pwd -P)" || exit 0
unset _pa_here

# shellcheck source=hooks/lib/hook-output.sh
. "$PA_ROOT/hooks/lib/hook-output.sh" 2>/dev/null || exit 0

input="$(hook_read_stdin)"
case "$input" in
  *plugin-config.sh*confirm*) ;;
  *) exit 0 ;;
esac
command -v jq >/dev/null 2>&1 || exit 0
command -v python3 >/dev/null 2>&1 || exit 0
hook_detect_platform "$input"
[ "${HOOK_PLATFORM:-claude}" = claude ] || exit 0
[ -z "${GEMINI_SESSION_ID:-}" ] && [ -z "${GEMINI_PROJECT_DIR:-}" ] || exit 0

out="$(printf '%s' "$input" | bash "$PA_ROOT/scripts/plugin-config.sh" promote --json 2>/dev/null)" || true
result="$(printf '%s' "$out" | jq -r '.result // "nothing"' 2>/dev/null)" || result=nothing
msg="$(printf '%s' "$out" | jq -r '(.messages // []) | join("\n")' 2>/dev/null)" || msg=""
case "$result" in
  written|ticket)
    text="tamirs-superpowers: the permission change you approved is now active.
$msg" ;;
  refused)
    text="tamirs-superpowers: the approved confirm was NOT applied.
$msg" ;;
  *) exit 0 ;;
esac
jq -n --arg m "$text" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$m},systemMessage:$m}'
exit 0
