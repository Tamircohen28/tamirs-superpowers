#!/usr/bin/env bash
# score-inventory-gaps.sh — deterministic P1/P2/P3 gaps from inventory JSON.
#
# Usage:
#   inventory-agent-setup.sh <root> | score-inventory-gaps.sh
#   score-inventory-gaps.sh < inventory.json
#   score-inventory-gaps.sh -h | --help
#
# Output: JSON { gaps: [...], counts: { p1, p2, p3 } }
set -euo pipefail

usage() { sed -n '2,10p' "$0" | sed 's/^# \?//'; exit "${1:-0}"; }
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage 0; fi

INV="$(cat)"
add_gap() {
  GAPS+=("$(jq -nc --arg id "$1" --arg sev "$2" --arg msg "$3" --argjson phase "$4" \
    '{id: $id, severity: $sev, message: $msg, phase: $phase}')")
}

GAPS=()
P1=0 P2=0 P3=0

inc() {
  case "$1" in P1) P1=$((P1 + 1)) ;; P2) P2=$((P2 + 1)) ;; P3) P3=$((P3 + 1)) ;; esac
}

agents_exists=$(echo "$INV" | jq -r '.agents_md.exists')
agents_over=$(echo "$INV" | jq -r '.agents_md.over_codex_limit')
claude_exists=$(echo "$INV" | jq -r '.claude_md.exists')
claude_imports=$(echo "$INV" | jq -r '.claude_md.imports_agents')
cursor_count=$(echo "$INV" | jq -r '.cursor_rules.count')
cursor_always=$(echo "$INV" | jq -r '.cursor_rules.always_apply_count')
cursor_non_mdc=$(echo "$INV" | jq -r '.cursor_rules.non_mdc_count')
repo_type=$(echo "$INV" | jq -r '.repo_type')
drift=$(echo "$INV" | jq -r '.enforcement.drift_script')
agent_check=$(echo "$INV" | jq -r '.enforcement.has_agent_check')
has_ci=$(echo "$INV" | jq -r '.enforcement.has_ci')
guidelines=$(echo "$INV" | jq -r '.docs.agent_guidelines_dir')
agents_skills=$(echo "$INV" | jq -r '.skills.agents_dir')
claude_project_skills=$(echo "$INV" | jq -r '.skills.claude_project_skills')
plugin_manifest=$(echo "$INV" | jq -r '.manifests.claude_plugin')
plugin_skills=$(echo "$INV" | jq -r '.skills.plugin_skills_dir')
plugin_skill_count=$(echo "$INV" | jq -r '.skills.plugin_skill_count')
has_portable_skills=false
if [[ "$agents_skills" == true || "$plugin_skills" == true || "$claude_project_skills" == true ]]; then
  has_portable_skills=true
fi

if [[ "$agents_exists" != true ]]; then
  add_gap "L1-01" "P1" "AGENTS.md missing at repo root" 0; inc P1
fi
if [[ "$agents_over" == true ]]; then
  add_gap "L1-04" "P1" "AGENTS.md exceeds 32 KiB Codex limit" 0; inc P1
fi
if [[ "$claude_exists" != true ]]; then
  add_gap "L2-01" "P1" "CLAUDE.md missing" 1; inc P1
elif [[ "$claude_imports" != true ]]; then
  add_gap "L2-02" "P1" "CLAUDE.md does not reference AGENTS.md" 1; inc P1
fi
if (( cursor_non_mdc > 0 )); then
  add_gap "L3-02" "P1" ".cursor/rules contains .md files (Cursor ignores them)" 1; inc P1
fi
if (( cursor_always > 2 )); then
  add_gap "L3-04" "P1" "More than 2 Cursor rules with alwaysApply: true" 1; inc P1
fi
if [[ "$cursor_count" == "0" ]]; then
  add_gap "L3-01" "P2" ".cursor/rules/ directory missing or empty" 1; inc P2
fi
if [[ "$repo_type" == "app" && "$has_portable_skills" != true ]]; then
  add_gap "L4-02" "P2" "No portable skills directory (.agents/skills/, skills/, or .claude/skills/)" 3; inc P2
fi
if [[ "$repo_type" == "claude-plugin" && "$plugin_manifest" != true ]]; then
  add_gap "L4-03" "P1" "Claude plugin repo missing .claude-plugin/plugin.json" 3; inc P1
elif [[ "$plugin_skills" == true && "$plugin_skill_count" -gt 0 && "$plugin_manifest" != true ]]; then
  add_gap "L4-03" "P1" "Plugin-like repo (skills/) missing .claude-plugin/plugin.json" 3; inc P1
fi
if [[ "$guidelines" != true ]]; then
  add_gap "L5-01" "P2" "docs/agent-guidelines/ missing" 2; inc P2
fi
if [[ "$agent_check" != true ]]; then
  add_gap "L6-03" "P1" "No agent:check / validate command in Makefile or package.json" 4; inc P1
fi
if [[ "$has_ci" == true && "$agent_check" != true ]]; then
  add_gap "L6-04" "P1" "CI exists but no documented agent validation command" 4; inc P1
fi
if [[ "$drift" != true ]]; then
  add_gap "L7-01" "P2" "No check-agent-drift script" 4; inc P2
fi

# Build JSON array
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
