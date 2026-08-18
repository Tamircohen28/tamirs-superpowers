#!/usr/bin/env bash
# build-gemini-extension.sh — generate the Gemini adapter surface from canonical sources.
#
# Usage:
#   bash scripts/build-gemini-extension.sh [repo-root] [--check]
#   bash scripts/build-gemini-extension.sh -h | --help
#
# Generates:
#   .gemini/skills/<name>  — symlink to skills/<domain>/<name>
#   .gemini/agents/<n>.md  — translated from agents/<n>.md
#
# --check regenerates into a temp dir and compares, so CI can fail on drift without
# writing to the working tree. Drift includes entries whose canonical source was
# deleted; a normal run prunes those.
#
# WHY THIS EXISTS
#   Gemini CLI discovers skills exactly ONE level below a skills root — measured on
#   0.55.1, `skills/flat/SKILL.md` is found and `skills/domain/nested/SKILL.md` is
#   not. Canonical skills here are two levels deep (`skills/<domain>/<name>/`), so
#   every Gemini skills root pointed at the canonical tree resolves to ZERO skills,
#   silently. A flat mirror is the only shape Gemini can read, and it cannot be the
#   canonical tree itself: Claude Code and OpenCode both discover `skills/`
#   recursively, so flat entries beside the domains would resolve every skill twice
#   under two names.
#
# WHY SYMLINKS AND NOT COPIES
#   Verified on 0.55.1 that Gemini follows symlinks for skill discovery, both at the
#   workspace tier (`.gemini/skills/`) and through `gemini skills install --path`.
#   Copying instead would duplicate ~1.3M of skill content into the repo and put
#   every future skill edit in the diff twice. With symlinks there is exactly one
#   copy of every skill, so the mirror cannot drift in CONTENT at all — only in
#   membership, which --check still enforces.
#
# WHY .gemini/skills AND NOT THE EXTENSION ROOT
#   `gemini extensions install <git-url>` has no subdirectory flag, so an installed
#   extension's root is the repo root and its skills root is the canonical
#   `skills/` — unreadable, per above, and not relocatable (manifest fields naming
#   another path are silently ignored). `.gemini/skills/` is read natively at the
#   WORKSPACE tier instead, so a contributor with the repo cloned gets every skill
#   with no install step, and a user gets all of them from ONE command:
#   `gemini skills install <url> --path .gemini/skills`.
#
# WHY AGENTS ARE TRANSLATED AND NOT MIRRORED
#   Gemini's agent schema requires `tools` as an ARRAY of Gemini tool names. The
#   canonical files carry Claude's names as a comma STRING, which fails validation
#   with `tools.0: Invalid tool name` — measured. `model:` is omitted entirely: a
#   Claude alias like `sonnet` passes load-time validation and then fails at
#   invocation, which is worse than absent.
#
# Exit 0 on success; 1 if --check finds drift; 2 on a malformed or colliding source.
set -euo pipefail

usage() { sed -n '2,12p' "$0" | sed 's/^#[[:space:]]\{0,1\}//'; exit "${1:-0}"; }
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage 0; fi

ROOT="."
CHECK=false
for arg in "$@"; do
  case "$arg" in
    --check) CHECK=true ;;
    -*) echo "Unknown flag: $arg" >&2; exit 1 ;;
    *) ROOT="$arg" ;;
  esac
done
ROOT="$(cd "$ROOT" && pwd)"

SKILL_SRC="$ROOT/skills"
AGENT_SRC="$ROOT/agents"
REAL_DEST="$ROOT/.gemini"

DEST="$REAL_DEST"
if [[ "$CHECK" == true ]]; then
  DEST="$(mktemp -d)"
  trap 'rm -rf "$DEST"' EXIT
fi
mkdir -p "$DEST/skills" "$DEST/agents"

# --- skills: flat symlink mirror -------------------------------------------
# The glob is deliberately exactly two levels: skills/<domain>/<name>/SKILL.md.
# That is also what keeps the gold fixtures out — they sit deeper, at
# skills/repo/_contract/fixtures/<fixture>/skills/... — with no exclusion list to
# maintain.
skill_count=0
skill_names=()
declare -a seen_names=()
declare -a seen_sources=()

