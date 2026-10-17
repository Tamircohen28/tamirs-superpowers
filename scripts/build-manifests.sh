#!/usr/bin/env bash
# build-manifests.sh — generate every per-host plugin manifest from one source.
#
# Usage:
#   bash scripts/build-manifests.sh [repo-root] [--check] [--verbose]
#   bash scripts/build-manifests.sh -h | --help
#
# Generates, from .claude-plugin/plugin.json (identity), plugin-version.json (version)
# and platforms/manifests.source.json (per-target overlay):
#   plugin.json                   — root Agent Plugins 1.0 manifest (Codex >= 0.147,
#                                   Cursor, Copilot CLI, Kiro); carries the Codex
#                                   settings under extensions.com.openai
#   mcp.json                      — root Agent Plugins MCP file (stdio, ${PLUGIN_ROOT})
#   .codex-plugin/plugin.json     — Codex overlay, kept as the pre-0.147 fallback
#   .cursor-plugin/plugin.json    — Cursor manifest, with the `variables` schema
#   platforms/cursor/mcp.json     — Cursor MCP file (plugin variables, ${CURSOR_PLUGIN_ROOT})
#   gemini-extension.json         — Gemini CLI extension manifest
#
# --check regenerates into a temp dir and diffs, so CI can fail on drift without writing
# to the working tree. The Claude manifest (.claude-plugin/plugin.json) and the Claude
# MCP file (.mcp.json) are inputs, never outputs.
#
# WHY THIS EXISTS
#   Six manifests carried the same name, author, homepage, repository, license and
#   keywords by hand, and three of them carried the same skills list. Every identity
#   edit was a six-file edit and the files drifted: the Claude manifest said one
#   description, the Codex one another, and nobody could say which was deliberate.
#   plugin-version.json already made the VERSION single-sourced; this makes the rest of
#   the identity single-sourced the same way, with the per-target differences written
#   down in one overlay file where a reader can see they are deliberate.
#
# WHY A ROOT plugin.json AT ALL
#   Agent Plugins 1.0 is the manifest Codex, Cursor, Copilot CLI and Kiro all read. On
#   Codex it is the primary manifest from 0.147 and, when extensions.com.openai is
#   present, it REPLACES .codex-plugin/plugin.json entirely (the two are not merged),
#   so the Codex settings must be complete in both places. The generator writes both
#   from the same overlay so they cannot disagree.
#
# WHY CURSOR GETS ITS OWN MCP FILE
#   In a Cursor plugin, a ${VAR} in an MCP file is a plugin variable that must be
#   declared under the manifest's `variables` schema; an undeclared one fails the
#   directory validator. The Claude MCP file's ${user_config.*} is not a declarable
#   name, so Cursor gets a generated file whose one variable is declared, and this
#   script refuses to write an MCP file that uses a variable the manifest does not
#   declare.
#
# WHY THE ROOT MCP FILE CARRIES NO CREDENTIAL ENV
#   Agent Plugins 1.0 expands only ${PLUGIN_ROOT} and ${PLUGIN_DATA}, says `env`
#   values are visible package data and defines no credential mechanism (that is
#   client-managed). Any other placeholder stays a literal string, which the github
#   server would then present as its credential and fail on its first call. An absent
#   value is better: the launcher refuses to start and says what is missing.
#
# Exit 0 on success; 1 if --check finds drift; 2 on a malformed or inconsistent source.
set -euo pipefail

usage() { sed -n '2,20p' "$0" | sed 's/^#[[:space:]]\{0,1\}//'; exit "${1:-0}"; }

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

for src in .claude-plugin/plugin.json plugin-version.json platforms/manifests.source.json; do
  [[ -f "$ROOT/$src" ]] || { printf 'error: missing source %s under %s\n' "$src" "$ROOT" >&2; exit 2; }
done

DEST="$ROOT"
if [[ "$CHECK" == true ]]; then
  DEST="$(mktemp -d)"
  trap 'rm -rf "$DEST"' EXIT
fi

# The generated files, relative to the plugin root. The order is the order --check
# reports drift in.
OUTPUTS=(
  plugin.json
  mcp.json
  .codex-plugin/plugin.json
  .cursor-plugin/plugin.json
  platforms/cursor/mcp.json
  gemini-extension.json
)

