#!/usr/bin/env bash
# Platform contract — OpenCode.
# shellcheck shell=bash

# Fragment, not an entrypoint: sourced by tests/contract/run.sh. Run standalone it would die on
# the first helper call with an opaque 127, so say what to run instead.
if ! declare -f judge >/dev/null 2>&1; then
  printf 'This file is a test fragment, not an entrypoint.\nRun: bash tests/contract/run.sh\n' >&2
  exit 2
fi

section "platform contract: OpenCode"

contract_registry_entry opencode "OpenCode CLI"
contract_manifest "opencode config" "opencode.json"

M="$REPO_ROOT/opencode.json"
judge "opencode.json declares a \$schema" yes \
  "$(if [ -n "$(jq -r '."$schema" // ""' "$M")" ]; then echo yes; else echo no; fi)"

# A regression to the OpenCode 1 `{ "paths": [...], "urls": [...] }` object would make the
# `.skills[]?` read below iterate the object's values and look like a populated config.
judge "opencode.json skills is a flat array (OpenCode 2), not the v1 {paths} object" array \
  "$(jq -r '.skills | type' "$M")"

oc_paths=()
# v2 defines `skills` as a flat array of strings (Schema.String.pipe(Schema.Array)).
# URL entries are skipped: the array accepts "paths OR URLs", and the path/coverage
# assertions below are about directories on disk.
read_lines oc_paths < <(jq -r '
  (.skills[]? )
  | select(type == "string")
  | select(startswith("http") | not)
' "$M")
judge "opencode.json declares skill paths" yes \
  "$(if [ "${#oc_paths[@]}" -gt 0 ]; then echo yes; else echo no; fi)"
contract_skill_paths "opencode" ${oc_paths[@]+"${oc_paths[@]}"}
contract_skill_coverage "opencode" ${oc_paths[@]+"${oc_paths[@]}"}

# Agent adapters are GENERATED from agents/ — drift here is a real shipping bug.
if [ -d "$REPO_ROOT/.opencode/agents" ]; then
  an="$(find "$REPO_ROOT/.opencode/agents" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')"
  cn="$(find "$REPO_ROOT/agents" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')"
  judge ".opencode/agents mirrors agents/ one-for-one" "$cn" "$an"

  nofm=""
  while IFS= read -r f; do
    head -1 "$f" | grep -q '^---' || nofm="$nofm $(basename "$f")"
  done < <(find "$REPO_ROOT/.opencode/agents" -maxdepth 1 -name '*.md')
  judge "every generated OpenCode agent opens with frontmatter" "" "$nofm"
else
  skip "opencode agent adapters" ".opencode/agents not present"
fi

# node_modules must never be shipped as repo content.
judge ".opencode/node_modules is gitignored" yes \
  "$(if git -C "$REPO_ROOT" check-ignore -q .opencode/node_modules 2>/dev/null; then echo yes; else echo no; fi)"

# Generated-adapter drift, via the repo's own generator in --check mode.
contract_peer_suite "opencode adapter suite (peer-owned)" "tests/test-opencode-adapter.sh"

# --- CLI half --------------------------------------------------------------
contract_cli "opencode CLI is available for a live load test" opencode opencode --version
