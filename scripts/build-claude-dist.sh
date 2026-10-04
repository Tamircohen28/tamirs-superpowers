#!/usr/bin/env bash
# build-claude-dist.sh — the Claude-only distribution of this plugin, as a directory.
#
# WHAT IT IS FOR
#   Anthropic's plugin directory reads one plugin folder from one tracked branch or
#   tag and holds a submission for review on, among other things, more than 512
#   files, any symbolic link, and every development-only file it cannot vouch for.
#   This repository ships five platforms from one source and carries its tests,
#   docs, evals, fixtures and platform mirrors beside the plugin, so the tree the
#   directory should see is a SUBSET of master, not master.
#
#   This script writes that subset. The release workflow commits its output as a
#   generated commit, tags it `v<version>-claude` (immutable) and moves the tag
#   `claude` (the one the directory tracks) onto it. Nobody develops on that tree:
#   every change lands on master and is rebuilt from it. CI runs this on every
#   pull request, followed by check-claude-dist.sh, so master never merges a
#   change that would break the Claude-only tree. See
#   docs/engineering/build-and-release/directory-distribution.md.
#
# WHAT GOES IN
#   The roots below, copied as regular files (symlinks are dereferenced), with the
#   development-only subtrees pruned; then every file a shipped Markdown file links
#   to relatively, pulled in transitively so no shipped doc points at a 404. A link
#   whose target exists nowhere in the repository is reported and left alone (it
#   was already broken on master). README.md is the directory-specific one from
#   platforms/claude/directory/.
#
# Usage: build-claude-dist.sh <out-dir> [--source <repo-root>] [--force] [--quiet]
#   <out-dir> must not exist, or be empty, unless --force (then it is emptied).
set -euo pipefail

OUT=""; SRC=""; FORCE=0; QUIET=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) SRC="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    --quiet) QUIET=1; shift ;;
    -h|--help) sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; $d'; exit 0 ;;
    *) if [[ -z "$OUT" ]]; then OUT="$1"; shift; else echo "unexpected argument: $1" >&2; exit 2; fi ;;
  esac
done
[[ -n "$OUT" ]] || { echo "usage: build-claude-dist.sh <out-dir> [--source <repo-root>] [--force]" >&2; exit 2; }

SRC="${SRC:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SRC="$(cd "$SRC" && pwd)"
[[ -f "$SRC/.claude-plugin/plugin.json" ]] || { echo "build-claude-dist: $SRC has no .claude-plugin/plugin.json" >&2; exit 1; }

if [[ -e "$OUT" ]]; then
  if [[ -n "$(ls -A "$OUT" 2>/dev/null)" ]]; then
    if [[ "$FORCE" -eq 1 ]]; then rm -rf "${OUT:?}"/* "${OUT:?}"/.[!.]* 2>/dev/null || true
    else echo "build-claude-dist: $OUT is not empty (pass --force to empty it)" >&2; exit 1; fi
  fi
fi
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
case "$OUT" in "$SRC"|"$SRC"/*) ;; esac   # an out-dir inside the repo is fine (build/ is gitignored)

log() { [[ "$QUIET" -eq 1 ]] || echo "$@"; }

# --- 1. roots ---------------------------------------------------------------
# Files and directories shipped whole. Order does not matter.
ROOTS=(
  .claude-plugin/plugin.json
  .mcp.json
  listing/icon.png
  LICENSE
  SECURITY.md
  PRIVACY.md
  plugin-version.json
  hooks
  mod
  agents
  skills
  core
  rules
  output-styles
  templates
  config
  scripts
  platforms/claude
)
# Subtrees and files pruned from the roots above: development-only, or another
# platform's. A path here is relative to the repo root; a bare directory name
# matches that directory at any depth.
PRUNE_DIRS=(evals fixtures eval-viewer __pycache__ .pytest_cache node_modules)
PRUNE_PATHS=(
  scripts/check-branch-literals.sh
  scripts/check-capability-registry.sh
  scripts/check-feature-equivalence.sh
  scripts/check-manifest-declares.sh
  scripts/check-platform-targets.sh
  scripts/check-action-pinning.sh
  platforms/claude/directory
  docs/engineering
  docs/changelog
  docs/user/install/codex.md
  docs/user/install/cursor.md
  docs/user/install/gemini.md
  docs/user/install/opencode.md
  docs/user/platform-setup.md
  docs/user/platform-differences.md
  docs/user/cross-platform-workflow.md
  skills/repo/_contract/templates/legacy-scaffold-templates.md
  scripts/build-claude-dist.sh
  scripts/check-claude-dist.sh
  scripts/build-cursor-commands.sh
  scripts/build-gemini-extension.sh
  scripts/build-opencode-agents.sh
  scripts/build-opencode-commands.sh
  scripts/probe-platform-versions.sh
  scripts/typecheck-mods.sh
  scripts/check-platform-version-pins.sh
  scripts/check-gemini-adapter.sh
  scripts/check-opencode-permission-keys.sh
  scripts/lib/setup-codex.sh
  scripts/lib/setup-cursor.sh
  scripts/lib/setup-gemini.sh
  scripts/lib/setup-opencode.sh
)

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
    log "build-claude-dist: note: $root is absent on this source, skipped"
  fi
done

# The directory-specific README replaces the five-platform one.
cp -L "$SRC/platforms/claude/directory/README.md" "$OUT/README.md"

# --- 2. markdown-link closure ----------------------------------------------
# Every shipped .md may link to a file that is not shipped yet (a doc under docs/,
# say). Pull such targets in from the source, transitively, so the shipped tree is
# self-contained. Targets missing from the source too are listed, not fetched.
# Only a target inside the shipped roots or under docs/user/ is pulled; a link to a
# contributor, engineering or other-platform file (CLAUDE.md, AGENTS.md, CHANGELOG.md,
# docs/engineering/, .cursor-plugin/, the evals and fixtures pruned above, ...) is
# left out and listed, since those are not part of the Claude distribution whatever
# links to them. The changelog and the engineering docs are left out on purpose:
# they are where this repository talks about what it used to do, and the directory's
# scanner reads a sentence such as "no longer reads the token from the environment"
# as a credential read.
CLOSURE_ALLOW="docs/user ${ROOTS[*]}"
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
    # Strip fenced code: a path in a code block is an example, not a link.
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
            # A link to a directory: ship the directory's README or index only.
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
        print(f"build-claude-dist: pulled {len(pulled)} linked file(s) in:")
        for p in sorted(pulled):
            print(f"  + {p}")
    if left_out:
        print(f"build-claude-dist: {len(left_out)} link(s) point at files outside the Claude distribution (left out):")
        for f, t in sorted(left_out):
            print(f"  - {f} -> {t}")
    if broken:
        print(f"build-claude-dist: {len(broken)} link(s) resolve nowhere (already broken on master):")
        for f, t in sorted(broken):
            print(f"  ! {f} -> {t}")
PY

# --- 3. tidy ------------------------------------------------------------------
find "$OUT" -type d -empty -delete
count="$(find "$OUT" -type f | wc -l | tr -d ' ')"
links="$(find "$OUT" -type l | wc -l | tr -d ' ')"
log "build-claude-dist: $count files, $links symlinks -> $OUT"
[[ "$links" -eq 0 ]] || { echo "build-claude-dist: symlinks in the output" >&2; exit 1; }
