#!/usr/bin/env bash
# test-hook-tiers.sh — the notification and contributor hook tiers.
#
# WHY
#   Two plugin options, `notification_hooks` (default on) and `contributor_hooks`
#   (default off), reach every hook as CLAUDE_PLUGIN_OPTION_NOTIFICATION_HOOKS /
#   CLAUDE_PLUGIN_OPTION_CONTRIBUTOR_HOOKS and gate seven hooks through
#   hooks/lib/hook-output.sh's hook_tier_gate. The failure modes this suite exists
#   for are all silent: a gated-off hook that still fires is noise the user turned
#   off; a gated-on hook that no longer fires is a feature that vanished without an
#   error; and a PreToolUse guard that answers a switched-off tier with EMPTY stdout
#   is a DENIAL on Cursor, which fail-closes on empty output. None of those shows up
#   anywhere but here.
#
#   For each gated hook: tier off → exit 0 and nothing on stdout (or the documented
#   no-op); tier on, and the tier's default → the hook's existing behaviour, driven
#   by the smallest payload that makes it say something.
#
# Hermetic: temp HOME, curl and python3 stubbed on PATH where a hook would reach
# the network or start a process, no gh, no model calls.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$ROOT/tests/lib/harness.sh"

harness_require jq python3 bash

export SUPERPOWERS_WORKTREE_CLEANUP=0
TMP="$(harness_tmpdir)"
export HOME="$TMP/home"
mkdir -p "$HOME/.claude"
export CLAUDE_TASK_SLUG=tiers-test   # keeps notify.sh off the session-state path
unset CLAUDE_PLUGIN_OPTION_NOTIFICATION_HOOKS CLAUDE_PLUGIN_OPTION_CONTRIBUTOR_HOOKS \
      CLAUDE_EXIT_PROXY CLAUDE_EXIT_PUBLIC_IP TAMIRS_USAGE_CAPTURE 2>/dev/null || true

LIB="$ROOT/hooks/lib/hook-output.sh"
MANIFEST="$ROOT/.claude-plugin/plugin.json"
NOTIFY="$ROOT/hooks/notify.sh"
PUSHOVER="$ROOT/scripts/notify-pushover.sh"
ENSURE_EXIT="$ROOT/hooks/ensure-exit.sh"
USAGE_ENSURE="$ROOT/hooks/usage-capture-ensure.sh"
RELOAD="$ROOT/hooks/plugin-reload-reminder.sh"
LINKS="$ROOT/hooks/validate-report-links.sh"
SKILL_GUARD="$ROOT/hooks/skill-creator-guard.sh"

# Stubs: curl prints a fixed IP (ensure-exit) or echoes its token= argument
# (pushover, which only prints under PUSHOVER_DEBUG=1); python3 records its argv
# and exits 0 when invoked as the usage-capture collector, else defers to the real one.
STUB="$TMP/bin"; mkdir -p "$STUB"
REAL_PYTHON3="$(command -v python3)"
cat > "$STUB/curl" <<'EOF'
#!/bin/sh
for a in "$@"; do case "$a" in token=*) printf '%s\n' "$a"; exit 0;; esac; done
printf '203.0.113.7'
EOF
cat > "$STUB/python3" <<EOF
#!/bin/sh
case "\$1" in
  */collector.py) printf '%s\n' "\$*" >> "$TMP/collector.calls"; exit 0 ;;
esac
exec "$REAL_PYTHON3" "\$@"
EOF
chmod +x "$STUB/curl" "$STUB/python3"
export PATH="$STUB:$PATH"

# run_hook <var>=<value>|- <hook> [stdin-json] -> stdout in $OUT, stderr in $ERR, rc in $RC
OUT=""; ERR=""; RC=0
run_hook() {
  local setting="$1" hook="$2" payload="${3:-}" errf="$TMP/err"
  if [ "$setting" = "-" ]; then
    OUT="$(printf '%s' "$payload" | bash "$hook" 2>"$errf")"; RC=$?
  else
    OUT="$(printf '%s' "$payload" | env "$setting" bash "$hook" 2>"$errf")"; RC=$?
  fi
  ERR="$(cat "$errf")"
}

# ===========================================================================
section "the manifest declares both tiers as non-sensitive booleans"
# ===========================================================================

