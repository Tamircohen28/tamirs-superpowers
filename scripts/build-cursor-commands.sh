#!/usr/bin/env bash
# build-cursor-commands.sh — generate .cursor/commands/*.md from canonical skills/*/*/SKILL.md.
#
# Usage:
#   bash scripts/build-cursor-commands.sh [repo-root] [--check]
#   bash scripts/build-cursor-commands.sh -h | --help
#
# --check regenerates into a temp dir and diffs, so CI can fail on drift without
# writing to the working tree. Drift includes commands whose canonical skill was
# deleted or made internal; a normal run prunes those.
#
# WHY THIS EXISTS
#   #179's E6. The `slash_commands` capability row recorded the gap precisely:
#   "Cursor plugins do support a commands component, discovered from commands/ when
#   the manifest names no path -- this repo has no commands/ directory and no
#   commands key, so it ships zero of them." What a Cursor user saw under `/` were
#   this plugin's skills, never a repo-provided command. This closes that.
#
# WHY IT IS A TRANSLATION AND NOT A COPY
#   A Cursor command is a flat markdown file with optional YAML frontmatter, read
#   from the plugin's commands directory (https://cursor.com/docs/reference/plugins).
#   A SKILL.md body is instructions for an already-loaded skill. So each command is a
#   thin launcher that names its skill; the skill itself stays canonical and is never
#   duplicated -- the same shape as scripts/build-opencode-commands.sh, which this
#   deliberately mirrors rather than inventing a second idiom.
#
# WHY THE FRONTMATTER IS `name` + `description` AND NOTHING ELSE
#   Those are the two fields Cursor documents for a command, and they are all that is
#   emitted. `name` is stated explicitly rather than left to filename derivation
#   because the documented example does so. The OpenCode generator's `agent`/`model`/
#   `subtask` fields are OpenCode's, not Cursor's, and are NOT carried over.
#
# WHY THERE IS NO $ARGUMENTS LINE
#   The OpenCode command template ends with "Arguments (may be empty): $ARGUMENTS"
#   because OpenCode documents that interpolation. Cursor's plugin reference documents
#   NO argument interpolation for commands. Emitting a `$ARGUMENTS` placeholder here
#   would ship a literal, uninterpolated string into every command body -- a promise
#   the surface does not keep. If Cursor documents an interpolation syntax later, this
#   is the one place to add it.
#
# WHY `description` IS DERIVED AND NOT COPIED
#   A canonical `description` is written for TRIGGERING -- it opens "Use when ..." and
#   carries trigger phrases, up to 1536 characters of them. That is the right shape for
#   auto-invocation and the wrong shape for a command palette, where the user has
#   already typed `/name`. The derivation is mechanical, never invented: strip a leading
#   "Use when ", cut at the first sentence boundary, cap at 200 characters.
#
# WHY INTERNAL SKILLS ARE SKIPPED
#   `user-invocable: false` is this repo's "not on the slash surface" tier
#   (changelog-review, docs-review, mcp-pagination). Emitting commands for them would
#   contradict the tier model on exactly the surface the tier is about.
#
# Exit 0 on success; 1 if --check finds drift; 2 on a malformed canonical file.
set -euo pipefail

usage() { sed -n '2,9p' "$0" | sed 's/^#[[:space:]]\{0,1\}//'; exit "${1:-0}"; }
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage 0; fi

ROOT="."
CHECK=false
for arg in "$@"; do
  case "$arg" in
    --check) CHECK=true ;;
    -*) echo "unknown flag: $arg" >&2; usage 2 ;;
    *) ROOT="$arg" ;;
  esac
done

ROOT="$(cd "$ROOT" && pwd)"
SRC_GLOB="$ROOT/skills"
REAL_DEST="$ROOT/.cursor/commands"

if [[ ! -d "$SRC_GLOB" ]]; then
  echo "ERROR: no skills/ directory at $ROOT" >&2
  exit 2
fi

command -v python3 >/dev/null 2>&1 || { echo "ERROR: python3 is required" >&2; exit 2; }

if [[ "$CHECK" == true ]]; then
  DEST="$(mktemp -d)"
  trap 'rm -rf "$DEST"' EXIT
else
  DEST="$REAL_DEST"
fi
mkdir -p "$DEST"

