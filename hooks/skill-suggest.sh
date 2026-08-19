#!/usr/bin/env bash
# UserPromptSubmit hook — name the bundled skill that covers the situation the
# user just described, at the moment they describe it.
#
# WHY THIS EXISTS AND WHY IT IS NOT plugin-version-watch.sh
#   Fifteen of twenty-five bundled skills were never invoked across 953 real
#   sessions. The nudge that was supposed to fix that (plugin-version-watch.sh,
#   Stop hook) had three independent defects, any one of them fatal:
#
#     1. It emitted `systemMessage`, which renders in the USER's UI and is never
#        injected into the MODEL's context — so the agent could not act on it.
#        Every reminder hook here that actually changed behaviour
#        (scope-decompose-reminder.sh, goal-compact-reminder.sh,
#        handoff-reminder.sh) uses `additionalContext`. That one is the outlier,
#        and the one with zero conversions.
#     2. It wrote its 24h timestamp when the nudge FIRED, not when the user
#        ACTED — one ignored banner bought a full day of silence, no escalation.
#     3. Its cache was a single global file with no repo key, so a fire in one
#        repo silenced every other repo. The repo that most needed the check was
#        the one least likely to get it.
#
#   Also the wrong moment: `Stop` fires as the turn ends, when the user is about
#   to type their next instruction, so it proposes abandoning what they were
#   doing. `UserPromptSubmit` fires while they are ALREADY asking the question
#   the skill answers. That is the seam.
#
# CONTRACT
#   - Emits `additionalContext` (reaches the model), never `systemMessage`.
#   - One suggestion per skill per session, keyed by session AND repo, so a fire
#     in one repo never silences another.
#   - Silent when it has nothing to say. Never blocks. Always exits 0.
#   - Bounded stdin read via hook_read_stdin (bash `read -t`; `timeout(1)` is
#     GNU coreutils and absent on stock macOS).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hook-output.sh
source "${SCRIPT_DIR}/lib/hook-output.sh"

input="$(hook_read_stdin)"
prompt="$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null || true)"
session_id="$(printf '%s' "$input" | jq -r '.session_id // .conversation_id // empty' 2>/dev/null || true)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -n "$cwd" ] || cwd="$PWD"
[ -n "$session_id" ] || session_id="nosession"

# Nothing to match against — say nothing.
[ -n "$prompt" ] || exit 0

# Repo root, so two worktrees of one repo share a marker but two repos do not.
repo_root="$(cd "$cwd" 2>/dev/null && git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$cwd")"

CACHE_DIR="${HOME}/.claude/cache/skill-suggest"

# repo_key — a filesystem-safe digest of the repo path.
repo_key() {
  printf '%s' "$1" | cksum | tr -d ' \n' | cut -c1-16
}

# already_suggested <skill> — true when this skill already fired for this
# session in this repo. Marker creation is the same call, so the check and the
# claim cannot drift apart.
already_suggested() {
  local key marker
  key="$(repo_key "$repo_root")"
  marker="${CACHE_DIR}/${session_id}.${key}.$1"
  [ -e "$marker" ] && return 0
  mkdir -p "$CACHE_DIR" 2>/dev/null || return 0
  : > "$marker" 2>/dev/null || return 0
  return 1
}

matches() {
  printf '%s' "$prompt" | grep -qiE "$1"
}

# matches_cs — case-SENSITIVE. Stack-trace detection is shape matching, and the
# shapes are capitalised (`Traceback`, `TypeError:`). Case-insensitively,
# `error: ` alone would fire on any sentence containing the word "error".
matches_cs() {
  printf '%s' "$prompt" | grep -qE "$1"
}

# Markers are per session, so the directory would grow without bound. Prune on
# the way past — cheap, best-effort, and never a reason to fail the hook.
find "$CACHE_DIR" -type f -mtime +7 -delete 2>/dev/null || true

suggestions=()

add() {
  already_suggested "$1" && return 0
  suggestions+=("$2")
}

