#!/usr/bin/env bash
# gate-writes.sh — classify and gate every file an approved retro would write.
#
# Usage:
#   bash gate-writes.sh [--headless] [--repo <path>] <path>...
#   bash gate-writes.sh --help
#
# retro writes nothing until the user approves its proposal (SKILL.md step 3).
# Approval in chat is not the whole gate: each file it would then create or
# edit is classified here and asked of scripts/resolve-permission.sh (ADR 004
# D1, D2, D4; audit other-skills F3) BEFORE the first write:
#
#   framework policy   core/** or rules/** of this plugin (or of a checkout of
#                      it): blocked, always — a proposal only, never an edit
#   policy.edit        R4  host settings and permission files: ~/.claude/settings*.json,
#                          <repo>/.claude/settings*.json, ~/.codex/config.toml,
#                          ~/.gemini/settings.json, ~/.config/opencode/**, the
#                          plugin's own hooks/ ... (the catalog's path list)
#   config.global.write R4 any other global agent config: ~/.claude/** (CLAUDE.md,
#                          hooks/, agents/, commands/), ~/.codex/**, ~/.gemini/**,
#                          ~/.cursor/**, <repo>/.git/hooks/**, <repo>/.git/config
#   workflow.edit      R4  <repo>/.github/workflows/**
#   file.write.outside_repo R3  anything else outside the repo, including the
#                          project memory dir ~/.claude/projects/<p>/memory/
#   file.write.repo    R1  everything else inside the repo
#
# One JSON object per path on stdout:
#   {"path", "action", "verdict": allow|ask|deny, "decision": write|ask|blocked,
#    "reason", "allow_with"}
# decision "write": go ahead. "ask": write it only after the user says yes to
# THAT file in chat (name the path and the action); with --headless (no human
# in the session) an ask is a deny. "blocked": do not write it; tell the user
# the reason and the setting in allow_with.
#
# --headless  no human present (an orchestrated or `-p` run): ask => deny (D2)
# --repo      the checkout (default: the git top level of the working directory)
#
# A resolver that is missing, fails or prints something unparseable blocks the
# path (fail closed, D4). The resolver is found from this file's own location
# (<plugin root>/skills/toolkit/retro/scripts/), never from the environment.
#
# Exit: 0 when nothing is blocked; 3 when at least one path is blocked; 2 on
# a usage error.
#
# Example:
#   bash skills/toolkit/retro/scripts/gate-writes.sh .claude/memory/lesson.md ~/.claude/CLAUDE.md
set -uo pipefail

usage() { sed -n '2,/^set -uo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; $d'; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PLUGIN_DIR="$(cd "$SCRIPT_DIR/../../../.." && pwd -P)"
RESOLVER="$PLUGIN_DIR/scripts/resolve-permission.sh"

HEADLESS=""
REPO=""
PATHS=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help) usage; exit 0 ;;
    --headless) HEADLESS=1 ;;
    --repo) shift; [ $# -gt 0 ] || { echo "error: --repo needs a path" >&2; exit 2; }; REPO="$1" ;;
    --repo=*) REPO="${1#*=}" ;;
    --) shift; PATHS+=("$@"); break ;;
    -*) echo "error: unknown flag $1" >&2; usage >&2; exit 2 ;;
    *) PATHS+=("$1") ;;
  esac
  shift
done
[ "${#PATHS[@]}" -gt 0 ] || { echo "error: name at least one path retro would write" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "error: python3 is required" >&2; exit 2; }

if [ -z "$REPO" ]; then
  REPO="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"
fi