for opt in notification_hooks contributor_hooks; do
  judge "$opt is a boolean option" boolean "$(jq -r --arg o "$opt" '.userConfig[$o].type // "missing"' "$MANIFEST")"
  judge "$opt is not sensitive" no "$(jq -r --arg o "$opt" 'if .userConfig[$o].sensitive == true then "yes" else "no" end' "$MANIFEST")"
done
judge "notification_hooks defaults to true" true "$(jq -r '.userConfig.notification_hooks.default' "$MANIFEST")"
judge "contributor_hooks defaults to false" false "$(jq -r '.userConfig.contributor_hooks.default' "$MANIFEST")"

# ===========================================================================
section "hook_tier_enabled: parsing and the manifest's own defaults"
# ===========================================================================

# tier_state <tier> [VAR=value] -> on|off, from a clean subshell that sources the lib.
tier_state() {
  local tier="$1" setting="${2:-}"
  if [ -n "$setting" ]; then
    env "$setting" bash -c 'source "$1"; hook_tier_enabled "$2" && echo on || echo off' _ "$LIB" "$tier"
  else
    bash -c 'source "$1"; hook_tier_enabled "$2" && echo on || echo off' _ "$LIB" "$tier"
  fi
}

# The library's unset-default must be the manifest's default — the one place both are held together.
m_notif="$(jq -r '.userConfig.notification_hooks.default' "$MANIFEST")"
m_contrib="$(jq -r '.userConfig.contributor_hooks.default' "$MANIFEST")"
judge "unset notification tier matches manifest default ($m_notif)" "$([ "$m_notif" = true ] && echo on || echo off)" "$(tier_state notification)"
judge "unset contributor tier matches manifest default ($m_contrib)" "$([ "$m_contrib" = true ] && echo on || echo off)" "$(tier_state contributor)"

for v in false 0 no off FALSE Off NO; do
  judge "notification: '$v' switches off" off "$(tier_state notification "CLAUDE_PLUGIN_OPTION_NOTIFICATION_HOOKS=$v")"
done
for v in true 1 yes on TRUE On YES; do
  judge "contributor: '$v' switches on" on "$(tier_state contributor "CLAUDE_PLUGIN_OPTION_CONTRIBUTOR_HOOKS=$v")"
done
judge "notification: empty value falls back to the default (on)" on "$(tier_state notification "CLAUDE_PLUGIN_OPTION_NOTIFICATION_HOOKS=")"
judge "notification: garbage falls back to the default (on)" on "$(tier_state notification "CLAUDE_PLUGIN_OPTION_NOTIFICATION_HOOKS=maybe")"
judge "contributor: garbage falls back to the default (off)" off "$(tier_state contributor "CLAUDE_PLUGIN_OPTION_CONTRIBUTOR_HOOKS=maybe")"
judge "an unknown tier name is never gated" on "$(tier_state nonsense)"
judge "the contributor variable does not leak into the notification tier" on "$(tier_state notification "CLAUDE_PLUGIN_OPTION_CONTRIBUTOR_HOOKS=false")"

# ===========================================================================
section "hook_tier_gate: the three no-op dialects"
# ===========================================================================

gate_out() { # <tier> <noop> <VAR=value> [HOOK_PLATFORM]
  env "$3" ${4:+HOOK_PLATFORM="$4"} bash -c 'source "$1"; hook_tier_gate "$2" "$3"; echo CONTINUED' _ "$LIB" "$1" "$2"
}
judge "silent: off prints nothing and exits" "" "$(gate_out notification silent CLAUDE_PLUGIN_OPTION_NOTIFICATION_HOOKS=false)"
judge "allow (claude): off prints {}" '{}' "$(gate_out contributor allow CLAUDE_PLUGIN_OPTION_CONTRIBUTOR_HOOKS=false claude)"
judge "allow (cursor): off prints the Cursor allow" '{"permission":"allow"}' "$(gate_out contributor allow CLAUDE_PLUGIN_OPTION_CONTRIBUTOR_HOOKS=false cursor)"
judge "suppress: off prints suppressOutput" '{"suppressOutput": true}' "$(gate_out notification suppress CLAUDE_PLUGIN_OPTION_NOTIFICATION_HOOKS=0)"
judge "on: the gate returns and the hook continues" CONTINUED "$(gate_out contributor allow CLAUDE_PLUGIN_OPTION_CONTRIBUTOR_HOOKS=true cursor)"
judge "gate exits 0 when off" 0 "$(env CLAUDE_PLUGIN_OPTION_NOTIFICATION_HOOKS=false bash -c 'source "$1"; hook_tier_gate notification' _ "$LIB" >/dev/null; echo $?)"