while IFS= read -r skillmd; do
  [[ -e "$skillmd" ]] || continue
  dir="$(dirname "$skillmd")"
  name="$(basename "$dir")"
  domain="$(basename "$(dirname "$dir")")"

  # Flattening makes cross-domain name collisions real: two domains shipping the
  # same skill name would silently overwrite one another in the mirror, and the
  # loser would vanish from Gemini with nothing to say so.
  for i in "${!seen_names[@]}"; do
    if [[ "${seen_names[$i]}" == "$name" ]]; then
      echo "ERROR: skill name collision on flattening: '$name' exists in both" >&2
      echo "         ${seen_sources[$i]}" >&2
      echo "         skills/$domain/$name" >&2
      echo "       Gemini's skill namespace is flat; rename one of them." >&2
      exit 2
    fi
  done
  seen_names+=("$name")
  seen_sources+=("skills/$domain/$name")

  ln -sfn "../../skills/$domain/$name" "$DEST/skills/$name"
  skill_names+=("$name")
  skill_count=$((skill_count + 1))
done < <(find "$SKILL_SRC" -mindepth 3 -maxdepth 3 -name SKILL.md 2>/dev/null | sort)

if (( skill_count == 0 )); then
  echo "ERROR: no canonical skills found at skills/<domain>/<name>/SKILL.md" >&2
  echo "       Refusing to generate an empty mirror — an empty .gemini/skills/ is" >&2
  echo "       indistinguishable from a working one until a user finds no skills." >&2
  exit 2
fi

# --- agents: translated frontmatter ----------------------------------------
# Canonical Claude tool name -> Gemini tool name. Every value below was validated
# against Gemini 0.55.1's agent loader, which rejects unknown names outright with
# `tools.0: Invalid tool name`. Unlisted canonical tools (notably `mcp__*` server
# tools) have no Gemini equivalent and are reported rather than silently dropped.
map_tool() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    read)            echo read_file ;;
    grep)            echo search_file_content ;;
    glob)            echo glob ;;
    bash)            echo run_shell_command ;;
    write)           echo write_file ;;
    edit|multiedit)  echo replace ;;
    websearch)       echo google_web_search ;;
    webfetch)        echo web_fetch ;;
    *)               echo "" ;;
  esac
}

# Read one frontmatter scalar. Restricted to the frontmatter block so a body line
# like "description: ..." cannot be picked up.
fm_get() {
  local file="$1" key="$2"
  awk -v k="^${key}:[[:space:]]*" '
    NR == 1 && /^---[[:space:]]*$/ { infm = 1; next }
    infm && /^---[[:space:]]*$/    { exit }
    infm && $0 ~ k                 { sub(k, ""); print; exit }
  ' "$file"
}

agent_count=0
agent_files=()
unmapped_report=()

