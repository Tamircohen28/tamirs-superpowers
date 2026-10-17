#!/usr/bin/env bash
# build-codex-agents.sh — generate .codex/agents/*.toml from canonical agents/*.md.
#
# Usage:
#   bash scripts/build-codex-agents.sh [repo-root] [--check]
#   bash scripts/build-codex-agents.sh -h | --help
#
# Example:
#   bash scripts/build-codex-agents.sh . --check    # what CI runs (make codex-agents-check)
#
# --check regenerates into a temp dir and diffs, so CI can fail on drift without
# writing to the working tree. Drift includes adapters whose canonical source was
# deleted; a normal run prunes those.
#
# WHY THIS EXISTS
#   A Codex plugin manifest has no `agents` field, so the ten canonical agents/*.md
#   have no plugin route on Codex (core/capabilities/platforms.json, codex.subagents).
#   Codex DOES read custom subagents — as standalone TOML files, one agent each, in
#   `~/.codex/agents/` or a repo's `.codex/agents/` (Codex docs: Agent configuration →
#   Subagents). That is a REPO-LEVEL route: a project that adopts this toolkit and
#   commits the generated files gets every specialist agent in Codex, while the
#   plugin-shipped route stays an open upstream request. This generator produces that
#   tree from the canonical files so the two cannot drift.
#
# WHAT IS EMITTED, AND WHAT DELIBERATELY IS NOT
#   The documented required fields: `name` (the frontmatter name — Codex treats the
#   field, not the filename, as authoritative, so the two are kept equal), `description`
#   and `developer_instructions` (the Markdown body). `model` and the
#   `model_reasoning_*` fields are documented but NOT emitted: the canonical `model:`
#   is a Claude alias with no Codex meaning, and pinning a Codex model here would put a
#   model name in a shipped file that nothing in this repo re-validates. An agent
#   without `model` inherits `agents.default_subagent_model`, which is the user's call.
#
# WHY `[features] shell_tool = false`
#   The canonical `tools:` line is an ALLOWLIST: an agent listing `Read, Grep, Glob`
#   is read-only. Codex has no per-agent tool allowlist; what it has is a documented
#   set of capability REDUCTIONS an agent file may set to false — `features.shell_tool`,
#   `features.apps`, `features.plugins`, `features.memories`,
#   `features.request_permissions_tool`. The one that maps onto the canonical list is
#   `shell_tool`: an allowlist with no Bash (or shell) entry becomes `shell_tool = false`,
#   the same way scripts/build-opencode-agents.sh turns the allowlist into explicit
#   `permission:` denies. Nothing else in the canonical frontmatter maps onto the other
#   four reductions, so they are never emitted — only documented keys, and only when
#   the canonical file says so. Read/Edit/Write are not shell, so an edit-capable agent
#   without Bash still loses the shell, which is what its allowlist says.
#
# WHY THE BODY IS A MULTI-LINE LITERAL STRING
#   TOML's `'''...'''` form takes the Markdown verbatim — no escaping of backslashes
#   or quotes, so the body reads back exactly as written. The one thing it cannot
#   contain is `'''` itself; a body that does is emitted as a basic `"""..."""`
#   string with `\` and `"` escaped instead, and tests/test-generators.sh round-trips
#   such a body. Relative links in the body (`](../core/...)`, written for a file under
#   agents/) are re-based to repo-root-relative (`](core/...)`), because the string is
#   read by an agent whose working directory is the repo root, not rendered from a
#   path. Every emitted file is parsed back with python3's tomllib when python3 >= 3.11
#   is present; an unparsable file is a build failure, not a warning.
#
# Exit 0 on success; 1 if --check finds drift; 2 on a malformed canonical file or
# an emitted file that does not parse as TOML.
set -euo pipefail

usage() { sed -n '2,13p' "$0" | sed 's/^#[[:space:]]\{0,1\}//'; exit "${1:-0}"; }
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage 0; fi

