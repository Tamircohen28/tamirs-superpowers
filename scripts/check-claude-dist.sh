#!/usr/bin/env bash
# check-claude-dist.sh — hold the Claude-only distribution to the directory's rules.
#
# WHAT IT MIRRORS
#   The automated checks Anthropic's plugin directory runs at validation and on every
#   scanned commit, as its pre-submission checklist documents them, plus the findings
#   its first review of this plugin raised. The portal is the authority; this is the
#   local stand-in that runs on every pull request (make check-claude-dist, CI) so a
#   change that would block or hold the listing fails on master, not at release.
#   Where `claude` is on PATH it also runs the CLI's own strict validation and the
#   mod's tests against the built tree.
#
#   Blocks (the portal refuses the submission): manifest and hooks parse, README of
#   40+ words, a license, an https privacy policy where the plugin sends anything,
#   no credential read off the machine and forwarded, no CLAUDE.md shipped as plugin
#   context, a mod whose every `$` call is written at the call site.
#   Holds (a reviewer reads the version): over 512 files, a symlink, a non-image
#   file over 256 KiB, a binary that is not an image or font, a broad allowed-tools
#   entry, a bin/ directory, a package launcher, a lockfile install.
#
# Usage: check-claude-dist.sh <dist-dir> [--no-claude]
#   Exit 0 when every check passes; 1 with the failing checks listed.
# shellcheck disable=SC2015,SC2016  # `test && ok || bad` is the intended shape: ok() never fails; the sed range is a literal fence
set -uo pipefail

DIST=""; USE_CLAUDE=1
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-claude) USE_CLAUDE=0; shift ;;
    -h|--help) sed -n '2,/^set -uo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
    *) DIST="$1"; shift ;;
  esac
done
[[ -n "$DIST" && -d "$DIST" ]] || { echo "usage: check-claude-dist.sh <dist-dir> [--no-claude]" >&2; exit 2; }
DIST="$(cd "$DIST" && pwd)"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PASS=0; FAIL=0; FAILED=()
ok()  { PASS=$((PASS+1)); echo "  ok   $1"; }
bad() { FAIL=$((FAIL+1)); FAILED+=("$1"); echo "  FAIL $1${2:+ — $2}"; }
note(){ echo "  note $1"; }

echo "--- layout: what the directory can list ---"
count="$(find "$DIST" -type f | wc -l | tr -d ' ')"
[[ "$count" -le 512 ]] && ok "$count files (512 holds a version for review)" || bad "file count $count exceeds 512"
links="$(find "$DIST" -type l | wc -l | tr -d ' ')"
[[ "$links" -eq 0 ]] && ok "no symbolic links" || bad "$links symbolic link(s)" "$(find "$DIST" -type l | head -3 | tr '\n' ' ')"
junk="$(find "$DIST" \( -name .DS_Store -o -name Thumbs.db -o -name desktop.ini -o -name __MACOSX \) | head -3)"
[[ -z "$junk" ]] && ok "no OS junk files" || bad "OS junk files present" "$junk"
[[ ! -e "$DIST/bin" ]] && ok "no bin/ directory (claude.ai and Cowork refuse a plugin with one)" || bad "bin/ directory present"
[[ ! -e "$DIST/CLAUDE.md" && ! -e "$DIST/CLAUDE.local.md" ]] && ok "no CLAUDE.md at the plugin root (never loaded as plugin context)" || bad "CLAUDE.md at the plugin root"
for lock in package-lock.json npm-shrinkwrap.json bun.lock bun.lockb; do
  [[ -e "$DIST/$lock" ]] && bad "$lock at the plugin root (a lockfile install is held for review)"
done
big="$(find "$DIST" -type f -size +256k ! \( -iname '*.png' -o -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.gif' -o -iname '*.webp' -o -iname '*.svg' -o -iname '*.woff' -o -iname '*.woff2' -o -iname '*.ttf' -o -iname '*.otf' \) | head -5)"
[[ -z "$big" ]] && ok "no non-image file over 256 KiB" || bad "file(s) over 256 KiB" "$(echo "$big" | tr '\n' ' ')"
over5="$(find "$DIST" -type f -size +5M | head -3)"
[[ -z "$over5" ]] && ok "no file over 5 MiB" || bad "file(s) over 5 MiB" "$over5"
bins="$(find "$DIST" -type f -print0 | xargs -0 file --mime-type 2>/dev/null | sed -E 's/:[[:space:]]+/: /' | grep -vE ': (text/|application/(json|xml|javascript|ecmascript|x-sh|x-shellscript|x-python|toml|x-yaml|yaml|x-ndjson)|image/svg|image/(png|jpeg|gif|webp)|font/|application/(x-)?font|inode/x-empty|application/x-empty)' | head -5)"
[[ -z "$bins" ]] && ok "every file is text, an image or a font" || bad "binary file(s) the validator cannot read" "$(echo "$bins" | tr '\n' ' ')"