# One python pass emits a NUL-delimited stream of (name, relpath, brief) so the YAML is
# parsed by a real parser rather than by sed. A malformed frontmatter file exits 2 here
# rather than silently producing a command with an empty description.
emit_rows() {
  python3 - "$SRC_GLOB" <<'PY'
import sys, os, glob, re
try:
    import yaml
except ImportError:
    sys.stderr.write("ERROR: pyyaml is required (pip install -r scripts/requirements-validate.txt)\n")
    sys.exit(2)

root = sys.argv[1]
def brief(desc):
    d = ' '.join((desc or '').split())
    d = re.sub(r'^[Uu]se when ', '', d)
    m = re.search(r'(?<=[a-z0-9)\]])\.\s+(?=[A-Z])', d)
    if m:
        d = d[:m.start() + 1]
    if len(d) > 200:
        d = d[:200].rsplit(' ', 1)[0] + '…'
    return (d[0].upper() + d[1:]) if d else d

rows = []
for f in sorted(glob.glob(os.path.join(root, '*', '*', 'SKILL.md'))):
    txt = open(f, encoding='utf-8').read()
    if not txt.startswith('---'):
        sys.stderr.write("ERROR: no frontmatter in %s\n" % f)
        sys.exit(2)
    try:
        fm = yaml.safe_load(txt.split('---', 2)[1]) or {}
    except Exception as e:
        sys.stderr.write("ERROR: unparseable frontmatter in %s: %s\n" % (f, e))
        sys.exit(2)
    if fm.get('user-invocable', True) is False:
        continue
    name = fm.get('name') or os.path.basename(os.path.dirname(f))
    # Cursor documents command names as lowercase kebab-case; every canonical skill
    # name already is one, so this asserts rather than rewrites -- a name that needed
    # mangling would be a SKILL.md bug, not something to paper over here.
    if not re.fullmatch(r'[a-z0-9]+(-[a-z0-9]+)*', name):
        sys.stderr.write("ERROR: %s has name %r, which is not lowercase kebab-case\n" % (f, name))
        sys.exit(2)
    rel = os.path.relpath(f, os.path.dirname(root))
    b = brief(fm.get('description', ''))
    if not b:
        sys.stderr.write("ERROR: %s has no description to derive from\n" % f)
        sys.exit(2)
    rows.append((name, rel, b))

for name, rel, b in rows:
    sys.stdout.write('%s\0%s\0%s\0' % (name, rel, b))
PY
}

generated=()
count=0

while IFS= read -r -d '' name && IFS= read -r -d '' relpath && IFS= read -r -d '' brief; do
  base="${name}.md"
  {
    echo "---"
    echo "name: ${name}"
    # description is single-quoted YAML; a literal quote is doubled per the YAML spec.
    printf "description: '%s'\n" "${brief//\'/\'\'}"
    echo "---"
    echo
    echo "<!-- GENERATED FILE — DO NOT EDIT."
    echo "     Source:     ${relpath}"
    echo "     Generator:  scripts/build-cursor-commands.sh"
    echo "     Regenerate: make cursor-commands -->"
    echo
    echo "Use the \`${name}\` skill from the tamirs-superpowers toolkit."
    echo
    echo "If it is not already loaded, read \`${relpath}\` and follow it exactly —"
    echo "it is authoritative and this command deliberately does not restate it."
  } > "$DEST/$base"
  generated+=("$base")
  count=$((count + 1))
done < <(emit_rows)

if (( count == 0 )); then
  echo "ERROR: no user-invocable skills found — refusing to prune every command" >&2
  exit 2
fi

# Prune commands whose canonical skill is gone or has become internal.
pruned=0
for existing in "$DEST"/*.md; do
  [[ -e "$existing" ]] || continue
  eb="$(basename "$existing")"
  found=false
  for g in "${generated[@]:-}"; do [[ "$g" == "$eb" ]] && found=true && break; done
  if [[ "$found" == false ]]; then
    rm -f "$existing"
    pruned=$((pruned + 1))
  fi
done

if [[ "$CHECK" == true ]]; then
  if ! diff -r -q "$REAL_DEST" "$DEST" >/dev/null 2>&1; then
    {
      echo "ERROR: .cursor/commands/ is out of sync with skills/."
      echo "       These files are GENERATED — fix the SKILL.md, then run: make cursor-commands"
      echo
      diff -r -u "$REAL_DEST" "$DEST" || true
    } >&2
    exit 1
  fi
  echo "Cursor commands in sync ($count command(s))"
  exit 0
fi

echo "Generated $count Cursor command(s) in .cursor/commands/${pruned:+ (pruned $pruned stale)}"
