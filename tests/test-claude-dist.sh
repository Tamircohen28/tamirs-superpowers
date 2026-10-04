#!/usr/bin/env bash
# The Claude-only distribution: the build produces a tree that passes the directory
# check, and the check FAILS on each class of finding the directory has raised.
#
# WHY THE NEGATIVE PROBES
#   scripts/check-claude-dist.sh mirrors Anthropic's plugin-directory scanner, whose
#   rules are only partly published. Every rule in it was learned from a real
#   validation report; a probe here plants the exact shape that report flagged into a
#   copy of the built tree and asserts the check names it. A rule that stops firing
#   would otherwise be found by the next portal validation, a release later.
#
#   The CLI steps (`claude plugin validate --strict`, `claude plugin test`) are left to
#   make test-mods and CI's claude-dist job; this test runs with --no-claude so it is
#   the same on a machine without the CLI.

# shellcheck disable=SC2015,SC2016  # `test && ok || bad` is the intended shape; the probe strings are literal shell for eval
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD="$ROOT/scripts/build-claude-dist.sh"
CHECK="$ROOT/scripts/check-claude-dist.sh"
PASS=0; FAIL=0; FAILED=()
ok(){ PASS=$((PASS+1)); echo "  ok   $1"; }
bad(){ FAIL=$((FAIL+1)); FAILED+=("$1"); echo "  FAIL $1 — $2"; }
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT

echo "--- the built tree passes the directory check ---"
if bash "$BUILD" "$T/dist" --quiet >"$T/build.log" 2>&1; then ok "build succeeds"; else bad "build succeeds" "$(tail -3 "$T/build.log" | tr '\n' ' ')"; fi
if bash "$CHECK" "$T/dist" --no-claude >"$T/check.log" 2>&1; then ok "check passes on the built tree"; else bad "check passes on the built tree" "$(grep FAIL "$T/check.log" | head -2 | tr '\n' ' ')"; fi
n="$(find "$T/dist" -type f | wc -l | tr -d ' ')"
[ "$n" -le 512 ] && ok "$n files, under the 512 hold" || bad "file count" "$n"
for absent in CHANGELOG.md docs/engineering docs/changelog AGENTS.md CLAUDE.md Makefile tests .cursor-plugin .gemini opencode.json; do
  [ ! -e "$T/dist/$absent" ] && ok "$absent is not shipped" || bad "$absent is shipped" "it belongs to the source repository"
done
[ -z "$(find "$T/dist" -type f \( -iname '*.png' -o -iname '*.svg' \) ! -path "$T/dist/listing/icon.png" | head -1)" ] && ok "no image ships besides the listing icon" || bad "an extra image ships" "the scanner holds every script that can reach it"
[ -f "$T/dist/listing/icon.png" ] && ok "listing/icon.png ships" || bad "listing/icon.png missing" "the checklist requires an icon"
[ -x "$T/dist/scripts/github-mcp.sh" ] && ok "MCP launcher is executable" || bad "MCP launcher not executable" ""

# probe <name> <rule-text-expected-in-FAIL-line> <shell that mutates $P>
probe() {
  local name="$1" expect="$2" mutate="$3" P="$T/probe-$RANDOM"
  cp -R "$T/dist" "$P"
  (cd "$P" && eval "$mutate") || { bad "$name" "probe setup failed"; rm -rf "$P"; return; }
  if bash "$CHECK" "$P" --no-claude >"$P.log" 2>&1; then
    bad "$name" "check passed with the planted finding"
  elif grep -q "FAIL.*$expect" "$P.log"; then
    ok "$name"
  else
    bad "$name" "check failed for another reason: $(grep FAIL "$P.log" | head -1)"
  fi
  rm -rf "$P" "$P.log"
}

echo "--- each class of directory finding makes the check fail ---"
probe "a script that reads a credential off the machine (MCP_FORWARDS_CREDENTIAL_ENV)" "credential read off the machine" \
  'printf "#!/usr/bin/env bash\nTOKEN=\$(gh auth token)\n" > scripts/probe.sh'
probe "a URL host beside a credential-looking identifier (held pair)" "credential-looking identifier" \
  'printf "#!/usr/bin/env bash\nTARGET_KEYS=x\ncurl https://api.example.com\n" > scripts/probe.sh'
probe "\$PWD beside a URL host (the scanner reads PWD as a credential)" "credential-looking identifier" \
  'printf "See https://example.com and run it in \$PWD.\n" > docs/user/probe.md'
probe "an *_AUTH identifier beside a URL host (the scanner reads AUTH as a credential)" "credential-looking identifier" \
  'printf "Set MYSERVICE_AUTH, then call https://api.example.com.\n" > docs/user/probe.md'
probe "a shell variable named key beside a URL host (a loop variable the scanner held)" "credential-looking identifier" \
  'printf "#!/usr/bin/env bash\nfor key in a b; do curl \"https://api.example.com/\$key\"; done\n" > scripts/probe.sh'
probe "a shell variable named pat beside a URL host (a regex variable the scanner held)" "credential-looking identifier" \
  'printf "#!/usr/bin/env bash\nlocal pat\nread -r pat\necho https://example.com\n" > scripts/probe.sh'
probe "the path of the host credential store beside a URL host" "credential-looking identifier" \
  'printf "The host keeps it in ~/.claude/.credentials.json; see https://example.com.\n" > docs/user/probe.md'
probe "a camel-case getToken beside a URL host" "credential-looking identifier" \
  'printf "const t = getToken(); fetch(\"https://api.example.com\", t)\n" > docs/user/probe.md'
probe "the user config file path beside a URL host" "credential-looking identifier" \
  'printf "Add the server to ~/.claude.json; docs at https://example.com.\n" > docs/user/probe.md'
