#!/usr/bin/env bash
# UserPromptSubmit hook — refuse to arm a `/goal` condition that cannot terminate.
#
# WHY THIS BLOCKS INSTEAD OF ADVISING
#   Claude Code's built-in `/goal` evaluator re-judges the condition from scratch
#   on every turn-end, with no memory of having already blocked and without
#   consulting `stop_hook_active`. So a condition that is unsatisfiable IN
#   PRINCIPLE does not fail once — it blocks every turn until the harness block
#   cap trips or the user runs `/goal clear`. Observed twice on this machine:
#   2026-08-17 (21 consecutive blocks) and 2026-08-31 (~15).
#
#   An ADVISORY hook was tried first and does not work, for a reason worth
#   recording: the `/goal` command injects, in the same turn, "treat the
#   condition itself as your directive and do not pause to ask the user what to
#   do." Advisory `additionalContext` asking the model to stop and question the
#   condition is competing with a first-party instruction telling it not to
#   pause, and it loses. `goal-compact-reminder.sh` fired correctly on
#   2026-08-31 and was ignored for exactly this reason. The only intervention
#   that survives the conflict is one that prevents the prompt from being
#   processed at all.
#
# WHY THE MENU IS TEXT AND NOT AN AskUserQuestion PICKER
#   A blocked UserPromptSubmit prompt is erased and Claude gets no turn, so
#   there is no opportunity to render an interactive picker. The block reason is
#   therefore written AS the menu: a one-line diagnosis, two ready-to-paste
#   rewrites, a keep-as-is escape, and a free-form option. That is the same
#   shape as the `decision` skill's menu, delivered in the only place the
#   harness leaves available.
#
# WHAT IT DOES *NOT* BLOCK
#   Deliberately narrow. Only two families of phrasing are refused, both with no
#   legitimate use:
#     1. "do not yield" / "don't stop" — makes STOPPING the violation, so no
#        state of the world can satisfy it; ending the turn is what it forbids.
#     2. unbounded scope ("all remaining work", "everything left") with no
#        carve-out for externally-blocked work — third-party-gated work still
#        counts as "remaining", so the condition stays false no matter what the
#        session does.
#   A condition that names a checkable predicate, or that already carries a
#   carve-out, passes untouched. `/goal clear`, `/goal status` and a bare
#   `/goal` are never touched. False positives cost the user a real workflow, so
#   the bar for adding a pattern here is "there is no phrasing of this that can
#   terminate", not "this looks risky".
#
# ONE THING VERIFIED BY DOCS, AND ONE THING NOT
#   Verified against code.claude.com/docs/en/hooks: `decision:"block"` is a
#   valid UserPromptSubmit output, `reason` is shown to the USER, and a blocked
#   prompt is "erased" with Claude never running. That last point is why the
#   menu is text -- there is no turn in which to render a picker, and
#   `additionalContext` cannot be combined with a block.
#
#   NOT settled by the docs: whether erasing the prompt also prevents a SLASH
#   COMMAND's local side effect -- i.e. whether `/goal` still arms its condition
#   before this hook's block lands. Ordering suggests it does not (the hook runs
#   on submission; command expansion happens during processing), but that is
#   inference, not documentation, and it was deliberately not tested because the
#   only way to test it is to arm a known-bad goal and reproduce the incident.
#   The block message therefore tells the user to run `/goal clear` if the
#   condition armed anyway, which is correct under either behaviour.
#
# ESCAPE HATCH
#   `/goal force: <condition>` arms verbatim. The user overrides; the hook never
#   gets a second opinion. Documented in the block message itself so it is
#   discoverable at exactly the moment it is wanted.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hook-output.sh
source "${SCRIPT_DIR}/lib/hook-output.sh"

input="$(hook_read_stdin)"
prompt="$(printf '%s' "$input" | jq -r '.prompt // empty' 2>/dev/null)"

# Not a /goal invocation at all -> silent pass.
printf '%s' "$prompt" | grep -qiE '^[[:space:]]*/goal([[:space:]]|$)' || exit 0

# Everything after the command word, trimmed.
condition="$(printf '%s' "$prompt" \
  | sed -E 's@^[[:space:]]*/goal[[:space:]]*@@' \
  | sed -E 's@^[[:space:]]+@@; s@[[:space:]]+$@@')"

