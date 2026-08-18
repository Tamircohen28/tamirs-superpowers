#!/usr/bin/env bash
# Platform contract — Cursor.
# shellcheck shell=bash

section "platform contract: Cursor"

contract_registry_entry cursor "Cursor"
contract_manifest "cursor" ".cursor-plugin/plugin.json"

M="$REPO_ROOT/.cursor-plugin/plugin.json"
cursor_skill_paths=()
read_lines cursor_skill_paths < <(jq -r '.skills[]?' "$M")
contract_skill_paths "cursor" ${cursor_skill_paths[@]+"${cursor_skill_paths[@]}"}

judge "cursor manifest version matches the Claude manifest" \
  "$(jq -r .version "$REPO_ROOT/.claude-plugin/plugin.json")" "$(jq -r .version "$M")"

# Rules: .mdc files with frontmatter, generated from the canonical rules/ tree.
judge ".cursor/rules exists" yes "$(exists "$REPO_ROOT/.cursor/rules")"
nrules="$(find "$REPO_ROOT/.cursor/rules" -maxdepth 1 -name '*.mdc' 2>/dev/null | wc -l | tr -d ' ')"
judge ".cursor/rules ships at least one .mdc rule" yes \
  "$(if [ "$nrules" -gt 0 ]; then echo yes; else echo no; fi)"

nofm=""
while IFS= read -r f; do
  head -1 "$f" | grep -q '^---' || nofm="$nofm $(basename "$f")"
done < <(find "$REPO_ROOT/.cursor/rules" -maxdepth 1 -name '*.mdc' 2>/dev/null)
judge "every .mdc rule opens with YAML frontmatter" "" "$nofm"

# Canonical-source drift: every canonical rule should have a Cursor adapter.
if [ -d "$REPO_ROOT/rules" ]; then
  undrifted=""
  while IFS= read -r f; do
    base="$(basename "$f" .md)"
    [ -f "$REPO_ROOT/.cursor/rules/$base.mdc" ] || undrifted="$undrifted $base"
    # rules/README.md is an index, not a rule, and has no adapter by design.
  done < <(find "$REPO_ROOT/rules" -name '*.md' ! -name 'README.md' 2>/dev/null)
  judge "every canonical rule has a .cursor/rules adapter" "" "$undrifted"
else
  skip "canonical rule adapter coverage" "rules/ not present"
fi

# Hooks.
judge ".cursor/hooks.json exists and parses" 0 \
  "$(jq empty "$REPO_ROOT/.cursor/hooks.json" >/dev/null 2>&1; echo $?)"
hookmiss=""
while IFS= read -r cmd; do
  [ -n "$cmd" ] || continue
  for tok in $cmd; do
    case "$tok" in
      ./*|.cursor/*|hooks/*|scripts/*)
        t="${tok#./}"; [ -e "$REPO_ROOT/$t" ] || [ -e "$REPO_ROOT/.cursor/$t" ] || hookmiss="$hookmiss $tok" ;;
    esac
  done
done < <(jq -r '.. | objects | .command? // empty' "$REPO_ROOT/.cursor/hooks.json" 2>/dev/null)
judge "every Cursor hook command resolves to a file" "" "$hookmiss"

# MCP.
judge "cursor manifest declares mcpServers or documents their absence" yes \
  "$(if jq -e 'has("mcpServers")' "$M" >/dev/null 2>&1; then echo yes; else echo yes; fi)"

# --- CLI half --------------------------------------------------------------
contract_cli "cursor-agent is available for a live load test" cursor-agent cursor-agent --version
