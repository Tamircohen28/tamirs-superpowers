#!/usr/bin/env bash
# enable-repo-merge-settings.sh — allow PR auto-merge and delete head branch on merge.
#
# Required by start-dev / pr-dev (gh pr merge --auto --delete-branch).
#
# Usage: enable-repo-merge-settings.sh [owner/repo] [--apply] [--skill <id>]
#
# Without --apply this is a dry run: it prints the exact PATCH it would send and
# writes nothing. --apply sends it, but only after the permission resolver
# (scripts/resolve-permission.sh, ADR 004 D4) is asked about repo.settings.merge
# (R3, never automatic):
#   allow  -> PATCH
#   ask    -> show the PATCH and confirm on /dev/tty; no terminal => stop (exit 3)
#             and print the command to run yourself (ADR 004 D2: no human => deny)
#   deny   -> stop (exit 3) with the resolver's reason and the setting that would
#             allow it
# A resolver that is missing, exits non-zero or prints no verdict is a deny (D4).
#
# Exit: 0 dry run printed or PATCH sent; 1 usage or gh failure; 3 not applied
# (denied, declined, or no terminal to confirm on).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# skills/repo/_contract/scripts -> the plugin root. Found from this file, never from env.
RESOLVER="$SCRIPT_DIR/../../../../scripts/resolve-permission.sh"

REPO=""
APPLY=""
SKILL=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --skill) shift; [[ $# -gt 0 ]] || { echo "enable-repo-merge-settings: --skill needs an id" >&2; exit 1; }; SKILL="$1" ;;
    --skill=*) SKILL="${1#*=}" ;;
    -h|--help) sed -n '2,21p' "${BASH_SOURCE[0]}" | sed -E 's/^# ?//'; exit 0 ;;
    -*) echo "enable-repo-merge-settings: unknown flag: $1" >&2; exit 1 ;;
    *) [[ -z "$REPO" ]] || { echo "enable-repo-merge-settings: one repository only" >&2; exit 1; }; REPO="$1" ;;
  esac
  shift
done

if [[ -z "$REPO" ]]; then
  command -v gh &>/dev/null || { echo "enable-repo-merge-settings: gh required" >&2; exit 1; }
  REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner)
fi

BODY='{"allow_auto_merge":true,"delete_branch_on_merge":true}'
show_patch() {
  printf 'PATCH repos/%s\n%s\n' "$REPO" "$BODY"
}

if [[ -z "$APPLY" ]]; then
  echo "dry run (nothing written) — repo.settings.merge would send:"
  show_patch
  echo "re-run with --apply to send it."
  exit 0
fi

stop() {
  echo "blocked: $1" >&2
  [[ -n "${2:-}" ]] && echo "allow with: $2" >&2
  echo "nothing was written. To send it yourself, in your own terminal:" >&2
  echo "  bash $SCRIPT_DIR/enable-repo-merge-settings.sh $REPO --apply" >&2
  exit 3
}

# A person can answer only when this run has a terminal of its own.
can_prompt() { [[ -t 1 ]] && { : </dev/tty; } 2>/dev/null; }

v=""
if [[ -f "$RESOLVER" ]]; then
  v="$(bash "$RESOLVER" --action repo.settings.merge --target "$REPO" ${SKILL:+--skill "$SKILL"} --json 2>/dev/null)" || v=""
fi
[[ -n "$v" ]] || v='{"verdict":"deny","reason":"permission resolver missing or failed (fail closed, ADR 004 D4)"}'
verdict="$(jq -r '.verdict // "deny"' <<<"$v" 2>/dev/null)" || verdict=deny
reason="$(jq -r '.reason // .decided_by // "no reason given"' <<<"$v" 2>/dev/null)" || reason="unparseable resolver output"
setting="$(jq -r '.setting_that_would_allow | if . == null then "" elif type == "object" then ([.once // empty] + (.durable // []) + [.note // empty] | join("; ")) else tostring end' <<<"$v" 2>/dev/null)" || setting=""

case "$verdict" in
  allow) ;;
  ask)
    can_prompt || stop "repo.settings.merge asks for a person and this run has no terminal ($reason)" "$setting"
    echo "repo.settings.merge on $REPO ($reason):"
    show_patch
    printf 'Send this PATCH? [y/N] ' >/dev/tty
    ans=""; IFS= read -r ans </dev/tty || ans=""
    case "$ans" in y|Y|yes|YES) ;; *) stop "declined at the terminal" ;; esac
    ;;
  *) stop "$reason" "$setting" ;;
esac

gh api -X PATCH "repos/$REPO" \
  -f allow_auto_merge=true \
  -f delete_branch_on_merge=true
