#!/usr/bin/env bash
# Start the GitHub MCP server for the plugin's `github` entry in .mcp.json, with
# the tool set the permission level allows (ADR 004 D8).
#
# Usage:
#   github-mcp.sh [--host <h>]                 start the server (stdio)
#   github-mcp.sh --print-flags [--host <h>]   print the flags it would pass and why,
#                                              as JSON; starts nothing, needs no token
#
# The token arrives in GITHUB_PERSONAL_ACCESS_TOKEN, which .mcp.json sets from the
# manifest's `github_token` userConfig option (`${user_config.github_token}`):
# the person pastes it once in the plugin's config dialog (or `claude plugin
# configure tamirs-superpowers`), and the host keeps it in secure storage.
#
# Nothing is read from the machine. An earlier version asked the gh CLI for its
# token; the Anthropic directory policy forbids a plugin reading a credential
# already on the user's machine and handing it to a server, so that path is gone.
# A person who prefers the gh CLI's token prints it with the gh CLI and pastes the
# result into the option.
#
# FLAGS BY LEVEL (D8; flags checked against `github-mcp-server stdio --help`,
# v2.1.0: --read-only and --exclude-tools are global flags)
#   supervised            --read-only
#   standard, unattended  --exclude-tools merge_pull_request,delete_repository,
#                         create_repository,fork_repository, plus every tool whose
#                         arguments can reach R3/R4 until the host's MCP matcher is
#                         verified: create_or_update_file,push_files,delete_file,
#                         issue_write,update_pull_request,pull_request_review_write.
#   merge_pull_request is excluded at every level: the only automatic merge is
#   `gh pr merge --auto`, and R4 tools keep their human gate on the gh path.
#   The extended list applies on every host, Cursor included: it is the only host
#   whose matcher is source-cited, but this script cannot tell its hosts apart
#   from anything a project cannot also set, so it takes the stricter row.
#
# THE LEVEL
#   scripts/resolve-permission.sh --level (the D4 resolver: the passwd-home user
#   file, never HOME or XDG_*, D3), with --host only when one is passed or the
#   Claude Code plugin environment is present (CLAUDE_PLUGIN_DATA without
#   CODEX_HOME), so only that host's option store may set it; otherwise an option
#   store can only lower it. A resolver that is missing, fails or answers anything
#   but a level means supervised (D4: failure is the strict answer). The flags are
#   fixed for the server's lifetime (ADR Open risks: a mid-session level change
#   applies at L1/L2 only). The script writes no state.
#
# Tries the official binary first, falls back to Docker.
set -euo pipefail

case "${BASH_SOURCE[0]}" in
  */*) _gm_here="${BASH_SOURCE[0]%/*}" ;;
  *) _gm_here=. ;;
esac
GM_ROOT="$(CDPATH='' cd -- "$_gm_here/.." 2>/dev/null && pwd -P)" || GM_ROOT=""
unset _gm_here

PRINT=0
HOST=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --print-flags) PRINT=1 ;;
    --host) HOST="${2:-}"; shift ;;
    --host=*) HOST="${1#--host=}" ;;
    -h|--help) sed -n '2,8p' "${BASH_SOURCE[0]}" | sed 's/^#[[:space:]]\{0,1\}//'; exit 0 ;;
    *) echo "github-mcp.sh: unknown argument: $1" >&2; exit 2 ;;
  esac
  shift
done
case "$HOST" in
  ''|claude|codex|cursor|gemini|opencode) ;;
  *) echo "github-mcp.sh: --host must be claude, codex, cursor, gemini or opencode" >&2; exit 2 ;;
esac
if [[ -z "$HOST" && -n "${CLAUDE_PLUGIN_DATA:-}" && -z "${CODEX_HOME:-}" ]]; then
  HOST=claude
fi

EXCLUDE_ALWAYS="merge_pull_request,delete_repository,create_repository,fork_repository"
EXCLUDE_UNVERIFIED="create_or_update_file,push_files,delete_file,issue_write,update_pull_request,pull_request_review_write"

# gm_level — the effective level, or supervised on any failure. Prints "level<TAB>why".
gm_level() {
  local out="" lv="" args=(--level --json)
  [[ -n "$HOST" ]] && args+=(--host "$HOST")
  if [[ -n "$GM_ROOT" && -f "$GM_ROOT/scripts/resolve-permission.sh" ]] && command -v python3 >/dev/null 2>&1; then
    out="$(bash "$GM_ROOT/scripts/resolve-permission.sh" "${args[@]}" 2>/dev/null)" || out=""
    lv="$(printf '%s' "$out" | python3 -I -S -c 'import json, sys
try:
    d = json.load(sys.stdin)
except ValueError:
    d = {}
print(d.get("level") if isinstance(d, dict) and d.get("level") in ("supervised", "standard", "unattended") else "")' 2>/dev/null)" || lv=""
  fi
  if [[ -z "$lv" ]]; then
    printf 'supervised\tthe resolver gave no level (fail closed, ADR 004 D4)'
    return 0
  fi
  printf '%s\tresolve-permission.sh --level%s' "$lv" "${HOST:+ --host $HOST}"
}

IFS=$'\t' read -r LEVEL WHY < <(gm_level) || true
LEVEL="${LEVEL:-supervised}"
case "$LEVEL" in
  supervised) FLAGS=(--read-only) ;;
  standard|unattended) FLAGS=(--exclude-tools "$EXCLUDE_ALWAYS,$EXCLUDE_UNVERIFIED") ;;
  *) LEVEL=supervised; FLAGS=(--read-only) ;;
esac

if [[ "$PRINT" -eq 1 ]]; then
  printf '{"level": "%s", "host": "%s", "why": "%s", "flags": [' "$LEVEL" "$HOST" "${WHY//\"/\'}"
  sep=""
  for f in "${FLAGS[@]}"; do printf '%s"%s"' "$sep" "$f"; sep=", "; done
  printf ']}\n'
  exit 0
fi

if [[ -z "${GITHUB_PERSONAL_ACCESS_TOKEN:-}" ]]; then
  echo '{"jsonrpc":"2.0","error":{"code":-32000,"message":"github_token is not set. Run: claude plugin configure tamirs-superpowers (or /plugin > tamirs-superpowers > Configure) and paste a GitHub token with repo scope."}}' >&2
  exit 1
fi
export GITHUB_PERSONAL_ACCESS_TOKEN

if command -v github-mcp-server &>/dev/null; then
  exec github-mcp-server stdio "${FLAGS[@]}"
elif command -v docker &>/dev/null; then
  exec docker run -i --rm \
    -e GITHUB_PERSONAL_ACCESS_TOKEN \
    ghcr.io/github/github-mcp-server stdio "${FLAGS[@]}"
else
  echo '{"jsonrpc":"2.0","error":{"code":-32000,"message":"Install github-mcp-server: brew install github-mcp-server"}}' >&2
  exit 1
fi
