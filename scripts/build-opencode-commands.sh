#!/usr/bin/env bash
# build-opencode-commands.sh — generate .opencode/commands/*.md from canonical skills/*/*/SKILL.md.
#
# Usage:
#   bash scripts/build-opencode-commands.sh [repo-root] [--check]
#   bash scripts/build-opencode-commands.sh -h | --help
#
# --check regenerates into a temp dir and diffs, so CI can fail on drift without
# writing to the working tree. Drift includes commands whose canonical skill was
# deleted or made internal; a normal run prunes those.
#
# WHY THIS EXISTS
#   OpenCode users reach this toolkit's skills through the narrowest door it has.
#   `docs/user/install/opencode.md` tells them to "name the skill explicitly" — so
#   every skill is discoverable only by already knowing it exists. OpenCode has a
#   real command surface (`/name`, listed in the TUI) and this repo was not using it.
#
# WHY IT IS A TRANSLATION AND NOT A COPY
#   An OpenCode command is a flat markdown file whose BODY IS A PROMPT TEMPLATE, not
#   a skill: `.opencode/commands/<name>.md`, frontmatter `description`/`agent`/
#   `model`/`subtask`, body sent to the model with `$ARGUMENTS` interpolated
#   (https://opencode.ai/docs/commands/). A SKILL.md body is instructions for an
#   already-loaded skill. So each command is a thin launcher that names its skill;
#   the skill itself stays canonical and is not duplicated.
#
# WHY `description` IS DERIVED AND NOT COPIED
#   A canonical `description` is written for TRIGGERING — it opens "Use when …" and
#   carries trigger phrases, up to 1536 characters of them. That is the right shape
#   for auto-invocation and the wrong shape for a command palette, where the user has
#   already typed `/name` and the trigger phrases are noise. The derivation is
#   mechanical, never invented: strip a leading "Use when ", cut at the first sentence
#   boundary, cap at 200 characters. No new prose is written for any skill.
#
# WHY INTERNAL SKILLS ARE SKIPPED
#   `user-invocable: false` is this repo's "not on the slash surface" tier
#   (changelog-review, docs-review, mcp-pagination — reachable from a parent skill via
#   the Skill tool, hidden from users). Emitting commands for them would contradict
#   the tier model on exactly the surface the tier is about.
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
REAL_DEST="$ROOT/.opencode/commands"

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

# One python pass emits a NUL-delimited stream of (name, category, brief) so the
# YAML is parsed by a real parser rather than by sed. A malformed frontmatter file
# exits 2 here rather than silently producing a command with an empty description.
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
    # description is single-quoted YAML; a literal quote is doubled per the YAML spec.
    printf "description: '%s'\n" "${brief//\'/\'\'}"
    echo "---"
    echo
    echo "<!-- GENERATED FILE — DO NOT EDIT."
    echo "     Source:     ${relpath}"
    echo "     Generator:  scripts/build-opencode-commands.sh"
    echo "     Regenerate: make opencode-commands -->"
    echo
    echo "Use the \`${name}\` skill from the tamirs-superpowers toolkit."
    echo
    echo "If it is not already loaded, read \`${relpath}\` and follow it exactly —"
    echo "it is authoritative and this command deliberately does not restate it."
    echo
    echo "Arguments (may be empty): \$ARGUMENTS"
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
      echo "ERROR: .opencode/commands/ is out of sync with skills/."
      echo "       These files are GENERATED — fix the SKILL.md, then run: make opencode-commands"
      echo
      diff -r -u "$REAL_DEST" "$DEST" || true
    } >&2
    exit 1
  fi
  echo "OpenCode commands in sync ($count command(s))"
  exit 0
fi

echo "Generated $count OpenCode command(s) in .opencode/commands/${pruned:+ (pruned $pruned stale)}"
