#!/usr/bin/env bash
# Credential source for scripts/notify-pushover.sh.
#
# WHY THIS IS A TEST AND NOT A COMMENT
#   The notifier has exactly ONE credential source: the manifest's sensitive
#   `pushover_token`/`pushover_user` userConfig options, exported to the plugin's
#   hooks as CLAUDE_PLUGIN_OPTION_PUSHOVER_TOKEN / _USER. Earlier versions also read
#   PUSHOVER_TOKEN/PUSHOVER_USER from the environment and ~/.claude/pushover.env;
#   the Anthropic directory policy forbids a plugin sending a credential it found
#   on the machine, so a regression that quietly re-adds either source would fail
#   directory review AND send with credentials the person never handed the plugin.
#   Nothing errors in that case: notifications simply go out. Hence a test.
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
# A credentials file an older install may have left behind. It must be ignored.
mkdir -p "$T/home/.claude"
printf 'PUSHOVER_TOKEN=from_file\nPUSHOVER_USER=file_user\n' > "$T/home/.claude/pushover.env"

run(){ env -i PATH="$T:$PATH" HOME="$T/home" PUSHOVER_DEBUG=1 "$@" \
        bash "$N" "hello" "default" </dev/null 2>&1 | head -1; }

echo "--- the manifest options are the one source ---"
got="$(run CLAUDE_PLUGIN_OPTION_PUSHOVER_TOKEN=from_uc CLAUDE_PLUGIN_OPTION_PUSHOVER_USER=u)"
[ "$got" = "token=from_uc" ] && ok "userConfig options send" || bad "userConfig options send" "got: $got"

echo "--- a credential found on the machine is never used ---"
got="$(run PUSHOVER_TOKEN=from_env PUSHOVER_USER=u)"
[ -z "$got" ] && ok "PUSHOVER_TOKEN/PUSHOVER_USER in the environment are ignored" || bad "environment credentials are ignored" "got: $got"

got="$(run)"
[ -z "$got" ] && ok "a pushover.env under HOME is ignored" || bad "pushover.env is ignored" "got: $got"

got="$(run PUSHOVER_ENV="$T/home/.claude/pushover.env")"
[ -z "$got" ] && ok "the old PUSHOVER_ENV override is ignored too" || bad "PUSHOVER_ENV override is ignored" "got: $got"

echo "--- half a configuration sends nothing ---"
got="$(run CLAUDE_PLUGIN_OPTION_PUSHOVER_TOKEN=only_token)"
[ -z "$got" ] && ok "a token without a user key does not send" || bad "a token without a user key does not send" "got: $got"

echo "--- unconfigured is a normal state ---"
if env -i PATH="$T:$PATH" HOME="$T/home" bash "$N" "x" "default" </dev/null >/dev/null 2>&1; then
  ok "exits 0 when nothing is configured"
else
  bad "exits 0 when nothing is configured" "non-zero exit"
fi
out="$(env -i PATH="$T:$PATH" HOME="$T/home" bash "$N" "x" "default" </dev/null 2>&1)"
[ -z "$out" ] && ok "stays silent when nothing is configured" || bad "stays silent when nothing is configured" "got: $out"

echo "--- the hook is the plugin's own, so the options reach it ---"
if jq -e '[.hooks.Notification[].hooks[].command] | any(test("notify-pushover"))' "$ROOT/hooks/hooks.json" >/dev/null 2>&1; then
  ok "hooks.json wires notify-pushover.sh on Notification (a settings.json hook never gets CLAUDE_PLUGIN_OPTION_*)"
else
  bad "hooks.json wires notify-pushover.sh on Notification" "not found"
fi

echo "--- the manifest declares every credential as sensitive ---"
M="$ROOT/.claude-plugin/plugin.json"
for k in pushover_token pushover_user github_token; do
  if jq -e --arg k "$k" '.userConfig[$k].sensitive == true' "$M" >/dev/null 2>&1; then
    ok "$k is declared sensitive (credential store, not settings.json)"
  else
    bad "$k is declared sensitive" "missing or not sensitive"
  fi
done

echo "--- no shipped script reads a credential off the machine ---"
# The scanner's rule, mirrored: a hook, script or mod that reads a token from the
# environment or a dotfile and could send it. `gh auth token` and pushover.env
# reads are the two this repo used to have.
hits="$(grep -rnE 'gh auth token|pushover\.env|\$\{?PUSHOVER_TOKEN|\$\{?GITHUB_TOKEN|\$\{?GH_TOKEN' "$ROOT/scripts" "$ROOT/hooks" "$ROOT/mod" --include='*.sh' --include='*.py' --include='*.tsx' --include='*.ts' 2>/dev/null \
  | grep -vE '^\S+:[0-9]+:\s*#' | grep -vE 'mods\.test\.tsx|check-claude-dist\.sh|build-claude-dist\.sh' || true)"
[ -z "$hits" ] && ok "scripts/, hooks/ and mod/ read no machine credential" || bad "scripts/, hooks/ and mod/ read no machine credential" "$hits"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -gt 0 ] && { printf 'failing:'; printf ' %s' "${FAILED[@]}"; echo; exit 1; }
exit 0
