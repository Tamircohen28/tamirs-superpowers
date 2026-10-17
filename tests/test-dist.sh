#!/usr/bin/env bash
# The per-host distributions: build-dist.sh writes one subset per target, check-dist.sh
# holds each to its host's rules, and the check FAILS on each class of finding a host's
# parser is known to reject.
#
# WHY THE NEGATIVE PROBES
#   A rule that stops firing is found by the next host failure, a release later. Every
#   rule in check-dist.sh came from a documented or source-read host edge (Codex's
#   strict hooks file, Cursor's declared variables, the Agent Plugins manifest's
#   $schema); a probe here plants the exact shape into a copy of the built tree and
#   asserts the check names it. The Claude target has its own test,
#   tests/test-claude-dist.sh, against the directory's rules.

# shellcheck disable=SC2015,SC2016  # `test && ok || bad` is the intended shape; probe strings are literal shell for eval
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/scripts/build-dist.sh"
CHECK="$ROOT/scripts/check-dist.sh"
PASS=0; FAIL=0; FAILED=()
ok(){ PASS=$((PASS+1)); echo "  ok   $1"; }
bad(){ FAIL=$((FAIL+1)); FAILED+=("$1"); echo "  FAIL $1 — $2"; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

echo "--- every target builds and passes its check ---"
for t in codex cursor gemini antigravity opencode agent-plugins; do
  if bash "$BUILD" "$T/$t" --target "$t" --quiet >"$T/$t.build.log" 2>&1; then ok "$t builds"; else bad "$t builds" "$(tail -2 "$T/$t.build.log" | tr '\n' ' ')"; continue; fi
  if bash "$CHECK" "$T/$t" --target "$t" >"$T/$t.check.log" 2>&1; then ok "$t passes its check"; else bad "$t passes its check" "$(grep FAIL "$T/$t.check.log" | head -2 | tr '\n' ' ')"; fi
done
# The Claude target through the generic builder is the same tree the Claude-specific
# wrapper produces (the wrapper is what the release workflow calls).
bash "$BUILD" "$T/claude-a" --target claude --quiet >/dev/null 2>&1
bash "$ROOT/scripts/build-claude-dist.sh" "$T/claude-b" --quiet >/dev/null 2>&1
diff -rq "$T/claude-a" "$T/claude-b" >/dev/null 2>&1 && ok "build-claude-dist.sh and build-dist.sh --target claude agree" || bad "the Claude wrapper and the generic builder differ" "$(diff -rq "$T/claude-a" "$T/claude-b" | head -2 | tr '\n' ' ')"
bash "$BUILD" "$T/x" --target nonsense --quiet >/dev/null 2>&1 && bad "an unknown target is accepted" "" || ok "an unknown target is refused"

# probe <target> <name> <rule-text-expected-in-FAIL-line> <shell that mutates $P>
probe() {
  local t="$1" name="$2" expect="$3" mutate="$4" P="$T/probe-$RANDOM"
  cp -R "$T/$t" "$P"
  (cd "$P" && eval "$mutate") || { bad "$name" "probe setup failed"; rm -rf "$P"; return; }
  if bash "$CHECK" "$P" --target "$t" >"$P.log" 2>&1; then
    bad "$name" "check passed with the planted finding"
  elif grep -q "FAIL.*$expect" "$P.log"; then
    ok "$name"
  else
    bad "$name" "check failed for another reason: $(grep FAIL "$P.log" | head -1)"
  fi
  rm -rf "$P" "$P.log"
}

echo "--- each class of host finding makes the check fail ---"
probe codex "the Claude hooks file shipped to Codex (its modules key fails Codex's parser)" "hooks/hooks.json is shipped" \
  'cp platforms/codex/hooks.json hooks/hooks.json'
probe codex "a root Agent Plugins manifest shipped to Codex (its loader then empties every hook source)" "root plugin.json is shipped" \
  'printf "{\"\$schema\":\"https://agent-plugins.org/schemas/1.0.0/plugin.schema.json\",\"name\":\"tamirs-superpowers\"}\n" > plugin.json'
probe codex "a modules key in the Codex hooks file" "breaks a Codex rule" \
  'python3 - <<'"'"'PY'"'"'
import json
p="platforms/codex/hooks.json"; d=json.load(open(p)); d["modules"]=["../mod/register.tsx"]; json.dump(d,open(p,"w"),indent=2)
PY'
probe codex "an event Codex lacks in the Codex hooks file" "breaks a Codex rule" \
  'python3 - <<'"'"'PY'"'"'
import json
p="platforms/codex/hooks.json"; d=json.load(open(p)); d["hooks"]["Notification"]=[{"hooks":[{"type":"command","command":"bash \"${CLAUDE_PLUGIN_ROOT}\"/hooks/notify.sh"}]}]; json.dump(d,open(p,"w"),indent=2)
PY'
probe codex "onFailure (a Claude key) in the Codex hooks file" "breaks a Codex rule" \
  'python3 - <<'"'"'PY'"'"'
import json
p="platforms/codex/hooks.json"; d=json.load(open(p)); d["hooks"]["Stop"][0]["hooks"][0]["onFailure"]="block"; json.dump(d,open(p,"w"),indent=2)
PY'
probe codex "a hook naming a script the tree does not ship" "breaks a Codex rule" \
  'python3 - <<'"'"'PY'"'"'
import json
p="platforms/codex/hooks.json"; d=json.load(open(p)); d["hooks"]["Stop"][0]["hooks"][0]["command"]="bash \"${CLAUDE_PLUGIN_ROOT}\"/hooks/missing.sh"; json.dump(d,open(p,"w"),indent=2)
PY'
probe codex "the mod shipped to Codex" "mod/ is shipped" \
  'mkdir -p mod && printf "export const register = () => {}\n" > mod/register.tsx'
probe cursor "an undeclared \${VAR} in the Cursor mcp.json" "undeclared" \
  'python3 - <<'"'"'PY'"'"'
import json
p="platforms/cursor/mcp.json"; d=json.load(open(p)); s=d["mcpServers"]["github"]; s.setdefault("env",{})["EXTRA"]="${UNDECLARED_THING}"; json.dump(d,open(p,"w"),indent=2)
PY'
probe cursor "a Cursor hooks bundle without version 1" "version is not 1" \
  'python3 - <<'"'"'PY'"'"'
import json
p="platforms/cursor/hooks.json"; d=json.load(open(p)); d.pop("version",None); json.dump(d,open(p,"w"),indent=2)
PY'
probe cursor "the Claude hooks file shipped to Cursor" "hooks/hooks.json is shipped" \
  'mkdir -p hooks && printf "{\"hooks\":{}}\n" > hooks/hooks.json'
probe agent-plugins "a root manifest without the Agent Plugins \$schema" "not a conformant Agent Plugins manifest" \
  'python3 - <<'"'"'PY'"'"'
import json
p="plugin.json"; d=json.load(open(p)); d.pop("$schema",None); json.dump(d,open(p,"w"),indent=2)
PY'
probe agent-plugins "a Claude-only transport name in mcp.json" "breaks the Agent Plugins shape" \
  'python3 - <<'"'"'PY'"'"'
import json
p="mcp.json"; d=json.load(open(p)); d["mcpServers"]["github"]["type"]="http"; json.dump(d,open(p,"w"),indent=2)
PY'
probe agent-plugins "hooks shipped in the portable package" "hooks is shipped" \
  'mkdir -p hooks && printf "{}\n" > hooks/hooks.json'
probe opencode "a shell hook shipped to OpenCode" "hooks/ is shipped" \
  'mkdir -p hooks && printf "#!/usr/bin/env bash\n" > hooks/x.sh'
probe gemini "the generated Gemini hooks file missing (Gemini reads only hooks/hooks.json)" "hooks/hooks.json missing" \
  'rm hooks/hooks.json'
probe gemini "the Claude hooks file shipped to Gemini (its modules key, CLAUDE_PLUGIN_ROOT and event names)" "breaks a Gemini rule" \
  'python3 - <<'"'"'PY'"'"'
import json
d={"modules":["./mod/register.tsx"],"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":"bash \"${CLAUDE_PLUGIN_ROOT}\"/hooks/protect-other-branches.sh"}]}]}}
json.dump(d,open("hooks/hooks.json","w"),indent=2)
PY'
probe gemini "an event Gemini lacks in the Gemini hooks file" "breaks a Gemini rule" \
  'python3 - <<'"'"'PY'"'"'
