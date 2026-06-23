#!/usr/bin/env bash
# inventory-agent-setup.sh — JSON snapshot of multi-agent file layout in a repo.
#
# Usage:
#   inventory-agent-setup.sh <repo-root>
#   inventory-agent-setup.sh -h | --help
#
# Exit 0 always; output is JSON on stdout.
set -euo pipefail

usage() { sed -n '2,9p' "$0" | sed 's/^# \?//'; exit "${1:-0}"; }
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage 0; fi

ROOT="${1:-.}"
ROOT="$(cd "$ROOT" 2>/dev/null && pwd || { echo "{\"error\":\"not a directory: $1\"}"; exit 0; })"

# --- helpers ---
file_bytes() {
  if [[ -f "$1" ]]; then wc -c <"$1" | tr -d ' '; else echo 0; fi
}

file_exists() { [[ -f "$1" ]] && echo true || echo false; }

imports_agents() {
  local f="$1"
  [[ -f "$f" ]] || { echo false; return; }
  if grep -qE '@AGENTS\.md|AGENTS\.md' "$f" 2>/dev/null; then echo true; else echo false; fi
}

count_skills() {
  local n=0
  if [[ -d "$1" ]]; then
    n=$(find "$1" -name 'SKILL.md' 2>/dev/null | wc -l | tr -d ' ')
  fi
  echo "$n"
}

# --- repo type ---
repo_type="app"
if [[ -f "$ROOT/.claude-plugin/plugin.json" ]]; then
  if [[ -f "$ROOT/package.json" || -f "$ROOT/pyproject.toml" || -f "$ROOT/Cargo.toml" || -f "$ROOT/go.mod" ]]; then
    repo_type="hybrid"
  else
    repo_type="claude-plugin"
  fi
fi

# --- AGENTS.md ---
agents_exists=$(file_exists "$ROOT/AGENTS.md")
agents_bytes=0
if [[ "$agents_exists" == true ]]; then
  agents_bytes=$(file_bytes "$ROOT/AGENTS.md")
fi
agents_over_limit=false
if (( agents_bytes > 32768 )); then agents_over_limit=true; fi

# --- CLAUDE.md ---
claude_exists=$(file_exists "$ROOT/CLAUDE.md")
claude_imports=$(imports_agents "$ROOT/CLAUDE.md")