echo "--- manifest and listing ---"
M="$DIST/.claude-plugin/plugin.json"
if [[ -f "$M" ]] && jq -e . "$M" >/dev/null 2>&1; then
  ok ".claude-plugin/plugin.json parses"
  for k in name version description author license; do
    jq -e --arg k "$k" '.[$k] != null and .[$k] != ""' "$M" >/dev/null 2>&1 && ok "plugin.json has $k" || bad "plugin.json lacks $k"
  done
  for k in privacyPolicyUrl documentationUrl supportUrl; do
    if jq -e --arg k "$k" '.[$k] | type == "string" and startswith("https://")' "$M" >/dev/null 2>&1; then ok "plugin.json $k is an https URL"; else bad "plugin.json $k missing or not https"; fi
  done
  types="$(jq -r '.types // empty' "$M")"
  if [[ -n "$types" ]]; then
    [[ -f "$DIST/${types#./}" ]] && ok "types file $types exists" || bad "types file $types missing"
  fi
  # Every credential-shaped option is sensitive, and nothing else ships a secret.
  while IFS= read -r key; do
    jq -e --arg k "$key" '.userConfig[$k].sensitive == true' "$M" >/dev/null 2>&1 && ok "userConfig.$key is sensitive" || bad "userConfig.$key must be sensitive"
  done < <(jq -r '.userConfig // {} | keys[] | select(test("token|secret|key|password"))' "$M")
else
  bad ".claude-plugin/plugin.json missing or invalid JSON"
fi
[[ -f "$DIST/LICENSE" ]] && ok "LICENSE present" || bad "LICENSE missing"
if [[ -f "$DIST/README.md" ]]; then
  words="$(sed '/^```/,/^```/d' "$DIST/README.md" | wc -w | tr -d ' ')"
  [[ "$words" -ge 40 ]] && ok "README.md has $words words outside code blocks (40 required)" || bad "README.md too short ($words words)"
  grep -qi 'privacy' "$DIST/README.md" && ok "README.md mentions privacy" || bad "README.md never mentions privacy"
else
  bad "README.md missing"
fi
[[ -f "$DIST/PRIVACY.md" ]] && ok "PRIVACY.md present" || bad "PRIVACY.md missing"
icon="$(jq -r '.icon // ".claude-plugin/icon.png"' "$M" 2>/dev/null | sed 's#^\./##')"
if [[ -f "$DIST/$icon" ]]; then
  read -r iw ih < <(python3 -c "import struct,sys;d=open(sys.argv[1],'rb').read(32);print(*struct.unpack('>II',d[16:24]))" "$DIST/$icon" 2>/dev/null || echo "0 0")
  isz="$(stat -c %s "$DIST/$icon" 2>/dev/null || stat -f %z "$DIST/$icon")"
  if head -c 8 "$DIST/$icon" | grep -q 'PNG' && [[ "$iw" -eq "$ih" && "$iw" -ge 512 && "$iw" -le 2048 && "$isz" -lt 2097152 ]]; then
    ok "listing icon $icon is a square PNG (${iw}px, $((isz/1024)) KiB)"
  else
    bad "listing icon $icon must be a square PNG, 512–2048 px, under 2 MB" "${iw}x${ih}, $isz bytes"
  fi
else
  bad "listing icon missing" "$icon (the directory warns, and the first submission fixes the icon for good)"
fi
for gone in CHANGELOG.md docs/engineering docs/changelog AGENTS.md Makefile; do
  [[ -e "$DIST/$gone" ]] && bad "$gone is in the distribution" "it belongs to the source repository, not the listing"
done
# Prose that names a credential variable or the gh token command reads as a credential
# read to the scanner, whatever the sentence says. The three files that must name
# GITHUB_PERSONAL_ACCESS_TOKEN (the manifest, .mcp.json and the launcher) are allowed.
prose="$(grep -rnE 'gh auth token|PUSHOVER_TOKEN|PUSHOVER_USER|GITHUB_TOKEN|GH_TOKEN|GITHUB_PERSONAL_ACCESS_TOKEN|pushover\.env' "$DIST" --include='*.md' --include='*.json' --include='*.sh' --include='*.py' --include='*.tsx' --include='*.tmpl' --include='*.yaml' 2>/dev/null | grep -vE '^[^:]+/(\.mcp\.json|\.claude-plugin/plugin\.json|scripts/github-mcp\.sh|scripts/notify-pushover\.sh):' | head -3)"
[[ -z "$prose" ]] && ok "no shipped file names a credential variable or the gh token command (outside the three that must)" || bad "credential name in shipped text" "$prose"

