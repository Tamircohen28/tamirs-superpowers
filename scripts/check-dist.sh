#!/usr/bin/env bash
# check-dist.sh — hold one host's distribution (built by build-dist.sh) to that host's
# rules.
#
# WHY A SECOND CHECKER
#   check-claude-dist.sh encodes Anthropic's plugin directory: forty-odd readings of a
#   scanner whose rules were learned one validation at a time. The other hosts have no
#   such scanner, but each has a parser with hard edges — Codex rejects an unknown key
#   in a hooks file and knows twelve events, Cursor requires `"version": 1` on its
#   bundle and a declared variable behind every `${VAR}` in its mcp.json, the Agent
#   Plugins manifest needs its `$schema` — and every host shares the structural rules a
#   tarball must meet (no symlinks, no binary the host cannot read, one version
#   everywhere). This script is the per-target table of those rules. A rule learned
#   from a real host failure goes here with the failure quoted, the way the Claude
#   checker does, and tests/test-dist.sh plants the shape to prove the rule fires.
#
# Usage: check-dist.sh <dist-dir> --target <codex|cursor|gemini|antigravity|opencode|agent-plugins> [--source <repo-root>]
#   For --target claude use check-claude-dist.sh.
# shellcheck disable=SC2015,SC2016  # `test && ok || bad` is the intended shape: ok() never fails; the single-quoted xargs bodies are literal shell
set -uo pipefail

DIST=""; TARGET=""; SRC=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --source) SRC="$2"; shift 2 ;;
    -h|--help) sed -n '2,/^set -uo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
    *) DIST="$1"; shift ;;
  esac
done
[[ -n "$DIST" && -d "$DIST" && -n "$TARGET" ]] || { echo "usage: check-dist.sh <dist-dir> --target <codex|cursor|gemini|antigravity|opencode|agent-plugins> [--source <repo-root>]" >&2; exit 2; }
[[ "$TARGET" != "claude" ]] || { echo "check-dist: use check-claude-dist.sh for the Claude tree" >&2; exit 2; }
DIST="$(cd "$DIST" && pwd)"
SRC="${SRC:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

PASS=0; FAIL=0; FAILED=()
ok()  { PASS=$((PASS+1)); echo "  ok   $1"; }
bad() { FAIL=$((FAIL+1)); FAILED+=("$1"); echo "  FAIL $1${2:+ — $2}"; }
has() { [[ -e "$DIST/$1" ]]; }

echo "--- structure [$TARGET] ---"
n="$(find "$DIST" -type f | wc -l | tr -d ' ')"
[[ "$n" -gt 0 && "$n" -le 2000 ]] && ok "$n files" || bad "file count out of range" "$n"
links="$(find "$DIST" -type l | head -3)"
[[ -z "$links" ]] && ok "no symbolic links" || bad "symbolic link(s) in the tree" "$(echo "$links" | tr '\n' ' ')"
bins="$(find "$DIST" -type f -print0 | xargs -0 file --mime-type 2>/dev/null | sed -E 's/:[[:space:]]+/: /' | grep -vE ': (text/|application/(json|xml|javascript|ecmascript|x-sh|x-shellscript|x-python|toml|x-yaml|yaml|x-ndjson)|image/svg|image/(png|jpeg|gif|webp)|font/|application/(x-)?font|inode/x-empty|application/x-empty)' | head -3)"
[[ -z "$bins" ]] && ok "every file is text, an image or a font" || bad "binary file(s) a host cannot read" "$(echo "$bins" | tr '\n' ' ')"
badjson="$(find "$DIST" -type f -name '*.json' -print0 | xargs -0 -n1 sh -c 'python3 -m json.tool "$0" >/dev/null 2>&1 || echo "$0"' | head -3)"
[[ -z "$badjson" ]] && ok "every .json file parses" || bad "unparseable JSON" "$(echo "$badjson" | tr '\n' ' ')"
for f in README.md LICENSE PRIVACY.md SECURITY.md plugin-version.json; do
  has "$f" && ok "$f present" || bad "$f missing"
done
for absent in CHANGELOG.md docs/engineering docs/changelog tests evals Makefile .github mod/mods.test.tsx; do
  has "$absent" && bad "$absent is shipped" "it belongs to the source repository" || ok "$absent is not shipped"