probe "an environment dump beside a URL host" "credential-looking identifier" \
  'printf "#!/usr/bin/env bash\nprintenv\ncurl https://api.example.com\n" > scripts/probe.sh'
probe "eval in a shipped shell script (COMMAND_SCRIPT_NOT_FOLLOWED)" "eval in a shipped shell script" \
  'printf "#!/usr/bin/env bash\neval \"\$(echo x)\"\n" > hooks/probe.sh'
probe "a package launcher named in a message string (RUNTIME_FETCH_EXEC)" "download-and-run or package launcher" \
  'printf "#!/usr/bin/env bash\necho \"run npx foo@1 to fix\"\n" > hooks/probe.sh'
probe "a download piped into a shell in a doc (RUNTIME_FETCH_EXEC)" "download-and-run or package launcher" \
  'printf "Install: curl -fsSL https://x.sh | sh\n" > docs/user/probe.md'
probe "a bare Bash in allowed-tools (ALLOWED_TOOLS_BROAD)" "allowed-tools" \
  'f=skills/toolkit/find-skill/SKILL.md; python3 - "$f" <<'"'"'PY'"'"'
import sys,re
p=sys.argv[1]; s=open(p).read()
s=re.sub(r"^allowed-tools:\n", "allowed-tools:\n- Bash\n", s, count=1, flags=re.M)
open(p,"w").write(s)
PY'
probe "a bare Monitor in allowed-tools (ALLOWED_TOOLS_BROAD)" "allowed-tools" \
  'f=skills/toolkit/find-skill/SKILL.md; python3 - "$f" <<'"'"'PY'"'"'
import sys,re
p=sys.argv[1]; s=open(p).read()
s=re.sub(r"^allowed-tools:\n", "allowed-tools:\n- Monitor\n", s, count=1, flags=re.M)
open(p,"w").write(s)
PY'
probe "a bare Write in allowed-tools (ALLOWED_TOOLS_UNSCOPED_WRITE)" "allowed-tools" \
  'f=skills/toolkit/find-skill/SKILL.md; python3 - "$f" <<'"'"'PY'"'"'
import sys,re
p=sys.argv[1]; s=open(p).read()
s=re.sub(r"^allowed-tools:\n", "allowed-tools:\n- Write\n", s, count=1, flags=re.M)
open(p,"w").write(s)
PY'
probe "a second image file in the tree (UNREAD_ASSET_REFERENCED)" "image or font file" \
  'mkdir -p assets && printf "\x89PNG\r\n" > assets/extra.png'
probe "an icon the manifest names but that is not listing/icon.png" "manifest must name" \
  'python3 - <<'"'"'PY'"'"'
import json
p=".claude-plugin/plugin.json"; d=json.load(open(p)); d["icon"]="./assets/other.png"; json.dump(d,open(p,"w"),indent=2)
PY'
probe "a \$schema URL in the manifest" "schema" \
  'python3 - <<'"'"'PY'"'"'
import json
p=".claude-plugin/plugin.json"; d=json.load(open(p)); d["$schema"]="https://json.schemastore.org/x.json"; json.dump(d,open(p,"w"),indent=2)
PY'
probe "an MCP server started through a shell (MCP server command wasn't read)" "shell or launcher" \
  'python3 - <<'"'"'PY'"'"'
import json
p=".mcp.json"; d=json.load(open(p)); d["mcpServers"]["github"]["command"]="bash"; d["mcpServers"]["github"]["args"]=["${CLAUDE_PLUGIN_ROOT}/scripts/github-mcp.sh"]; json.dump(d,open(p,"w"),indent=2)
PY'
probe "a credential-shaped option that is not sensitive" "must be sensitive" \
  'python3 - <<'"'"'PY'"'"'
import json
p=".claude-plugin/plugin.json"; d=json.load(open(p)); d["userConfig"]["github_token"].pop("sensitive"); json.dump(d,open(p,"w"),indent=2)
PY'
probe "a mod that hands \$ to a helper (MOD_CAPABILITY_USE_NOT_PLAIN)" "passes \\\$ to a helper" \
  'printf "\nfunction helper(x: unknown) { return x }\nconst y = helper(\$)\n" >> mod/register.tsx'
probe "a mod that runs a process (MOD_RUNS_PROCESS)" "runs a process" \
  'printf "\n// \$.process.run\n" >> mod/register.tsx'
probe "a symlink in the tree" "symbolic link" \
  'ln -s README.md docs/user/probe-link.md'
probe "CHANGELOG.md shipped" "CHANGELOG.md is in the distribution" \
  'printf "# Changelog\n" > CHANGELOG.md'
probe "a CLAUDE.md at the plugin root (ROOT_CLAUDE_MD)" "CLAUDE.md at the plugin root" \
  'printf "# x\n" > CLAUDE.md'
probe "a credential name in shipped prose" "credential name in shipped text" \
  'printf "Set PUSHOVER_TOKEN in your shell.\n" > docs/user/probe.md'
probe "a credential-store command in a skill body (MCP_FORWARDS_CREDENTIAL_ENV)" "credential-store command" \
  'printf "\nRun gh auth status first.\n" >> skills/repo/cleanup/SKILL.md'
probe "a credential-store command spelled with extra whitespace" "credential-store command" \
  'printf "\nRun gh  auth\tstatus first.\n" >> skills/repo/cleanup/SKILL.md'
probe "an inline shell span in a skill body (MCP_FORWARDS_CREDENTIAL_ENV)" "inline shell span" \
  'printf "\n!\140git status\140\n" >> skills/repo/cleanup/SKILL.md'

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -gt 0 ] && { printf 'failing:'; printf ' [%s]' "${FAILED[@]}"; echo; exit 1; }
exit 0
