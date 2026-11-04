#!/usr/bin/env bash
# test-mcp-gates.sh — mcp-builder's permission gate (skills/mcp/mcp-builder/
# scripts/gate.sh) maps the resolver's verdict onto proceed / ask / blocked,
# and fails closed (ADR 004 L1, D4; permissions-gates task-004).
#
# WHAT IS HELD
#   allow => exit 0 (proceed); ask => exit 10, naming the action and the exact
#   target for the user's chat yes; ask --headless (or CI=true) => the resolver
#   is told --headless and its deny stops the step; deny => exit 3 naming the
#   setting that would allow it; resolver missing / non-zero / not JSON / no
#   verdict => exit 3. There is no flag that skips an ask. The SKILL.md gates
#   Phase 2's installs, Phase 4's inspector and Phase 6's out-of-project config
#   writes through this script.
#
# HOW
#   A COPY of gate.sh inside a temp plugin tree whose scripts/resolve-permission.sh
#   is a stub (tests/test-merge-policy.sh Part A): the gate finds the resolver
#   from its own location, never from the environment.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$ROOT/tests/lib/harness.sh"

harness_require jq

TMP="$(harness_tmpdir)"
REAL_GATE="$ROOT/skills/mcp/mcp-builder/scripts/gate.sh"
SKILL="$ROOT/skills/mcp/mcp-builder/SKILL.md"

PLUG="$TMP/plugin"
mkdir -p "$PLUG/skills/mcp/mcp-builder/scripts" "$PLUG/scripts"
cp "$REAL_GATE" "$PLUG/skills/mcp/mcp-builder/scripts/gate.sh"
GATE="$PLUG/skills/mcp/mcp-builder/scripts/gate.sh"
RES="$PLUG/scripts/resolve-permission.sh"
STUB_LOG="$TMP/stub.log"
export STUB_LOG

# The stub records its argv and answers per STUB_MODE: allow | ask | deny
# (exit 0; with --headless an ask becomes deny, as the real resolver does),
# exit3, allow-exit1, garbage, noverdict.
cat > "$RES" <<'STUB'
#!/usr/bin/env bash
printf 'ARGV %s\n' "$*" >> "$STUB_LOG"
mode="${STUB_MODE:-ask}"
case "$mode" in
  garbage)     printf 'not json\n'; exit 0 ;;
  noverdict)   printf '{}\n'; exit 0 ;;
  exit3)       printf '{"verdict":"deny","reason":"internal"}\n'; exit 3 ;;
  allow-exit1) printf '{"verdict":"allow"}\n'; exit 1 ;;
esac
case " $* " in *" --headless "*) [ "$mode" = ask ] && mode=deny ;; esac
printf '{"action":"x","r":4,"verdict":"%s","reason":"stub %s","setting_that_would_allow":{"once":null,"durable":["/plugin-config pkg.install.network allow"],"note":"stub note"}}\n' "$mode" "$mode"
STUB
chmod +x "$RES"

# gate <mode> <args...> — "<exit>|<stdout>" of the copy with the stub answering <mode>.
gate() {
  local mode="$1"; shift
  : > "$STUB_LOG"
  local out rc
  out="$(env -u CI STUB_MODE="$mode" bash "$GATE" "$@" 2>/dev/null)"; rc=$?
  printf '%s|%s' "$rc" "$out"
}
rc_of()  { printf '%s' "${1%%|*}"; }
out_of() { printf '%s' "${1#*|}"; }
argv()   { sed -n 's/^ARGV //p' "$STUB_LOG"; }

CFG='/Users/you/Library/Application Support/Claude/claude_desktop_config.json'
INSTALL='npm install --ignore-scripts @modelcontextprotocol/sdk zod'

