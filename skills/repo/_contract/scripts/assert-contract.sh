#!/usr/bin/env bash
# assert-contract.sh — exit 0 only when profile gap counts are all zero.
#
# Usage:
#   assert-contract.sh <repo-root> [profile]
#   CONTRACT_OFFLINE=1 assert-contract.sh fixtures/scaffold-gold app-gold
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${1:-.}"
PROFILE="${2:-app-gold}"

RESULT="$(bash "$SCRIPT_DIR/score-contract-gaps.sh" "$ROOT" "$PROFILE")"
P1="$(echo "$RESULT" | jq -r '.counts.p1')"
P2="$(echo "$RESULT" | jq -r '.counts.p2')"
P3="$(echo "$RESULT" | jq -r '.counts.p3')"

if [[ "$P1" -eq 0 && "$P2" -eq 0 && "$P3" -eq 0 ]]; then
  echo "Contract profile '$PROFILE' passed (P1=$P1 P2=$P2 P3=$P3)"
  exit 0
fi

echo "Contract profile '$PROFILE' FAILED (P1=$P1 P2=$P2 P3=$P3)" >&2
echo "$RESULT" | jq '.gaps' >&2
exit 1