# --- render ------------------------------------------------------------------
# One Python pass: read the three sources, build each manifest as an ordered object,
# validate what can be validated from the tree, write 2-space JSON with a trailing
# newline. Key order is the order the overlay lists keys in, after the identity block,
# so a diff stays a one-line diff.
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
version = load("plugin-version.json").get("version")
ov = load("platforms/manifests.source.json")

errors = []
def err(msg): errors.append(msg)

if not isinstance(version, str) or not re.match(r"^\d+\.\d+\.\d+([-+][0-9A-Za-z.-]+)?$", version):
    err("plugin-version.json .version is not semver: %r" % (version,))
for k in ("name", "description", "author", "homepage", "repository", "license", "keywords", "skills"):
    if k not in canon:
        err(".claude-plugin/plugin.json lacks the identity field %r" % k)
for k in ("agent_plugins", "codex", "cursor", "gemini"):
    if k not in ov:
        err("platforms/manifests.source.json lacks the %r section" % k)
if errors:
    sys.exit("\n".join("error: " + e for e in errors))

name = canon["name"]
if not re.match(r"^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$", name) or "--" in name or ".." in name:
    err("name %r is not a valid Agent Plugins name (lowercase, digits, hyphens, periods; no -- or ..)" % name)

def keywords(section):
    drop = set(section.get("keywords_exclude", []))
    return [k for k in canon["keywords"] if k not in drop]

def description(section):
    return section.get("description", canon["description"])

def author():
    a = canon["author"]
    out = {}
    for k in ("name", "email", "url"):
        if k in a:
            out[k] = a[k]
    extra = set(a) - {"name", "email", "url"}
    if extra:
        err("author carries fields Agent Plugins rejects: %s" % sorted(extra))
    return out

def with_manifest_keys(obj, section):
    for k, v in section.get("manifest", {}).items():
        obj[k] = canon["skills"] if (k == "skills" and v is None) else v
    return obj

def legacy(section):
    obj = {
        "name": name,
        "version": version,
        "description": description(section),
        "author": author(),
        "homepage": canon["homepage"],
        "repository": canon["repository"],
        "license": canon["license"],
        "keywords": keywords(section),
    }
    return with_manifest_keys(obj, section)

ap = ov["agent_plugins"]
root_manifest = {
    "$schema": ap["plugin_schema"],
    "name": name,
    "version": version,
    "description": description(ap),
    "homepage": canon["homepage"],
    "repository": canon["repository"],
    "author": author(),
    "license": canon["license"],
    "keywords": keywords(ap),
}
if ap.get("emit_codex_extension", True):
    root_manifest["extensions"] = ap["extensions"]

root_mcp = {"$schema": ap["mcp_schema"], "mcpServers": ap["mcpServers"]}

codex = legacy(ov["codex"])
cursor = legacy(ov["cursor"])
cursor_mcp = {"mcpServers": ov["cursor"]["mcpServers"]}
gem = ov["gemini"]
gemini = with_manifest_keys({"name": name, "version": version, "description": description(gem)}, gem)

outputs = {
    "plugin.json": root_manifest,
    "mcp.json": root_mcp,
    ".codex-plugin/plugin.json": codex,
    ".cursor-plugin/plugin.json": cursor,
    "platforms/cursor/mcp.json": cursor_mcp,
    "gemini-extension.json": gemini,
}

# --- validation against the tree -------------------------------------------------
# A path this run writes counts as present: the Cursor manifest names the Cursor MCP
# file, and both come out of this one pass.
def rel_paths(value):
    """Every './'-prefixed string reachable from a value."""
    if isinstance(value, str):
        return [value] if value.startswith("./") else []
    if isinstance(value, list):
        return [p for v in value for p in rel_paths(v)]
    if isinstance(value, dict):
        return [p for v in value.values() for p in rel_paths(v)]
    return []

def check_paths(label, value, skip=()):
    for p in rel_paths({k: v for k, v in value.items() if k not in skip} if isinstance(value, dict) else value):
        if ".." in p.split("/"):
            err("%s names %s, which escapes the plugin root" % (label, p))
        elif p[2:] not in outputs and not os.path.exists(os.path.join(root, p[2:])):
            err("%s names %s, which does not exist in this tree" % (label, p))