echo "--- hooks, mod and MCP ---"
H="$DIST/hooks/hooks.json"
if [[ -f "$H" ]] && jq -e . "$H" >/dev/null 2>&1; then
  ok "hooks/hooks.json parses"
  while IFS= read -r m; do
    [[ -f "$DIST/hooks/$m" ]] && ok "modules entry $m exists" || bad "modules entry $m missing"
  done < <(jq -r '.modules[]? // empty' "$H")
  # Every shell-form command spells its path from CLAUDE_PLUGIN_ROOT, quoted, no other variable.
  badcmd="$(jq -r '.. | .command? // empty' "$H" | grep -vE '^(bash|python3) ("\$\{CLAUDE_PLUGIN_ROOT\}"/[A-Za-z0-9_./-]+|"\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9_./-]+")( [^$`]*)?$' | head -3)"
  [[ -z "$badcmd" ]] && ok "every hook command is <interp> \"\${CLAUDE_PLUGIN_ROOT}\"/<path>, quoted, no other variable" || bad "hook command not in the plain CLAUDE_PLUGIN_ROOT form" "$badcmd"
else
  bad "hooks/hooks.json missing or invalid"
fi
MCP="$DIST/.mcp.json"
if [[ -f "$MCP" ]]; then
  jq -e . "$MCP" >/dev/null 2>&1 && ok ".mcp.json parses" || bad ".mcp.json invalid JSON"
  badurl="$(jq -r '.mcpServers[] | select(.url) | .url' "$MCP" | grep -vE '^(https://|wss://|\$\{user_config\.|$)' | head -2)"
  [[ -z "$badurl" ]] && ok "every remote MCP url is https/wss or a user_config reference" || bad "MCP url not https" "$badurl"
  secretval="$(jq -r '.mcpServers[] | (.env // {}, .headers // {}) | to_entries[] | select(.key | test("token|secret|key|password"; "i")) | .value' "$MCP" | grep -vE '^\$\{user_config\.[A-Za-z0-9_]+\}$' | head -2)"
  [[ -z "$secretval" ]] && ok "every MCP credential is a \${user_config.KEY} reference" || bad "MCP credential is not a user_config reference" "$secretval"
  # A local server starts by running a file in the plugin with plain arguments, not a shell.
  shellcmd="$(jq -r '.mcpServers[] | select(.command) | .command' "$MCP" | grep -vE '^\$\{CLAUDE_PLUGIN_ROOT\}/[A-Za-z0-9_./-]+$' | head -2)"
  [[ -z "$shellcmd" ]] && ok "every local MCP server runs a plugin file directly (no shell, no launcher)" || bad "MCP server command goes through a shell or launcher" "$shellcmd"
  while IFS= read -r cmdf; do
    [[ -x "$DIST/$cmdf" ]] && ok "MCP command $cmdf is executable" || bad "MCP command $cmdf is not executable"
  done < <(jq -r '.mcpServers[] | select(.command) | .command' "$MCP" | sed 's#^\${CLAUDE_PLUGIN_ROOT}/##')
