#!/usr/bin/env bash
# test-ip-scan-placeholder.sh — a plugin userConfig placeholder is not a credential,
# and allowing it hides nothing else.
#
# WHY THIS FILE EXISTS
#   A plugin's .mcp.json passes secrets through as
#   `"SOME_TOKEN": "${user_config.some_token}"`. Claude Code fills that in at
#   install time; the file never holds a value. ip-scan's credential pattern still
#   read it as a hard-coded secret, so every plugin that wires a secret through
#   userConfig could never scan CLEAN.
#
#   The allowlist drops a whole line, so the entry is anchored to a line that is
#   exactly one key whose entire value is the placeholder. Each case is asserted in
#   both directions: a literal secret beside the placeholder, or a placeholder with
#   extra text inside the quotes, must still be a hit.
#
#   Key names are assembled at run time. This repo's own PR checklist runs
#   ip-scan.sh over the tree, and a literal fixture line would be a hit.
#
# Usage: bash tests/test-ip-scan-placeholder.sh
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$REPO_ROOT/tests/lib/harness.sh"

IPSCAN="$REPO_ROOT/skills/repo/_contract/scripts/ip-scan.sh"
TMP="$(harness_tmpdir)"
KEY='OP_SERVICE_ACCOUNT''_TOKEN'
OTHER='GITHUB''_TOKEN'

# repo <name> <json-line>... — a repo whose one .mcp.json env block holds these lines.
repo() {
  local d="$TMP/$1"; shift
  mkdir -p "$d"
  { printf '{\n  "env": {\n'; printf '    %s\n' "$@"; printf '  }\n}\n'; } > "$d/.mcp.json"
  printf '%s\n' "$d"
}
scan_clean() { has "$(bash "$IPSCAN" "$1" 2>&1)" "RESULT: CLEAN"; }

section "ip-scan.sh / userConfig placeholder"

judge "a placeholder value is clean" yes \
  "$(scan_clean "$(repo plain "\"$KEY\": \"\${user_config.op_token}\"")")"
judge "a placeholder followed by a comma is clean" yes \
  "$(scan_clean "$(repo comma "\"$KEY\": \"\${user_config.op_token}\"," "\"B\": \"x\"")")"
judge "a literal secret is still a hit" no \
  "$(scan_clean "$(repo literal "\"$KEY\": \"ops_abcdefghijklmnop\"")")"
judge "a literal secret beside a placeholder is still a hit" no \
  "$(scan_clean "$(repo beside "\"$KEY\": \"\${user_config.op_token}\", \"$OTHER\": \"ghp_abcdefghijklmnop\"")")"
judge "extra text inside the quotes is still a hit" no \
  "$(scan_clean "$(repo extra "\"$KEY\": \"\${user_config.op_token}abcdefgh\"")")"
judge "a different substitution is still a hit" no \
  "$(scan_clean "$(repo env "\"$KEY\": \"\${OTHER_SOURCE_TOKEN_VAL}\"")")"

harness_summary