# --- Cursor rules ---
cursor_rules_dir="$ROOT/.cursor/rules"
cursor_count=0
cursor_always=0
cursor_non_mdc=0
if [[ -d "$cursor_rules_dir" ]]; then
  cursor_count=$(find "$cursor_rules_dir" -maxdepth 1 -name '*.mdc' 2>/dev/null | wc -l | tr -d ' ')
  cursor_non_mdc=$(find "$cursor_rules_dir" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
  while IFS= read -r f; do
    if grep -qE '^alwaysApply:\s*true' "$f" 2>/dev/null; then
      cursor_always=$((cursor_always + 1))
    fi
  done < <(find "$cursor_rules_dir" -maxdepth 1 -name '*.mdc' 2>/dev/null)
fi
cursor_legacy_rules=$(file_exists "$ROOT/.cursorrules")

# --- Skills paths ---
agents_skills_dir=false
agents_skill_count=0
if [[ -d "$ROOT/.agents/skills" ]]; then
  agents_skills_dir=true
  agents_skill_count=$(count_skills "$ROOT/.agents/skills")
fi
plugin_skills=false
plugin_skill_count=0
if [[ -d "$ROOT/skills" ]]; then
  plugin_skills=true
  plugin_skill_count=$(count_skills "$ROOT/skills")
fi
claude_project_skills=false
claude_project_skill_count=0
if [[ -d "$ROOT/.claude/skills" ]]; then
  claude_project_skills=true
  claude_project_skill_count=$(count_skills "$ROOT/.claude/skills")
fi

# --- Plugin manifests ---
claude_plugin_manifest=$(file_exists "$ROOT/.claude-plugin/plugin.json")
cursor_plugin_manifest=$(file_exists "$ROOT/.cursor-plugin/plugin.json")
codex_plugin_manifest=$(file_exists "$ROOT/.codex-plugin/plugin.json")

# --- docs/agent-guidelines ---
agent_guidelines_dir=false
agent_guidelines_count=0
if [[ -d "$ROOT/docs/agent-guidelines" ]]; then
  agent_guidelines_dir=true
  agent_guidelines_count=$(find "$ROOT/docs/agent-guidelines" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
fi

# --- drift script ---
drift_script=false
for candidate in \
  "$ROOT/scripts/check-agent-drift.sh" \
  "$ROOT/scripts/check-no-agent-drift.mjs" \
  "$ROOT/scripts/verify-agent-rules.sh"; do
  if [[ -f "$candidate" ]]; then drift_script=true; break; fi
done

# --- CI / agent:check ---
has_agent_check=false
if [[ -f "$ROOT/Makefile" ]] && grep -qE 'agent:check|agent:rules|validate-skill-frontmatter' "$ROOT/Makefile" 2>/dev/null; then
  has_agent_check=true
fi
if [[ -f "$ROOT/package.json" ]] && grep -qE '"agent:check"|"agent:rules"' "$ROOT/package.json" 2>/dev/null; then
  has_agent_check=true
fi
has_ci=false
if [[ -d "$ROOT/.github/workflows" ]] && find "$ROOT/.github/workflows" -name '*.yml' -print -quit | grep -q .; then
  has_ci=true
fi

# --- git ---
is_git_repo=false
if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  is_git_repo=true
fi

jq -nc \
  --arg root "$ROOT" \
  --arg repo_type "$repo_type" \
  --argjson agents_exists "$agents_exists" \
  --argjson agents_bytes "$agents_bytes" \
  --argjson agents_over_limit "$agents_over_limit" \
  --argjson claude_exists "$claude_exists" \
  --argjson claude_imports "$claude_imports" \
  --argjson cursor_count "$cursor_count" \
  --argjson cursor_always "$cursor_always" \
  --argjson cursor_non_mdc "$cursor_non_mdc" \
  --argjson cursor_legacy_rules "$cursor_legacy_rules" \
  --argjson agents_skills_dir "$agents_skills_dir" \
  --argjson agents_skill_count "$agents_skill_count" \
  --argjson plugin_skills "$plugin_skills" \
  --argjson plugin_skill_count "$plugin_skill_count" \
  --argjson claude_project_skills "$claude_project_skills" \
  --argjson claude_project_skill_count "$claude_project_skill_count" \
  --argjson claude_plugin_manifest "$claude_plugin_manifest" \
  --argjson cursor_plugin_manifest "$cursor_plugin_manifest" \
  --argjson codex_plugin_manifest "$codex_plugin_manifest" \
  --argjson agent_guidelines_dir "$agent_guidelines_dir" \
  --argjson agent_guidelines_count "$agent_guidelines_count" \
  --argjson drift_script "$drift_script" \
  --argjson has_agent_check "$has_agent_check" \
  --argjson has_ci "$has_ci" \
  --argjson is_git_repo "$is_git_repo" \
  '{
    root: $root,
    repo_type: $repo_type,
    agents_md: { exists: $agents_exists, bytes: $agents_bytes, over_codex_limit: $agents_over_limit },
    claude_md: { exists: $claude_exists, imports_agents: $claude_imports },
    cursor_rules: {
      count: $cursor_count,
      always_apply_count: $cursor_always,
      non_mdc_count: $cursor_non_mdc,
      legacy_cursorrules: $cursor_legacy_rules
    },
    skills: {
      agents_dir: $agents_skills_dir,
      agents_skill_count: $agents_skill_count,
      plugin_skills_dir: $plugin_skills,
      plugin_skill_count: $plugin_skill_count,
      claude_project_skills: $claude_project_skills,
      claude_project_skill_count: $claude_project_skill_count
    },
    manifests: {
      claude_plugin: $claude_plugin_manifest,
      cursor_plugin: $cursor_plugin_manifest,
      codex_plugin: $codex_plugin_manifest
    },
    docs: { agent_guidelines_dir: $agent_guidelines_dir, markdown_count: $agent_guidelines_count },
    enforcement: { drift_script: $drift_script, has_agent_check: $has_agent_check, has_ci: $has_ci },
    git: { is_repo: $is_git_repo }
  }'
