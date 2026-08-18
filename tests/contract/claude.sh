#!/usr/bin/env bash
# Platform contract — Claude Code (and Claude Desktop as a runtime surface of it).
# shellcheck shell=bash

section "platform contract: Claude Code"

contract_registry_entry claude_code "Claude Code"
contract_manifest "claude" ".claude-plugin/plugin.json"
contract_manifest "marketplace" ".claude-plugin/marketplace.json"

M="$REPO_ROOT/.claude-plugin/plugin.json"
judge "plugin name is tamirs-superpowers" "tamirs-superpowers" "$(jq -r .name "$M")"
judge "plugin declares a semver version" yes \
  "$(if jq -r .version "$M" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+'; then echo yes; else echo no; fi)"

claude_skill_paths=()
read_lines claude_skill_paths < <(jq -r '.skills[]?' "$M")
judge "the manifest declares skill paths" yes \
  "$(if [ "${#claude_skill_paths[@]}" -gt 0 ]; then echo yes; else echo no; fi)"
contract_skill_paths "claude" ${claude_skill_paths[@]+"${claude_skill_paths[@]}"}

# Agent discovery: Claude reads agents/ from the plugin root.
judge "agents/ is present and non-empty" yes \
  "$(if [ -n "$(find "$REPO_ROOT/agents" -maxdepth 1 -name '*.md' -print -quit 2>/dev/null)" ]; then echo yes; else echo no; fi)"

# Hook config: the only target where the Claude-shaped hook bundle runs as shipped.
judge "hooks/hooks.json exists" yes "$(exists "$REPO_ROOT/hooks/hooks.json")"
judge "hooks/hooks.json parses" 0 "$(jq empty "$REPO_ROOT/hooks/hooks.json" >/dev/null 2>&1; echo $?)"
hookmiss=""
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  # Commands are written against ${CLAUDE_PLUGIN_ROOT}; resolve to this checkout.
  rel="${cmd//\$\{CLAUDE_PLUGIN_ROOT\}\//}"
  rel="${rel//\$CLAUDE_PLUGIN_ROOT\//}"
  for tok in $rel; do
    case "$tok" in
      hooks/*.sh|scripts/*.sh) [ -f "$REPO_ROOT/$tok" ] || hookmiss="$hookmiss $tok" ;;
    esac
  done
done < <(jq -r '.. | objects | .command? // empty' "$REPO_ROOT/hooks/hooks.json")
judge "every hook command points at a script that exists" "" "$hookmiss"

# MCP config.
judge ".mcp.json exists and parses" 0 "$(jq empty "$REPO_ROOT/.mcp.json" >/dev/null 2>&1; echo $?)"
# `.mcpServers` may be an inline object or a path to a file. A `case` cannot be
# written inside $( ) — its `)` closes the substitution — so resolve it first.
mcpref="$(jq -r 'if (.mcpServers | type) == "string" then .mcpServers else "" end' "$M")"
if [ -n "$mcpref" ]; then
  judge "the manifest's mcpServers file reference resolves ($mcpref)" yes \
    "$(exists "$REPO_ROOT/${mcpref#./}")"
else
  judge "the manifest declares mcpServers inline and .mcp.json parses" 0 \
    "$(jq empty "$REPO_ROOT/.mcp.json" >/dev/null 2>&1; echo $?)"
fi

# Statusline is declared in settings and must actually run.
sl="$(jq -r '.settings.statusLine.command // empty' "$M")"
if [ -n "$sl" ]; then
  judge "settings.statusLine is an object with a command (not a bare string)" "command" \
    "$(jq -r '.settings.statusLine | if type == "object" then (if has("command") then "command" else "no-command" end) else "string" end' "$M")"
  # The command is a shell expression with fallbacks, not a bare path, so assert
  # on the script it ultimately runs.
  judge "the statusline script it invokes exists" yes "$(exists "$REPO_ROOT/scripts/statusline.sh")"
  judge "the statusline runs headless against empty session JSON" 0 \
    "$(printf '{}' | bash "$REPO_ROOT/scripts/statusline.sh" >/dev/null 2>&1; echo $?)"
else
  skip "statusline declaration" "no settings.statusLine in the manifest"
fi

# Generated-adapter drift for this target: none — Claude consumes canonical files.
judge "no generated Claude adapter exists to drift" yes \
  "$(if [ ! -d "$REPO_ROOT/.claude/generated" ]; then echo yes; else echo no; fi)"

# --- CLI half --------------------------------------------------------------
contract_cli "claude plugin validate ." claude claude plugin validate "$REPO_ROOT"
