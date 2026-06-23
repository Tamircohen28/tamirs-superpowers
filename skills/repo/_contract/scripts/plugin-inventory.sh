#!/usr/bin/env bash
# plugin-inventory.sh — JSON snapshot of agent-kit / plugin-gold layout.
#
# Usage: plugin-inventory.sh <repo-root>
set -euo pipefail

ROOT="${1:-.}"
ROOT="$(cd "$ROOT" 2>/dev/null && pwd || { echo '{"error":"not a directory"}'; exit 0; })"

exists() { [[ -f "$1" ]] && echo true || echo false; }
dir_exists() { [[ -d "$1" ]] && echo true || echo false; }

canonical_core=$(exists "$ROOT/canonical/rules/core.md")
canonical_skills_dir=$(dir_exists "$ROOT/canonical/skills")
canonical_skill_count=0
if [[ "$canonical_skills_dir" == true ]]; then
  canonical_skill_count=$(find "$ROOT/canonical/skills" -name 'SKILL.md' 2>/dev/null | wc -l | tr -d ' ')
fi

agent_kit_config=$(exists "$ROOT/agent-kit.config.json")
build_script=$(exists "$ROOT/scripts/build.mjs")
validate_script=$(exists "$ROOT/scripts/validate.mjs")
package_json=$(exists "$ROOT/package.json")
package_lock_json=$(exists "$ROOT/package-lock.json")
marketplace_json=$(exists "$ROOT/.claude-plugin/marketplace.json")

plugin_wrapper=false
plugin_manifest=false
plugin_skills_dir=false
plugin_name=""
if compgen -G "$ROOT/plugins/*" >/dev/null; then
  for plugin_dir in "$ROOT"/plugins/*/; do
    [[ -d "$plugin_dir" ]] || continue
    plugin_wrapper=true
    plugin_name="$(basename "$plugin_dir")"
    if [[ -f "$plugin_dir/.claude-plugin/plugin.json" ]]; then
      plugin_manifest=true
    fi
    if [[ -d "$plugin_dir/skills" ]]; then
      plugin_skills_dir=true
    fi
    break
  done
fi

dist_codex_agents=$(exists "$ROOT/dist/codex/AGENTS.md")
dist_cursor_core=$(exists "$ROOT/dist/cursor/.cursor/rules/000-core.mdc")

dist_codex_generated=false
dist_cursor_generated=false
if [[ -f "$ROOT/dist/codex/AGENTS.md" ]]; then
  grep -q 'GENERATED FILE' "$ROOT/dist/codex/AGENTS.md" 2>/dev/null && dist_codex_generated=true
fi
if [[ -f "$ROOT/dist/cursor/.cursor/rules/000-core.mdc" ]]; then
  grep -q 'GENERATED FILE' "$ROOT/dist/cursor/.cursor/rules/000-core.mdc" 2>/dev/null && dist_cursor_generated=true
fi

codeowners_canonical=false
codeowners_plugins=false
codeowners_scripts=false
codeowners_hooks=false
if [[ -f "$ROOT/CODEOWNERS" ]]; then
  grep -qE 'canonical/' "$ROOT/CODEOWNERS" 2>/dev/null && codeowners_canonical=true
  grep -qE 'plugins/' "$ROOT/CODEOWNERS" 2>/dev/null && codeowners_plugins=true
  grep -qE 'scripts/' "$ROOT/CODEOWNERS" 2>/dev/null && codeowners_scripts=true
  grep -qE 'hooks/' "$ROOT/CODEOWNERS" 2>/dev/null && codeowners_hooks=true
fi

validate_job=false
if [[ -d "$ROOT/.github/workflows" ]]; then
  while IFS= read -r wf; do
    [[ -f "$wf" ]] || continue
    if grep -Eiq '^[[:space:]]{2}validate:' "$wf" 2>/dev/null; then
      validate_job=true
      break
    fi
  done < <(find "$ROOT/.github/workflows" \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null)
fi

npm_validate=false
if [[ -f "$ROOT/package.json" ]]; then
  grep -qE '"validate"' "$ROOT/package.json" 2>/dev/null && npm_validate=true
fi

jq -nc \
  --arg root "$ROOT" \
  --arg plugin_name "$plugin_name" \
  --argjson canonical_core "$canonical_core" \
  --argjson canonical_skills_dir "$canonical_skills_dir" \
  --argjson canonical_skill_count "$canonical_skill_count" \
  --argjson agent_kit_config "$agent_kit_config" \
  --argjson build_script "$build_script" \
  --argjson validate_script "$validate_script" \
  --argjson package_json "$package_json" \
  --argjson package_lock_json "$package_lock_json" \
  --argjson marketplace_json "$marketplace_json" \
  --argjson plugin_wrapper "$plugin_wrapper" \
  --argjson plugin_manifest "$plugin_manifest" \
  --argjson plugin_skills_dir "$plugin_skills_dir" \
  --argjson dist_codex_agents "$dist_codex_agents" \
  --argjson dist_cursor_core "$dist_cursor_core" \
  --argjson dist_codex_generated "$dist_codex_generated" \
  --argjson dist_cursor_generated "$dist_cursor_generated" \
  --argjson codeowners_canonical "$codeowners_canonical" \
  --argjson codeowners_plugins "$codeowners_plugins" \
  --argjson codeowners_scripts "$codeowners_scripts" \
  --argjson codeowners_hooks "$codeowners_hooks" \
  --argjson validate_job "$validate_job" \
  --argjson npm_validate "$npm_validate" \
  '{
    root: $root,
    plugin_name: $plugin_name,
    agent_kit_config: $agent_kit_config,
    canonical: {
      core_rules: $canonical_core,
      skills_dir: $canonical_skills_dir,
      skill_count: $canonical_skill_count
    },
    scripts: { build_mjs: $build_script, validate_mjs: $validate_script },
    package_json: $package_json,
    package_lock_json: $package_lock_json,
    marketplace_json: $marketplace_json,
    plugin_wrapper: {
      exists: $plugin_wrapper,
      manifest: $plugin_manifest,
      skills_dir: $plugin_skills_dir
    },
    dist: {
      codex_agents_md: $dist_codex_agents,
      cursor_core_mdc: $dist_cursor_core,
      codex_generated: $dist_codex_generated,
      cursor_generated: $dist_cursor_generated
    },
    codeowners: {
      canonical: $codeowners_canonical,
      plugins: $codeowners_plugins,
      scripts: $codeowners_scripts,
      hooks: $codeowners_hooks
    },
    ci: { validate_job: $validate_job },
    npm: { validate_script: $npm_validate }
  }'
