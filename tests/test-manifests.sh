#!/usr/bin/env bash
# The one-source manifests: every per-host manifest and the Codex hooks file are in
# step with their sources, each generated file obeys its host's rules, and a planted
# drift or a planted rule violation makes the generator say so.
#
# WHY THE NEGATIVE PROBES
#   scripts/build-manifests.sh and scripts/build-codex-hooks.sh exist because the
#   hand-kept copies drifted silently: Codex got a hooks file with a key its parser
#   rejects, Cursor an MCP file with a placeholder its validator rejects. A --check that
#   passed on a drifted tree, or a generator that accepted an undeclared variable, would
#   reintroduce exactly that. Each probe plants one such shape into a copy of the tree
#   and asserts the check or the build names it. Probes are shell functions, not strings,
#   so nothing here is passed through eval.

# shellcheck disable=SC2015,SC2016  # `test && ok || bad` is the intended shape; the python one-liners are literal
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BM="$ROOT/scripts/build-manifests.sh"
BC="$ROOT/scripts/build-codex-hooks.sh"
PASS=0; FAIL=0; FAILED=()
ok(){ PASS=$((PASS+1)); echo "  ok   $1"; }
bad(){ FAIL=$((FAIL+1)); FAILED+=("$1"); echo "  FAIL $1 — $2"; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
for tool in jq python3; do
  command -v "$tool" >/dev/null 2>&1 || { echo "FATAL: $tool required"; exit 1; }
done

CODEX_EVENTS="SessionStart SessionEnd SubagentStart UserPromptSubmit PreToolUse PermissionRequest PostToolUse PreCompact PostCompact SubagentStop Stop Interrupt"
DROPPED_EVENTS="Notification DirectoryAdded WorktreeCreate WorktreeRemove StopFailure"

echo "--- the tree is in step with its sources ---"
[ -x "$BM" ] && ok "build-manifests.sh is executable" || bad "build-manifests.sh is executable" "chmod +x it"
[ -x "$BC" ] && ok "build-codex-hooks.sh is executable" || bad "build-codex-hooks.sh is executable" "chmod +x it"
if bash "$BM" "$ROOT" --check >"$T/bm.log" 2>&1; then ok "build-manifests.sh --check passes"; else bad "build-manifests.sh --check passes" "$(grep -E 'DRIFT|error' "$T/bm.log" | head -2 | tr '\n' ' ')"; fi
if bash "$BC" "$ROOT" --check >"$T/bc.log" 2>&1; then ok "build-codex-hooks.sh --check passes"; else bad "build-codex-hooks.sh --check passes" "$(grep -E 'DRIFT|error' "$T/bc.log" | head -2 | tr '\n' ' ')"; fi
grep -q -- '--help' "$BM" && bash "$BM" --help >/dev/null 2>&1 && ok "build-manifests.sh --help exits 0" || bad "build-manifests.sh --help" "non-zero"
bash "$BC" --help >/dev/null 2>&1 && ok "build-codex-hooks.sh --help exits 0" || bad "build-codex-hooks.sh --help" "non-zero"
bash "$BM" --bogus >/dev/null 2>&1 && bad "build-manifests.sh rejects an unknown flag" "exit 0" || ok "build-manifests.sh rejects an unknown flag"
for s in "$BM" "$BC"; do
  grep -qE '^\s*eval\b|[;&|]\s*eval\b' "$s" && bad "$(basename "$s") uses no eval" "found" || ok "$(basename "$s") uses no eval"
done

echo "--- the root Agent Plugins manifest ---"
P="$ROOT/platforms/agent-plugins/plugin.json"
if jq empty "$P" 2>/dev/null; then ok "plugin.json parses"; else bad "plugin.json parses" "invalid JSON"; fi
[ "$(jq -r '."$schema" // empty' "$P")" = "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json" ] && ok "plugin.json carries the 1.0.0 \$schema" || bad "plugin.json \$schema" "$(jq -r '."$schema"' "$P")"
[ "$(jq -r '.name // empty' "$P")" = "$(jq -r .name "$ROOT/.claude-plugin/plugin.json")" ] && ok "plugin.json name matches the Claude manifest" || bad "plugin.json name" "$(jq -r .name "$P")"
[ "$(jq -r '.version // empty' "$P")" = "$(jq -r .version "$ROOT/plugin-version.json")" ] && ok "plugin.json version is the canonical version" || bad "plugin.json version" "$(jq -r .version "$P")"
unknown="$(jq -r 'keys[] | select(. as $k | ["$schema","name","version","description","homepage","repository","author","license","keywords","extensions"] | index($k) | not)' "$P")"
[ -z "$unknown" ] && ok "plugin.json has no top-level key outside the spec (a client reports and ignores one)" || bad "plugin.json has a top-level key outside the spec" "$unknown"
jq -e '.author | keys - ["name","email","url"] | length == 0' "$P" >/dev/null 2>&1 && ok "plugin.json author has only name/email/url (Codex rejects anything else)" || bad "plugin.json author fields" "$(jq -c .author "$P")"
jq -e 'any(.keywords[]; . == "claude-code") | not' "$P" >/dev/null 2>&1 && ok "plugin.json keywords name no other host" || bad "plugin.json keywords" "claude-code is a Claude-only keyword"
# The Codex extension is emitted only when the overlay's emit_codex_extension switch is
# on; off (the 5.0.0 default, until a live Codex run proves the root-manifest route finds
# the nested skills) the root manifest carries no extensions key at all, and Codex falls
# back to .codex-plugin/plugin.json. Both states are asserted; the switch itself is read.
EMIT="$(jq -r '.agent_plugins.emit_codex_extension' "$ROOT/platforms/manifests.source.json")"
if [ "$EMIT" = "true" ]; then
  ext_hooks="$(jq -r '.extensions["com.openai"].hooks // empty' "$P")"
  [ "$ext_hooks" = "./platforms/codex/hooks.json" ] && ok "extensions.com.openai.hooks -> ./platforms/codex/hooks.json" || bad "extensions.com.openai.hooks" "$ext_hooks"
  jq -e '.extensions["com.openai"].interface.displayName' "$P" >/dev/null 2>&1 && ok "extensions.com.openai.interface is populated" || bad "extensions.com.openai.interface" "missing"
  jq -e '.extensions["com.openai"] | has("skills") or has("mcpServers") | not' "$P" >/dev/null 2>&1 && ok "extensions.com.openai carries no skills/mcpServers (undocumented there; Codex reads ./skills and ./mcp.json)" || bad "extensions.com.openai carries an undocumented key" "skills or mcpServers"
else
  jq -e 'has("extensions") | not' "$P" >/dev/null 2>&1 && ok "emit_codex_extension is off: the root manifest carries no extensions key, so Codex reads .codex-plugin/plugin.json" || bad "emit_codex_extension is off but the root manifest carries extensions" "$(jq -c .extensions "$P")"
  jq -e '.agent_plugins.emit_codex_extension_note | length > 0' "$ROOT/platforms/manifests.source.json" >/dev/null 2>&1 && ok "the overlay says why the switch is off" || bad "the overlay's emit_codex_extension_note is missing" ""
fi
grep -q '"$schema"' "$ROOT/platforms/agent-plugins/plugin.json" && ! grep -q '"$schema"' "$ROOT/.claude-plugin/plugin.json" && ok "the Claude manifest still carries no \$schema (the directory holds one)" || bad "the Claude manifest carries a \$schema" "check-claude-dist rejects it"

echo "--- the Codex overlay (pre-0.147 fallback) ---"
C="$ROOT/.codex-plugin/plugin.json"
[ "$(jq -r '.hooks // empty' "$C")" = "./platforms/codex/hooks.json" ] && ok ".codex-plugin/plugin.json hooks -> ./platforms/codex/hooks.json" || bad ".codex-plugin/plugin.json hooks" "$(jq -r .hooks "$C")"
if [ "$EMIT" = "true" ]; then
  [ "$(jq -c '.interface' "$C")" = "$(jq -c '.extensions["com.openai"].interface' "$P")" ] && ok "overlay interface equals the root extension's (Codex reads one or the other, never both)" || bad "overlay interface differs from the root extension" ""
else
  [ "$(jq -c '.interface' "$C")" = "$(jq -c '.codex.manifest.interface' "$ROOT/platforms/manifests.source.json")" ] && ok "overlay interface equals the source overlay's" || bad "overlay interface differs from the source" ""
fi
[ "$(jq -c '.skills' "$C")" = "$(jq -c '.skills' "$ROOT/.claude-plugin/plugin.json")" ] && ok "overlay skills list is the canonical one" || bad "overlay skills list" "differs from the Claude manifest"

echo "--- the root MCP file ---"
M="$ROOT/platforms/agent-plugins/mcp.json"
if jq empty "$M" 2>/dev/null; then ok "mcp.json parses"; else bad "mcp.json parses" "invalid JSON"; fi
[ "$(jq -r '."$schema" // empty' "$M")" = "https://agent-plugins.org/schemas/1.0.0/mcp.schema.json" ] && ok "mcp.json carries the 1.0.0 mcp \$schema" || bad "mcp.json \$schema" "$(jq -r '."$schema"' "$M")"
unknown="$(jq -r 'keys[] | select(. != "$schema" and . != "mcpServers")' "$M")"
[ -z "$unknown" ] && ok "mcp.json has no top-level key outside the spec (one disables MCP for the plugin)" || bad "mcp.json top-level key outside the spec" "$unknown"
[ "$(jq -r '.mcpServers.github.type // empty' "$M")" = "stdio" ] && ok "mcp.json github server is stdio" || bad "mcp.json github server type" "$(jq -r '.mcpServers.github.type' "$M")"
cmd="$(jq -r '.mcpServers.github.command // empty' "$M")"
case "$cmd" in
  ./*) [ -x "$ROOT/${cmd#./}" ] && ok "mcp.json command $cmd is an executable in the tree (resolved from the distribution root, where the file is placed)" || bad "mcp.json command" "$cmd is not executable" ;;
  *) bad "mcp.json command is a ./-relative single token" "$cmd" ;;
esac
bad_ph="$(jq -r '.mcpServers[] | [.args[]?, (.env // {} | .[]), (.cwd // "")] | .[]' "$M" | grep -oE '\$\{[^}]*\}' | grep -vE '^\$\{(PLUGIN_ROOT|PLUGIN_DATA)\}$' || true)"
[ -z "$bad_ph" ] && ok "mcp.json uses only the two placeholders the spec expands" || bad "mcp.json uses a placeholder the spec leaves literal" "$bad_ph"
jq -e '.mcpServers.github | has("env") | not' "$M" >/dev/null 2>&1 && ok "mcp.json passes no credential env (the spec defines no credential mechanism; a literal would be presented as the token)" || bad "mcp.json carries an env block" "$(jq -c '.mcpServers.github.env' "$M")"

echo "--- the Cursor manifest and MCP file ---"
CU="$ROOT/.cursor-plugin/plugin.json"; CM="$ROOT/platforms/cursor/mcp.json"
if jq empty "$CM" 2>/dev/null; then ok "platforms/cursor/mcp.json parses"; else bad "platforms/cursor/mcp.json parses" "invalid JSON"; fi
[ "$(jq -r '.mcpServers // empty' "$CU")" = "./platforms/cursor/mcp.json" ] && ok ".cursor-plugin/plugin.json mcpServers -> ./platforms/cursor/mcp.json" || bad ".cursor-plugin/plugin.json mcpServers" "$(jq -r .mcpServers "$CU")"
used="$(grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*\}' "$CM" | tr -d '${}' | grep -vE '^(CURSOR_PLUGIN_ROOT|CLAUDE_PLUGIN_ROOT)$' | sort -u)"
[ -n "$used" ] && ok "the Cursor MCP file uses at least one plugin variable ($(echo "$used" | tr '\n' ' '))" || bad "the Cursor MCP file uses a plugin variable" "none found"
undeclared=""
for v in $used; do jq -e --arg v "$v" '.variables.properties[$v]' "$CU" >/dev/null 2>&1 || undeclared="$undeclared $v"; done
[ -z "$undeclared" ] && ok "every \${VAR} in the Cursor MCP file is declared under variables.properties" || bad "undeclared Cursor plugin variable" "$undeclared"
for v in $used; do
  jq -e --arg v "$v" '.variables.properties[$v] | (.title | length > 0) and (.description | length > 0) and (has("default") | not)' "$CU" >/dev/null 2>&1 \
    && ok "variable $v has a title and description and no default" || bad "variable $v shape" "needs title + description, no default"
done
grep -q 'CURSOR_PLUGIN_ROOT' "$CM" && ok "the Cursor MCP file uses \${CURSOR_PLUGIN_ROOT} (Cursor does not expand \${PLUGIN_ROOT})" || bad "Cursor MCP file root placeholder" "not CURSOR_PLUGIN_ROOT"
literal="$(jq -r '.. | strings | select(test("^(ghp_|github_pat_|sk-|AKIA)"))' "$CM" "$M" 2>/dev/null || true)"
[ -z "$literal" ] && ok "no generated MCP file carries a literal credential" || bad "a generated MCP file carries a literal credential" "$literal"

echo "--- the Codex hooks file ---"
H="$ROOT/platforms/codex/hooks.json"
if jq empty "$H" 2>/dev/null; then ok "platforms/codex/hooks.json parses"; else bad "platforms/codex/hooks.json parses" "invalid JSON"; fi
jq -e 'has("modules") | not' "$H" >/dev/null 2>&1 && ok "no modules key (Codex's parser rejects it)" || bad "modules key present" "Codex rejects the file"
unknown="$(jq -r 'keys[] | select(. != "description" and . != "hooks")' "$H")"
[ -z "$unknown" ] && ok "only description and hooks at the top level" || bad "top-level key Codex rejects" "$unknown"
jq -e '.description | type == "string" and length > 0 and test("generated|Generated")' "$H" >/dev/null 2>&1 && ok "description says the file is generated" || bad "description" "missing or does not say generated"
[ "$(jq '[.hooks[][].hooks[] | select(has("onFailure"))] | length' "$H")" = "0" ] && ok "no hook entry carries onFailure" || bad "onFailure present" "Codex has no such field"
for ev in $(jq -r '.hooks | keys[]' "$H"); do
  case " $CODEX_EVENTS " in *" $ev "*) ok "event $ev is one Codex supports" ;; *) bad "event $ev" "Codex has no such event" ;; esac
done
for ev in $DROPPED_EVENTS; do
  jq -e --arg e "$ev" '.hooks | has($e) | not' "$H" >/dev/null 2>&1 && ok "dropped event $ev is absent" || bad "dropped event $ev present" ""
done
# What Codex supports and the canonical file wires must all be present: dropping a
# supported event would be a silent loss, adding one a hook with no handler.
expected="$(jq -r '.hooks | keys[]' "$ROOT/hooks/hooks.json" | while read -r e; do case " $CODEX_EVENTS " in *" $e "*) echo "$e";; esac; done | sort)"
actual="$(jq -r '.hooks | keys[]' "$H" | sort)"
[ "$expected" = "$actual" ] && ok "the kept events are exactly the Codex-supported events hooks/hooks.json wires" || bad "kept events differ from the canonical supported set" "expected [$(echo "$expected" | tr '\n' ' ')] got [$(echo "$actual" | tr '\n' ' ')]"
missing=""
while IFS= read -r script; do [ -f "$ROOT/$script" ] || missing="$missing $script"; done < <(jq -r '.hooks[][].hooks[].command' "$H" | sed -nE 's/.*\$\{CLAUDE_PLUGIN_ROOT\}"?\/([^ "]+).*/\1/p')
[ -z "$missing" ] && ok "every command's script exists" || bad "a command names a missing script" "$missing"
[ "$(jq '[.hooks[][].hooks[] | select(.type != "command")] | length' "$H")" = "0" ] && ok "every hook is a command hook (Codex skips prompt/agent hooks)" || bad "a non-command hook" ""

# --- fixtures and probes ---------------------------------------------------------
# A fixture is the subset of the tree both generators read or validate, plus the
# generated files. Skill, rule, command and agent directories only need to exist.
mkfix() {
  local F="$T/fix-$RANDOM"
  mkdir -p "$F/.claude-plugin" "$F/.codex-plugin" "$F/.cursor-plugin" "$F/.cursor/rules" "$F/.cursor/commands" "$F/agents" "$F/scripts" "$F/platforms/cursor" "$F/platforms/codex" "$F/platforms/agent-plugins"
  cp "$ROOT/.claude-plugin/plugin.json" "$F/.claude-plugin/"
  cp "$ROOT/plugin-version.json" "$ROOT/.mcp.json" "$ROOT/gemini-extension.json" "$F/"
  cp "$ROOT/platforms/agent-plugins/plugin.json" "$ROOT/platforms/agent-plugins/mcp.json" "$F/platforms/agent-plugins/"
  cp "$ROOT/.codex-plugin/plugin.json" "$F/.codex-plugin/"
  cp "$ROOT/.cursor-plugin/plugin.json" "$F/.cursor-plugin/"
  cp "$ROOT/platforms/manifests.source.json" "$F/platforms/"
  cp "$ROOT/platforms/cursor/mcp.json" "$ROOT/platforms/cursor/hooks.json" "$F/platforms/cursor/"
  cp "$ROOT/platforms/codex/hooks.json" "$F/platforms/codex/"
  cp -R "$ROOT/hooks" "$F/hooks"
  cp "$ROOT/scripts/github-mcp.sh" "$ROOT/scripts/notify-pushover.sh" "$F/scripts/"
  for d in $(jq -r '.skills[]' "$ROOT/.claude-plugin/plugin.json"); do mkdir -p "$F/${d#./}"; done
  echo "$F"
}

# probe_check <name> <generator> <expected-text> <mutation-fn>
#   plants a mutation into a fixture and asserts --check fails naming the regenerate command.
probe_check() {
  local name="$1" gen="$2" expect="$3" fn="$4" F
  F="$(mkfix)"
  ( cd "$F" && "$fn" ) || { bad "$name" "probe setup failed"; rm -rf "$F"; return; }
  if bash "$gen" "$F" --check >"$F.log" 2>&1; then
    bad "$name" "--check passed with the planted drift"
  elif grep -q "$expect" "$F.log" && grep -q "Regenerate: bash scripts/build-" "$F.log"; then
    ok "$name"
  else
    bad "$name" "--check failed without naming it: $(grep -E 'DRIFT|error' "$F.log" | head -1)"
  fi
  rm -rf "$F" "$F.log"
}

# probe_source <name> <generator> <expected-text> <mutation-fn>
#   plants a bad SOURCE and asserts the build refuses it with exit 2.
probe_source() {
  local name="$1" gen="$2" expect="$3" fn="$4" F rc
  F="$(mkfix)"
  ( cd "$F" && "$fn" ) || { bad "$name" "probe setup failed"; rm -rf "$F"; return; }
  bash "$gen" "$F" >"$F.log" 2>&1; rc=$?
  if [ "$rc" -ne 2 ]; then
    bad "$name" "build exited $rc, expected 2: $(tail -1 "$F.log")"
  elif grep -q "$expect" "$F.log"; then
    ok "$name"
  else
    bad "$name" "build refused for another reason: $(grep error "$F.log" | head -1)"
  fi
  rm -rf "$F" "$F.log"
}

# JSON edits run through python3 -c with the file as argv, never through eval.
jedit() { python3 -c "$2" "$1"; }

m_root_description() { jedit platforms/agent-plugins/plugin.json 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["description"]="edited by hand"; json.dump(d,open(p,"w"),indent=2)'; }
m_cursor_extra_key() { jedit .cursor-plugin/plugin.json 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["displayName"]="x"; json.dump(d,open(p,"w"),indent=2)'; }
m_codex_old_hooks() { jedit .codex-plugin/plugin.json 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["hooks"]="./hooks/hooks.json"; json.dump(d,open(p,"w"),indent=2)'; }
m_missing_mcp() { rm -f platforms/agent-plugins/mcp.json; }
m_version_bump_unsynced() { jedit plugin-version.json 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["version"]="99.0.0"; json.dump(d,open(p,"w"),indent=2)'; }
m_undeclared_var() { jedit platforms/manifests.source.json 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["cursor"]["mcpServers"]["github"]["env"]["EXTRA"]="${UNDECLARED_THING}"; json.dump(d,open(p,"w"),indent=2)'; }
m_var_with_default() { jedit platforms/manifests.source.json 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["cursor"]["manifest"]["variables"]["properties"]["GITHUB_TOKEN"]["default"]="x"; json.dump(d,open(p,"w"),indent=2)'; }
m_root_literal_placeholder() { jedit platforms/manifests.source.json 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["agent_plugins"]["mcpServers"]["github"]["env"]={"X":"${user_config.thing}"}; json.dump(d,open(p,"w"),indent=2)'; }
m_root_command_placeholder() { jedit platforms/manifests.source.json 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["agent_plugins"]["mcpServers"]["github"]["command"]="${PLUGIN_ROOT}/scripts/github-mcp.sh"; json.dump(d,open(p,"w"),indent=2)'; }
m_codex_hooks_path_missing() { jedit platforms/manifests.source.json 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["codex"]["manifest"]["hooks"]="./platforms/codex/nope.json"; json.dump(d,open(p,"w"),indent=2)'; }
m_ext_overlay_disagree() { jedit platforms/manifests.source.json 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["agent_plugins"]["emit_codex_extension"]=True; d["codex"]["manifest"]["interface"]["displayName"]="Other"; json.dump(d,open(p,"w"),indent=2)'; }
m_hooks_modules() { jedit platforms/codex/hooks.json 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["modules"]=["../mod/register.tsx"]; json.dump(d,open(p,"w"),indent=2)'; }
m_hooks_onfailure() { jedit platforms/codex/hooks.json 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["hooks"]["PreToolUse"][0]["hooks"][0]["onFailure"]="block"; json.dump(d,open(p,"w"),indent=2)'; }
m_hooks_notification() { jedit platforms/codex/hooks.json 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["hooks"]["Notification"]=[{"hooks":[{"type":"command","command":"bash \"${CLAUDE_PLUGIN_ROOT}\"/hooks/notify.sh"}]}]; json.dump(d,open(p,"w"),indent=2)'; }
m_hooks_missing_script() { jedit hooks/hooks.json 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["hooks"]["Stop"][0]["hooks"][0]["command"]="bash \"${CLAUDE_PLUGIN_ROOT}\"/hooks/does-not-exist.sh"; json.dump(d,open(p,"w"),indent=2)'; }
m_hooks_unknown_event() { jedit hooks/hooks.json 'import json,sys; p=sys.argv[1]; d=json.load(open(p)); d["hooks"]["PreModelSwitch"]=[{"hooks":[{"type":"command","command":"bash \"${CLAUDE_PLUGIN_ROOT}\"/hooks/notify.sh"}]}]; json.dump(d,open(p,"w"),indent=2)'; }

echo "--- a planted drift makes --check fail and name the regenerate command ---"
probe_check "root plugin.json edited by hand" "$BM" "DRIFT: platforms/agent-plugins/plugin.json" m_root_description
probe_check "a key added by hand to .cursor-plugin/plugin.json" "$BM" "DRIFT: .cursor-plugin/plugin.json" m_cursor_extra_key
probe_check ".codex-plugin/plugin.json pointed back at the Claude hooks file" "$BM" "DRIFT: .codex-plugin/plugin.json" m_codex_old_hooks
probe_check "root mcp.json deleted" "$BM" "DRIFT: platforms/agent-plugins/mcp.json is missing" m_missing_mcp
probe_check "plugin-version.json bumped without regenerating" "$BM" "DRIFT: platforms/agent-plugins/plugin.json" m_version_bump_unsynced
probe_check "a modules key planted in the Codex hooks file" "$BC" "DRIFT: platforms/codex/hooks.json" m_hooks_modules
probe_check "onFailure planted in the Codex hooks file" "$BC" "DRIFT: platforms/codex/hooks.json" m_hooks_onfailure
probe_check "a Notification event planted in the Codex hooks file" "$BC" "DRIFT: platforms/codex/hooks.json" m_hooks_notification

echo "--- a bad source is refused, not rendered ---"
probe_source "an undeclared \${VAR} in the Cursor MCP overlay" "$BM" "does not declare" m_undeclared_var
probe_source "a Cursor variable with a default" "$BM" "carries a default" m_var_with_default
probe_source "a placeholder the spec leaves literal in the root mcp.json env" "$BM" "would stay literal" m_root_literal_placeholder
probe_source "a placeholder in the root mcp.json command" "$BM" "no placeholder" m_root_command_placeholder
probe_source "a Codex hooks path that does not exist" "$BM" "does not exist in this tree" m_codex_hooks_path_missing
probe_source "root extension and Codex overlay disagreeing" "$BM" "differs from .codex-plugin/plugin.json" m_ext_overlay_disagree
probe_source "a hook whose script is missing" "$BC" "does not exist in this tree" m_hooks_missing_script
probe_source "a canonical event neither supported nor known-dropped" "$BC" "neither Codex's list nor the known-dropped list" m_hooks_unknown_event

echo "--- regenerating a drifted fixture brings --check back to green ---"
F="$(mkfix)"
( cd "$F" && m_root_description && m_hooks_onfailure ) || bad "round-trip setup" "mutation failed"
if bash "$BM" "$F" >/dev/null 2>&1 && bash "$BC" "$F" >/dev/null 2>&1 \
   && bash "$BM" "$F" --check >/dev/null 2>&1 && bash "$BC" "$F" --check >/dev/null 2>&1; then
  ok "regenerate then --check passes on the fixture"
else
  bad "regenerate then --check passes on the fixture" "see $F"
fi
same=1
for f in platforms/agent-plugins/plugin.json platforms/agent-plugins/mcp.json .codex-plugin/plugin.json .cursor-plugin/plugin.json platforms/cursor/mcp.json gemini-extension.json platforms/codex/hooks.json; do
  cmp -s "$F/$f" "$ROOT/$f" || { bad "fixture regeneration reproduces $f byte for byte" "differs"; same=0; }
done
[ "$same" = 1 ] && ok "fixture regeneration reproduces every generated file byte for byte"
rm -rf "$F"

echo
echo "$PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then printf '  - %s\n' "${FAILED[@]}"; exit 1; fi
