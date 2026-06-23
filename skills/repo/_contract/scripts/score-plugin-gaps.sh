#!/usr/bin/env bash
# score-plugin-gaps.sh — P1/P2/P3 gaps for plugin-gold profile.
#
# Usage:
#   plugin-inventory.sh <root> | score-plugin-gaps.sh
#   score-plugin-gaps.sh <repo-root>
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -n "${1:-}" && -d "${1:-}" ]]; then
  INV="$(bash "$SCRIPT_DIR/plugin-inventory.sh" "$1")"
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

canonical_core=$(echo "$INV" | jq -r '.canonical.core_rules')
canonical_skills=$(echo "$INV" | jq -r '.canonical.skills_dir')
skill_count=$(echo "$INV" | jq -r '.canonical.skill_count')
agent_kit_config=$(echo "$INV" | jq -r '.agent_kit_config')
build_script=$(echo "$INV" | jq -r '.scripts.build_mjs')
validate_script=$(echo "$INV" | jq -r '.scripts.validate_mjs')
package_json=$(echo "$INV" | jq -r '.package_json')
package_lock_json=$(echo "$INV" | jq -r '.package_lock_json')
marketplace=$(echo "$INV" | jq -r '.marketplace_json')
plugin_wrapper=$(echo "$INV" | jq -r '.plugin_wrapper.exists')
plugin_manifest=$(echo "$INV" | jq -r '.plugin_wrapper.manifest')
plugin_skills=$(echo "$INV" | jq -r '.plugin_wrapper.skills_dir')
dist_codex=$(echo "$INV" | jq -r '.dist.codex_agents_md')
dist_cursor=$(echo "$INV" | jq -r '.dist.cursor_core_mdc')
codex_gen=$(echo "$INV" | jq -r '.dist.codex_generated')
cursor_gen=$(echo "$INV" | jq -r '.dist.cursor_generated')
co_canonical=$(echo "$INV" | jq -r '.codeowners.canonical')
co_plugins=$(echo "$INV" | jq -r '.codeowners.plugins')
co_scripts=$(echo "$INV" | jq -r '.codeowners.scripts')
co_hooks=$(echo "$INV" | jq -r '.codeowners.hooks')
validate_job=$(echo "$INV" | jq -r '.ci.validate_job')
npm_validate=$(echo "$INV" | jq -r '.npm.validate_script')

[[ "$canonical_core" != true ]] && { add_gap "PK1-01" "P1" "canonical/rules/core.md missing" 3; inc P1; }
[[ "$canonical_skills" != true ]] && { add_gap "PK1-02" "P1" "canonical/skills/ directory missing" 3; inc P1; }
[[ "$canonical_skills" == true && "$skill_count" -lt 1 ]] && { add_gap "PK1-03" "P1" "canonical/skills/ has no SKILL.md" 3; inc P1; }
[[ "$agent_kit_config" != true ]] && { add_gap "PK1-04" "P1" "agent-kit.config.json missing" 3; inc P1; }
[[ "$build_script" != true ]] && { add_gap "PK1-05" "P1" "scripts/build.mjs missing" 3; inc P1; }
[[ "$validate_script" != true ]] && { add_gap "PK1-06" "P1" "scripts/validate.mjs missing" 3; inc P1; }
[[ "$package_json" != true ]] && { add_gap "PK1-07" "P1" "package.json missing (plugin repos require node toolchain)" 3; inc P1; }
[[ "$package_lock_json" != true ]] && { add_gap "PK1-14" "P1" "package-lock.json missing (required for npm ci in CI/Makefile)" 3; inc P1; }
[[ "$marketplace" != true ]] && { add_gap "PK1-08" "P1" ".claude-plugin/marketplace.json missing" 3; inc P1; }
[[ "$plugin_wrapper" != true ]] && { add_gap "PK1-09" "P1" "plugins/<name>/ wrapper directory missing" 3; inc P1; }
[[ "$plugin_manifest" != true ]] && { add_gap "PK1-10" "P1" "plugins/<name>/.claude-plugin/plugin.json missing" 3; inc P1; }
[[ "$plugin_skills" != true ]] && { add_gap "PK1-11" "P1" "plugins/<name>/skills/ missing" 3; inc P1; }
[[ "$dist_codex" != true ]] && { add_gap "PK1-12" "P1" "dist/codex/AGENTS.md missing (run npm run build)" 3; inc P1; }
[[ "$dist_cursor" != true ]] && { add_gap "PK1-13" "P1" "dist/cursor/.cursor/rules/000-core.mdc missing (run npm run build)" 3; inc P1; }

[[ "$codex_gen" != true && "$dist_codex" == true ]] && { add_gap "PK2-01" "P2" "dist/codex/AGENTS.md missing GENERATED FILE marker" 3; inc P2; }
[[ "$cursor_gen" != true && "$dist_cursor" == true ]] && { add_gap "PK2-02" "P2" "dist/cursor/.cursor/rules/000-core.mdc missing GENERATED FILE marker" 3; inc P2; }
[[ "$validate_job" != true ]] && { add_gap "PK2-03" "P2" "CI missing validate job" 3; inc P2; }
[[ "$npm_validate" != true ]] && { add_gap "PK2-04" "P2" "package.json missing validate script" 3; inc P2; }

[[ "$co_canonical" != true ]] && { add_gap "PK2-05" "P2" "CODEOWNERS missing canonical/ entry" 4; inc P2; }
[[ "$co_plugins" != true ]] && { add_gap "PK2-06" "P2" "CODEOWNERS missing plugins/ entry" 4; inc P2; }
[[ "$co_scripts" != true ]] && { add_gap "PK2-07" "P2" "CODEOWNERS missing scripts/ entry" 4; inc P2; }
[[ "$co_hooks" != true ]] && { add_gap "PK2-08" "P2" "CODEOWNERS missing hooks/ entry" 4; inc P2; }

GAPS_JSON="["
for i in "${!GAPS[@]}"; do
  [[ $i -gt 0 ]] && GAPS_JSON+=","
  GAPS_JSON+="${GAPS[$i]}"
done
GAPS_JSON+="]"

jq -nc --argjson gaps "$GAPS_JSON" --argjson p1 "$P1" --argjson p2 "$P2" --argjson p3 "$P3" \
  '{gaps: $gaps, counts: {p1: $p1, p2: $p2, p3: $p3}}'
