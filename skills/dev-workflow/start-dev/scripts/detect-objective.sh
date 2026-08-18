#!/usr/bin/env bash
# detect-objective.sh — decide which mode the start-dev facade must run in.
#
# Usage:
#   detect-objective.sh [repo_root]
#
# Prints one JSON object and always exits 0 (routing is advisory, never fatal):
#   {
#     "mode": "worker-only" | "worker-and-deliver",
#     "objective_id": "auth-system" | null,
#     "objective_file": ".dev-files/objectives/auth-system/objective.json" | null,
#     "orchestrated": true | false,
#     "reason": "<one line explaining the decision>"
#   }
#
# mode=worker-only  -> an objective already owns this work. Run worker-dev and
#                      stop at commit + handoff. Do NOT open a PR; deliver-dev
#                      (driven by orchestrate-dev) owns delivery for the whole
#                      objective.
# mode=worker-and-deliver -> no objective owns this work. Standalone task:
#                      worker-dev then deliver-dev.
#
# Signals, highest precedence first:
#   1. TAMIRS_OBJECTIVE_ID / OBJECTIVE_ID env var set by the orchestrator
#   2. TAMIRS_ORCHESTRATED=1 (orchestrator invoked us without naming an id)
#   3. an objective.json under .dev-files/objectives/ whose status is not
#      completed/abandoned
#
# Never reads stdin. Degrades to worker-and-deliver when jq is unavailable.
set -euo pipefail

usage() {
  sed -n '2,30p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage 0
fi

REPO_ROOT="${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}"
OBJ_DIR="$REPO_ROOT/.dev-files/objectives"

emit() {
  # emit <mode> <objective_id|""> <objective_file|""> <orchestrated> <reason>
  if command -v jq >/dev/null 2>&1; then
    jq -nc \
      --arg mode "$1" \
      --arg id "$2" \
      --arg file "$3" \
      --argjson orchestrated "$4" \
      --arg reason "$5" \
      '{mode: $mode,
        objective_id: ($id | if . == "" then null else . end),
        objective_file: ($file | if . == "" then null else . end),
        orchestrated: $orchestrated,
        reason: $reason}'
  else
    printf '{"mode":"%s","objective_id":%s,"objective_file":%s,"orchestrated":%s,"reason":"%s"}\n' \
      "$1" \
      "$([ -n "$2" ] && printf '"%s"' "$2" || printf 'null')" \
      "$([ -n "$3" ] && printf '"%s"' "$3" || printf 'null')" \
      "$4" "$5"
  fi
  exit 0
}

ENV_ID="${TAMIRS_OBJECTIVE_ID:-${OBJECTIVE_ID:-}}"
if [[ -n "$ENV_ID" ]]; then
  FILE="$OBJ_DIR/$ENV_ID/objective.json"
  [[ -f "$FILE" ]] || FILE=""
  emit "worker-only" "$ENV_ID" "$FILE" true \
    "objective id supplied by the caller via TAMIRS_OBJECTIVE_ID/OBJECTIVE_ID"
fi

if [[ "${TAMIRS_ORCHESTRATED:-}" == "1" ]]; then
  emit "worker-only" "" "" true \
    "TAMIRS_ORCHESTRATED=1 — an orchestrator owns delivery for this run"
fi

if [[ -d "$OBJ_DIR" ]]; then
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    status="unknown"
    id="$(basename "$(dirname "$f")")"
    if command -v jq >/dev/null 2>&1; then
      status="$(jq -r '.status // "unknown"' "$f" 2>/dev/null || echo unknown)"
      id="$(jq -r --arg fallback "$id" '.id // $fallback' "$f" 2>/dev/null || echo "$id")"
    fi
    case "$status" in
      completed|abandoned) continue ;;
    esac
    emit "worker-only" "$id" "${f#"$REPO_ROOT"/}" false \
      "active objective '$id' (status=$status) already owns delivery"
  done < <(find "$OBJ_DIR" -mindepth 2 -maxdepth 2 -name objective.json -print 2>/dev/null | sort)
fi

emit "worker-and-deliver" "" "" false \
  "no objective owns this work — standalone task, worker-dev then deliver-dev"
