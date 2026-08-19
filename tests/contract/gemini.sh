#!/usr/bin/env bash
# Platform contract — Gemini CLI (new first-class target, REFACTOR-SPEC §13.4).
# shellcheck shell=bash

# Fragment, not an entrypoint: sourced by tests/contract/run.sh. Run standalone it would die on
# the first helper call with an opaque 127, so say what to run instead.
if ! declare -f judge >/dev/null 2>&1; then
  printf 'This file is a test fragment, not an entrypoint.\nRun: bash tests/contract/run.sh\n' >&2
  exit 2
fi

section "platform contract: Gemini CLI"

contract_registry_entry gemini_cli "Gemini CLI"
contract_manifest "gemini extension" "gemini-extension.json"

M="$REPO_ROOT/gemini-extension.json"
judge "extension name is tamirs-superpowers" "tamirs-superpowers" "$(jq -r .name "$M")"
judge "gemini extension version matches the Claude manifest" \
  "$(jq -r .version "$REPO_ROOT/.claude-plugin/plugin.json")" "$(jq -r .version "$M")"

ctx="$(jq -r '.contextFileName // empty' "$M")"
if [ -n "$ctx" ]; then
  judge "the declared context file exists ($ctx)" yes "$(exists "$REPO_ROOT/$ctx")"
else
  skip "gemini context file" "extension declares no contextFileName"
fi

# MCP server commands must resolve inside the extension.
mcpmiss=""
while IFS= read -r a; do
  [ -n "$a" ] || continue
  case "$a" in
    *'${extensionPath}/'*) t="${a#*\$\{extensionPath\}/}"; [ -e "$REPO_ROOT/$t" ] || mcpmiss="$mcpmiss $t" ;;
  esac
done < <(jq -r '.mcpServers // {} | to_entries[] | .value.args[]? // empty' "$M")
judge "every mcpServers arg under \${extensionPath} resolves" "" "$mcpmiss"

# Skill discovery — Gemini gets a generated skills tree.
if [ -d "$REPO_ROOT/.gemini/skills" ]; then
  # -L: the generated tree may be symlinks into skills/, and find does not
  # descend a symlinked directory without it.
  gn="$(find -L "$REPO_ROOT/.gemini/skills" -maxdepth 2 -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')"
  cn="$(find "$REPO_ROOT/skills" -maxdepth 3 -name SKILL.md 2>/dev/null | grep -vc '_contract' || true)"
  judge ".gemini/skills ships a SKILL.md for every canonical skill" "$cn" "$gn"
else
  skip "gemini skill discovery" ".gemini/skills not present"
fi

# Agent discovery.
if [ -d "$REPO_ROOT/.gemini/agents" ]; then
  an="$(find "$REPO_ROOT/.gemini/agents" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')"
  cn="$(find "$REPO_ROOT/agents" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')"
  judge ".gemini/agents mirrors agents/" "$cn" "$an"
else
  skip "gemini agent discovery" ".gemini/agents not present"
fi

# Generated-adapter drift — owned by the gemini-adapter peer; called, not copied.
contract_peer_suite "gemini adapter suite (peer-owned)" "tests/test-gemini-adapter.sh"

# --- CLI half --------------------------------------------------------------
contract_cli "gemini extensions validate ." gemini gemini extensions validate "$REPO_ROOT"
