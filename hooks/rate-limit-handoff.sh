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
#   - Also drops the same facts as data, for the next session rather than the
#     user: .dev-files/handoffs/rate-limit-<ts>.json, shape and readers in
#     docs/engineering/architecture/handoff-protocol.md. Only when a .dev-files/
#     workspace already exists, and never on stdout — see the block at the end.
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

# ---------------------------------------------------------------------------
# THE STRUCTURED RECORD (docs/engineering/architecture/handoff-protocol.md)
#
#   The systemMessage above reaches the user and nobody else. The next session,
#   a sibling session, an orchestrator, or diagnose-objective needs the same
#   facts as data, so the hook also drops a rate-limit handoff record at
#   .dev-files/handoffs/rate-limit-<ts>.json — but only when the repository
#   already keeps a .dev-files/ workspace. Creating one in a repository that
#   never opted in, at the exact moment a session dies, is a side effect nobody
#   asked for; a repository without the workspace gets the message only.
#
#   The messaging socket. Claude Code exports CLAUDE_CODE_MESSAGING_SOCKET and
#   CLAUDE_CODE_MESSAGING_TOKEN to hooks so "a script or hook can post into a
#   session". What the docs specify (cross-session-messaging, env-vars; read
#   2026-10-17): a Unix domain socket, an optional first line
#   {"type":"auth","token":"<token>"} (required on native Windows), a complete
#   line within 30 seconds, and own-child verification by process evidence or
#   that token. What they do not specify: the JSON shape of the message line
#   itself. A guessed line is either dropped or delivered as noise, so nothing
#   is written to the socket. The record names the socket path (not a secret)
#   so a reader that knows the protocol can post; the token is never written
#   anywhere. When the line format is published, posting belongs here, after
#   the record is on disk, and the record's `messaging.posted` flips to true.
#
#   Nothing in this block may change the stdout above or the exit status: every
#   failure path returns quietly and the systemMessage is emitted regardless.
# ---------------------------------------------------------------------------
write_handoff_record() {
  local ws="${repo_root}/.dev-files" dir f ts session_id resume socket reason
  [ -d "$ws" ] || return 0
  dir="${ws}/handoffs"
  mkdir -p "$dir" 2>/dev/null || return 0
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  f="${dir}/rate-limit-${ts}.json"
  # Second record in the same second: a suffix that still sorts after the first.
  [ -e "$f" ] && f="${dir}/rate-limit-${ts}_$$.json"
  session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2>/dev/null || true)"
  if [ -n "$open_objective" ]; then
    resume="/switch-dev handoff objective=${open_objective}"
  else
    resume="/switch-dev handoff"
  fi
  socket="${CLAUDE_CODE_MESSAGING_SOCKET:-}"
  if [ -n "$socket" ] && [ -n "${CLAUDE_CODE_MESSAGING_TOKEN:-}" ]; then
    if [ -S "$socket" ]; then
      reason="messaging socket exported, but the message line format is undocumented; nothing was posted"
    else
      reason="messaging socket path exported, but no socket exists at it; nothing was posted"
    fi
  else
    reason="no messaging socket exported to this hook"
  fi
  jq -n \
    --arg written_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg session_id "$session_id" \
    --arg cwd "$cwd" \
    --arg branch "$branch" \
    --arg objective "$open_objective" \
    --argjson uncommitted "$((uncommitted + 0))" \
    --arg resume "$resume" \
    --arg message "$msg" \
    --arg socket "$socket" \
    --arg reason "$reason" \
    '{
      kind: "rate-limit-handoff",
      schema_version: 1,
      written_at: $written_at,
      session_id: (if $session_id == "" then null else $session_id end),
      cwd: $cwd,
      branch: (if $branch == "" then null else $branch end),
      objective: (if $objective == "" then null else $objective end),
      uncommitted: $uncommitted,
      resume: $resume,
      message: $message,
      messaging: {
        socket: (if $socket == "" then null else $socket end),
        posted: false,
        reason: $reason
      }
    }' > "${f}.tmp" && mv "${f}.tmp" "$f"
}
write_handoff_record 2>/dev/null || true

jq -n --arg msg "$msg" '{systemMessage: $msg}'