# ===========================================================================
section "notification tier: notify.sh (Notification)"
# ===========================================================================

NOTIFY_PAYLOAD='{"title":"T","message":"needs you","session_id":"s1"}'
run_hook - "$NOTIFY" "$NOTIFY_PAYLOAD"
judge "unset: notify.sh exits 0" 0 "$RC"
judge "unset: notify.sh emits its Notification JSON" Notification "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.hookEventName // "none"')"
run_hook CLAUDE_PLUGIN_OPTION_NOTIFICATION_HOOKS=true "$NOTIFY" "$NOTIFY_PAYLOAD"
judge "true: notify.sh still emits" Notification "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.hookEventName // "none"')"
run_hook CLAUDE_PLUGIN_OPTION_NOTIFICATION_HOOKS=false "$NOTIFY" "$NOTIFY_PAYLOAD"
judge "false: notify.sh exits 0" 0 "$RC"
judge "false: notify.sh prints nothing" "" "$OUT"

# ===========================================================================
section "notification tier: scripts/notify-pushover.sh (Notification)"
# ===========================================================================

pushover() { # <VAR=value or ->
  local setting="$1"
  if [ "$setting" = "-" ]; then
    env PUSHOVER_DEBUG=1 CLAUDE_PLUGIN_OPTION_PUSHOVER_TOKEN=tok CLAUDE_PLUGIN_OPTION_PUSHOVER_USER=usr \
      bash "$PUSHOVER" "hello" "default" </dev/null 2>/dev/null
  else
    env "$setting" PUSHOVER_DEBUG=1 CLAUDE_PLUGIN_OPTION_PUSHOVER_TOKEN=tok CLAUDE_PLUGIN_OPTION_PUSHOVER_USER=usr \
      bash "$PUSHOVER" "hello" "default" </dev/null 2>/dev/null
  fi
}
judge "unset: configured pushover posts" "token=tok" "$(pushover - | head -1)"
judge "true: configured pushover posts" "token=tok" "$(pushover CLAUDE_PLUGIN_OPTION_NOTIFICATION_HOOKS=true | head -1)"
judge "false: configured pushover posts nothing" "" "$(pushover CLAUDE_PLUGIN_OPTION_NOTIFICATION_HOOKS=false)"
judge "false: pushover exits 0" 0 "$(pushover CLAUDE_PLUGIN_OPTION_NOTIFICATION_HOOKS=false >/dev/null; echo $?)"

# ===========================================================================
section "notification tier: ensure-exit.sh (UserPromptSubmit)"
# ===========================================================================

exit_check() { # <VAR=value or ->  — the stub curl answers 203.0.113.7, the expected IP differs
  local setting="$1"
  if [ "$setting" = "-" ]; then
    env CLAUDE_EXIT_PROXY=http://proxy.invalid:1 CLAUDE_EXIT_PUBLIC_IP=198.51.100.1 bash "$ENSURE_EXIT" </dev/null 2>&1
  else
    env "$setting" CLAUDE_EXIT_PROXY=http://proxy.invalid:1 CLAUDE_EXIT_PUBLIC_IP=198.51.100.1 bash "$ENSURE_EXIT" </dev/null 2>&1
  fi
}
judge "unset: configured exit check warns on a mismatch" yes "$(has "$(exit_check -)" "Proxy not routing")"
judge "true: configured exit check warns on a mismatch" yes "$(has "$(exit_check CLAUDE_PLUGIN_OPTION_NOTIFICATION_HOOKS=true)" "Proxy not routing")"
judge "false: configured exit check says nothing" "" "$(exit_check CLAUDE_PLUGIN_OPTION_NOTIFICATION_HOOKS=false)"
judge "false: exit check exits 0" 0 "$(exit_check CLAUDE_PLUGIN_OPTION_NOTIFICATION_HOOKS=false >/dev/null; echo $?)"
judge "on, but CLAUDE_EXIT_* unset: still silent (the env gate survives)" "" "$(env CLAUDE_PLUGIN_OPTION_NOTIFICATION_HOOKS=true bash "$ENSURE_EXIT" </dev/null 2>&1)"