# Bare `/goal`, and the management subcommands, carry no condition to lint.
case "$(printf '%s' "$condition" | tr '[:upper:]' '[:lower:]')" in
  ""|clear|status|show|list) exit 0 ;;
esac

# Explicit override: user has seen the objection and wants it anyway.
if printf '%s' "$condition" | grep -qiE '^force:'; then exit 0; fi

lower="$(printf '%s' "$condition" | tr '[:upper:]' '[:lower:]')"

# --- Pattern 1: stopping is itself the violation -----------------------------
NEVER_STOP=''
if printf '%s' "$lower" | grep -qE "do( not|n'?t) (yield|stop|halt|pause|ask)|never (yield|stop|halt)|without (stopping|yielding|pausing)|keep going until (everything|all|it'?s all)"; then
  NEVER_STOP=1
fi

# --- Pattern 2: unbounded scope with no external-gate carve-out --------------
UNBOUNDED=''
if printf '%s' "$lower" | grep -qE "(all|every|any) (of the )?(the )?(remaining|outstanding|open|left ?over|pending) (work|tasks?|items?|things?)|everything (thats? )?(left|remaining|open|pending)|complete everything|finish everything|all remain"; then
  UNBOUNDED=1
fi

# A carve-out makes an unbounded scope terminate: external blockers become an
# accepted end state rather than an outstanding item.
if [ -n "$UNBOUNDED" ] && printf '%s' "$lower" | grep -qE "exclud|except|other than|apart from|unless blocked|not blocked|skip(ping)? (anything|what) ?(is )?blocked|report (anything|what) ?(is )?blocked|stop and report|that (i|you) can|within (my|your) control|actionable"; then
  UNBOUNDED=''
fi

[ -z "$NEVER_STOP" ] && [ -z "$UNBOUNDED" ] && exit 0

# ---------------------------------------------------------------------------
# Build the menu. Two rewrites, both derived from the user's own words so they
# read as the same goal made checkable rather than a different goal.
# ---------------------------------------------------------------------------
if [ -n "$NEVER_STOP" ]; then
  why="it forbids stopping, so **ending any turn is the violation** — no state of the world can satisfy it."
  fix_a="work through the open items, then stop and report what is left"
else
  why="\"all remaining work\" counts work blocked on someone else as still remaining, so it **stays false no matter what gets done**."
  # Strip a trailing . or ; first, or the clause reads "…validated., excluding…".
  fix_a="$(printf '%s' "$condition" | sed -E 's@[.;[:space:]]+$@@')"
  fix_a="${fix_a}, excluding anything blocked on billing, an upstream release, or my decision"
fi
fix_b="until \`gh pr list --state open\` is empty in the repos we touched, or the only ones left are blocked on something outside this session"

# jq -Rs would escape the whole thing as one string; assemble with --arg so the
# reason survives quotes, backticks and newlines in the user's own condition.
reason="$(jq -rn \
  --arg cond "$condition" \
  --arg why "$why" \
  --arg a "$fix_a" \
  --arg b "$fix_b" \
  '"⛔ /goal not armed — this condition cannot terminate.\n\nYou asked for:\n  \($cond)\n\nProblem: \($why)\nA goal like this blocks every turn-end until the harness cap trips or you run /goal clear. It has happened twice: 2026-08-17 (21 blocks) and 2026-08-31 (~15).\n\nPick one — paste a line:\n\n  1) /goal \($a)\n     (recommended — same intent, but a real blocker ENDS it instead of extending it)\n\n  2) /goal \($b)\n     (a predicate a command can answer yes/no)\n\n  3) /goal force: \($cond)\n     (keep it exactly as written — arms verbatim, no further checks)\n\n  4) /goal <your own wording>\n\nIf the condition armed anyway (the harness may run a slash command before this\nhook blocks), run /goal clear first — then paste your choice.\n\nRule of thumb: a goal terminates when a command can answer it yes/no, and when \"blocked on someone else\" counts as done rather than outstanding."')"

# Claude Code: block the prompt; the reason is shown to the user.
# `decision: block` is the documented UserPromptSubmit form; the exit-2 path is
# not used because it routes to stderr and loses the formatting.
jq -n --arg reason "$reason" '{decision:"block", reason:$reason}'
exit 0