fi
# Nothing shipped reads a credential off the machine and could forward it.
creds="$(grep -rnE 'gh auth token|pushover\.env|\$\{?(GITHUB_TOKEN|GH_TOKEN|PUSHOVER_TOKEN|PUSHOVER_USER|ANTHROPIC_API_KEY|OPENAI_API_KEY)\b' "$DIST/scripts" "$DIST/hooks" "$DIST/mod" --include='*.sh' --include='*.py' --include='*.ts' --include='*.tsx' 2>/dev/null | grep -vE '^[^:]+:[0-9]+:\s*#' | grep -v 'mods\.test\.tsx' | head -3)"
[[ -z "$creds" ]] && ok "no shipped script or mod reads a credential from the environment or a file" || bad "credential read off the machine" "$creds"
# No download-and-run in anything that executes.
# A launcher counts only at command position (line start, or after ; & | $( or a
# backtick): a word inside a message string is not a launch.
fetchexec="$(grep -rnE '(curl|wget)[^|"]*\|\s*(ba)?sh\b|(^|[;&|(`]|\$\()\s*(npx|bunx|uvx|pipx run|pnpm dlx|yarn dlx|uv run)\s' "$DIST/scripts" "$DIST/hooks" "$DIST/mod" --include='*.sh' --include='*.py' --include='*.ts' --include='*.tsx' 2>/dev/null | grep -vE '^[^:]+:[0-9]+:\s*#' | head -3)"
[[ -z "$fetchexec" ]] && ok "no shipped script downloads and runs code, and no package launcher" || bad "download-and-run or package launcher in a shipped script" "$fetchexec"
# The mod hands $ to no helper (the directory's MOD_CAPABILITY_USE_NOT_PLAIN).
if [[ -f "$DIST/mod/register.tsx" ]]; then
  # A call `name($ ...)`: an identifier right before the parenthesis. A hook's own
  # parameter list `async ($, e, next)` has no identifier there and is not a call.
  aliased="$(grep -noE '\b[A-Za-z_][A-Za-z0-9_]*\(\s*\$\s*[,)]' "$DIST/mod/register.tsx" | grep -vE ':(atom|read|update|derive|memberOf)\(' | head -3)"
  [[ -z "$aliased" ]] && ok "mod never passes \$ to a helper (only the claude-code state helpers take it)" || bad "mod passes \$ to a helper" "$aliased"
  grep -qE '\$\.process\.' "$DIST/mod/register.tsx" && bad "mod runs a process" || ok "mod runs no process"
fi

echo "--- skills ---"
if [[ -f "$HERE/validate-skill-frontmatter.py" ]]; then
  if (cd "$DIST" && python3 "$HERE/validate-skill-frontmatter.py" skills/*/*/SKILL.md >/tmp/claude-dist-skills.$$ 2>&1); then
    ok "every shipped SKILL.md passes frontmatter validation (broad allowed-tools included)"
  else
    bad "SKILL.md frontmatter validation failed" "$(grep -E 'FAIL|too broad' /tmp/claude-dist-skills.$$ | head -3 | tr '\n' ' ')"
  fi
  rm -f /tmp/claude-dist-skills.$$
fi
broad="$(awk 'FNR==1{f=0} /^allowed-tools:/{f=1;next} f&&/^[a-z-]+:/{f=0} f&&/^\s*- (Bash|Skill|Write|Edit|MultiEdit|NotebookEdit|WebFetch|WebSearch|Bash\(\*\)|Bash\([a-z0-9]+:\*\))\s*$/{print FILENAME": "$0}' "$DIST"/skills/*/*/SKILL.md 2>/dev/null | head -3)"
[[ -z "$broad" ]] && ok "no bare Bash/Skill/Write/Edit/WebFetch/WebSearch or interpreter wildcard in any allowed-tools" || bad "broad or unscoped allowed-tools entry" "$broad"

echo "--- links ---"
dangling="$(python3 - "$DIST" <<'PY'
import os, re, sys
root = sys.argv[1]
link = re.compile(r'\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)')
out = []
for d, _, fs in os.walk(root):
    for f in fs:
        if not f.endswith(".md"):
            continue
        p = os.path.join(d, f)
        text = re.sub(r"```.*?```", "", open(p, encoding="utf-8", errors="replace").read(), flags=re.S)
        for m in link.finditer(text):
            t = m.group(1).strip("<>")
            if t.startswith(("http://", "https://", "mailto:", "#")) or ":" in t.split("/")[0]:
                continue
            t = t.split("#", 1)[0]
            if not t:
                continue
            tgt = os.path.normpath(os.path.join(d, t))
            if not os.path.exists(tgt):
                out.append(f"{os.path.relpath(p, root)} -> {t}")
print("\n".join(out))
PY
)"
n="$(printf '%s' "$dangling" | grep -c . || true)"
if [[ "$n" -eq 0 ]]; then ok "every relative link in README.md resolves"; else
  rl="$(printf '%s\n' "$dangling" | grep -E '^README\.md ' | head -3)"
  [[ -z "$rl" ]] && ok "every relative link in README.md resolves ($n elsewhere point at files not in this distribution)" || bad "README.md has dangling links" "$rl"
fi

echo "--- Claude Code CLI ---"
if [[ "$USE_CLAUDE" -eq 1 ]] && command -v claude >/dev/null 2>&1; then
  if out="$(claude plugin validate --strict "$DIST/.claude-plugin/plugin.json" 2>&1)"; then
    ok "claude plugin validate --strict passes"
  else
    bad "claude plugin validate --strict failed" "$(printf '%s' "$out" | grep -E '^\s*(>|✗|x|error)' | head -3 | tr '\n' ' ')"
  fi
  if [[ -f "$DIST/mod/register.tsx" ]]; then
    if out="$(cd "$DIST" && claude plugin test . 2>&1)"; then ok "claude plugin test passes on the built tree"; else bad "claude plugin test failed on the built tree" "$(printf '%s' "$out" | tail -3 | tr '\n' ' ')"; fi
  fi
else
  note "claude CLI not on PATH (or --no-claude): strict validate and plugin test skipped"
fi

echo
echo "passed: $PASS   failed: $FAIL"
if [[ "$FAIL" -gt 0 ]]; then printf 'failing:'; printf ' [%s]' "${FAILED[@]}"; echo; exit 1; fi
exit 0
