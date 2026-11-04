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
# THE SERVER BINARY (L1, the second adversarial pass)
#   The token goes to exactly one program, so that program is never looked up on
#   the inherited PATH (a repository's env or .envrc can put its own
#   `github-mcp-server` first). It is the first of these that holds an acceptable
#   binary: /opt/homebrew/bin, /usr/local/bin, Linuxbrew's bin (its fixed prefix),
#   <passwd home>/.local/bin (the passwd entry's home, D3, never HOME), /usr/bin;
#   the Docker fallback's `docker` likewise (plus Docker Desktop's
#   /Applications/Docker.app/Contents/Resources/bin). A symlink is followed to its
#   file. Acceptable: a regular executable file owned by root or this user and
#   writable by neither group nor others, in a directory (its own and the listed
#   one) owned by root or this user and not world-writable (Homebrew's bin is
#   group-writable by design). Under the permission suites' accepted test root the
#   list is that root's .local/bin alone. The token is taken out of the
#   environment first and handed back only to that binary at exec, so no helper
#   (python3, bash, ps) this script runs on PATH ever sees it; those helpers are
#   trusted as every hook of this plugin trusts them (ADR 004 Open risks).
#
# Tries the official binary first, falls back to Docker.
set -euo pipefail

# The token is for the server alone: no helper below inherits it (L1).
GM_TOKEN="${GITHUB_PERSONAL_ACCESS_TOKEN:-}"
unset GITHUB_PERSONAL_ACCESS_TOKEN

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

GM_FIND=/usr/bin/find; [[ -x "$GM_FIND" ]] || GM_FIND=/bin/find
GM_READLINK=/usr/bin/readlink; [[ -x "$GM_READLINK" ]] || GM_READLINK=/bin/readlink

# gm_owned_ok <path> — owned by root or this user (fixed-path find, never PATH).
gm_owned_ok() {
  [[ -O "$1" ]] && return 0
  [[ -n "$("$GM_FIND" "$1" -maxdepth 0 -user 0 -print 2>/dev/null)" ]]
}
# gm_writable_by <path> <perm> — prints the path when any of the given write bits is set.
gm_writable_by() { "$GM_FIND" "$1" -maxdepth 0 -perm "$2" -print 2>/dev/null; }

# gm_real <path> — the file a symlink chain ends at, absolute (at most 16 hops).
gm_real() {
  local p="$1" t n=0 d
  while [[ -L "$p" && "$n" -lt 16 ]]; do
    t="$("$GM_READLINK" "$p" 2>/dev/null)" || return 1
    case "$t" in /*) p="$t" ;; *) p="${p%/*}/$t" ;; esac
    n=$((n + 1))
  done
  [[ -L "$p" ]] && return 1
  d="$(CDPATH='' cd -P -- "${p%/*}" 2>/dev/null && pwd -P)" || return 1
  printf '%s/%s\n' "$d" "${p##*/}"
}

# gm_home_dirs — "<home><TAB><home_source>" from the permission library (passwd home, D3).
gm_home_dirs() {
  local out=""
  # shellcheck source=scripts/lib/permission-common.sh
  if [[ -n "$GM_ROOT" ]] && . "$GM_ROOT/scripts/lib/permission-common.sh" 2>/dev/null; then
    out="$(perm_dirs 2>/dev/null | python3 -I -S -c 'import json, sys
try:
    d = json.load(sys.stdin)
except ValueError:
    d = {}
h, s = d.get("home"), d.get("home_source")
print("%s\t%s" % (h, s) if isinstance(h, str) and h.startswith("/") and "\t" not in h else "")' 2>/dev/null)" || out=""
  fi
  printf '%s' "$out"
}