# --- session-report: the user is asking what something cost -----------------
if matches '\b(token|tokens)\b|\bcost(s|ing)?\b|\bspend(ing)?\b|\bexpensive\b|\bburn(ing)? through\b|\bbudget\b|\bcache hit\b|\busage report\b'; then
  add session-report "session-report — reports token spend, cache hit rate and cost per project from the local session transcripts. Invoke it rather than estimating."
fi

# --- targeted-debug: a stack trace was pasted -------------------------------
# Shape-based, not vocabulary-based: the frames themselves, in any language.
if matches_cs 'Traceback|^[[:space:]]*at [^[:space:]]+\(.*:[0-9]+|panic:|File "[^"]*", line [0-9]+|[A-Za-z]+(Exception|Error): |nil pointer dereference|goroutine [0-9]+ \['; then
  add targeted-debug "targeted-debug — forks the investigation into a bounded Explore agent that reads only the frames named in the trace, so the root cause comes back without spending main-thread context on a codebase sweep. Prefer it over reading files ad hoc."
fi

# --- platform-sync: docs currency, or a manifest/CHANGELOG bump -------------
# platform-sync audits a repo against the live docs of the AI harnesses it
# TARGETS. A CHANGELOG.md edit is not evidence of that — every repo has one —
# so the file-change branch is gated on the repo actually targeting a harness.
# The prompt-wording branch stays ungated: an explicit "what am I missing"
# question is the user asking, not the hook guessing.
targets_ai_platform() {
  [ -f "${repo_root}/CLAUDE.md" ] && return 0
  [ -f "${repo_root}/AGENTS.md" ] && return 0
  [ -f "${repo_root}/GEMINI.md" ] && return 0
  [ -d "${repo_root}/.cursor/rules" ] && return 0
  [ -f "${repo_root}/opencode.json" ] && return 0
  [ -f "${repo_root}/.claude-plugin/plugin.json" ] && return 0
  [ -d "${repo_root}/.claude/skills" ] && return 0
  return 1
}

platform_signal=0
if matches 'up[- ]to[- ]date|new features|latest docs|what am I missing|out of date|current best practice|newest (version|release)'; then
  platform_signal=1
elif targets_ai_platform && git -C "$repo_root" diff --name-only HEAD 2>/dev/null \
     | grep -qE '(^|/)[a-z-]*-?plugin/plugin\.json$|(^|/)CHANGELOG\.md$'; then
  platform_signal=1
fi
if [ "$platform_signal" = 1 ]; then
  add platform-sync "platform-sync — fetches live docs for every AI platform this repo targets and returns a numbered list of features it is not yet using. It never edits the repo."
fi

# --- switch-dev: a rate limit, or an open objective to hand off -------------
switch_signal=0
if matches 'rate[- ]limit|usage limit|out of (tokens|quota)|hit the limit|continue (this )?(on|in) (cursor|codex|gemini|opencode)|switch (to|platform)|pick up where'; then
  switch_signal=1
elif [ -d "${repo_root}/.dev-files/objectives" ] \
     && find "${repo_root}/.dev-files/objectives" -mindepth 1 -maxdepth 1 -print -quit 2>/dev/null | grep -q .; then
  # An open objective only matters when the prompt is about stopping.
  if matches 'hand ?off|resume|later|tomorrow|stop(ping)? here|wrap(ping)? up'; then
    switch_signal=1
  fi
fi
if [ "$switch_signal" = 1 ]; then
  add switch-dev "switch-dev — writes objective/task/handoff state so the work can be resumed on another platform (Cursor, Codex, Gemini CLI, OpenCode) without losing context. Use it before the session ends, not after."
fi

[ "${#suggestions[@]}" -gt 0 ] || exit 0

body="Bundled skills that cover what was just described — invoke the skill, or tell the user in one line that it exists. Do not silently hand-roll the work."
for s in "${suggestions[@]}"; do
  body="${body}"$'\n'"• ${s}"
done

jq -n --arg ctx "$body" \
  '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}'