done
# Secrets never ship, whatever the host.
leak="$(grep -rnE '(ghp|gho|ghu|ghs|github_pat)_[A-Za-z0-9_]{20,}|sk-ant-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}' "$DIST" 2>/dev/null | head -2)"
[[ -z "$leak" ]] && ok "no credential-shaped literal" || bad "credential-shaped literal in the tree" "$leak"

echo "--- version [$TARGET] ---"
ver="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1]))['version'])" "$DIST/plugin-version.json" 2>/dev/null)"
[[ -n "$ver" ]] && ok "plugin-version.json says $ver" || bad "plugin-version.json unreadable"
for m in plugin.json .codex-plugin/plugin.json .cursor-plugin/plugin.json gemini-extension.json; do
  has "$m" || continue
  # Antigravity's plugin.json is a closed {name, description} schema with no version field.
  [[ "$TARGET" == "antigravity" && "$m" == "plugin.json" ]] && continue
  mv_="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('version',''))" "$DIST/$m")"
  [[ "$mv_" == "$ver" ]] && ok "$m is $ver" || bad "$m version differs" "$mv_"
done

echo "--- skills [$TARGET] ---"
if [[ -d "$DIST/skills" ]]; then
  shipped="$(find "$DIST/skills" -name SKILL.md -not -path '*/fixtures/*' -not -path '*/_contract/*' | wc -l | tr -d ' ')"
  if [[ -d "$SRC/skills" ]]; then
    canon="$(find "$SRC/skills" -name SKILL.md -not -path '*/fixtures/*' -not -path '*/_contract/*' | wc -l | tr -d ' ')"
    [[ "$shipped" == "$canon" ]] && ok "$shipped skills, the same as the source" || bad "skill count differs from the source" "$shipped vs $canon"
  else
    [[ "$shipped" -gt 0 ]] && ok "$shipped skills" || bad "no skills"
  fi
  badname="$(find "$DIST/skills" -name SKILL.md -not -path '*/fixtures/*' -not -path '*/_contract/*' -print0 | xargs -0 -n1 sh -c 'd="$(basename "$(dirname "$0")")"; n="$(sed -n "s/^name: *//p" "$0" | head -1 | tr -d "\"'"'"'")"; [ "$n" = "$d" ] || echo "$0 ($n)"' | head -3)"
  [[ -z "$badname" ]] && ok "every skill's name matches its folder (Agent Skills rule)" || bad "skill name differs from its folder" "$(echo "$badname" | tr '\n' ' ')"
fi

case "$TARGET" in
  codex)
    echo "--- codex ---"
    # Measured on codex-cli 0.163.0 (tests/hooks/test-codex-contract.sh provenance): a plugin
    # with a root Agent Plugins plugin.json has its hook sources emptied before any hooks
    # path is read, whichever manifest names them. The Codex subset ships the overlay route.
    has plugin.json && bad "root plugin.json is shipped" "Codex 0.163.0 empties a plugin's hook sources when a root Agent Plugins manifest is present" || ok "no root Agent Plugins manifest (Codex would drop every hook)"
    has .codex-plugin/plugin.json && ok ".codex-plugin/plugin.json present (the Codex route)" || bad ".codex-plugin/plugin.json missing"
    has platforms/codex/hooks.json && ok "platforms/codex/hooks.json present" || bad "platforms/codex/hooks.json missing"
    has hooks/hooks.json && bad "hooks/hooks.json is shipped" "Codex's HooksFile rejects its modules key; only the generated file ships" || ok "the Claude hooks file is not shipped"
    has mod && bad "mod/ is shipped" "Codex runs no mod" || ok "no mod"
    if has platforms/codex/hooks.json; then
      python3 - "$DIST/platforms/codex/hooks.json" "$DIST" <<'PY' && ok "Codex hooks file: no modules, no onFailure, Codex events only, every script present" || bad "Codex hooks file breaks a Codex rule" "see above"