# classify <abs-realpath> — prints "<action>\t<why>" (action "framework" = blocked).
classify() {
  python3 -I -S - "$1" "$REPO" "$PLUGIN_DIR" "$HOME" <<'PYCLASSIFY'
import fnmatch, os, sys
path, repo, plugin, home = sys.argv[1:5]
repo = os.path.realpath(repo)
plugin = os.path.realpath(plugin)
home = os.path.realpath(home)

def under(root, p):
    return p == root or p.startswith(root.rstrip("/") + "/")

def rel(root, p):
    return os.path.relpath(p, root)

def is_framework(root):
    return (os.path.isfile(os.path.join(root, "core", "permissions", "actions.json"))
            and os.path.isdir(os.path.join(root, "rules")))

def out(action, why):
    print("%s\t%s" % (action, why))
    sys.exit(0)

for root in {plugin, repo}:
    if under(root, path) and is_framework(root):
        r = rel(root, path)
        if r.split("/")[0] in ("core", "rules"):
            out("framework", "framework policy (%s): retro proposes it, never edits it" % r)
        if r.split("/")[0] == "hooks" and root == plugin:
            out("policy.edit", "the plugin's own guard hooks")

POLICY_HOME = [".config/tamirs-superpowers/**", ".local/state/tamirs-superpowers/**",
               ".claude/plugins/cache/**", ".claude/settings*.json", ".gemini/settings.json",
               ".gemini/policies/**", ".gemini/extensions/tamirs-superpowers/**", ".codex/config.toml",
               ".codex/hooks*", ".codex/rules/**", ".codex/plugins/**", ".cursor/hooks.json",
               ".cursor/cli-config.json", ".cursor/permissions.json", ".config/opencode/**",
               ".config/gh/**", ".gitconfig"]
POLICY_REPO = [".tamirs-superpowers/**", ".claude/settings*.json", ".gemini/**", ".cursor/hooks.json",
               "opencode.json", "opencode.jsonc", ".opencode/**"]

def match(r, pats):
    return any(fnmatch.fnmatchcase(r, p) or (p.endswith("/**") and (r == p[:-3] or r.startswith(p[:-2])))
               for p in pats)

if under(repo, path):
    r = rel(repo, path)
    if match(r, POLICY_REPO):
        out("policy.edit", "repo permission/host settings (%s)" % r)
    if r.startswith(".github/workflows/"):
        out("workflow.edit", "a CI workflow (%s)" % r)
    if r.startswith(".git/hooks/") or r == ".git/config":
        out("config.global.write", "git config or hooks that run code (%s)" % r)
    out("file.write.repo", "inside the repo (%s)" % r)

if under(home, path):
    r = rel(home, path)
    if match(r, POLICY_HOME):
        out("policy.edit", "host settings or permission files (~/%s)" % r)
    if fnmatch.fnmatchcase(r, ".claude/projects/*/memory/*") or fnmatch.fnmatchcase(r, ".claude/projects/*/memory"):
        out("file.write.outside_repo", "project memory outside the repo (~/%s)" % r)
    if r.split("/")[0] in (".claude", ".codex", ".gemini", ".cursor", ".agents"):
        out("config.global.write", "global agent config (~/%s)" % r)
out("file.write.outside_repo", "outside the repo (%s)" % path)
PYCLASSIFY
}

# realpath_of <path> — the realpath, resolving the nearest existing parent for a
# file that does not exist yet (retro creates memory files).
realpath_of() { python3 -I -S -c 'import os,sys; print(os.path.realpath(os.path.expanduser(sys.argv[1])))' "$1"; }

# field <json> <key>
field() {
  python3 -I -S -c 'import json,sys
try:
    v = json.loads(sys.argv[1]).get(sys.argv[2])
except Exception:
    v = None
if isinstance(v, dict):
    parts = ([v["once"]] if v.get("once") else []) + list(v.get("durable") or []) + ([v["note"]] if v.get("note") else [])
    v = "; ".join(parts)
print("" if v is None else v)' "$1" "$2" 2>/dev/null || true
}

emit() {  # emit <path> <action> <verdict> <decision> <reason> <allow_with>
  python3 -I -S -c 'import json,sys
k = ["path", "action", "verdict", "decision", "reason", "allow_with"]
print(json.dumps(dict(zip(k, sys.argv[1:7]))))' "$@"
}

BLOCKED=0
for p in "${PATHS[@]}"; do
  case "$p" in /*|'~'*) ;; *) p="$PWD/$p" ;; esac
  abs="$(realpath_of "$p")"
  line="$(classify "$abs")"
  action="${line%%$'\t'*}"
  why="${line#*$'\t'}"
  if [ "$action" = framework ]; then
    emit "$abs" "$action" deny blocked "$why" "none: open a separate, reviewed change for it"
    BLOCKED=$((BLOCKED + 1)); continue
  fi
  v=""
  if [ -f "$RESOLVER" ]; then
    v="$(bash "$RESOLVER" --action "$action" --skill retro --target "$abs" --repo "$REPO" \
          ${HEADLESS:+--headless} --json 2>/dev/null)" || v=""
  fi
  verdict="$(field "$v" verdict)"
  case "$verdict" in
    allow) emit "$abs" "$action" allow write "$why" "" ;;
    ask)   emit "$abs" "$action" ask ask "$why — $(field "$v" reason)" "$(field "$v" setting_that_would_allow)" ;;
    deny)  emit "$abs" "$action" deny blocked "$why — $(field "$v" reason)" "$(field "$v" setting_that_would_allow)"
           BLOCKED=$((BLOCKED + 1)) ;;
    *)     emit "$abs" "$action" deny blocked "$why — the permission resolver is missing or failed (fail closed, ADR 004 D4)" ""
           BLOCKED=$((BLOCKED + 1)) ;;
  esac
done

[ "$BLOCKED" -eq 0 ] || exit 3
exit 0
