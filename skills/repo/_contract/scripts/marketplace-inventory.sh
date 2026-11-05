#!/usr/bin/env bash
# marketplace-inventory.sh — JSON snapshot of a plugin-marketplace repo (marketplace-gold).
#
# Usage: marketplace-inventory.sh <repo-root>
#
# A marketplace repo is a catalog of plugins published in the manifest each platform reads.
# Three platforms have one (doc-cited 2026-11-05, docs/engineering/research/marketplace-standards.md):
# Claude Code .claude-plugin/marketplace.json, Cursor .cursor-plugin/marketplace.json, Codex
# .agents/plugins/marketplace.json. OpenCode has none, so this inventory records nothing for it
# beyond whether the README says so.
set -euo pipefail

ROOT="${1:-.}"
if ! ROOT="$(cd "$ROOT" 2>/dev/null && pwd)"; then
  echo '{"error":"not a directory"}'
  exit 0
fi

exists() { [[ -f "$1" ]] && echo true || echo false; }

claude_manifest=$(exists "$ROOT/.claude-plugin/marketplace.json")
cursor_manifest=$(exists "$ROOT/.cursor-plugin/marketplace.json")
codex_manifest=$(exists "$ROOT/.agents/plugins/marketplace.json")
validate_script=$(exists "$ROOT/scripts/validate-marketplace.sh")
catalog_doc=$(exists "$ROOT/docs/user/catalog.md")

# The validate script is the deterministic gate for manifest content; the platform CLI is
# skipped here so the score does not depend on what is installed on the scoring machine.
validate_passes=false
if [[ "$validate_script" == true ]]; then
  MARKETPLACE_SKIP_CLI=1 bash "$ROOT/scripts/validate-marketplace.sh" "$ROOT" >/dev/null 2>&1 && validate_passes=true
fi

# Local plugins: every directory under plugins/ and whether it carries a Claude manifest.
local_plugin_count=0
local_plugins_without_manifest=0
if compgen -G "$ROOT/plugins/*" >/dev/null; then
  for plugin_dir in "$ROOT"/plugins/*/; do
    [[ -d "$plugin_dir" ]] || continue
    local_plugin_count=$((local_plugin_count + 1))
    [[ -f "$plugin_dir/.claude-plugin/plugin.json" ]] || local_plugins_without_manifest=$((local_plugins_without_manifest + 1))
  done
fi

readme_catalog_table=false
readme_mentions_opencode=false
if [[ -f "$ROOT/README.md" ]]; then
  grep -qE '^## Catalog' "$ROOT/README.md" 2>/dev/null \
    && grep -qE '^\| *Plugin *\|' "$ROOT/README.md" 2>/dev/null && readme_catalog_table=true
  grep -q 'OpenCode' "$ROOT/README.md" 2>/dev/null && readme_mentions_opencode=true
fi

co_plugins=false; co_scripts=false; co_claude=false; co_cursor=false; co_agents=false
if [[ -f "$ROOT/CODEOWNERS" ]]; then
  grep -qE 'plugins/' "$ROOT/CODEOWNERS" 2>/dev/null && co_plugins=true
  grep -qE 'scripts/' "$ROOT/CODEOWNERS" 2>/dev/null && co_scripts=true
  grep -qE '\.claude-plugin/' "$ROOT/CODEOWNERS" 2>/dev/null && co_claude=true
  grep -qE '\.cursor-plugin/' "$ROOT/CODEOWNERS" 2>/dev/null && co_cursor=true
  grep -qE '\.agents/' "$ROOT/CODEOWNERS" 2>/dev/null && co_agents=true
fi

validate_job=false
if [[ -d "$ROOT/.github/workflows" ]]; then
  while IFS= read -r wf; do
    [[ -f "$wf" ]] || continue
    if grep -Eiq '^[[:space:]]{2}validate:' "$wf" 2>/dev/null; then validate_job=true; break; fi
  done < <(find "$ROOT/.github/workflows" \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null)
fi

make_validate=false
[[ -f "$ROOT/Makefile" ]] && grep -qE '^validate:' "$ROOT/Makefile" 2>/dev/null && make_validate=true

jq -nc \
  --arg root "$ROOT" \
  --argjson claude_manifest "$claude_manifest" \
  --argjson cursor_manifest "$cursor_manifest" \
  --argjson codex_manifest "$codex_manifest" \
  --argjson validate_script "$validate_script" \
  --argjson validate_passes "$validate_passes" \
  --argjson catalog_doc "$catalog_doc" \
  --argjson local_plugin_count "$local_plugin_count" \
  --argjson local_plugins_without_manifest "$local_plugins_without_manifest" \
  --argjson readme_catalog_table "$readme_catalog_table" \
  --argjson readme_mentions_opencode "$readme_mentions_opencode" \
  --argjson co_plugins "$co_plugins" --argjson co_scripts "$co_scripts" \
  --argjson co_claude "$co_claude" --argjson co_cursor "$co_cursor" --argjson co_agents "$co_agents" \
  --argjson validate_job "$validate_job" \
  --argjson make_validate "$make_validate" \
  '{
    root: $root,
    manifests: { claude_code: $claude_manifest, cursor: $cursor_manifest, codex: $codex_manifest, opencode: null },
    validate: { script: $validate_script, passes: $validate_passes, make_target: $make_validate, ci_job: $validate_job },
    local_plugins: { count: $local_plugin_count, without_manifest: $local_plugins_without_manifest },
    readme: { catalog_table: $readme_catalog_table, mentions_opencode: $readme_mentions_opencode },
    docs: { catalog: $catalog_doc },
    codeowners: { plugins: $co_plugins, scripts: $co_scripts, claude_plugin: $co_claude, cursor_plugin: $co_cursor, agents: $co_agents }
  }'
