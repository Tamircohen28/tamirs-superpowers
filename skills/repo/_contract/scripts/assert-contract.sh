#!/usr/bin/env bash
# assert-contract.sh — exit 0 only when profile gap counts are all zero.
#
# Usage:
#   assert-contract.sh <repo-root> [profile] [--manifests-only]
#   CONTRACT_OFFLINE=1 assert-contract.sh fixtures/scaffold-gold app-gold
#   assert-contract.sh . app-gold --manifests-only   # release PR before tag exists
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${1:-.}"
PROFILE="${2:-app-gold}"
MANIFESTS_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --manifests-only) MANIFESTS_ONLY=true ;;
    app-gold|plugin-gold) PROFILE="$arg" ;;
    -*) echo "assert-contract: unknown flag: $arg" >&2; exit 1 ;;
    *) ROOT="$arg" ;;
  esac
done

if [[ "$MANIFESTS_ONLY" == true ]]; then
  export CONTRACT_MANIFESTS_ONLY=1
fi

# The contract cannot be asserted with a forked copy of itself. Several checkers ship in
# three places (plugin scripts/, scaffold template, gold fixtures); if a copy has drifted,
# the fixture is no longer exercising the logic the live script runs and a green gate means
# nothing. Runs only when this contract sits inside its own source repo — a consumer repo
# asserting its own compliance has no canonical sources to compare against.
if [[ -f "$SCRIPT_DIR/sync-contract-scripts.sh" && -f "$SCRIPT_DIR/../script-sync.json" ]]; then
  CONTRACT_SRC_ROOT="$(cd "$SCRIPT_DIR/../../../.." && pwd)"
  if [[ -f "$CONTRACT_SRC_ROOT/scripts/check-feature-equivalence.sh" ]]; then
    bash "$SCRIPT_DIR/sync-contract-scripts.sh" "$CONTRACT_SRC_ROOT" --check
  fi
fi

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
