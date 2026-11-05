#!/usr/bin/env bash
# score-marketplace-gaps.sh — P1/P2/P3 gaps for the marketplace-gold profile.
#
# Usage:
#   marketplace-inventory.sh <root> | score-marketplace-gaps.sh
#   score-marketplace-gaps.sh <repo-root>
#
# MK1 — a manifest a platform reads is missing, or the manifests do not validate.
# MK2 — the catalog is published but not maintainable: no catalog table, no doc, no CI
#       job, no CODEOWNERS on the supply-chain paths, a local plugin with no manifest.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "${1:-}" && -d "${1:-}" ]]; then
  INV="$(bash "$SCRIPT_DIR/marketplace-inventory.sh" "$1")"
else
  INV="$(cat)"
fi

add_gap() {
  GAPS+=("$(jq -nc --arg id "$1" --arg sev "$2" --arg msg "$3" --argjson phase "$4" \
    '{id: $id, severity: $sev, message: $msg, phase: $phase}')")
}

GAPS=()
P1=0 P2=0 P3=0
inc() { case "$1" in P1) P1=$((P1+1));; P2) P2=$((P2+1));; P3) P3=$((P3+1));; esac; }

claude_m=$(echo "$INV" | jq -r '.manifests.claude_code')
cursor_m=$(echo "$INV" | jq -r '.manifests.cursor')
codex_m=$(echo "$INV" | jq -r '.manifests.codex')
v_script=$(echo "$INV" | jq -r '.validate.script')
v_passes=$(echo "$INV" | jq -r '.validate.passes')
v_make=$(echo "$INV" | jq -r '.validate.make_target')
v_ci=$(echo "$INV" | jq -r '.validate.ci_job')
lp_nomanifest=$(echo "$INV" | jq -r '.local_plugins.without_manifest')
r_table=$(echo "$INV" | jq -r '.readme.catalog_table')
r_opencode=$(echo "$INV" | jq -r '.readme.mentions_opencode')
d_catalog=$(echo "$INV" | jq -r '.docs.catalog')
co_plugins=$(echo "$INV" | jq -r '.codeowners.plugins')
co_scripts=$(echo "$INV" | jq -r '.codeowners.scripts')
co_claude=$(echo "$INV" | jq -r '.codeowners.claude_plugin')
co_cursor=$(echo "$INV" | jq -r '.codeowners.cursor_plugin')
co_agents=$(echo "$INV" | jq -r '.codeowners.agents')

[[ "$claude_m" != true ]] && { add_gap "MK1-01" "P1" ".claude-plugin/marketplace.json missing (Claude Code and Claude Desktop read it; Codex reads it as legacy-compatible)" 3; inc P1; }
[[ "$cursor_m" != true ]] && { add_gap "MK1-02" "P1" ".cursor-plugin/marketplace.json missing (Cursor reads it from the repo root)" 3; inc P1; }
[[ "$codex_m" != true ]] && { add_gap "MK1-03" "P1" ".agents/plugins/marketplace.json missing (Codex's repo-scope marketplace)" 3; inc P1; }
[[ "$v_script" != true ]] && { add_gap "MK1-04" "P1" "scripts/validate-marketplace.sh missing (copy from _contract/templates/marketplace/scripts/validate-marketplace.sh.tmpl)" 3; inc P1; }
[[ "$v_script" == true && "$v_passes" != true ]] && { add_gap "MK1-05" "P1" "scripts/validate-marketplace.sh fails — run it for the manifest errors" 3; inc P1; }
# OpenCode deliberately has no MK1 row: it defines no marketplace, so there is nothing to require.

[[ "$r_table" != true ]] && { add_gap "MK2-01" "P2" "README missing a '## Catalog' section with a '| Plugin |' table" 1; inc P2; }
[[ "$r_opencode" != true ]] && { add_gap "MK2-02" "P2" "README does not say what happens on OpenCode (it has no marketplace; say so)" 1; inc P2; }
[[ "$d_catalog" != true ]] && { add_gap "MK2-03" "P2" "docs/user/catalog.md missing (how to add a local, GitHub or npm plugin per platform)" 2; inc P2; }
[[ "$v_ci" != true ]] && { add_gap "MK2-04" "P2" "CI missing validate job" 3; inc P2; }
[[ "$v_make" != true ]] && { add_gap "MK2-05" "P2" "Makefile missing validate target" 3; inc P2; }
(( lp_nomanifest > 0 )) && { add_gap "MK2-06" "P2" "$lp_nomanifest local plugin(s) under plugins/ without .claude-plugin/plugin.json" 3; inc P2; }
[[ "$co_plugins" != true ]] && { add_gap "MK2-07" "P2" "CODEOWNERS missing plugins/ entry" 4; inc P2; }
[[ "$co_scripts" != true ]] && { add_gap "MK2-08" "P2" "CODEOWNERS missing scripts/ entry" 4; inc P2; }
[[ "$co_claude" != true ]] && { add_gap "MK2-09" "P2" "CODEOWNERS missing .claude-plugin/ entry" 4; inc P2; }
[[ "$co_cursor" != true ]] && { add_gap "MK2-10" "P2" "CODEOWNERS missing .cursor-plugin/ entry" 4; inc P2; }
[[ "$co_agents" != true ]] && { add_gap "MK2-11" "P2" "CODEOWNERS missing .agents/ entry" 4; inc P2; }

GAPS_JSON="["
for i in "${!GAPS[@]}"; do
  [[ $i -gt 0 ]] && GAPS_JSON+=","
  GAPS_JSON+="${GAPS[$i]}"
done
GAPS_JSON+="]"

jq -nc --argjson gaps "$GAPS_JSON" --argjson p1 "$P1" --argjson p2 "$P2" --argjson p3 "$P3" \
  '{gaps: $gaps, counts: {p1: $p1, p2: $p2, p3: $p3}}'
