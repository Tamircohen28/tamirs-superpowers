#!/usr/bin/env bash
# resolve-permission.sh — decide one plugin action: allow, ask or deny (ADR 004 D4).
#
# Usage:
#   resolve-permission.sh <action-id> [options]
#   resolve-permission.sh --action <action-id> [options]
#   resolve-permission.sh --level [--skill <id>] [--host <h>] [--repo <path>]
#   resolve-permission.sh -h | --help
#
# Options:
#   --skill <id>        the skill taking the step (per-skill and per-group levels)
#   --target <t>        what it acts on; for pr.merge.auto trust: a PR number (the
#                       repo gh would use: GH_REPO, else origin), <owner>/<repo>[#n],
#                       <host>/<owner>/<repo>[#n] or a PR URL
#   --repo <path>       the checkout (default: the working directory)
#   --host <h>          claude | codex | cursor | gemini | opencode. Selects the option
#                       store that may set the level. Without it every store may only
#                       LOWER the level (an unknown host reads as one with no store).
#   --headless          no human present: ask becomes deny (D2)
#   --objective <id>    read .dev-files/objectives/<id>/objective.json (and
#                       $OBJECTIVES_ROOT/<id>/) delivery.auto_merge (D4 row 3)
#   --call <token>      the L1 call stamp (D8): no <state>/seen/<token> from the guard
#                       means the call is answered as supervised
#   --cond <name>=true|false
#                       a catalog condition the caller established (repeatable). A
#                       raise or invariant deny applies unless its condition is
#                       established false; a precondition holds only when true.
#   --level             print the effective level and its sources instead
#   --explain           a readable trace instead of JSON (with --json: JSON + trace)
#   --json              JSON output (the default)
#
# Output (JSON, one object):
#   {action, requested, effective_action, r, level, level_source, level_sources[],
#    verdict: allow|ask|deny, decision (= verdict), reason, decided_by,
#    deny_wins_from, never_auto, precondition {name, state}, raised_by[],
#    unclassified, headless, headless_ask_to_deny, setting_that_would_allow
#    {once, durable[], note}, allow_with (= setting_that_would_allow), skill, host,
#    target, home_source, warnings[]}
#
# Exit: 0 for a decided verdict (allow, ask or deny); 2 for a usage error; 3 for
# an internal error (missing or corrupt catalog or schema, no python3, a crash).
# On 2 and 3 the JSON verdict is deny: a caller that cannot run the resolver,
# gets a non-zero exit or cannot parse the output must deny (D4, SR S-12).
#
# PRECEDENCE (D4, highest first; "tighten" moves only toward deny)
#   0  safety invariants (catalog denies), R4 never allow, never_auto never allow
#   1  --perms= tickets (D5) -- not read yet: nothing in this resolver raises
#   2  TAMIRS_AUTO_MERGE: never => pr.merge.auto deny; always => ignored + warning
#   3  objective delivery.auto_merge: false => deny; true => grants nothing
#   4  project file <repo>/.tamirs-superpowers/permissions.json: tightens; widens
#      only actions["pr.merge.auto"], only with a matching trust entry in a verified
#      user file (sha256, repo realpath, remote = origin = target). Legacy
#      .dev-files/policy.json delivery.auto_merge is tighten-only.
#   5  user file: skill_actions > actions > skills > groups (may widen). Any deny
#      is final.
#   6  level = the lower of the host's option store and the user file's level;
#      an absent source is skipped. TS_PERMISSION_LEVEL and
#      CLAUDE_PLUGIN_OPTION_PERMISSION_LEVEL only lower it.
#   7  supervised
#   An unknown action id is UNCLASSIFIED: R4. Where the files live and how they
#   are checked: scripts/lib/permission-common.sh.
#
# Examples:
#   resolve-permission.sh pr.create --skill pr-dev --host claude
#   resolve-permission.sh --action pr.merge.auto --target 42 --skill pr-dev --headless
#   resolve-permission.sh git.push.branch --cond default_branch=false --cond tag_ref=false
set -uo pipefail

usage() {
  local line n=0
  while IFS= read -r line; do
    n=$((n + 1))
    [ "$n" -eq 1 ] && continue
    case "$line" in
      '#'*) line="${line#\#}"; printf '%s\n' "${line# }" ;;
      *) break ;;
    esac
  done < "${BASH_SOURCE[0]}"
}

for _arg in "$@"; do
  case "$_arg" in -h|--help) usage; exit 0 ;; esac
done
unset _arg

case "${BASH_SOURCE[0]}" in
  */*) _here="${BASH_SOURCE[0]%/*}" ;;
  *) _here=. ;;
esac

# shellcheck source=scripts/lib/permission-common.sh
if ! . "$_here/lib/permission-common.sh" 2>/dev/null || ! command -v perm_resolve >/dev/null 2>&1; then
  printf '%s\n' '{"action": null, "r": 4, "level": null, "level_source": null, "level_sources": [], "verdict": "deny", "decision": "deny", "reason": "denied: resolver error: scripts/lib/permission-common.sh is missing (fail closed, D4, SR S-12)", "decided_by": "resolver-error", "deny_wins_from": "resolver-error", "never_auto": true, "precondition": null, "headless_ask_to_deny": false, "setting_that_would_allow": null, "allow_with": null, "warnings": ["permission-common.sh is missing"], "error": "permission-common.sh is missing"}'
  exit 3
fi

perm_resolve "$@"
exit $?