import json, os, re, sys
d = json.load(open(sys.argv[1])); dist = sys.argv[2]
allowed = {"SessionStart","SessionEnd","SubagentStart","UserPromptSubmit","PreToolUse","PermissionRequest","PostToolUse","PreCompact","PostCompact","SubagentStop","Stop","Interrupt"}
bad = []
if set(d) - {"description", "hooks"}: bad.append("unknown top-level key: %s" % (set(d) - {"description","hooks"}))
for ev, groups in d.get("hooks", {}).items():
    if ev not in allowed: bad.append("event Codex lacks: " + ev)
    for g in groups:
        for h in g.get("hooks", []):
            if "onFailure" in h: bad.append("onFailure on " + h.get("command",""))
            m = re.search(r'\$\{CLAUDE_PLUGIN_ROOT\}"?/([^ "]+)', h.get("command",""))
            if m and not os.path.exists(os.path.join(dist, m.group(1))): bad.append("missing script " + m.group(1))
for b in bad: print("    " + b)
sys.exit(1 if bad else 0)
PY
    fi
    if has .codex-plugin/plugin.json; then
      h="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('hooks',''))" "$DIST/.codex-plugin/plugin.json")"
      [[ "$h" == "./platforms/codex/hooks.json" ]] && ok ".codex-plugin/plugin.json hooks -> ./platforms/codex/hooks.json" || bad ".codex-plugin/plugin.json hooks points elsewhere" "$h"
    fi
    ;;
  cursor)
    echo "--- cursor ---"
    has .cursor-plugin/plugin.json && ok ".cursor-plugin/plugin.json present" || bad ".cursor-plugin/plugin.json missing"
    has platforms/cursor/hooks.json && ok "platforms/cursor/hooks.json present" || bad "platforms/cursor/hooks.json missing"
    has hooks/hooks.json && bad "hooks/hooks.json is shipped" "Cursor cannot read the Claude-format file and would bind to it by default" || ok "the Claude hooks file is not shipped"
    has mod && bad "mod/ is shipped" "Cursor runs no mod" || ok "no mod"
    if has platforms/cursor/hooks.json; then
      v="$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('version',''))" "$DIST/platforms/cursor/hooks.json")"
      [[ "$v" == "1" ]] && ok "Cursor hooks bundle declares version 1" || bad "Cursor hooks bundle version is not 1" "$v"
    fi
    if has platforms/cursor/mcp.json && has .cursor-plugin/plugin.json; then
      python3 - "$DIST/platforms/cursor/mcp.json" "$DIST/.cursor-plugin/plugin.json" <<'PY' && ok "every \${VAR} in the Cursor mcp.json is a declared plugin variable" || bad "an undeclared \${VAR} in the Cursor mcp.json" "see above"
import json, re, sys
mcp = open(sys.argv[1]).read(); man = json.load(open(sys.argv[2]))
declared = set((man.get("variables") or {}).get("properties", {}).keys())
used = set(re.findall(r'\$\{([A-Z][A-Z0-9_]*)\}', mcp)) - {"CURSOR_PLUGIN_ROOT", "CLAUDE_PLUGIN_ROOT"}
missing = used - declared
for m in sorted(missing): print("    undeclared: " + m)
sys.exit(1 if missing else 0)
PY
    fi
    [[ -d "$DIST/.cursor/rules" ]] && ok ".cursor/rules present" || bad ".cursor/rules missing"
    [[ -d "$DIST/agents" ]] && ok "agents/ present" || bad "agents/ missing"
    ;;
  gemini)
    echo "--- gemini ---"
    has gemini-extension.json && ok "gemini-extension.json present" || bad "gemini-extension.json missing"
    [[ -d "$DIST/.gemini/skills" ]] && ok ".gemini/skills mirror present (dereferenced)" || bad ".gemini/skills missing"
    # Gemini CLI 0.64.0 runs hooks from <extension>/hooks/hooks.json only (loadExtensionHooks
    # reads the `hooks` object of that one path; the manifest cannot point elsewhere). The
    # shipped file must be the GENERATED one from scripts/build-gemini-hooks.sh: Gemini
    # event names, anchored Gemini tool matchers, millisecond timeouts, every command
    # through hooks/gemini-wrap.sh. The Claude file would run `/hooks/x.sh` (Gemini never
    # exports CLAUDE_PLUGIN_ROOT) and misname every event but three.
    if has hooks/hooks.json; then
      ok "hooks/hooks.json present (the generated Gemini file)"
      gem_err="$(python3 - "$DIST" <<'PYG'