ROOT="."
CHECK=false
for arg in "$@"; do
  case "$arg" in
    --check) CHECK=true ;;
    -*) echo "Unknown flag: $arg" >&2; usage 1 ;;
    *) ROOT="$arg" ;;
  esac
done
ROOT="$(cd "$ROOT" && pwd)"

SRC="$ROOT/agents"
REAL_DEST="$ROOT/.codex/agents"
[[ -d "$SRC" ]] || { echo "No agents/ directory — nothing to build"; exit 0; }

DEST="$REAL_DEST"
if [[ "$CHECK" == true ]]; then
  DEST="$(mktemp -d)"
  trap 'rm -rf "$DEST"' EXIT
fi
mkdir -p "$DEST"

# Read one frontmatter scalar from a canonical agent file. Restricted to the
# frontmatter block so a body line like "description: ..." cannot be picked up.
fm_get() {
  local file="$1" key="$2"
  awk -v k="^${key}:[[:space:]]*" '
    NR == 1 && /^---[[:space:]]*$/ { infm = 1; next }
    infm && /^---[[:space:]]*$/    { exit }
    infm && $0 ~ k                 { sub(k, ""); print; exit }
  ' "$file"
}

# A TOML basic (double-quoted) one-line string: escape backslash, quote, and the
# control characters a frontmatter scalar could plausibly carry.
toml_basic() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g'
}

# True when the canonical allowlist grants a shell. `tools` may be empty (no
# allowlist: everything inherited, nothing reduced).
grants_shell() {
  local t
  while IFS= read -r t; do
    t="$(printf '%s' "$t" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')"
    case "$t" in bash|shell) return 0 ;; esac
  # printf with a trailing newline: `read` discards a final unterminated line,
  # which would silently drop the LAST tool of every allowlist.
  done < <(printf '%s\n' "$1" | tr ',' '\n')
  return 1
}

count=0
generated=()

