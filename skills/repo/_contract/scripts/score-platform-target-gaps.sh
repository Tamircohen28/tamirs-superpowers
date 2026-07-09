#!/usr/bin/env bash
# score-platform-target-gaps.sh — V-layer gaps from inventory JSON.
#
# Usage:
#   inventory-agent-setup.sh <root> | score-platform-target-gaps.sh
#   score-platform-target-gaps.sh < inventory.json
set -euo pipefail

INV="$(cat)"
add_gap() {
  GAPS+=("$(jq -nc --arg id "$1" --arg sev "$2" --arg msg "$3" --argjson phase "$4" \
    '{id: $id, severity: $sev, message: $msg, phase: $phase}')")
}

GAPS=()
P1=0 P2=0 P3=0
inc() { case "$1" in P1) P1=$((P1+1));; P2) P2=$((P2+1));; P3) P3=$((P3+1));; esac; }

multi=$(echo "$INV" | jq -r '.platform_targets.multi_platform')
file_exists=$(echo "$INV" | jq -r '.platform_targets.file_exists')
badges_match=$(echo "$INV" | jq -r '.platform_targets.readme_badges_match')
md_exists=$(echo "$INV" | jq -r '.platform_targets.md_exists')
stale=$(echo "$INV" | jq -r '.platform_targets.stale')
review_stale=$(echo "$INV" | jq -r '.platform_targets.review_stale')

if [[ "$multi" != true ]]; then
  jq -nc '{gaps: [], counts: {p1: 0, p2: 0, p3: 0}}'
  exit 0
fi

[[ "$file_exists" != true ]] && { add_gap "V1-01" "P1" "Missing docs/engineering/build-and-release/platform-targets.json" 5; inc P1; }
[[ "$badges_match" != true ]] && { add_gap "V1-02" "P1" "README AI-target badges do not match platform-targets.json validated_against" 5; inc P1; }
[[ "$md_exists" != true ]] && { add_gap "V1-03" "P2" "Missing docs/engineering/build-and-release/platform-targets.md" 5; inc P2; }
[[ "$stale" == true ]] && { add_gap "V1-04" "P2" "validated_against < latest_known for one or more platform targets" 5; inc P2; }
[[ "$review_stale" == true ]] && { add_gap "V1-05" "P2" "platform-targets last_reviewed older than 90 days" 5; inc P2; }

GAPS_JSON="["
for i in "${!GAPS[@]}"; do
  [[ $i -gt 0 ]] && GAPS_JSON+=","
  GAPS_JSON+="${GAPS[$i]}"
done
GAPS_JSON+="]"

jq -nc \
  --argjson gaps "$GAPS_JSON" \
  --argjson p1 "$P1" --argjson p2 "$P2" --argjson p3 "$P3" \
  '{gaps: $gaps, counts: {p1: $p1, p2: $p2, p3: $p3}}'
