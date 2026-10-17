#!/usr/bin/env bash
# build-antigravity-plugin.sh — generate the Antigravity CLI plugin files.
#
# Usage:
#   bash scripts/build-antigravity-plugin.sh [repo-root] [--check] [--verbose]
#   bash scripts/build-antigravity-plugin.sh -h | --help
#
# Generates, from .claude-plugin/plugin.json (identity) and the `antigravity`
# section of platforms/manifests.source.json (overlay):
#   platforms/antigravity/plugin.json       — {name, description} and nothing else
#   platforms/antigravity/mcp_config.json   — the github stdio server
#
# --check regenerates into a temp dir and diffs, so CI can fail on drift without
# writing to the working tree.
#
# WHY THIS EXISTS
#   Antigravity CLI (`agy`) is Google's successor to Gemini CLI for consumer tiers
#   (retired 2026-06-18). Its native plugin is a folder: a required plugin.json,
#   optional mcp_config.json and hooks.json, and skills/<name>/SKILL.md,
#   agents/<name>.md, rules/<name>.md beside them; workspace plugins live in
#   .agents/plugins/, global ones in ~/.gemini/config/plugins/. The plugin.json
#   schema is CLOSED — `name` (required, ^[a-zA-Z0-9-_]+$) and `description`,
#   `additionalProperties: false` — so it cannot be the Agent Plugins root
#   plugin.json (which requires `$schema`) and cannot carry version, author or
#   keywords. Two closed schemas means two files, and a generated one cannot
#   drift from the canonical identity.
#
# WHAT IS DELIBERATELY NOT GENERATED
#   hooks.json. Google says hooks carry over from Gemini extensions "at launch"
#   without 1:1 parity; one third-party source says `agy` loads hooks but does
#   not fire them. Neither was measured here (no `agy` binary is available in
#   this environment and the CLI is not open source). A hooks file that is
#   loaded and never fired is worse than none: it reads as a guard that is not
#   one. The Gemini extension's generated hooks (platforms/gemini/hooks.json)
#   are what `agy plugin import gemini` would carry over, once that is verified.
#
# WHAT IS UNVERIFIED IN WHAT IS GENERATED
#   mcp_config.json's documented stdio shape is {command, args, env, cwd} with
#   absolute example paths and no plugin-root placeholder (nothing like Gemini's
#   ${extensionPath}). The generated file uses a path relative to the plugin
#   root; whether `agy` resolves it against the plugin directory is recorded as
#   unverified in platforms/antigravity/README.md and the install doc.
#
# Exit 0 on success; 1 if --check finds drift; 2 on a malformed source.
set -euo pipefail

usage() { sed -n '2,15p' "$0" | sed 's/^#[[:space:]]\{0,1\}//'; exit "${1:-0}"; }

ROOT="."
CHECK=false
VERBOSE=false
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage 0 ;;
    --check) CHECK=true ;;
    -v|--verbose) VERBOSE=true ;;
    -*) printf 'Unknown flag: %s\n' "$arg" >&2; usage 1 ;;
    *) ROOT="$arg" ;;
  esac
done
ROOT="$(cd "$ROOT" && pwd)"

command -v python3 >/dev/null 2>&1 || { printf 'error: python3 is required (it renders the JSON)\n' >&2; exit 2; }
for src in .claude-plugin/plugin.json platforms/manifests.source.json; do
  [[ -f "$ROOT/$src" ]] || { printf 'error: missing source %s under %s\n' "$src" "$ROOT" >&2; exit 2; }
done

OUTPUTS=(platforms/antigravity/plugin.json platforms/antigravity/mcp_config.json)
DEST="$ROOT"
if [[ "$CHECK" == true ]]; then
  DEST="$(mktemp -d)"
  trap 'rm -rf "$DEST"' EXIT
fi

python3 - "$ROOT" "$DEST" "$VERBOSE" <<'PY' || exit 2
import json, os, re, sys

root, dest, verbose = sys.argv[1], sys.argv[2], sys.argv[3] == "true"

def load(rel):
    with open(os.path.join(root, rel), encoding="utf-8") as f:
        try:
            return json.load(f)
        except ValueError as e:
            sys.exit("error: %s is not valid JSON: %s" % (rel, e))

canon = load(".claude-plugin/plugin.json")
ov = load("platforms/manifests.source.json").get("antigravity")
errors = []
def err(m): errors.append(m)

if not isinstance(ov, dict):
    sys.exit("error: platforms/manifests.source.json has no `antigravity` section")
name = canon.get("name", "")
if not re.fullmatch(r"[a-zA-Z0-9-_]+", name or ""):
    err("name %r does not match Antigravity's ^[a-zA-Z0-9-_]+$" % name)
desc = ov.get("plugin_description") or canon.get("description", "")
if not isinstance(desc, str) or not desc.strip():
    err("no description: set antigravity.plugin_description or the canonical description")

servers = ov.get("mcpServers")
if not isinstance(servers, dict) or not servers:
    err("antigravity.mcpServers must be a non-empty object")
    servers = {}
for sname, s in servers.items():
    if "command" in s:
        for k in s:
            if k not in ("command", "args", "env", "cwd"):
                err("mcpServers.%s: %r is not a documented stdio field (command, args, env, cwd)" % (sname, k))
        for a in s.get("args", []):
            if "${" in a:
                err("mcpServers.%s: %r uses a placeholder; Antigravity documents none" % (sname, a))
            if a.endswith(".sh") and not os.path.isfile(os.path.join(root, a)):
                err("mcpServers.%s: %s does not exist in this tree" % (sname, a))
        for k, v in (s.get("env") or {}).items():
            if re.search(r"(ghp|gho|ghu|ghs|github_pat)_[A-Za-z0-9_]{20,}", str(v)):
                err("mcpServers.%s: env %s carries a credential-shaped literal" % (sname, k))
    elif "serverUrl" in s:
        for k in s:
            if k not in ("serverUrl", "headers", "env"):
                err("mcpServers.%s: %r is not a documented remote field (serverUrl, headers)" % (sname, k))
    else:
        err("mcpServers.%s: needs `command` (stdio) or `serverUrl` (remote); legacy url/httpUrl are not accepted by Antigravity" % sname)

if errors:
    sys.exit("\n".join("error: " + e for e in errors))

outputs = {
    "platforms/antigravity/plugin.json": {"name": name, "description": desc},
    "platforms/antigravity/mcp_config.json": {"mcpServers": servers},
}
for rel, obj in outputs.items():
    path = os.path.join(dest, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(json.dumps(obj, indent=2, ensure_ascii=False) + "\n")
    if verbose:
        print("wrote %s" % rel)
PY

if [[ "$CHECK" == true ]]; then
  drift=0
  for f in "${OUTPUTS[@]}"; do
    if [[ ! -f "$ROOT/$f" ]]; then
      printf 'DRIFT: %s is missing from the tree\n' "$f" >&2; drift=1
    elif ! diff -u "$ROOT/$f" "$DEST/$f" >&2; then
      printf 'DRIFT: %s differs from what its sources generate\n' "$f" >&2; drift=1
    fi
  done
  if (( drift )); then
    printf 'Regenerate: bash scripts/build-antigravity-plugin.sh .\n' >&2
    exit 1
  fi
  printf 'antigravity plugin: %d generated files match their sources\n' "${#OUTPUTS[@]}"
  exit 0
fi
printf 'antigravity plugin: wrote %d files under platforms/antigravity/\n' "${#OUTPUTS[@]}"
