#!/usr/bin/env bash
# Platform contract — OpenAI Codex CLI.
# shellcheck shell=bash

# Fragment, not an entrypoint: sourced by tests/contract/run.sh. Run standalone it would die on
# the first helper call with an opaque 127, so say what to run instead.
if ! declare -f judge >/dev/null 2>&1; then
  printf 'This file is a test fragment, not an entrypoint.\nRun: bash tests/contract/run.sh\n' >&2
  exit 2
fi

section "platform contract: Codex"

contract_registry_entry codex "Codex CLI"
contract_manifest "codex" ".codex-plugin/plugin.json"

M="$REPO_ROOT/.codex-plugin/plugin.json"
codex_skill_paths=()
read_lines codex_skill_paths < <(jq -r '.skills[]?' "$M")
contract_skill_paths "codex" ${codex_skill_paths[@]+"${codex_skill_paths[@]}"}

judge "codex manifest version matches the Claude manifest" \
  "$(jq -r .version "$REPO_ROOT/.claude-plugin/plugin.json")" "$(jq -r .version "$M")"

# AGENTS.md is the Codex entrypoint — the canonical contributor contract.
judge "AGENTS.md exists at the repo root" yes "$(exists "$REPO_ROOT/AGENTS.md")"
judge "AGENTS.md is not a stub" yes \
  "$(if [ "$(wc -l < "$REPO_ROOT/AGENTS.md")" -gt 20 ]; then echo yes; else echo no; fi)"

# Hooks, if declared, must point at a file that exists.
hookref="$(jq -r '.hooks // empty' "$M")"
if [ -n "$hookref" ]; then
  judge "the declared hooks file exists ($hookref)" yes "$(exists "$REPO_ROOT/${hookref#./}")"
  judge "the declared hooks file parses" 0 \
    "$(jq empty "$REPO_ROOT/${hookref#./}" >/dev/null 2>&1; echo $?)"
else
  skip "codex hook config" "manifest declares no hooks"
fi

# Codex config.
if [ -f "$REPO_ROOT/.codex/config.toml" ]; then
  contract_manifest "codex config" ".codex/config.toml"
  judge ".codex/config.toml carries no absolute home path" "" \
    "$(grep -nE '/(Users|home)/[A-Za-z0-9._-]+' "$REPO_ROOT/.codex/config.toml" \
       | grep -vE '/Users/(you|username|\$USER)' || true)"
else
  skip "codex config.toml" "not present"
fi

# MCP.
judge "codex manifest declares mcpServers" yes \
  "$(if jq -e 'has("mcpServers")' "$M" >/dev/null 2>&1; then echo yes; else echo no; fi)"

# --- CLI half --------------------------------------------------------------
contract_cli "codex CLI is available for a live load test" codex codex --version
