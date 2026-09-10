#!/usr/bin/env bash
# init-bundle.sh — create the .refusal-debug/ diagnostic bundle skeleton.
#
# Usage:
#   init-bundle.sh [--root <dir>] [-v|--verbose] [-h|--help]
#
# Creates (or refreshes stubs in) <root>/.refusal-debug/:
#   report.md, request.json, response.json, routing.md, environment.md, manifest.txt
#
# Does not overwrite a non-empty report.md (preserves in-progress diagnosis).
# Example:
#   bash skills/debugging/diagnose-refusal/scripts/init-bundle.sh
set -euo pipefail

usage() {
  sed -n '2,14p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

ROOT=""
VERBOSE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage 0 ;;
    -v|--verbose) VERBOSE=1; shift ;;
    --root)
      [[ $# -ge 2 ]] || { echo "ERROR: --root needs a directory" >&2; usage 1; }
      ROOT="$2"; shift 2
      ;;
    -*)
      echo "ERROR: unknown flag: $1" >&2
      usage 1
      ;;
    *)
      echo "ERROR: unexpected argument: $1" >&2
      usage 1
      ;;
  esac
done

if [[ -z "$ROOT" ]]; then
  if ROOT="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    :
  else
    ROOT="$(pwd)"
  fi
fi

BUNDLE="$ROOT/.refusal-debug"
mkdir -p "$BUNDLE"

log() { if [[ "$VERBOSE" -eq 1 ]]; then printf '%s\n' "$*" >&2; fi; }

write_stub() {
  local path="$1" contents="$2"
  if [[ -f "$path" && -s "$path" && "$(basename "$path")" == "report.md" ]]; then
    log "keeping existing $(basename "$path")"
    return 0
  fi
  printf '%s\n' "$contents" >"$path"
  log "wrote $path"
}

UTC="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || echo unknown)"

write_stub "$BUNDLE/report.md" "# Refusal diagnostic report

_Initialized: ${UTC}_

Most likely refusal layer: UNKNOWN
Confidence: LOW
Primary evidence: (pending)
Second-most likely layer: none
Missing evidence needed:
- (pending)

---

## 1. Incident

(pending)

## 2. Conversation state

(pending)

## 3. Active repository instructions

(pending)

## 4. LiteLLM / proxy

(pending)

## 5. Environment

See environment.md

## 6. Refusal classification

(pending)

## 7. Request-path reconstruction

See routing.md

## 8. Comparison tests

(pending)

## 9. Final assessment

(pending)
"

write_stub "$BUNDLE/request.json" '{
  "status": "unavailable",
  "reason": "not yet captured"
}'

write_stub "$BUNDLE/response.json" '{
  "status": "unavailable",
  "reason": "not yet captured"
}'

write_stub "$BUNDLE/routing.md" "# Request path

\`\`\`text
HARNESS   UNKNOWN
  ↓
LITELLM   UNKNOWN
  ↓
PROVIDER  UNKNOWN
  ↓
MODEL     UNKNOWN
\`\`\`

Refusal origin annotation: (pending)
"

write_stub "$BUNDLE/environment.md" "_Run collect-environment.sh to populate this file._
"

find "$BUNDLE" -type f | sort >"$BUNDLE/manifest.txt"
printf '%s\n' "$BUNDLE"