GM_REFUSED=()
GM_FOUND=""
# gm_trusted <name> — sets GM_FOUND to the absolute path of an acceptable <name> from the fixed list (THE
# SERVER BINARY), or to nothing (returns 1). Every candidate it rejects is appended to GM_REFUSED with the
# reason. Called directly, never in a subshell, so both survive.
gm_trusted() {
  local name="$1" home="" src="" dirs=() d c real x
  GM_FOUND=""
  IFS=$'\t' read -r home src < <(gm_home_dirs) || true
  if [[ "$src" == test-root ]]; then
    dirs=("$home/.local/bin")
  else
    # Linuxbrew's fixed prefix is /home/<lb>/.<lb> with <lb> = linuxbrew (spelled through a variable so
    # this file names no home directory).
    local lb=linuxbrew
    dirs=(/opt/homebrew/bin /usr/local/bin "/home/$lb/.$lb/bin")
    [[ "$home" == /* ]] && dirs+=("$home/.local/bin")
    dirs+=(/usr/bin)
    [[ "$name" == docker ]] && dirs+=(/Applications/Docker.app/Contents/Resources/bin)
  fi
  for d in "${dirs[@]}"; do
    c="$d/$name"
    [[ -e "$c" || -L "$c" ]] || continue
    if ! real="$(gm_real "$c")"; then GM_REFUSED+=("$c: the symlink does not resolve"); continue; fi
    if [[ ! -f "$real" || ! -x "$real" ]]; then GM_REFUSED+=("$c: $real is not an executable file"); continue; fi
    if ! gm_owned_ok "$real"; then GM_REFUSED+=("$c: $real is owned by another user"); continue; fi
    if [[ -n "$(gm_writable_by "$real" -0020)$(gm_writable_by "$real" -0002)" ]]; then
      GM_REFUSED+=("$c: $real is group- or world-writable"); continue
    fi
    local bad=""
    for x in "${real%/*}" "$d"; do
      if ! gm_owned_ok "$x" || [[ -n "$(gm_writable_by "$x" -0002)" ]]; then bad="$x"; break; fi
    done
    if [[ -n "$bad" ]]; then GM_REFUSED+=("$c: its directory $bad is world-writable or owned by another user"); continue; fi
    GM_FOUND="$real"
    return 0
  done
  return 1
}

IFS=$'\t' read -r LEVEL WHY < <(gm_level) || true
LEVEL="${LEVEL:-supervised}"
case "$LEVEL" in
  supervised) FLAGS=(--read-only) ;;
  standard|unattended) FLAGS=(--exclude-tools "$EXCLUDE_ALWAYS,$EXCLUDE_UNVERIFIED") ;;
  *) LEVEL=supervised; FLAGS=(--read-only) ;;
esac

SERVER="" DOCKER=""
if gm_trusted github-mcp-server; then
  SERVER="$GM_FOUND"
elif gm_trusted docker; then
  DOCKER="$GM_FOUND"
fi

gm_jstr() { local s="$1"; s="${s//\\/\\\\}"; s="${s//\"/\\\"}"; s="${s//$'\n'/ }"; s="${s//$'\t'/ }"; printf '"%s"' "$s"; }

if [[ "$PRINT" -eq 1 ]]; then
  printf '{"level": "%s", "host": "%s", "why": %s, "flags": [' "$LEVEL" "$HOST" "$(gm_jstr "$WHY")"
  sep=""
  for f in "${FLAGS[@]}"; do printf '%s"%s"' "$sep" "$f"; sep=", "; done
  printf '], "server": %s, "docker": %s, "refused": [' \
    "$([[ -n "$SERVER" ]] && gm_jstr "$SERVER" || printf null)" "$([[ -n "$DOCKER" ]] && gm_jstr "$DOCKER" || printf null)"
  sep=""
  for r in ${GM_REFUSED[@]+"${GM_REFUSED[@]}"}; do printf '%s%s' "$sep" "$(gm_jstr "$r")"; sep=", "; done
  printf ']}\n'
  exit 0
fi

if [[ -z "$GM_TOKEN" ]]; then
  echo '{"jsonrpc":"2.0","error":{"code":-32000,"message":"github_token is not set. Run: claude plugin configure tamirs-superpowers (or /plugin > tamirs-superpowers > Configure) and paste a GitHub token with repo scope."}}' >&2
  exit 1
fi

if [[ -n "$SERVER" ]]; then
  GITHUB_PERSONAL_ACCESS_TOKEN="$GM_TOKEN" exec "$SERVER" stdio "${FLAGS[@]}"
elif [[ -n "$DOCKER" ]]; then
  GITHUB_PERSONAL_ACCESS_TOKEN="$GM_TOKEN" exec "$DOCKER" run -i --rm \
    -e GITHUB_PERSONAL_ACCESS_TOKEN \
    ghcr.io/github/github-mcp-server stdio "${FLAGS[@]}"
else
  msg="Install github-mcp-server (brew install github-mcp-server): no acceptable github-mcp-server or docker in /opt/homebrew/bin, /usr/local/bin, Linuxbrew's bin, ~/.local/bin or /usr/bin (PATH is not searched)"
  for r in ${GM_REFUSED[@]+"${GM_REFUSED[@]}"}; do msg="$msg; refused $r"; done
  printf '{"jsonrpc":"2.0","error":{"code":-32000,"message":%s}}\n' "$(gm_jstr "$msg")" >&2
  exit 1
fi