# =============================================================================
section "verdict => what the skill does"
# =============================================================================
res="$(gate allow config.global.write "$CFG")"
judge "allow => exit 0 (proceed)" 0 "$(rc_of "$res")"
judge "  ... the resolver is asked for the action, as mcp-builder, on the exact target" yes \
  "$(has "$(argv)" "config.global.write --skill mcp-builder --target $CFG --json")"

res="$(gate ask pkg.install.network "$INSTALL")"
judge "ask => exit 10 (get an explicit yes in chat)" 10 "$(rc_of "$res")"
judge "  ... the line names the action" yes "$(has "$(out_of "$res")" "pkg.install.network")"
judge "  ... and the exact command the user approves" yes "$(has "$(out_of "$res")" "$INSTALL")"
judge "  ... and says only an explicit yes proceeds" yes "$(has "$(out_of "$res")" 'explicit "yes"')"

res="$(gate ask config.global.write "$CFG" --headless)"
judge "ask --headless => blocked (exit 3)" 3 "$(rc_of "$res")"
judge "  ... the resolver was told --headless" yes "$(has "$(argv)" "--headless")"

: > "$STUB_LOG"
out="$(STUB_MODE=ask CI=true bash "$GATE" pkg.exec.network 'npx @modelcontextprotocol/inspector@2.12.0 dist/index.js' 2>/dev/null)"; rc=$?
judge "CI=true is headless: ask => blocked" 3 "$rc"
judge "  ... with --headless passed on" yes "$(has "$(argv)" "--headless")"

res="$(gate deny config.global.write "$CFG")"
judge "deny => blocked (exit 3)" 3 "$(rc_of "$res")"
judge "  ... naming the reason" yes "$(has "$(out_of "$res")" "stub deny")"
judge "  ... and the setting that would allow it" yes "$(has "$(out_of "$res")" "allow with: durable: /plugin-config pkg.install.network allow stub note")"

for mode in exit3 allow-exit1 garbage noverdict; do
  res="$(gate "$mode" pkg.install.network "$INSTALL")"
  judge "resolver '$mode' => blocked (fail closed)" 3 "$(rc_of "$res")"
done

mv "$RES" "$RES.off"
res="$(gate allow pkg.install.network "$INSTALL")"
judge "resolver missing => blocked (fail closed)" 3 "$(rc_of "$res")"
judge "  ... and says why" yes "$(has "$(out_of "$res")" "missing")"
mv "$RES.off" "$RES"

res="$(gate allow pkg.install.network "$INSTALL" --yes)"
judge "there is no --yes: an unknown flag is a usage error, never a pass" 2 "$(rc_of "$res")"
judge "  ... and the resolver is not even asked" "" "$(argv)"
res="$(gate allow pkg.install.network)"
judge "a missing target is a usage error" 2 "$(rc_of "$res")"

res="$(gate allow pkg.install.network "$INSTALL" --cond pinned_lockfile=true --host claude)"
judge "--cond and --host reach the resolver" yes "$(has "$(argv)" "--cond pinned_lockfile=true --host claude")"

# =============================================================================
section "the in-tree gate, and the SKILL.md steps that call it"
# =============================================================================
out="$(env -u CI bash "$REAL_GATE" config.global.write "$CFG" --headless 2>/dev/null)"; rc=$?
judge "real resolver: a headless out-of-project config write is blocked (R4 never automatic)" 3 "$rc"

body="$(cat "$SKILL")"
judge "SKILL.md gates the out-of-project config write" yes "$(has "$body" "gate.sh config.global.write")"
judge "SKILL.md gates package installs" yes "$(has "$body" "gate.sh pkg.install.network")"
judge "SKILL.md gates the inspector run" yes "$(has "$(printf '%s' "$body" | tr '\n' ' ')" "gate.sh pkg.exec.network")"
judge "SKILL.md installs with lifecycle scripts off" yes "$(has "$body" "npm install --ignore-scripts")"
judge "SKILL.md no longer says 'detect them ... or ask' for Phase 6" no "$(has "$body" "detect them the way")"

harness_summary