import json
p="hooks/hooks.json"; d=json.load(open(p)); d["hooks"]["SubagentStop"]=d["hooks"]["AfterAgent"]; json.dump(d,open(p,"w"),indent=2)
PY'
probe gemini "a Gemini hook naming a script the tree does not ship" "breaks a Gemini rule" \
  'python3 - <<'"'"'PY'"'"'
import json
p="hooks/hooks.json"; d=json.load(open(p)); d["hooks"]["AfterAgent"][0]["hooks"][0]["command"]="bash \"${extensionPath}/hooks/gemini-wrap.sh\" \"${extensionPath}/hooks/missing.sh\""; json.dump(d,open(p,"w"),indent=2)
PY'
probe gemini "a Gemini hook timeout in seconds (Gemini's unit is milliseconds)" "breaks a Gemini rule" \
  'python3 - <<'"'"'PY'"'"'
import json
p="hooks/hooks.json"; d=json.load(open(p)); d["hooks"]["AfterAgent"][0]["hooks"][0]["timeout"]=10; json.dump(d,open(p,"w"),indent=2)
PY'
probe gemini "the deny policies missing" "policies/tamirs-superpowers.toml missing" \
  'rm policies/tamirs-superpowers.toml'
probe antigravity "an extra key in the closed Antigravity plugin.json" "closed Antigravity schema" \
  'python3 - <<'"'"'PY'"'"'
