#!/usr/bin/env bash
# build-dist.sh — one host's subset of this repository, as a directory.
#
# WHAT IT IS FOR
#   This repository ships to several hosts from one source and carries its tests,
#   engineering docs, evals, fixtures and every other host's adapter beside the plugin.
#   No host should receive the whole tree: Anthropic's plugin directory holds a listing
#   on files it cannot vouch for, Codex's hooks parser rejects the key that names the
#   mod, Cursor reads a different hooks bundle, and a marketplace tarball with five
#   hosts' manifests in it is five times the surface to review. So each host gets a
#   SUBSET, written by this script from a per-target table (roots, prunes, README),
#   then held to that target's rules by check-dist.sh (or, for Claude, by
#   check-claude-dist.sh, whose rules are the directory's).
#
#   build-claude-dist.sh is a thin wrapper around `--target claude`; the release
#   workflow tags that tree (the directory tracks a tag) and attaches the other targets
#   to the GitHub Release as tarballs. CI builds and checks every target on every pull
#   request, so master never merges a change that would break a host's subset.
#   Design: docs/engineering/build-and-release/directory-distribution.md (the Claude
#   tree) and docs/engineering/build-and-release/manifests.md (the one-source manifests).
#
# WHAT GOES IN
#   The target's roots, copied as regular files (symlinks are dereferenced), with the
#   development-only subtrees pruned; then every file a shipped Markdown file links to
#   relatively, pulled in transitively so no shipped doc points at a 404. A link whose
#   target exists nowhere in the repository is reported and left alone (it was already
#   broken on master); a link to a file outside the target's allowed set (another
#   host's docs, the changelog, docs/engineering/) is left out and listed.
#
# Usage: build-dist.sh <out-dir> --target <claude|codex|cursor|gemini|antigravity|opencode|agent-plugins>
#                      [--source <repo-root>] [--force] [--quiet]
#   <out-dir> must not exist, or be empty, unless --force (then it is emptied).
#   --list-targets prints the target names and exits.
set -euo pipefail

OUT=""; SRC=""; FORCE=0; QUIET=0; TARGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) TARGET="$2"; shift 2 ;;
    --source) SRC="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --quiet) QUIET=1; shift ;;
    --list-targets) echo "claude codex cursor gemini antigravity opencode agent-plugins"; exit 0 ;;
    -h|--help) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
    *) if [[ -z "$OUT" ]]; then OUT="$1"; shift; else echo "unexpected argument: $1" >&2; exit 2; fi ;;
  esac
done
usage() { echo "usage: build-dist.sh <out-dir> --target <claude|codex|cursor|gemini|antigravity|opencode|agent-plugins> [--source <repo-root>] [--force] [--quiet]" >&2; exit 2; }
[[ -n "$OUT" && -n "$TARGET" ]] || usage

SRC="${SRC:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SRC="$(cd "$SRC" && pwd)"
[[ -f "$SRC/.claude-plugin/plugin.json" ]] || { echo "build-dist: $SRC has no .claude-plugin/plugin.json" >&2; exit 1; }

log() { [[ "$QUIET" -eq 1 ]] || echo "$@"; }