for f in "$SRC"/*.md; do
  [[ -e "$f" ]] || continue
  base="$(basename "$f")"

  head -1 "$f" | grep -q '^---[[:space:]]*$' || {
    echo "ERROR: $f has no YAML frontmatter (line 1 must be '---')" >&2; exit 2; }

  name=$(fm_get "$f" name)
  desc=$(fm_get "$f" description)
  tools=$(fm_get "$f" tools)
  [[ -n "$name" ]] || { echo "ERROR: $f has no 'name:' — Codex requires it" >&2; exit 2; }
  [[ -n "$desc" ]] || { echo "ERROR: $f has no 'description:' — Codex requires it" >&2; exit 2; }
  [[ "$name" == "${base%.md}" ]] || {
    echo "ERROR: $f: frontmatter name '$name' differs from filename — Codex keys on the name field, keep them equal" >&2; exit 2; }
  case "$name" in
    *[!A-Za-z0-9_-]*) echo "ERROR: $f: name '$name' must be [A-Za-z0-9_-] to be a safe filename" >&2; exit 2 ;;
  esac

  # Body = everything after the closing --- of the frontmatter, leading/trailing
  # blank lines dropped, relative links re-based from agents/ to the repo root.
  body_start=$(awk 'NR>1 && /^---[[:space:]]*$/ {print NR+1; exit}' "$f")
  [[ -n "$body_start" ]] || body_start=1
  body="$(tail -n "+$body_start" "$f" | sed 's|](\.\./|](|g' | awk '
    { lines[NR] = $0; if ($0 !~ /^[[:space:]]*$/) { if (!first) first = NR; last = NR } }
    END { for (i = first; i <= last; i++) print lines[i] }')"

  features=""
  if [[ -n "$tools" ]] && ! grants_shell "$tools"; then
    features="shell_tool = false"
  fi

  {
    echo "# GENERATED FILE — DO NOT EDIT."
    echo "#   Source:     agents/$base"
    echo "#   Generator:  scripts/build-codex-agents.sh"
    echo "#   Regenerate: make codex-agents"
    echo
    echo "name = \"$(toml_basic "$name")\""
    echo "description = \"$(toml_basic "$desc")\""
    echo
    if [[ "$body" == *"'''"* ]]; then
      # Literal strings cannot contain ''' — fall back to a basic multi-line string.
      echo 'developer_instructions = """'
      printf '%s\n' "$body" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
      echo '"""'
    else
      echo "developer_instructions = '''"
      printf '%s\n' "$body"
      echo "'''"
    fi
    if [[ -n "$features" ]]; then
      echo
      echo "[features]"
      echo "$features"
    fi
  } > "$DEST/$name.toml"

  generated+=("$name.toml")
  count=$((count + 1))
done

# Prune adapters whose canonical source is gone, so a deleted agent does not linger.
pruned=0
for existing in "$DEST"/*.toml; do
  [[ -e "$existing" ]] || continue
  eb="$(basename "$existing")"
  found=false
  for g in "${generated[@]:-}"; do [[ "$g" == "$eb" ]] && found=true && break; done
  if [[ "$found" == false ]]; then
    rm -f "$existing"
    pruned=$((pruned + 1))
  fi
done

# Parse every emitted file back. tomllib is stdlib from python3.11; an older
# python3 (or none) degrades to a stated note, never to a silent pass.
if python3 -c 'import tomllib' >/dev/null 2>&1; then
  if ! python3 -I - "$DEST" <<'PY'
import sys, tomllib, pathlib
dest = pathlib.Path(sys.argv[1]); bad = 0
for p in sorted(dest.glob("*.toml")):
    try:
        data = tomllib.loads(p.read_text(encoding="utf-8"))
    except tomllib.TOMLDecodeError as e:
        print(f"ERROR: {p.name} is not valid TOML: {e}", file=sys.stderr); bad += 1; continue
    for k in ("name", "description", "developer_instructions"):
        if not isinstance(data.get(k), str) or not data[k]:
            print(f"ERROR: {p.name}: required field '{k}' missing or empty", file=sys.stderr); bad += 1
    if data.get("name") != p.stem:
        print(f"ERROR: {p.name}: name field '{data.get('name')}' does not match filename", file=sys.stderr); bad += 1
    if "model" in data or any(k.startswith("model_") for k in data):
        print(f"ERROR: {p.name}: a model field was emitted; this generator never emits one", file=sys.stderr); bad += 1
    for k in data.get("features", {}):
        if k not in {"shell_tool", "apps", "plugins", "memories", "request_permissions_tool"}:
            print(f"ERROR: {p.name}: features.{k} is not a documented Codex reduction", file=sys.stderr); bad += 1
sys.exit(1 if bad else 0)
PY
  then
    echo "ERROR: generated Codex agent TOML failed validation (see above)" >&2
    exit 2
  fi
else
  echo "note: python3 with tomllib (3.11+) not found — emitted TOML was not parsed back" >&2
fi

if [[ "$CHECK" == true ]]; then
  if [[ ! -d "$REAL_DEST" ]] || ! diff -r -q "$REAL_DEST" "$DEST" >/dev/null 2>&1; then
    {
      echo "ERROR: .codex/agents/ is out of sync with agents/."
      echo "       These files are GENERATED — fix agents/*.md, then run: make codex-agents"
      echo
      if [[ -d "$REAL_DEST" ]]; then diff -r -u "$REAL_DEST" "$DEST" || true; else echo "  .codex/agents/ does not exist"; fi
    } >&2
    exit 1
  fi
  echo "Codex agent adapters in sync ($count agent(s))"
  exit 0
fi

suffix=""; [[ "$pruned" -gt 0 ]] && suffix=" (pruned $pruned stale)"
echo "Generated $count Codex agent adapter(s) in .codex/agents/$suffix"