# ===========================================================================
section "notification tier: usage-capture-ensure.sh (SessionStart)"
# ===========================================================================

usage_ensure() { # <VAR=value or -> -> collector invocations recorded
  rm -f "$TMP/collector.calls"
  local setting="$1"
  if [ "$setting" = "-" ]; then
    env TAMIRS_USAGE_CAPTURE=1 TAMIRS_USAGE_CAPTURE_DIR="$TMP/usage" bash "$USAGE_ENSURE" </dev/null >"$TMP/u.out" 2>/dev/null
  else
    env "$setting" TAMIRS_USAGE_CAPTURE=1 TAMIRS_USAGE_CAPTURE_DIR="$TMP/usage" bash "$USAGE_ENSURE" </dev/null >"$TMP/u.out" 2>/dev/null
  fi
  RC=$?
  if [ -s "$TMP/collector.calls" ]; then echo started; else echo not-started; fi
}
judge "unset: opted-in collector is started" started "$(usage_ensure -)"
judge "true: opted-in collector is started" started "$(usage_ensure CLAUDE_PLUGIN_OPTION_NOTIFICATION_HOOKS=true)"
judge "false: opted-in collector is NOT started" not-started "$(usage_ensure CLAUDE_PLUGIN_OPTION_NOTIFICATION_HOOKS=false)"
usage_ensure CLAUDE_PLUGIN_OPTION_NOTIFICATION_HOOKS=false >/dev/null
judge "false: usage-capture-ensure exits 0" 0 "$RC"
judge "false: usage-capture-ensure prints nothing (SessionStart parses stdout)" "" "$(cat "$TMP/u.out")"
rm -f "$TMP/collector.calls"
env CLAUDE_PLUGIN_OPTION_NOTIFICATION_HOOKS=true bash "$USAGE_ENSURE" </dev/null >/dev/null 2>&1
judge "on, but TAMIRS_USAGE_CAPTURE unset: nothing starts (the env gate survives)" not-started "$([ -s "$TMP/collector.calls" ] && echo started || echo not-started)"

# ===========================================================================
section "contributor tier: plugin-reload-reminder.sh (PostToolUse)"
# ===========================================================================

RELOAD_PAYLOAD="$(jq -n --arg p "$TMP/.claude-plugin/plugin.json" '{tool_name:"Edit", tool_input:{file_path:$p}}')"
run_hook CLAUDE_PLUGIN_OPTION_CONTRIBUTOR_HOOKS=true "$RELOAD" "$RELOAD_PAYLOAD"
judge "true: a plugin.json edit gets the reload reminder" yes "$(has "$ERR" "/reload-plugins")"
judge "true: exits 0" 0 "$RC"
run_hook - "$RELOAD" "$RELOAD_PAYLOAD"
judge "unset (default off): no reminder" "" "$ERR$OUT"
judge "unset: exits 0" 0 "$RC"
run_hook CLAUDE_PLUGIN_OPTION_CONTRIBUTOR_HOOKS=false "$RELOAD" "$RELOAD_PAYLOAD"
judge "false: no reminder, nothing on stdout" "" "$ERR$OUT"
judge "false: exits 0" 0 "$RC"

# ===========================================================================
section "contributor tier: validate-report-links.sh (PostToolUse)"
# ===========================================================================

mkdir -p "$TMP/reports"
printf '# r\n\nSee https://example.com/placeholder-link for details.\n' > "$TMP/reports/report.md"
LINKS_PAYLOAD="$(jq -n --arg p "$TMP/reports/report.md" '{tool_name:"Write", tool_input:{file_path:$p}}')"
run_hook CLAUDE_PLUGIN_OPTION_CONTRIBUTOR_HOOKS=true "$LINKS" "$LINKS_PAYLOAD"
judge "true: a placeholder URL in report.md is blocked" block "$(printf '%s' "$OUT" | jq -r '.decision // "none"')"
run_hook - "$LINKS" "$LINKS_PAYLOAD"
judge "unset (default off): report.md is not checked" "" "$OUT"
judge "unset: exits 0" 0 "$RC"
run_hook CLAUDE_PLUGIN_OPTION_CONTRIBUTOR_HOOKS=false "$LINKS" "$LINKS_PAYLOAD"
judge "false: nothing on stdout" "" "$OUT"
judge "false: exits 0" 0 "$RC"