# --- the per-target table --------------------------------------------------------------
# Every target shares the canonical content (skills, agents where the host reads them,
# core, rules, templates, config, the scripts skills run) and the three policy files.
# What differs is the manifest set, the hooks file, and which docs come along.
COMMON_ROOTS=(LICENSE SECURITY.md PRIVACY.md plugin-version.json skills core rules templates config scripts)
# Development-only subtrees, pruned at any depth for every target.
PRUNE_DIRS=(evals fixtures eval-viewer __pycache__ .pytest_cache node_modules)
# Development-only paths, pruned for every target. Build and check scripts are not
# part of any distribution; other hosts' setup libraries are added per target below.
COMMON_PRUNE=(
  scripts/check-branch-literals.sh scripts/check-capability-registry.sh scripts/check-feature-equivalence.sh
  scripts/check-manifest-declares.sh scripts/check-platform-targets.sh scripts/check-action-pinning.sh
  docs/engineering docs/changelog
  skills/repo/_contract/templates/legacy-scaffold-templates.md
  scripts/build-dist.sh scripts/check-dist.sh scripts/build-claude-dist.sh scripts/check-claude-dist.sh
  scripts/build-cursor-commands.sh scripts/build-gemini-extension.sh scripts/build-opencode-agents.sh
  scripts/build-opencode-commands.sh scripts/build-codex-hooks.sh scripts/build-codex-agents.sh
  scripts/build-cursor-rules.sh scripts/build-manifests.sh scripts/probe-platform-versions.sh
  scripts/typecheck-mods.sh scripts/check-platform-version-pins.sh scripts/check-gemini-adapter.sh
  scripts/check-opencode-permission-keys.sh scripts/build-gemini-hooks.sh scripts/build-antigravity-plugin.sh
  scripts/build-agents-skills.sh scripts/check-skills-ref.sh scripts/check-token-budget.sh
)
ROOTS=(); PRUNE_PATHS=("${COMMON_PRUNE[@]}"); README_SRC="README.md"; CLOSURE_EXTRA="docs/user"
case "$TARGET" in
  claude)
    # Anthropic's plugin directory: the Claude manifest, the mod, the Claude hooks file, no
    # other host's manifest or docs, and the directory-specific README.
    ROOTS=(.claude-plugin/plugin.json listing/icon.png .mcp.json hooks mod agents output-styles platforms/claude "${COMMON_ROOTS[@]}")
    # The Gemini wrapper and its dialect library run only under the Gemini extension.
    PRUNE_PATHS+=(platforms/claude/directory hooks/gemini-wrap.sh hooks/lib/gemini-output.sh
      docs/user/install/codex.md docs/user/install/cursor.md docs/user/install/gemini.md docs/user/install/opencode.md
      docs/user/platform-setup.md docs/user/platform-differences.md docs/user/cross-platform-workflow.md
      scripts/lib/setup-codex.sh scripts/lib/setup-cursor.sh scripts/lib/setup-gemini.sh scripts/lib/setup-opencode.sh)
    README_SRC="platforms/claude/directory/README.md"
    ;;
  codex)
    # Codex loads the root Agent Plugins manifest (extensions.com.openai) or, before
    # 0.147, .codex-plugin/plugin.json; both point hooks at the generated Codex file,
    # which has no `modules` key. The mod, output styles and the Claude hooks file stay
    # out: Codex runs none of them.
    # No Agent Plugins root manifest here: measured on codex-cli 0.163.0, a plugin that
    # carries one has its hook sources emptied before any hooks path is read, so the
    # Codex subset ships the overlay route only.
    ROOTS=(.codex-plugin/plugin.json .agents/plugins/marketplace.json platforms/codex .codex hooks "${COMMON_ROOTS[@]}")
    PRUNE_PATHS+=(hooks/hooks.json
      docs/user/install/claude-code.md docs/user/install/claude-desktop.md docs/user/install/cursor.md docs/user/install/gemini.md docs/user/install/opencode.md
      scripts/lib/setup-claude.sh scripts/lib/setup-cursor.sh scripts/lib/setup-gemini.sh scripts/lib/setup-opencode.sh
      scripts/statusline.sh)
    ;;
  cursor)
    # Cursor prefers .cursor-plugin/plugin.json; its hooks bundle and mcp.json (with the
    # declared plugin variable) live under platforms/cursor. Rules and commands are the
    # generated .cursor/ adapters; agents are read from agents/ directly.
    ROOTS=(.cursor-plugin/plugin.json platforms/cursor .cursor agents hooks "${COMMON_ROOTS[@]}")
    PRUNE_PATHS+=(hooks/hooks.json
      docs/user/install/claude-code.md docs/user/install/claude-desktop.md docs/user/install/codex.md docs/user/install/gemini.md docs/user/install/opencode.md
      scripts/lib/setup-claude.sh scripts/lib/setup-codex.sh scripts/lib/setup-gemini.sh scripts/lib/setup-opencode.sh
      scripts/statusline.sh)
    ;;
  gemini)
    # Gemini CLI reads gemini-extension.json and the .gemini/ adapter (flat skill mirror,
    # translated agents). The mirror's symlinks are dereferenced into copies here, so the
    # tarball is self-contained. Gemini runs hooks from <extension>/hooks/hooks.json and
    # nowhere else (the manifest cannot point elsewhere; measured on 0.64.0), so the
    # Claude file is pruned and the GENERATED platforms/gemini/hooks.json takes its
    # place below, with the deny policies beside it under policies/.
    ROOTS=(gemini-extension.json .gemini platforms/gemini hooks "${COMMON_ROOTS[@]}")
    PRUNE_PATHS+=(hooks/hooks.json platforms/gemini/hooks.json platforms/gemini/policies platforms/gemini/policies.source.json
      docs/user/install/claude-code.md docs/user/install/claude-desktop.md docs/user/install/codex.md docs/user/install/cursor.md docs/user/install/opencode.md
      scripts/lib/setup-claude.sh scripts/lib/setup-codex.sh scripts/lib/setup-cursor.sh scripts/lib/setup-opencode.sh
      scripts/statusline.sh)
    ;;
  opencode)
    # OpenCode reads opencode.json, AGENTS.md and the .opencode/ adapter (agents, commands,
    # the V2 plugin). It executes no shell hook.
    ROOTS=(opencode.json AGENTS.md .opencode platforms/opencode "${COMMON_ROOTS[@]}")
    PRUNE_PATHS+=(
      docs/user/install/claude-code.md docs/user/install/claude-desktop.md docs/user/install/codex.md docs/user/install/cursor.md docs/user/install/gemini.md
      scripts/lib/setup-claude.sh scripts/lib/setup-codex.sh scripts/lib/setup-cursor.sh scripts/lib/setup-gemini.sh
      scripts/statusline.sh)
    ;;
  antigravity)
    # Antigravity's plugin is a closed schema: plugin.json {name, description},
    # mcp_config.json {mcpServers}, skills/<name>/SKILL.md one level deep, agents/*.md,
    # and no hooks file (it runs none). The flat skill set is the .agents/skills mirror
    # dereferenced into copies and moved to skills/ below; the agents are the Gemini
    # translations. Nothing here is measured against a live binary
    # (core/capabilities/platforms.json lists the surface as unverified).
    ROOTS=(platforms/antigravity .agents/skills .gemini/agents core rules templates config scripts/github-mcp.sh LICENSE SECURITY.md PRIVACY.md plugin-version.json)
    PRUNE_PATHS+=(platforms/antigravity/adapter.yaml platforms/antigravity/README.md docs/user/install scripts/lib scripts/statusline.sh)
    README_SRC="platforms/antigravity/README.md"
    ;;
  agent-plugins)
    # The portable package: the Agent Plugins 1.0 root manifest, mcp.json, skills, and
    # what the skills link to. No hooks, no agents, no host manifest — a client that
    # wants more reads its own namespace from plugin.json's extensions.
    # The manifest and mcp.json are generated under platforms/agent-plugins/ (a root
    # plugin.json in the repository makes Codex drop every hook) and moved to the root of
    # this subset below.
    ROOTS=(platforms/agent-plugins skills core rules templates config scripts/github-mcp.sh LICENSE SECURITY.md PRIVACY.md plugin-version.json)
    PRUNE_PATHS+=(docs/user/install scripts/lib scripts/statusline.sh)
    ;;
  *) echo "build-dist: unknown target '$TARGET' (try --list-targets)" >&2; exit 2 ;;