import json, os, re, sys
dist = sys.argv[1]
d = json.load(open(os.path.join(dist, "hooks/hooks.json")))
events = {"SessionStart", "SessionEnd", "BeforeAgent", "AfterAgent", "BeforeModel", "AfterModel",
          "BeforeToolSelection", "BeforeTool", "AfterTool", "PreCompress", "Notification"}
errs = []
if "modules" in d:
    errs.append("modules key present (a Claude mods key; the Claude file was shipped)")
hooks = d.get("hooks")
if not isinstance(hooks, dict) or not hooks:
    errs.append("no hooks object")
    hooks = {}
for ev, groups in hooks.items():
    if ev not in events:
        errs.append("event %s is not a Gemini event" % ev)
    for g in groups:
        for h in g.get("hooks", []):
            if "onFailure" in h:
                errs.append("%s: onFailure is a Claude key" % ev)
            cmd = h.get("command", "")
            if "${CLAUDE_PLUGIN_ROOT}" in cmd:
                errs.append("%s: ${CLAUDE_PLUGIN_ROOT} (Gemini never exports it)" % ev)
            if "hooks/gemini-wrap.sh" not in cmd:
                errs.append("%s: command does not run through hooks/gemini-wrap.sh" % ev)
            for m in re.findall(r'\$\{extensionPath\}/([^"\s]+)', cmd):
                if not os.path.exists(os.path.join(dist, m)):
                    errs.append("%s: names %s, which the tree does not ship" % (ev, m))
            t = h.get("timeout")
            if t is not None and (not isinstance(t, int) or t < 1000):
                errs.append("%s: timeout %r is not milliseconds (Gemini's unit)" % (ev, t))
print("; ".join(errs[:4]))
PYG
)"
      [[ -z "$gem_err" ]] && ok "hooks/hooks.json keeps Gemini's shape (events, wrapper, timeouts, shipped scripts)" || bad "hooks/hooks.json breaks a Gemini rule" "$gem_err"
    else
      bad "hooks/hooks.json missing" "Gemini runs hooks from this one path; the generated platforms/gemini/hooks.json must be placed here"
    fi
    has hooks/gemini-wrap.sh && ok "hooks/gemini-wrap.sh present" || bad "hooks/gemini-wrap.sh missing" "every Gemini hook command runs through it"
    has policies/tamirs-superpowers.toml && ok "policies/tamirs-superpowers.toml present (deny rules that hold with hooks disabled)" || bad "policies/tamirs-superpowers.toml missing"
    has platforms/gemini/hooks.json && bad "platforms/gemini/hooks.json is shipped" "the generated file belongs at hooks/hooks.json only" || ok "no second copy of the hooks file"
    has mod && bad "mod/ is shipped" || ok "no mod"
    ;;
  antigravity)
    echo "--- antigravity ---"
    # Antigravity's plugin schema is closed (https://antigravity.google/docs/plugins):
    # plugin.json carries exactly name and description, mcp_config.json exactly mcpServers,
    # skills sit one level under skills/, agents under agents/, and no hooks file exists
    # in the format. None of this is measured against a live binary; the registry lists the
    # surface as unverified and the rules here are the documented schema.
    if has plugin.json; then
      keys="$(python3 -c "import json,sys; print(' '.join(sorted(json.load(open(sys.argv[1])).keys())))" "$DIST/plugin.json")"
      [[ "$keys" == "description name" ]] && ok "plugin.json carries exactly name and description" || bad "plugin.json breaks the closed Antigravity schema" "keys: $keys"
    else
      bad "plugin.json missing"
    fi
    if has mcp_config.json; then
      keys="$(python3 -c "import json,sys; print(' '.join(sorted(json.load(open(sys.argv[1])).keys())))" "$DIST/mcp_config.json")"
      [[ "$keys" == "mcpServers" ]] && ok "mcp_config.json carries exactly mcpServers" || bad "mcp_config.json breaks the Antigravity shape" "keys: $keys"
    else
      bad "mcp_config.json missing"
    fi
    for absent in hooks hooks.json mod platforms .agents .gemini gemini-extension.json; do
      has "$absent" && bad "$absent is shipped" "Antigravity's format has no such thing" || ok "$absent is not shipped"
    done
    deep="$(find "$DIST/skills" -mindepth 3 -name SKILL.md 2>/dev/null | head -2)"
    [[ -d "$DIST/skills" && -z "$deep" ]] && ok "skills sit one level under skills/" || bad "skills are not one level deep" "$(echo "$deep" | tr '\n' ' ')"
    nagents="$(find "$DIST/agents" -maxdepth 1 -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
    [[ "$nagents" -gt 0 ]] && ok "$nagents agents under agents/" || bad "agents/ missing or empty"
    ;;
  opencode)
    echo "--- opencode ---"
    has opencode.json && ok "opencode.json present" || bad "opencode.json missing"
    has AGENTS.md && ok "AGENTS.md present (OpenCode 2 reads only this file)" || bad "AGENTS.md missing"
    [[ -d "$DIST/.opencode" ]] && ok ".opencode adapter present" || bad ".opencode missing"
    has hooks && bad "hooks/ is shipped" "OpenCode executes no shell hook" || ok "no shell hooks"
    has mod && bad "mod/ is shipped" || ok "no mod"
    ;;
  agent-plugins)
    echo "--- agent-plugins ---"
    if has plugin.json; then
      python3 - "$DIST/plugin.json" <<'PY' && ok "root plugin.json has the 1.0.0 \$schema and a conformant name" || bad "root plugin.json is not a conformant Agent Plugins manifest" "see above"
