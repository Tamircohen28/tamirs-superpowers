#!/usr/bin/env bash
# UserPromptSubmit hook — reject a `/goal` condition that cannot be satisfied by
# construction, before the harness ever accepts it.
#
# WHY THIS BLOCKS INSTEAD OF WARNING
#   dev#637: a `/goal` set on 2026-08-17 fired its Stop-condition gate 21
#   consecutive times and was stopped by Claude Code's own block cap, not by
#   anything in our code. The condition was
#       "complete ci/cd new system and then all of the remaing work … do not
#        yield for anything from me"
#   which contains BOTH clause families below. The gate re-evaluates from
#   scratch every turn with no memory of having already blocked, so identical
#   input yields an identical verdict forever — there is no convergence path.
#
#   The phrasing guidance already exists as prose (the cockpit's
#   docs/reference/tooling.md, "`/goal` conditions — phrase a predicate, not an
#   imperative"). Advice did not prevent the incident: the goal that caused it
#   was typed by someone who could have read that page. A hook that merely adds
#   another warning adds nothing the docs do not already say. The only new thing
#   a hook can contribute is refusing the prompt, so this refuses it.
#
# WHAT IT CANNOT DO — READ THIS BEFORE TRUSTING A PASS
#   This is a HEURISTIC OVER PHRASING. It recognises two known clause families
#   and nothing else. A condition can be perfectly unsatisfiable and sail
#   straight through — "keep going until you are certain", "finish everything",
#   any paraphrase not enumerated below. A PASS FROM THIS HOOK IS NOT EVIDENCE
#   THAT A GOAL IS SATISFIABLE. It means only that two specific phrasings are
#   absent. Do not cite it as proof, and do not extend it into a general
#   satisfiability checker — that is undecidable, not merely unimplemented.
#
# WHY IT DOES NOT BLOCK WHEN IT CANNOT PARSE ITS INPUT
#   A check that cannot run must say so rather than return a quiet success, so
#   every unparseable path below prints a loud, unmistakable message. It still
#   lets the prompt through, deliberately: when parsing fails we cannot even
#   tell whether this was a `/goal` prompt, and blocking every unreadable
#   payload would brick the session over a malformed field. Loud-and-open beats
#   both silent-and-open (the defect) and silent-and-closed (a worse defect).
#
# BLOCKING MECHANISM
#   `exit 2` is the blocking path documented for UserPromptSubmit across every
#   version of the hooks reference: the prompt is erased and stderr is shown to
#   the user. Newer docs also describe a stdout-JSON decision object, and the
#   two dialects disagree on the key name, so the JSON is emitted with both
#   shapes AND the exit code is 2. Whichever contract the running harness
#   honours, the prompt is refused; no shape is load-bearing on its own.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hook-output.sh
source "${SCRIPT_DIR}/lib/hook-output.sh"

# Loud channel for "this check could not run". stderr on a non-blocking exit is
# surfaced to the user without erasing their prompt.
cannot_run() {
  printf '⚠ goal-condition-guard: CHECK DID NOT RUN — %s\n' "$1" >&2
  printf '  Unsatisfiable `/goal` conditions are NOT being screened for this prompt.\n' >&2
  exit 0
}

input="$(hook_read_stdin)"

# No payload at all: hand-run, or a harness that passed nothing. Not a failure —
# there is genuinely no prompt to judge, which is a real state, not a masked one.
[ -n "$(printf '%s' "$input" | tr -d '[:space:]')" ] || exit 0

command -v jq >/dev/null 2>&1 || cannot_run "jq is not installed, so the hook payload cannot be parsed"

printf '%s' "$input" | jq -e . >/dev/null 2>&1 \
  || cannot_run "the hook payload on stdin is not valid JSON"

# `.prompt` is what every hook in this repo reads and what the harness has always
# sent; `.user_input` is the name in the current published schema. Read both, so
# a field rename cannot silently disarm this guard — the failure mode would be a
# hook that passes everything while appearing healthy.
prompt="$(printf '%s' "$input" | jq -r '.prompt // .user_input // empty' 2>/dev/null || true)"

if [ -z "$prompt" ]; then
  # Valid JSON, but neither field is present. Distinguish "the user submitted an
  # empty prompt" (a real, boring state) from "the field we depend on is gone"
  # (a defect that silently disables this hook).
  if printf '%s' "$input" | jq -e 'has("prompt") or has("user_input")' >/dev/null 2>&1; then
    exit 0 # present but empty — nothing to judge
  fi
  cannot_run "the payload has neither .prompt nor .user_input — the field this hook reads may have been renamed"
fi