# ===========================================================================
section "contributor tier: skill-creator-guard.sh (PreToolUse, Claude Code dialect)"
# ===========================================================================

SKILL_PAYLOAD="$(jq -n --arg p "$TMP/skills/foo/SKILL.md" '{tool_name:"Write", tool_input:{file_path:$p}}')"
run_hook CLAUDE_PLUGIN_OPTION_CONTRIBUTOR_HOOKS=true "$SKILL_GUARD" "$SKILL_PAYLOAD"
judge "true: a SKILL.md write gets the quality-gate reminder" yes "$(has "$(printf '%s' "$OUT" | jq -r '.hookSpecificOutput.additionalContext // ""')" "SKILL QUALITY GATE")"
run_hook - "$SKILL_GUARD" "$SKILL_PAYLOAD"
judge "unset (default off): the Claude allow, never empty stdout" '{}' "$OUT"
judge "unset: exits 0" 0 "$RC"
run_hook CLAUDE_PLUGIN_OPTION_CONTRIBUTOR_HOOKS=false "$SKILL_GUARD" "$SKILL_PAYLOAD"
judge "false: the Claude allow" '{}' "$OUT"
judge "false: no reminder" no "$(has "$OUT" "SKILL QUALITY GATE")"
judge "false: exits 0" 0 "$RC"

# ===========================================================================
section "contributor tier: skill-creator-guard.sh under Cursor must ALLOW, not go silent"
# ===========================================================================

# Cursor fail-closes on empty stdout: a gated-off guard that printed nothing
# would deny every SKILL.md write on Cursor while looking "off".
CURSOR_PAYLOAD="$(jq -n --arg p "$TMP/skills/foo/SKILL.md" '{conversation_id:"c1", cursor_version:"2026.07", tool_name:"Write", tool_input:{file_path:$p}}')"
run_hook CLAUDE_PLUGIN_OPTION_CONTRIBUTOR_HOOKS=false "$SKILL_GUARD" "$CURSOR_PAYLOAD"
judge "false (cursor): prints the Cursor allow" allow "$(printf '%s' "$OUT" | jq -r '.permission // "none"')"
judge "false (cursor): exits 0" 0 "$RC"
run_hook - "$SKILL_GUARD" "$CURSOR_PAYLOAD"
judge "unset (cursor, default off): prints the Cursor allow" allow "$(printf '%s' "$OUT" | jq -r '.permission // "none"')"
run_hook CLAUDE_PLUGIN_OPTION_CONTRIBUTOR_HOOKS=true "$SKILL_GUARD" "$CURSOR_PAYLOAD"
judge "true (cursor): the reminder rides on agent_message with allow" yes "$(has "$(printf '%s' "$OUT" | jq -r '.agent_message // ""')" "SKILL QUALITY GATE")"
judge "true (cursor): still an allow" allow "$(printf '%s' "$OUT" | jq -r '.permission // "none"')"

# ===========================================================================
section "the gate sits where it belongs: every gated hook names its tier, nothing else does"
# ===========================================================================

for h in "$NOTIFY" "$PUSHOVER" "$ENSURE_EXIT" "$USAGE_ENSURE"; do
  judge "$(basename "$h") gates on the notification tier" yes "$(grep -q '^hook_tier_gate notification' "$h" && echo yes || echo no)"
done
for h in "$RELOAD" "$LINKS"; do
  judge "$(basename "$h") gates on the contributor tier" yes "$(grep -q '^hook_tier_gate contributor$' "$h" && echo yes || echo no)"
done
judge "skill-creator-guard.sh gates with the allow no-op" yes "$(grep -q '^hook_tier_gate contributor allow$' "$SKILL_GUARD" && echo yes || echo no)"
# Core-safety, worktree-lifecycle and user-facing convenience hooks are never gated.
ungated="$(grep -l 'hook_tier_gate' "$ROOT"/hooks/*.sh "$ROOT"/scripts/*.sh 2>/dev/null | xargs -n1 basename | sort | tr '\n' ' ')"
judge "exactly the seven hooks call the gate" "ensure-exit.sh notify-pushover.sh notify.sh plugin-reload-reminder.sh skill-creator-guard.sh usage-capture-ensure.sh validate-report-links.sh " "$ungated"

harness_summary
