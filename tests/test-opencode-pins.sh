#!/usr/bin/env bash
# test-opencode-pins.sh — OpenCode 2.2.x version pins and v2-only config shape.
#
# WHAT THIS PINS
#   The v1 -> v2 cutover left four things that drift silently and that no other
#   test reads: the version the repo claims to support (platform-targets.json vs
#   the README badge), the plugin's peer-dependency floors, the guard's action
#   vocabulary, and the top-level key set of opencode.json.
#
#   OPENCODE_PINS_ROOT overrides the tree under test (default: this repo) so a
#   mutation can be run against a temp copy without touching tracked files.
#
# Hermetic: no network; the live smoke skips when no OpenCode 2 binary exists and
# never starts or touches a background service (it uses --standalone and a fresh HOME).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$HERE/tests/lib/harness.sh"
harness_require jq
ROOT="${OPENCODE_PINS_ROOT:-$HERE}"

TARGETS="$ROOT/docs/engineering/build-and-release/platform-targets.json"
README="$ROOT/README.md"
PKG="$ROOT/platforms/opencode/plugin/package.json"
GUARD="$ROOT/platforms/opencode/plugin/guard.ts"
CONFIG="$ROOT/opencode.json"

# semver_ge <a> <b> — true when a >= b (plain x.y.z, no prerelease).
semver_ge() { [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -1)" = "$2" ]; }
# floor <range> — the version in a `>=x.y.z` / `~x.y.z` / `^x.y.z` / `x.y.z` range.
floor() { printf '%s' "$1" | sed -E 's/^[^0-9]*//'; }

section "platform-targets.json: one coherent OpenCode version"
min="$(jq -r '.targets.opencode.supported_min // ""' "$TARGETS")"
val="$(jq -r '.targets.opencode.validated_against // ""' "$TARGETS")"
rev="$(jq -r '.targets.opencode.reviewed_through // ""' "$TARGETS")"
lat="$(jq -r '.targets.opencode.latest_known // ""' "$TARGETS")"
re='^[0-9]+\.[0-9]+\.[0-9]+$'
for v in "$min" "$val" "$rev" "$lat"; do
  [[ "$v" =~ $re ]] || { bad "opencode version fields are plain x.y.z" "got '$v'"; break; }
done
judge "validated_against == reviewed_through == latest_known" "$val $val" "$rev $lat"
judge "validated_against >= supported_min" yes \
  "$(if semver_ge "$val" "$min"; then echo yes; else echo no; fi)"
judge "supported_min is an OpenCode 2 release" 2 "${min%%.*}"

section "README OpenCode badge shows the same version"
badge="$(sed -n 's|.*img.shields.io/badge/OpenCode-\([0-9][0-9.]*\)-.*|\1|p' "$README" | head -1)"
judge "README OpenCode badge == validated_against" "$val" "$badge"

section "plugin package.json: peer floors"
oc="$(floor "$(jq -r '.peerDependencies["@opencode/plugin"] // ""' "$PKG")")"
core="$(floor "$(jq -r '.peerDependencies["@opentui/core"] // ""' "$PKG")")"
solid="$(floor "$(jq -r '.peerDependencies["@opentui/solid"] // ""' "$PKG")")"
judge "@opencode/plugin peer floor >= 2.2.5" yes "$(if [ -n "$oc" ] && semver_ge "$oc" 2.2.5; then echo yes; else echo no; fi)"
judge "@opentui/core peer floor >= 0.8.0" yes "$(if [ -n "$core" ] && semver_ge "$core" 0.8.0; then echo yes; else echo no; fi)"
judge "@opentui/solid peer floor >= 0.8.0" yes "$(if [ -n "$solid" ] && semver_ge "$solid" 0.8.0; then echo yes; else echo no; fi)"

section "guard.ts keys its permission hook on the v2 action names"
# 2.2.5 aliases the old `bash` action to `shell`; the guard must match the
# canonical names so the alias is never what makes it fire.
judge "guard checks e.action === \"shell\"" yes \
  "$(if grep -qF 'e.action === "shell"' "$GUARD"; then echo yes; else echo no; fi)"
judge "guard checks e.action === \"edit\"" yes \
  "$(if grep -qF 'e.action === "edit"' "$GUARD"; then echo yes; else echo no; fi)"
judge "guard has no bash-named action branch" "" \
  "$(grep -nE 'action[[:space:]]*(===|==|!==|!=)[[:space:]]*["'"'"']bash["'"'"']|case[[:space:]]+["'"'"']bash["'"'"']' "$GUARD" | tr '\n' ' ')"

section "opencode.json: v2-only keys"
judge "opencode.json is valid JSON" 0 "$(jq empty "$CONFIG" >/dev/null 2>&1; echo $?)"
judge "top-level keys are a subset of the v2 set" "" \
  "$(jq -r 'keys[] | select(. as $k | ["$schema","skills","plugins","mcp","permissions","model","small_model","default_agent","instructions","username","share","autoupdate","snapshot","provider","providers","formatter","lsp","compaction","watcher","experimental","theme","keybinds","logLevel"] | index($k) | not)' "$CONFIG" | tr '\n' ' ')"
judge "mcp.servers is present" object "$(jq -r '.mcp.servers | type' "$CONFIG" 2>/dev/null)"
judge "permissions is an array" array "$(jq -r '.permissions | type' "$CONFIG" 2>/dev/null)"
judge "every permission is {action,resource,effect} with a v2 effect" "" \
  "$(jq -r '.permissions | to_entries[] | select((.value | keys | sort) != ["action","effect","resource"] or (.value.effect | IN("allow","deny","ask") | not)) | .key' "$CONFIG" 2>/dev/null | tr '\n' ' ')"
judge "no v1 plugin/permission/agent/mode/tools key" "" \
  "$(jq -r 'keys[] | select(IN("plugin","permission","agent","mode","tools"))' "$CONFIG" | tr '\n' ' ')"

section "live smoke: debug agents lists the generated adapters (optional)"
bin=""
for c in "$HOME/.opencode/bin/opencode" "$(command -v opencode 2>/dev/null)"; do
  if [ -n "$c" ] && [ -x "$c" ]; then bin="$c"; break; fi
done
ver=""
[ -n "$bin" ] && ver="$("$bin" --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
if [ -z "$bin" ]; then
  skip "live opencode debug agents" "no opencode binary"
elif [ "${ver%%.*}" != "2" ]; then
  skip "live opencode debug agents" "opencode '$ver' is not 2.x"
else
  tmp="$(harness_tmpdir)"
  mkdir -p "$tmp/home" "$tmp/cfg" "$tmp/data" "$tmp/state" "$tmp/cache"
  n_src="$(find "$ROOT/agents" -maxdepth 1 -name '*.md' | wc -l | tr -d ' ')"
  out="$(cd "$ROOT" && HOME="$tmp/home" XDG_CONFIG_HOME="$tmp/cfg" XDG_DATA_HOME="$tmp/data" \
    XDG_STATE_HOME="$tmp/state" XDG_CACHE_HOME="$tmp/cache" "$bin" --standalone debug agents 2>/dev/null)"
  judge "opencode $ver --standalone debug agents lists every generated adapter ($n_src)" "$n_src" \
    "$(printf '%s' "$out" | jq '[.[] | select(.system // "" | contains("GENERATED FILE"))] | length' 2>/dev/null)"
fi

harness_summary
