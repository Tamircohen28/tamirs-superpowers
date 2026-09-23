#!/usr/bin/env bash
# rate-limit-handoff.sh — StopFailure hook, matcher `rate_limit` (ADVISORY, never blocks).
#
# WHY THIS EXISTS
#   switch-dev is the skill that writes objective/task/handoff state so work can
#   resume on another platform. It is precisely what you want when a session dies
#   on a rate limit — and it was invoked zero times across 953 sessions. The
#   reason was never that nobody needed it: it is that the moment you need it is
#   the moment you cannot ask for it. The turn has already ended. There is no
#   next model turn to inject context into, and the user is looking at an error,
#   not a prompt they can type a slash command into.
#
#   `StopFailure` with `"matcher": "rate_limit"` is the one signal that fires at
#   exactly that moment. The matcher is a documented error-type value alongside
#   `overloaded`, `authentication_failed`, `billing_error`, `server_error` and
#   others, so this fires on rate-limit exhaustion specifically and stays silent
#   for every other API failure — an auth error is not a handoff situation.
#
# WHY systemMessage AND NOT additionalContext
#   Same reasoning as handoff-reminder.sh: `additionalContext` is a model-visible
#   channel, and on a failed turn there is no model turn left to read it. The
#   person who needs this message is the user. `systemMessage` is what renders in
#   their UI. Getting this backwards would make the hook fire correctly and be
#   seen by nobody — the exact anti-pattern the CHANGELOG records for
#   plugin-version-watch.sh, in the opposite direction.
#
# CONTRACT
#   - Never blocks. Always exits 0. Silent when it has nothing useful to add.
#   - Names the resumable work when it can find it, because "run /switch-dev" is
#     advice and "run /switch-dev handoff #182, you have 3 uncommitted files" is
#     a decision.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hook-output.sh
source "${SCRIPT_DIR}/lib/hook-output.sh"

input="$(hook_read_stdin)"
cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2>/dev/null || true)"
[ -n "$cwd" ] || cwd="$PWD"

# Is there anything worth handing off? A rate limit that interrupts a read-only
# session costs nothing, and a reminder there is just noise at a bad moment.
uncommitted=0
branch=""
if git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  uncommitted="$(git -C "$cwd" status --porcelain 2>/dev/null | grep -c . || true)"
  branch="$(git -C "$cwd" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
fi

repo_root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || printf '%s' "$cwd")"
open_objective=""
if [ -d "${repo_root}/.dev-files/objectives" ]; then
  open_objective="$(
    find "${repo_root}/.dev-files/objectives" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null \
      | head -1 | xargs -I{} basename {} 2>/dev/null || true
  )"
fi

# Nothing in flight: stay quiet rather than train the user to ignore this hook.
if [ "$uncommitted" -eq 0 ] && [ -z "$open_objective" ]; then
  echo '{"suppressOutput": true}'
  exit 0
fi

detail=""
[ "$uncommitted" -gt 0 ] && detail="${uncommitted} uncommitted file(s)"
if [ -n "$open_objective" ]; then
  [ -n "$detail" ] && detail="${detail}, "
  detail="${detail}open objective '${open_objective}'"
fi
[ -n "$branch" ] && detail="${detail} on ${branch}"

msg="Rate limit ended this turn — ${detail}. /switch-dev handoff writes the objective, task and handoff state to disk so this work resumes on Cursor, Codex, Gemini CLI or OpenCode without re-deriving context. Run it before the window closes; it does not need a model turn to be useful later."

jq -n --arg msg "$msg" '{systemMessage: $msg}'
