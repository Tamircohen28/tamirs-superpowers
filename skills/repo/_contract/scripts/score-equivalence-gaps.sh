#!/usr/bin/env bash
# score-equivalence-gaps.sh — E-layer gaps from inventory JSON.
#
# Usage:
#   inventory-agent-setup.sh <root> | score-equivalence-gaps.sh
#   score-equivalence-gaps.sh < inventory.json
set -euo pipefail

INV="$(cat)"
add_gap() {
  GAPS+=("$(jq -nc --arg id "$1" --arg sev "$2" --arg msg "$3" --argjson phase "$4" \
    '{id: $id, severity: $sev, message: $msg, phase: $phase}')")
}

GAPS=()
P1=0 P2=0 P3=0
inc() { case "$1" in P1) P1=$((P1+1));; P2) P2=$((P2+1));; P3) P3=$((P3+1));; esac; }

repo_type=$(echo "$INV" | jq -r '.repo_type')
bridge_ok=$(echo "$INV" | jq -r '.skills.bridge_ok')
agents_skills=$(echo "$INV" | jq -r '.skills.agents_dir')
claude_skills=$(echo "$INV" | jq -r '.skills.claude_project_skills')
bridge_documented=$(echo "$INV" | jq -r '.skills.bridge_documented')
plugin_skill_count=$(echo "$INV" | jq -r '.skills.plugin_skill_count')
cursor_manifest=$(echo "$INV" | jq -r '.manifests.cursor_plugin')
codex_manifest=$(echo "$INV" | jq -r '.manifests.codex_plugin')
claude_manifest=$(echo "$INV" | jq -r '.manifests.claude_plugin')
manifest_paths_match=$(echo "$INV" | jq -r '.manifests.skills_paths_match')
mcp_stub=$(echo "$INV" | jq -r '.mcp.stub_exists')
mcp_refs_match=$(echo "$INV" | jq -r '.mcp.manifest_refs_match')
mcp_documented=$(echo "$INV" | jq -r '.mcp.documented')
codex_config=$(echo "$INV" | jq -r '.codex.config_exists')
hooks_claude=$(echo "$INV" | jq -r '.hooks.claude_exists')
hooks_codex=$(echo "$INV" | jq -r '.hooks.codex_declared')
hooks_cursor_doc=$(echo "$INV" | jq -r '.hooks.cursor_substitute_doc')
equiv_doc=$(echo "$INV" | jq -r '.docs.platform_equivalence')

# E1 — app skill bridge
if [[ "$repo_type" == "app" || "$repo_type" == "hybrid" ]]; then
  if [[ "$agents_skills" != true && "$claude_skills" == true && "$bridge_documented" != true ]]; then
    add_gap "E1-01" "P1" "No .agents/skills/ and no documented bridge for .claude/skills/" 3; inc P1
  fi
  if [[ "$bridge_ok" != true ]]; then
    add_gap "E1-02" "P1" "Skill sets differ between .agents/skills and .claude/skills" 3; inc P1
  fi
fi

# E2 — plugin manifests
if [[ "$repo_type" == "claude-plugin" || "$repo_type" == "hybrid" || "$repo_type" == "agent-kit" ]]; then
  if (( plugin_skill_count > 0 )) || [[ "$claude_manifest" == true ]]; then
    [[ "$cursor_manifest" != true ]] && { add_gap "E2-01" "P1" "Missing .cursor-plugin/plugin.json" 5; inc P1; }
    [[ "$codex_manifest" != true ]] && { add_gap "E2-01" "P1" "Missing .codex-plugin/plugin.json" 5; inc P1; }
  fi
  if [[ "$manifest_paths_match" != true ]]; then
    add_gap "E2-02" "P1" "Manifest skills paths disagree across platforms" 5; inc P1
  fi
fi

# E3 — MCP
if [[ "$mcp_stub" == true && "$mcp_refs_match" != true ]]; then
  add_gap "E3-01" "P1" ".mcp.json not referenced in all plugin manifests" 5; inc P1
fi
if [[ "$mcp_documented" == true && "$codex_config" != true ]]; then
  add_gap "E3-02" "P2" "MCP documented but .codex/config.toml stub missing" 5; inc P2
fi

# E4 — hooks
if [[ "$hooks_claude" == true ]]; then
  if [[ "$hooks_codex" != true ]]; then
    add_gap "E4-01" "P1" "hooks/hooks.json exists but .codex-plugin/plugin.json lacks hooks field" 5; inc P1
  fi
  if [[ "$hooks_cursor_doc" != true ]]; then
    add_gap "E4-01" "P1" "hooks/hooks.json exists but platform-equivalence.md lacks Cursor/hook mapping" 5; inc P1
  fi
fi

# E5 — equivalence doc
if [[ "$hooks_claude" == true || "$mcp_stub" == true ]]; then
  sev="P2"
  [[ "$repo_type" == "claude-plugin" || "$repo_type" == "hybrid" ]] && sev="P1"
  if [[ "$equiv_doc" != true ]]; then
    add_gap "E5-01" "$sev" "docs/agent-guidelines/platform-equivalence.md missing" 5; inc "$sev"
  fi
fi

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
