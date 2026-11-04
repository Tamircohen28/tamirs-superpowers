#!/usr/bin/env bash
# repo-create-gate.sh — the L1 gate repo-scaffold runs before it creates a repository.
#
# Usage:
#   repo-create-gate.sh --repo <owner/name> --visibility <private|public|internal>
#                       [--description <text>] [--headless] [--host <h>]
#
# Asks scripts/resolve-permission.sh (ADR 004 D4) about repo.create (R4: never
# automatic, D2) for exactly this repository, and prints the exact action so the
# person approving it sees owner, name and visibility. It never creates anything:
# the caller runs the create itself, as its own visible call, so the host's own
# prompt on that call (ADR 004 D5) still sees it.
#
#   exit 0   allow: proceed
#   exit 10  ask: show the printed action to the user and proceed only on an
#            explicit yes for this repository in this conversation
#   exit 3   blocked: denied, headless (--headless turns ask into deny, D2), or
#            the resolver is missing, failed or printed no verdict (fail closed)
#   exit 2   usage error
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# skills/repo/repo-scaffold/scripts -> the plugin root. Found from this file, never from env.
RESOLVER="$SCRIPT_DIR/../../../../scripts/resolve-permission.sh"

usage() { sed -n '2,19p' "${BASH_SOURCE[0]}" | sed -E 's/^# ?//'; exit "${1:-0}"; }

REPO="" VIS="" DESC="" HEADLESS="" HOST=""
while [ $# -gt 0 ]; do
  case "$1" in
    --repo)        shift; REPO="${1:-}" ;;
    --visibility)  shift; VIS="${1:-}" ;;
    --description) shift; DESC="${1:-}" ;;
    --headless)    HEADLESS=1 ;;
    --host)        shift; HOST="${1:-}" ;;
    -h|--help)     usage 0 ;;
    *) echo "repo-create-gate: unexpected argument: $1" >&2; usage 2 >&2 ;;
  esac
  shift
done
case "$REPO" in */*) ;; *) echo "repo-create-gate: --repo must be owner/name" >&2; exit 2 ;; esac
case "$VIS" in private|public|internal) ;; *) echo "repo-create-gate: --visibility must be private, public or internal" >&2; exit 2 ;; esac

echo "action: repo.create (R4) — create the $VIS GitHub repository $REPO${DESC:+ — \"$DESC\"}"

v=""
if [ -f "$RESOLVER" ]; then
  v="$(bash "$RESOLVER" --action repo.create --skill repo-scaffold --target "$REPO" \
        ${HOST:+--host "$HOST"} ${HEADLESS:+--headless} --json 2>/dev/null)" || v=""
fi
[ -n "$v" ] || v='{"verdict":"deny","reason":"permission resolver missing or failed (fail closed, ADR 004 D4)"}'
verdict="$(jq -r '.verdict // "deny"' <<<"$v" 2>/dev/null)" || verdict=deny
reason="$(jq -r '.reason // .decided_by // "no reason given"' <<<"$v" 2>/dev/null)" || reason="unparseable resolver output"
setting="$(jq -r '.setting_that_would_allow | if . == null then "" elif type == "object" then ([.once // empty] + (.durable // []) + [.note // empty] | join("; ")) else tostring end' <<<"$v" 2>/dev/null)" || setting=""

# --headless is a promise there is no one to ask: an ask is a deny (D2) even if
# the resolver answered from a stale or stubbed context.
[ "$verdict" = ask ] && [ -n "$HEADLESS" ] && { verdict=deny; reason="headless: no human present, so ask becomes deny (D2)"; }

case "$verdict" in
  allow) echo "verdict: allow ($reason)"; exit 0 ;;
  ask)
    echo "verdict: ask ($reason)"
    echo "confirm: ask the user to approve creating the $VIS repository $REPO; create it only on an explicit yes."
    exit 10 ;;
  *)
    echo "blocked: $reason${setting:+ — allow with: $setting}"
    echo "nothing was created. To create it yourself: gh repo create $REPO --$VIS"
    exit 3 ;;
esac