import json
p="plugin.json"; d=json.load(open(p)); d["version"]="1.0.0"; json.dump(d,open(p,"w"),indent=2)
PY'
probe antigravity "a hooks file shipped to Antigravity" "hooks.json is shipped" \
  'printf "{}\n" > hooks.json'
probe antigravity "a two-level skill tree shipped to Antigravity" "not one level deep" \
  'mkdir -p skills/dev-workflow/deep && printf -- "---\nname: deep\n---\n" > skills/dev-workflow/deep/SKILL.md'
probe gemini "a symbolic link in the Gemini tree" "symbolic link" \
  'ln -s README.md probe-link.md'
probe gemini "a version that disagrees with plugin-version.json" "version differs" \
  'python3 - <<'"'"'PY'"'"'
import json
p="gemini-extension.json"; d=json.load(open(p)); d["version"]="0.0.0"; json.dump(d,open(p,"w"),indent=2)
PY'
probe opencode "a skill whose name differs from its folder" "name differs from its folder" \
  'f="$(find skills -name SKILL.md -not -path "*/_contract/*" | head -1)"; sed -i "s/^name: .*/name: something-else/" "$f"'
probe opencode "CHANGELOG.md shipped" "CHANGELOG.md is shipped" \
  'printf "# Changelog\n" > CHANGELOG.md'
probe opencode "a credential-shaped literal" "credential-shaped literal" \
  'printf "token: ghp_%s\n" "$(printf "%040d" 0 | tr 0 a)" > docs/user/probe.md'

echo
echo "passed: $PASS   failed: $FAIL"
[[ "$FAIL" -gt 0 ]] && { printf 'failing:'; printf ' [%s]' "${FAILED[@]}"; echo; exit 1; }
exit 0