if [[ -d "$AGENT_SRC" ]]; then
  for f in "$AGENT_SRC"/*.md; do
    [[ -e "$f" ]] || continue
    base="$(basename "$f")"

    head -1 "$f" | grep -q '^---[[:space:]]*$' || {
      echo "ERROR: $f has no YAML frontmatter (line 1 must be '---')" >&2; exit 2; }

    name=$(fm_get "$f" name)
    desc=$(fm_get "$f" description)
    tools=$(fm_get "$f" tools)
    [[ -n "$name" ]] || name="${base%.md}"
    [[ -n "$desc" ]] || { echo "ERROR: $f has no 'description:' — Gemini requires it" >&2; exit 2; }

    body_start=$(awk 'NR>1 && /^---[[:space:]]*$/ {print NR+1; exit}' "$f")
    [[ -n "$body_start" ]] || body_start=1

    mapped=()
    if [[ -n "$tools" ]]; then
      while IFS= read -r t; do
        t="$(printf '%s' "$t" | tr -d '[:space:]')"
        [[ -n "$t" ]] || continue
        g="$(map_tool "$t")"
        if [[ -n "$g" ]]; then
          mapped+=("$g")
        else
          unmapped_report+=("$base: $t")
        fi
      # printf with a trailing newline, not bare '%s': `read` discards a final
      # unterminated line, which would silently drop the LAST tool of every list.
      done < <(printf '%s\n' "$tools" | tr ',' '\n')
    fi

    {
      echo "---"
      echo "name: $name"
      echo "description: $desc"
      if ((${#mapped[@]})); then
        printf 'tools: [%s]\n' "$(IFS=', '; echo "${mapped[*]}")"
      fi
      # No `model:` by design — see the header note.
      echo "---"
      echo
      echo "<!-- GENERATED FILE — DO NOT EDIT."
      echo "     Source:    agents/$base"
      echo "     Generator: scripts/build-gemini-extension.sh"
      echo "     Regenerate: make gemini-extension -->"
      echo
      # Re-anchor relative links. The canonical file sits at agents/<n>.md, one
      # level below the repo root, so its links read `](../core/...)`. The
      # generated file sits at .gemini/agents/<n>.md, TWO levels down, where the
      # same text resolves to a path that does not exist. Every relative link
      # gains one `../` because the depth gained exactly one level.
      # Only `](../` is rewritten: absolute paths and http(s) links must not move.
      # Known limit: the rewrite is not fence-aware, so a relative link inside a
      # fenced code SAMPLE would be rewritten too. No canonical agent has one
      # today (checked), and the link assertion in tests/test-gemini-adapter.sh
      # would fail loudly rather than corrupt silently — but if one ever appears,
      # this needs to skip fenced regions.
      tail -n "+$body_start" "$f" | sed 's|](\.\./|](../../|g'
    } > "$DEST/agents/$base"

    agent_files+=("$base")
    agent_count=$((agent_count + 1))
  done
fi

# --- prune entries whose canonical source is gone --------------------------
pruned=0
for existing in "$DEST"/skills/*; do
  [[ -e "$existing" || -L "$existing" ]] || continue
  eb="$(basename "$existing")"
  found=false
  for n in "${skill_names[@]:-}"; do [[ "$n" == "$eb" ]] && found=true && break; done
  if [[ "$found" == false ]]; then rm -rf "$existing"; pruned=$((pruned + 1)); fi
done
for existing in "$DEST"/agents/*.md; do
  [[ -e "$existing" ]] || continue
  eb="$(basename "$existing")"
  found=false
  for g in "${agent_files[@]:-}"; do [[ "$g" == "$eb" ]] && found=true && break; done
  if [[ "$found" == false ]]; then rm -f "$existing"; pruned=$((pruned + 1)); fi
done

if ((${#unmapped_report[@]})); then
  echo "note: canonical tools with no Gemini equivalent (omitted from the adapter):" >&2
  printf '  %s\n' "${unmapped_report[@]}" >&2
fi

# --- drift check ------------------------------------------------------------
# Skills are compared as name -> link target rather than by content: `diff -r`
# would follow the symlinks and compare the canonical trees against themselves,
# which passes no matter how wrong the mirror is.
link_manifest() {
  local d="$1" e
  for e in "$d"/skills/*; do
    [[ -e "$e" || -L "$e" ]] || continue
    printf '%s -> %s\n' "$(basename "$e")" "$(readlink "$e" 2>/dev/null || echo '<not-a-symlink>')"
  done | sort
}

if [[ "$CHECK" == true ]]; then
  drift=""
  if ! diff -u <(link_manifest "$REAL_DEST") <(link_manifest "$DEST") >/dev/null 2>&1; then
    drift="skills"
  fi
  if ! diff -r -q "$REAL_DEST/agents" "$DEST/agents" >/dev/null 2>&1; then
    drift="${drift:+$drift and }agents"
  fi
  if [[ -n "$drift" ]]; then
    {
      echo "ERROR: .gemini/ is out of sync with canonical sources ($drift)."
      echo "       These files are GENERATED — fix skills/ or agents/, then run: make gemini-extension"
      echo
      diff -u <(link_manifest "$REAL_DEST") <(link_manifest "$DEST") || true
      diff -r -u "$REAL_DEST/agents" "$DEST/agents" || true
    } >&2
    exit 1
  fi
  echo "Gemini adapter in sync ($skill_count skill(s), $agent_count agent(s))"
  exit 0
fi

echo "Generated Gemini adapter: $skill_count skill symlink(s), $agent_count agent adapter(s) in .gemini/${pruned:+ (pruned $pruned stale)}"
