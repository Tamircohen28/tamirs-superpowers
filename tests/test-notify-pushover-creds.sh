#!/usr/bin/env bash
# Credential precedence for scripts/notify-pushover.sh.
#
# WHY THIS IS A TEST AND NOT A COMMENT
#   The manifest's `userConfig` block adds a THIRD credential source alongside an
#   explicit environment override and ~/.claude/pushover.env. The ordering between
#   them is the whole contract:
#     - an explicit PUSHOVER_TOKEN must still win, or tests and CI jobs that export
#       it directly would silently start sending with someone's real credentials;
#     - userConfig must beat the file, or a user who reconfigures through the host
#       prompt would keep sending with stale credentials and have no way to tell;
#     - the file must still work alone, or every existing install breaks on upgrade
#       AND the Codex CLI - which loads this same hook and never sets
#       CLAUDE_PLUGIN_OPTION_* - loses notifications entirely.
#   Each of those fails silently: notifications simply go to the wrong place, or
#   stop. Nothing errors.
#
#   No network: curl is stubbed on PATH, and PUSHOVER_DEBUG=1 is required because
#   the real send discards output.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
N="$ROOT/scripts/notify-pushover.sh"
PASS=0; FAIL=0; FAILED=()
[ -f "$N" ] || { echo "FATAL: $N missing"; exit 1; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
ok(){ PASS=$((PASS+1)); echo "  ok   $1"; }
bad(){ FAIL=$((FAIL+1)); FAILED+=("$1"); echo "  FAIL $1 — $2"; }

printf '#!/bin/sh\nfor a in "$@"; do case "$a" in token=*) printf "%%s" "$a";; esac; done\nexit 0\n' > "$T/curl"
chmod +x "$T/curl"
printf 'PUSHOVER_TOKEN=from_file\nPUSHOVER_USER=file_user\n' > "$T/creds.env"

run(){ env PATH="$T:$PATH" PUSHOVER_DEBUG=1 PUSHOVER_ENV="$T/creds.env" "$@" \
        bash "$N" "hello" "default" </dev/null 2>&1 | head -1; }

echo "--- credential precedence ---"
got="$(run PUSHOVER_TOKEN=from_env PUSHOVER_USER=u CLAUDE_PLUGIN_OPTION_PUSHOVER_TOKEN=from_uc CLAUDE_PLUGIN_OPTION_PUSHOVER_USER=u)"
[ "$got" = "token=from_env" ] && ok "an explicit environment token still wins" || bad "an explicit environment token still wins" "got: $got"

got="$(run CLAUDE_PLUGIN_OPTION_PUSHOVER_TOKEN=from_uc CLAUDE_PLUGIN_OPTION_PUSHOVER_USER=u)"
[ "$got" = "token=from_uc" ] && ok "userConfig beats the credentials file" || bad "userConfig beats the credentials file" "got: $got"

got="$(run)"
[ "$got" = "token=from_file" ] && ok "the file alone still works (existing installs, Codex)" || bad "the file alone still works" "got: $got"

echo "--- a half-configured userConfig must not shadow the file ---"
got="$(run CLAUDE_PLUGIN_OPTION_PUSHOVER_TOKEN=only_token)"
[ "$got" = "token=only_token" ] && ok "token from userConfig, user from file, still sends" || bad "token from userConfig, user from file, still sends" "got: $got"

echo "--- unconfigured is a normal state ---"
if env PATH="$T:$PATH" PUSHOVER_ENV="$T/absent.env" bash "$N" "x" "default" </dev/null >/dev/null 2>&1; then
  ok "exits 0 when nothing is configured"
else
  bad "exits 0 when nothing is configured" "non-zero exit"
fi
out="$(env PATH="$T:$PATH" PUSHOVER_ENV="$T/absent.env" bash "$N" "x" "default" </dev/null 2>&1)"
[ -z "$out" ] && ok "stays silent when nothing is configured" || bad "stays silent when nothing is configured" "got: $out"

echo "--- the manifest declares both as sensitive ---"
M="$ROOT/.claude-plugin/plugin.json"
for k in pushover_token pushover_user; do
  if jq -e --arg k "$k" '.userConfig[$k].sensitive == true' "$M" >/dev/null 2>&1; then
    ok "$k is declared sensitive (Keychain, not settings.json)"
  else
    bad "$k is declared sensitive" "missing or not sensitive"
  fi
done

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -gt 0 ] && { printf 'failing:'; printf ' %s' "${FAILED[@]}"; echo; exit 1; }
exit 0
