#!/usr/bin/env bash
# gate.sh — mcp-builder's permission gate (ADR 004 L1: a resolver call before
# the step; D4 precedence, D8 enforcement).
#
# Usage:
#   bash gate.sh <action-id> <target> [--headless] [--host <h>] [--cond <name>=true|false]...
#
#   <action-id>  the catalog id of the step (core/permissions/actions.json):
#                  config.global.write   a client config outside the project
#                                        (user-level Claude Code config,
#                                        claude_desktop_config.json, ~/.codex,
#                                        ~/.cursor, ~/.gemini, ~/.config/opencode)
#                  pkg.install.network   npm install <pkgs>, pip install <pkgs>
#                  pkg.exec.network      npx <pkg>, fastmcp dev (runs the inspector)
#   <target>     the exact file (config) or the exact command (install/exec):
#                it is what the user is shown and what they approve.
#   --headless   no human in the chat (a subagent, a workflow, claude -p, CI):
#                ask becomes deny. CI=true in the environment implies it.
#   --host, --cond  passed to the resolver unchanged.
#
# Output: one line on stdout, then the exit code says what to do:
#   0   allow    proceed.
#   10  ask      show the user the action and the target exactly as printed and
#                proceed only on an explicit "yes" in chat; anything else is no.
#   3   blocked  do not proceed and do not work around it: the line names the
#                reason and the setting that would allow it.
#   2   usage error (also: do not proceed).
#
# The resolver is found from this file's own location
# (<plugin>/skills/mcp/mcp-builder/scripts/ -> <plugin>/scripts/), never from an
# environment variable, so the plugin works from its install cache. Anything
# short of a parsed verdict — no resolver, a non-zero exit, no JSON, no verdict
# — is blocked (fail closed, D4). No flag here skips an ask: there is no --yes.
set -uo pipefail

usage() { sed -n '4,27p' "$0" | sed 's/^# \{0,1\}//' >&2; exit 2; }

[ "$#" -ge 2 ] || usage
ACTION="$1" TARGET="$2"; shift 2
case "$ACTION" in ''|-*) usage ;; esac
[ -n "$TARGET" ] || usage

EXTRA=()
HEADLESS=0
case "${CI:-}" in ''|0|false|False|FALSE) : ;; *) HEADLESS=1 ;; esac
while [ "$#" -gt 0 ]; do
  case "$1" in
    --headless) HEADLESS=1; shift ;;
    --host|--cond) [ "$#" -ge 2 ] || usage; EXTRA+=("$1" "$2"); shift 2 ;;
    *) usage ;;
  esac
done
[ "$HEADLESS" = 1 ] && EXTRA+=(--headless)

case "${BASH_SOURCE[0]}" in
  */*) here="${BASH_SOURCE[0]%/*}" ;;
  *) here=. ;;
esac
RESOLVER="$(CDPATH='' cd -- "$here/../../../.." 2>/dev/null && pwd -P)/scripts/resolve-permission.sh"

blocked() { printf 'blocked: %s on %s — %s\n' "$ACTION" "$TARGET" "$1"; exit 3; }

command -v jq >/dev/null 2>&1 || blocked "jq is not installed, so the permission answer cannot be read (fail closed)"
[ -f "$RESOLVER" ] || blocked "the permission resolver (scripts/resolve-permission.sh) is missing (fail closed)"

out="$(bash "$RESOLVER" "$ACTION" --skill mcp-builder --target "$TARGET" --json ${EXTRA[@]+"${EXTRA[@]}"} </dev/null 2>/dev/null)"
rc=$?
[ "$rc" -eq 0 ] || blocked "the permission resolver exited $rc (fail closed)"
verdict="$(jq -r 'if type == "object" then (.verdict // "") else "" end' <<<"$out" 2>/dev/null)" \
  || blocked "the permission resolver printed no JSON (fail closed)"
reason="$(jq -r '.reason // ""' <<<"$out" 2>/dev/null)"
r="$(jq -r '.r // "?"' <<<"$out" 2>/dev/null)"
setting="$(jq -r '
  (.setting_that_would_allow // {}) as $s
  | [ (if $s.once then "once: \($s.once)" else empty end),
      (if (($s.durable // []) | length) > 0 then "durable: \($s.durable | join("; "))" else empty end),
      ($s.note // empty) ]
  | join(" ")' <<<"$out" 2>/dev/null)"

case "$verdict" in
  allow)
    printf 'allow: %s on %s\n' "$ACTION" "$TARGET"
    exit 0 ;;
  ask)
    printf 'ask: %s (R%s) on %s — %s. Show the user this action and target exactly, and proceed only on an explicit "yes" in chat; anything else is a no.\n' \
      "$ACTION" "$r" "$TARGET" "$reason"
    exit 10 ;;
  deny)
    blocked "${reason:-denied}${setting:+ — allow with: $setting}" ;;
  *)
    blocked "the permission resolver gave no verdict (fail closed)" ;;
esac