# `interface` is listing metadata (logo, screenshots) that the directory build supplies;
# the tree is not required to hold it, so it is not path-checked here.
check_paths("plugin.json extensions.com.openai", root_manifest.get("extensions", {}).get("com.openai", {}), skip=("interface",))
check_paths("mcp.json", root_mcp)
check_paths(".codex-plugin/plugin.json", codex, skip=("interface",))
check_paths(".cursor-plugin/plugin.json", cursor)
check_paths("gemini-extension.json", gemini)

# Agent Plugins mcp.json rules: closed top level, `type` on every server, a stdio
# `command` that is one token (bare name or ./-relative) with no placeholder, no env
# entry named after a placeholder, and only the two placeholders the spec expands.
for sname, s in root_mcp["mcpServers"].items():
    t = s.get("type")
    if t not in ("stdio", "streamable-http", "sse"):
        err("mcp.json server %r: type must be stdio, streamable-http or sse, not %r" % (sname, t))
    if t == "stdio":
        cmd = s.get("command", "")
        if not cmd or " " in cmd or "${" in cmd or not (cmd.startswith("./") or "/" not in cmd):
            err("mcp.json server %r: command must be a bare name or a ./-relative path with no placeholder, not %r" % (sname, cmd))
        for k in s.get("env", {}):
            if k in ("PLUGIN_ROOT", "PLUGIN_DATA"):
                err("mcp.json server %r: env may not name %s" % (sname, k))
        for field in ("args", "env", "cwd"):
            for ph in re.findall(r"\$\{([^}]*)\}", json.dumps(s.get(field, ""))):
                if ph not in ("PLUGIN_ROOT", "PLUGIN_DATA"):
                    err("mcp.json server %r: ${%s} in %s is not a placeholder Agent Plugins expands; it would stay literal" % (sname, ph, field))
        if "env" in s:
            for k, v in s["env"].items():
                if v == "":
                    err("mcp.json server %r: env %s is empty" % (sname, k))

# Cursor rule: every ${VAR} in the Cursor MCP file is a declared plugin variable.
declared = set(((cursor.get("variables") or {}).get("properties") or {}).keys())
used = set(re.findall(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\}", json.dumps(cursor_mcp)))
for v in sorted(used - {"CURSOR_PLUGIN_ROOT", "CLAUDE_PLUGIN_ROOT"} - declared):
    err("platforms/cursor/mcp.json uses ${%s}, which .cursor-plugin/plugin.json does not declare under variables.properties" % v)
for v in sorted(declared):
    spec = cursor["variables"]["properties"][v]
    if "default" in spec:
        err(".cursor-plugin/plugin.json variable %s carries a default; a credential-bearing variable must not" % v)
    for k in ("title", "description"):
        if not spec.get(k):
            err(".cursor-plugin/plugin.json variable %s lacks a %s" % (v, k))

# Codex settings must agree between the root extension and the fallback overlay, since
# whichever one Codex reads is the only one it reads.
ext = root_manifest.get("extensions", {}).get("com.openai", {})
if ext:
    for k in ("hooks", "interface"):
        if ext.get(k) != codex.get(k):
            err("extensions.com.openai.%s differs from .codex-plugin/plugin.json %s" % (k, k))

if errors:
    sys.exit("\n".join("error: " + e for e in errors))

for rel, obj in outputs.items():
    path = os.path.join(dest, rel)
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        f.write(json.dumps(obj, indent=2, ensure_ascii=False) + "\n")
    if verbose:
        print("wrote %s" % rel)
PY

# --- check: diff the regenerated files against the tree -------------------------
if [[ "$CHECK" == true ]]; then
  drift=0
  for f in "${OUTPUTS[@]}"; do
    if [[ ! -f "$ROOT/$f" ]]; then
      printf 'DRIFT: %s is missing from the tree\n' "$f" >&2
      drift=1
    elif ! diff -u "$ROOT/$f" "$DEST/$f" >&2; then
      printf 'DRIFT: %s differs from what the sources generate\n' "$f" >&2
      drift=1
    elif [[ "$VERBOSE" == true ]]; then
      printf 'ok: %s\n' "$f"
    fi
  done
  if (( drift )); then
    printf 'Manifests have drifted from their sources. Regenerate: bash scripts/build-manifests.sh .\n' >&2
    exit 1
  fi
  printf 'manifests: %d generated files match their sources\n' "${#OUTPUTS[@]}"
else
  printf 'manifests: wrote %d files under %s\n' "${#OUTPUTS[@]}" "$ROOT"
fi