# Only `/goal`. The sibling matcher in goal-compact-reminder.sh is the proven
# form; narrowed here to the one command whose argument is a stop-condition.
printf '%s' "$prompt" | grep -qiE '^[[:space:]]*/goal([[:space:]]|$)' || exit 0

# The condition is everything after the command word. Spelled with explicit
# character classes rather than sed's `I` flag, which is GNU-only and silently
# does nothing on the BSD sed shipped with macOS.
condition="$(printf '%s' "$prompt" | sed -E 's/^[[:space:]]*\/[Gg][Oo][Aa][Ll][[:space:]]*//')"

if [ -z "$(printf '%s' "$condition" | tr -d '[:space:]')" ]; then
  # Bare `/goal` — querying or clearing the current goal, not setting one.
  # A real state with nothing to screen, so this is a notice, not an alarm.
  printf '· goal-condition-guard: bare `/goal` with no condition text — nothing to screen.\n' >&2
  exit 0
fi

# --- clause family 1: stopping itself is the violation -----------------------
# "do not yield for anything from me", "don't stop", "never halt".
#
# `until`/`till`/`unless` is an EXEMPTION, not a trigger: "do not stop until CI
# is green on main" is a well-formed predicate and one of the shapes the docs
# actually recommend. Blocking it would punish the correct phrasing.
STOPPING_RE='(do[[:space:]]+not|don'"'"'?t|never)[[:space:]]+(yield|stop|halt|pause|rest|quit)'
STOPPING_EXEMPT_RE='(do[[:space:]]+not|don'"'"'?t|never)[[:space:]]+(yield|stop|halt|pause|rest|quit)[[:space:]]+(until|till|unless)'

# --- clause family 2: unbounded and self-replenishing ------------------------
# "all the remaining work", "all work needed", "everything remaining". Doing the
# work produces artifacts the next evaluation reads as new incomplete items.
#
# Deliberately tight: a bare "all" must not trip this. "fix all the failing
# tests" and "run all tests" are bounded, ordinary, and must pass clean.
UNBOUNDED_RE='all([[:space:]]+of)?([[:space:]]+the)?[[:space:]]+(remaining[[:space:]]+work|work[[:space:]]+(needed|required|left|remaining)|rest[[:space:]]+of[[:space:]]+the[[:space:]]+work)|everything([[:space:]]+that)?([[:space:]]+is)?[[:space:]]+(remaining|left|needed)'

offences=""

if printf '%s' "$condition" | grep -qiE "$STOPPING_RE" \
   && ! printf '%s' "$condition" | grep -qiE "$STOPPING_EXEMPT_RE"; then
  clause="$(printf '%s' "$condition" | grep -oiE "${STOPPING_RE}[^,.;]*" | head -1)"
  offences="${offences}
  • stopping-forbidden clause: \"${clause}\"
    Ending the turn is exactly what this forbids, so no world-state lets the
    turn end and satisfy it. Reporting status is a yield; naming a blocked
    dependency is a yield. There is no success state to reach."
fi

if printf '%s' "$condition" | grep -qiE "$UNBOUNDED_RE"; then
  clause="$(printf '%s' "$condition" | grep -oiE "${UNBOUNDED_RE}[^,.;]*" | head -1)"
  offences="${offences}
  • unbounded clause: \"${clause}\"
    Self-replenishing: doing the work produces artifacts (issues filed,
    decisions recorded) that the next evaluation reads as new incomplete
    items. The remaining set never empties."
fi

[ -n "$offences" ] || exit 0

reason="This /goal condition cannot be satisfied by construction — it was rejected before being set.
${offences}

Recorded incident: dev#637, 2026-08-17 — a condition with both clause types
blocked the turn 21 consecutive times and was stopped only by Claude Code's own
block cap. The gate re-evaluates from scratch each turn, so a condition like this
never converges.

Re-issue /goal with a CHECKABLE PREDICATE the gate can evaluate against
observable state:
  /goal until \`gh pr list --state open --repo A --repo B\` is empty
  /goal until issue #N is closed
  /goal until CI is green on main

A predicate also renders an external outage as *pending* rather than *failed*,
which is the behaviour you want when a dependency is down.

(This screen is a phrasing heuristic over two known clause families. It cannot
judge satisfiability in general — passing it is not proof a goal is sound.)"

# Both stdout dialects, plus the exit code. See BLOCKING MECHANISM above.
jq -n --arg r "$reason" \
  '{decision:"block",
    reason:$r,
    hookSpecificOutput:{
      hookEventName:"UserPromptSubmit",
      permissionDecision:"deny",
      permissionDecisionReason:$r
    }}' 2>/dev/null || true

printf '%s\n' "$reason" >&2
exit 2