import json, re, sys
d = json.load(open(sys.argv[1])); bad = []
if d.get("$schema") != "https://agent-plugins.org/schemas/1.0.0/plugin.schema.json": bad.append("$schema: %r" % d.get("$schema"))
n = d.get("name", "")
if not re.fullmatch(r"[a-z0-9][a-z0-9.-]{0,62}[a-z0-9]", n) or "--" in n or ".." in n: bad.append("name: %r" % n)
for b in bad: print("    " + b)
sys.exit(1 if bad else 0)
PY
    else bad "root plugin.json missing"; fi
    if has mcp.json; then
      python3 - "$DIST/mcp.json" <<'PY' && ok "mcp.json: stdio server, single-token command rooted at \${PLUGIN_ROOT}, no Claude-only transport name" || bad "mcp.json breaks the Agent Plugins shape" "see above"
import json, sys
d = json.load(open(sys.argv[1])); bad = []
if "$schema" not in d: bad.append("no $schema")
for name, s in d.get("mcpServers", {}).items():
    if s.get("type") not in ("stdio", "streamable-http"): bad.append("%s: type %r (Agent Plugins knows stdio and streamable-http)" % (name, s.get("type")))
    if s.get("type") == "stdio":
        cmd = s.get("command", "")
        # Spec 1.0.0: `command` is one token (a bare name or ./-relative); placeholders
        # expand in args, env values and cwd only. A ./-relative command needs cwd set to
        # ${PLUGIN_ROOT} or it runs relative to wherever the client happens to be.
        if " " in cmd or "${" in cmd: bad.append("%s: command must be a single token without placeholders (%r)" % (name, cmd))
        elif cmd.startswith("./") and s.get("cwd") != "${PLUGIN_ROOT}": bad.append("%s: a ./-relative command needs cwd \"${PLUGIN_ROOT}\"" % name)
for b in bad: print("    " + b)
sys.exit(1 if bad else 0)
PY
    else bad "mcp.json missing"; fi
    for absent in hooks agents mod .claude-plugin .codex-plugin .cursor-plugin; do
      has "$absent" && bad "$absent is shipped" "the portable package carries skills and MCP only" || ok "$absent is not shipped"
    done
    ;;
  *) bad "unknown target" "$TARGET" ;;
esac

echo
echo "passed: $PASS   failed: $FAIL"
[[ "$FAIL" -gt 0 ]] && { printf 'failing:'; printf ' [%s]' "${FAILED[@]}"; echo; exit 1; }
exit 0
