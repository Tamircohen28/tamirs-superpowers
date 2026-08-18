#!/usr/bin/env bash
# Platform contract — OpenCode.
# shellcheck shell=bash

section "platform contract: OpenCode"

contract_registry_entry opencode "OpenCode"
contract_manifest "opencode config" "opencode.json"

M="$REPO_ROOT/opencode.json"
judge "opencode.json declares a \$schema" yes \
  "$(if [ -n "$(jq -r '."$schema" // ""' "$M")" ]; then echo yes; else echo no; fi)"

oc_paths=()
read_lines oc_paths < <(jq -r '.skills.paths[]? // .skills[]? // empty' "$M")
judge "opencode.json declares skill paths" yes \
  "$(if [ "${#oc_paths[@]}" -gt 0 ]; then echo yes; else echo no; fi)"
contract_skill_paths "opencode" ${oc_paths[@]+"${oc_paths[@]}"}

# Agent adapters are GENERATED from agents/ — drift here is a real shipping bug.
if [ -d "$REPO_ROOT/.opencode/agent" ]; then
  an="$(find "$REPO_ROOT/.opencode/agent" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')"
  cn="$(find "$REPO_ROOT/agents" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')"
  judge ".opencode/agent mirrors agents/ one-for-one" "$cn" "$an"

  nofm=""
  while IFS= read -r f; do
    head -1 "$f" | grep -q '^---' || nofm="$nofm $(basename "$f")"
  done < <(find "$REPO_ROOT/.opencode/agent" -maxdepth 1 -name '*.md')
  judge "every generated OpenCode agent opens with frontmatter" "" "$nofm"
else
  skip "opencode agent adapters" ".opencode/agent not present"
fi

# node_modules must never be shipped as repo content.
judge ".opencode/node_modules is gitignored" yes \
  "$(if git -C "$REPO_ROOT" check-ignore -q .opencode/node_modules 2>/dev/null; then echo yes; else echo no; fi)"

# Generated-adapter drift, via the repo's own generator in --check mode.
contract_peer_suite "opencode adapter suite (peer-owned)" "tests/test-opencode-adapter.sh"

# --- CLI half --------------------------------------------------------------
contract_cli "opencode CLI is available for a live load test" opencode opencode --version
