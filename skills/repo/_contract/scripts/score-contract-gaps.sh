#!/usr/bin/env bash
# score-contract-gaps.sh — merge standards + multi-agent + plugin deterministic gaps.
#
# Usage:
#   score-contract-gaps.sh <repo-root> [profile]
#   CONTRACT_OFFLINE=1 score-contract-gaps.sh <fixture-root> app-gold
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="${1:-.}"
PROFILE="${2:-app-gold}"

STD_JSON="$(bash "$SCRIPT_DIR/standards-inventory.sh" "$ROOT" | bash "$SCRIPT_DIR/score-standards-gaps.sh")"
INV_JSON="$(bash "$SCRIPT_DIR/inventory-agent-setup.sh" "$ROOT")"
MA_JSON="$(echo "$INV_JSON" | bash "$SCRIPT_DIR/score-inventory-gaps.sh")"
EQ_JSON="$(echo "$INV_JSON" | bash "$SCRIPT_DIR/score-equivalence-gaps.sh")"
PT_JSON="$(echo "$INV_JSON" | bash "$SCRIPT_DIR/score-platform-target-gaps.sh")"

PLUGIN_JSON='{"gaps":[],"counts":{"p1":0,"p2":0,"p3":0}}'
if [[ "$PROFILE" == "plugin-gold" ]]; then
  PLUGIN_JSON="$(bash "$SCRIPT_DIR/score-plugin-gaps.sh" "$ROOT")"
fi

CONTRACT_FILE="$(cd "$SCRIPT_DIR/.." && pwd)/standards-contract.json"
SKIP_IDS='[]'
if [[ "${CONTRACT_OFFLINE:-}" == "1" && -f "$CONTRACT_FILE" ]]; then
  SKIP_IDS="$(jq -c --arg p "$PROFILE" '.profiles[$p].offline_scoring.skip_check_ids // []' "$CONTRACT_FILE")"
fi

jq -nc \
  --arg profile "$PROFILE" \
  --argjson std "$STD_JSON" \
  --argjson ma "$MA_JSON" \
  --argjson eq "$EQ_JSON" \
  --argjson pt "$PT_JSON" \
  --argjson plugin "$PLUGIN_JSON" \
  --argjson skip "$SKIP_IDS" \
  '
  ($std.gaps + $ma.gaps + $eq.gaps + $pt.gaps + $plugin.gaps) as $all |
  [ $all[] | select(.id as $id | ($skip | index($id) | not)) ] as $filtered |
  {
    profile: $profile,
    gaps: $filtered,
    counts: {
      p1: ([$filtered[] | select(.severity == "P1")] | length),
      p2: ([$filtered[] | select(.severity == "P2")] | length),
      p3: ([$filtered[] | select(.severity == "P3")] | length)
    },
    sources: {
      standards: $std.counts,
      multi_agent: $ma.counts,
      equivalence: $eq.counts,
      platform_targets: $pt.counts,
      plugin: $plugin.counts
    }
  }
  '