esac

if [[ -e "$OUT" ]]; then
  if [[ -n "$(ls -A "$OUT" 2>/dev/null)" ]]; then
    if [[ "$FORCE" -eq 1 ]]; then rm -rf "${OUT:?}"/* "${OUT:?}"/.[!.]* 2>/dev/null || true
    else echo "build-dist: $OUT is not empty (pass --force to empty it)" >&2; exit 1; fi
  fi
fi
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"

prune_dir_args=()
for d in "${PRUNE_DIRS[@]}"; do prune_dir_args+=(-not -path "*/$d/*" -not -name "$d"); done

copy_one() {
  # $1: path relative to SRC. Regular files only; a symlink is followed to its target.
  local rel="$1" src="$SRC/$1" dst="$OUT/$1"
  [[ -e "$src" ]] || return 0
  for p in "${PRUNE_PATHS[@]}"; do [[ "$rel" == "$p" || "$rel" == "$p"/* ]] && return 0; done
  mkdir -p "$(dirname "$dst")"
  cp -L "$src" "$dst"
}

for root in "${ROOTS[@]}"; do
  if [[ -d "$SRC/$root" ]]; then
    while IFS= read -r f; do copy_one "${f#"$SRC"/}"; done < <(find -L "$SRC/$root" -type f "${prune_dir_args[@]}" | sort)
  elif [[ -f "$SRC/$root" ]]; then
    copy_one "$root"
  else
    log "build-dist: note: $root is absent on this source, skipped"
  fi
done

# The README: the directory-specific one for Claude, the repository's for everyone else.
cp -L "$SRC/$README_SRC" "$OUT/README.md"

# The Agent Plugins package reads its manifest and mcp.json at the package root.
if [[ "$TARGET" == "agent-plugins" && -d "$OUT/platforms/agent-plugins" ]]; then
  mv "$OUT/platforms/agent-plugins/plugin.json" "$OUT/plugin.json"
  mv "$OUT/platforms/agent-plugins/mcp.json" "$OUT/mcp.json"
fi

# Gemini reads only <extension>/hooks/hooks.json: the generated file and the policies.
if [[ "$TARGET" == "gemini" ]]; then
  cp -L "$SRC/platforms/gemini/hooks.json" "$OUT/hooks/hooks.json"
  mkdir -p "$OUT/policies" && cp -L "$SRC"/platforms/gemini/policies/*.toml "$OUT/policies/"
fi

# --- markdown-link closure ---------------------------------------------------------------
# Every shipped .md may link to a file not shipped yet. Pull such targets in from the
# source, transitively, so the shipped tree is self-contained. Only a target inside the
# shipped roots or under docs/user/ is pulled; a link to a contributor, engineering or
# other-host file is left out and listed. The changelog and the engineering docs are
# left out on purpose: they are where this repository talks about what it used to do,
# and a scanner reads a sentence such as "no longer reads the token from the
# environment" as a credential read.
CLOSURE_ALLOW="$CLOSURE_EXTRA ${ROOTS[*]}"
CLOSURE_PRUNE_DIRS="${PRUNE_DIRS[*]}"
CLOSURE_PRUNE_PATHS="${PRUNE_PATHS[*]}"
export CLOSURE_ALLOW CLOSURE_PRUNE_DIRS CLOSURE_PRUNE_PATHS
python3 - "$SRC" "$OUT" "$QUIET" <<'PY'
import os, re, shutil, sys
src, out, quiet = sys.argv[1], sys.argv[2], sys.argv[3] == "1"
allow = os.environ["CLOSURE_ALLOW"].split()
prune_dirs = set(os.environ["CLOSURE_PRUNE_DIRS"].split())
prune_paths = os.environ["CLOSURE_PRUNE_PATHS"].split()
left_out = set()

def shippable(rel):
    parts = rel.split("/")
    if any(p in prune_dirs for p in parts[:-1]):
        return False
    if any(rel == p or rel.startswith(p + "/") for p in prune_paths):
        return False
    return any(rel == a or rel.startswith(a + "/") for a in allow)
link = re.compile(r'(?<!\!)\[[^\]]*\]\(([^)\s]+)(?:\s+"[^"]*")?\)')
img = re.compile(r'!\[[^\]]*\]\(([^)\s]+)')
skip_prefix = ("http://", "https://", "mailto:", "#", "//")
broken, pulled, seen = set(), [], set()

def targets(md_path):
    text = open(md_path, encoding="utf-8", errors="replace").read()
    text = re.sub(r"```.*?```", "", text, flags=re.S)
    for m in list(link.finditer(text)) + list(img.finditer(text)):
        t = m.group(1).strip("<>")
        if t.startswith(skip_prefix) or ":" in t.split("/")[0]:
            continue
        t = t.split("#", 1)[0]
        if not t:
            continue
        yield os.path.normpath(os.path.join(os.path.dirname(md_path), t))

def md_files():
    for d, _, fs in os.walk(out):
        for f in fs:
            if f.endswith(".md"):
                yield os.path.join(d, f)

queue = list(md_files())
while queue:
    md = queue.pop()
    if md in seen:
        continue
    seen.add(md)
    for tgt in targets(md):
        rel = os.path.relpath(tgt, out)
        if rel.startswith(".."):
            broken.add((os.path.relpath(md, out), rel))
            continue
        if os.path.exists(tgt):
            continue
        if not shippable(rel):
            left_out.add((os.path.relpath(md, out), rel))
            continue
        cand = os.path.join(src, rel)
        if os.path.isfile(cand):
            os.makedirs(os.path.dirname(tgt), exist_ok=True)
            shutil.copy(os.path.realpath(cand), tgt)
            pulled.append(rel)
            if tgt.endswith(".md"):
                queue.append(tgt)
        elif os.path.isdir(cand):
            for name in ("README.md", "index.md"):
                c = os.path.join(cand, name)
                if os.path.isfile(c):
                    os.makedirs(tgt, exist_ok=True)
                    shutil.copy(os.path.realpath(c), os.path.join(tgt, name))
                    pulled.append(os.path.join(rel, name))
                    queue.append(os.path.join(tgt, name))
                    break
            else:
                broken.add((os.path.relpath(md, out), rel))
        else:
            broken.add((os.path.relpath(md, out), rel))

if not quiet:
    if pulled:
        print(f"build-dist: pulled {len(pulled)} linked file(s) in:")
        for p in sorted(pulled):
            print(f"  + {p}")
    if left_out:
        print(f"build-dist: {len(left_out)} link(s) point at files outside this distribution (left out):")
        for f, t in sorted(left_out):
            print(f"  - {f} -> {t}")
    if broken:
        print(f"build-dist: {len(broken)} link(s) resolve nowhere (already broken on master):")
        for f, t in sorted(broken):
            print(f"  ! {f} -> {t}")
PY

# --- tidy ----------------------------------------------------------------------------------
find "$OUT" -type d -empty -delete
count="$(find "$OUT" -type f | wc -l | tr -d ' ')"
links="$(find "$OUT" -type l | wc -l | tr -d ' ')"
# Antigravity's layout, applied after the link closure so every relative link was
# resolved against the source layout: manifest and MCP config at the root, the flat
# skill mirror at skills/, the translated agents at agents/. The flat layout sits one
# directory shallower than the source tree, so a skill's relative link into core/ or
# rules/ resolves one level short there; Antigravity reads SKILL.md for the model, which
# the host resolves by name, not by path, so the prose link is informational.
if [[ "$TARGET" == "antigravity" ]]; then
  mv "$OUT/platforms/antigravity/plugin.json" "$OUT/plugin.json"
  mv "$OUT/platforms/antigravity/mcp_config.json" "$OUT/mcp_config.json"
  rmdir "$OUT/platforms/antigravity" "$OUT/platforms" 2>/dev/null || true
  if [[ -d "$OUT/.agents/skills" ]]; then
    mv "$OUT/.agents/skills" "$OUT/skills"; rmdir "$OUT/.agents" 2>/dev/null || true
  fi
  if [[ -d "$OUT/.gemini/agents" ]]; then
    mv "$OUT/.gemini/agents" "$OUT/agents"; rmdir "$OUT/.gemini" 2>/dev/null || true
  fi
fi

log "build-dist[$TARGET]: $count files, $links symlinks -> $OUT"
[[ "$links" -eq 0 ]] || { echo "build-dist: symlinks in the output" >&2; exit 1; }
