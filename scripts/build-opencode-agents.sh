#!/usr/bin/env bash
# build-opencode-agents.sh — generate .opencode/agent/*.md from canonical agents/*.md.
#
# Usage:
#   bash scripts/build-opencode-agents.sh [repo-root] [--check]
#   bash scripts/build-opencode-agents.sh -h | --help
#
# --check regenerates into a temp dir and diffs, so CI can fail on drift without
# writing to the working tree. Drift includes adapters whose canonical source was
# deleted; a normal run prunes those.
#
# WHY THIS EXISTS
#   OpenCode validates config strictly and refuses to start on a bad field, and its
#   agent frontmatter genuinely differs from the canonical Claude-shaped one:
#     - canonical `tools: Read, Grep, Bash` is a comma string; OpenCode has no such
#       field shape, and its `tools` object is deprecated in the published schema
#       ("@deprecated Use 'permission' field instead" — https://opencode.ai/config.json,
#       $defs.AgentConfig.properties.tools).
#     - canonical `model: sonnet` is an alias; OpenCode wants a provider-prefixed id.
#     - canonical `name:` is not an AgentConfig property at all — OpenCode derives the
#       agent id from the FILENAME.
#   So the canonical files cannot be copied, they are translated. The translation is
#   committed so a user installing from a clone needs no build step.
#
# WHY `permission:` AND NOT `tools:`
#   The canonical `tools:` list is an ALLOWLIST — an agent declaring `Read, Grep, Glob`
#   is read-only. Emitting only `{read: true, grep: true, glob: true}` does NOT say
#   that: every unlisted tool stays ENABLED. Verified on OpenCode 1.18.11 — an agent
#   with exactly that map resolves to
#     {bash: true, edit: true, write: true, task: true, webfetch: true, ...}
#   i.e. the read-only constraint is silently dropped. This generator therefore emits
#   an explicit `permission:` entry for every tool in OPENCODE_TOOLS: `allow` for the
#   ones the canonical file grants, `deny` for everything else. Same probe with the
#   generated shape resolves the denied tools to false.
#
# Exit 0 on success; 1 if --check finds drift; 2 on a malformed canonical file.
set -euo pipefail

usage() { sed -n '2,8p' "$0" | sed 's/^#[[:space:]]\{0,1\}//'; exit "${1:-0}"; }
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

SRC="$ROOT/agents"
REAL_DEST="$ROOT/.opencode/agent"
[[ -d "$SRC" ]] || { echo "No agents/ directory — nothing to build"; exit 0; }

DEST="$REAL_DEST"
if [[ "$CHECK" == true ]]; then
  DEST="$(mktemp -d)"
  trap 'rm -rf "$DEST"' EXIT
fi
mkdir -p "$DEST"

# Every tool OpenCode can gate through `permission`. Anything not granted by the
# canonical file is denied explicitly, so an allowlist stays an allowlist.
# Source: https://opencode.ai/config.json, $defs.PermissionConfig (plus `write`,
# accepted via additionalProperties and verified to resolve to write:false).
OPENCODE_TOOLS=(read edit write glob grep list bash task webfetch websearch skill)

# Canonical Claude tool name -> OpenCode permission key. Unlisted canonical tools
# (notably `mcp__*` server tools) have no OpenCode equivalent and are reported
# rather than silently dropped.
map_tool() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    read)                 echo read ;;
    edit|multiedit)       echo edit ;;
    write)                echo write ;;
    glob)                 echo glob ;;
    grep)                 echo grep ;;
    ls|list)              echo list ;;
    bash)                 echo bash ;;
    task|agent)           echo task ;;
    webfetch)             echo webfetch ;;
    websearch)            echo websearch ;;
    skill)                echo skill ;;
    *)                    echo "" ;;
  esac
}

# Claude model aliases -> OpenCode provider-prefixed ids. Every id below was
# confirmed present in the models.dev catalogue OpenCode resolves against
# (https://models.dev/api.json, provider `anthropic`).
map_model() {
  case "$1" in
    sonnet)     echo "anthropic/claude-sonnet-4-6" ;;
    opus)       echo "anthropic/claude-opus-4-5" ;;
    haiku)      echo "anthropic/claude-haiku-4-5" ;;
    ""|inherit) echo "" ;;
    *)          echo "$1" ;;   # already provider-prefixed, or an explicit id
  esac
}

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

count=0
generated=()
unmapped_report=()

for f in "$SRC"/*.md; do
  [[ -e "$f" ]] || continue
  base="$(basename "$f")"

  head -1 "$f" | grep -q '^---[[:space:]]*$' || {
    echo "ERROR: $f has no YAML frontmatter (line 1 must be '---')" >&2; exit 2; }

  desc=$(fm_get "$f" description)
  tools=$(fm_get "$f" tools)
  model=$(fm_get "$f" model)
  mode=$(fm_get "$f" mode)
  [[ -n "$mode" ]] || mode="subagent"

  [[ -n "$desc" ]] || { echo "ERROR: $f has no 'description:' — OpenCode requires it" >&2; exit 2; }

  # Body = everything after the closing --- of the frontmatter.
  body_start=$(awk 'NR>1 && /^---[[:space:]]*$/ {print NR+1; exit}' "$f")
  [[ -n "$body_start" ]] || body_start=1

  # Resolve the canonical allowlist into a granted set.
  granted=" "
  if [[ -n "$tools" ]]; then
    while IFS= read -r t; do
      t="$(printf '%s' "$t" | tr -d '[:space:]')"
      [[ -n "$t" ]] || continue
      oc="$(map_tool "$t")"
      if [[ -n "$oc" ]]; then
        granted="${granted}${oc} "
      else
        unmapped_report+=("$base: $t")
      fi
    # printf with a trailing newline, not bare '%s': `read` discards a final
    # unterminated line, which silently dropped the LAST tool of every allowlist.
    done < <(printf '%s\n' "$tools" | tr ',' '\n')
  fi

  {
    echo "---"
    echo "description: $desc"
    echo "mode: $mode"
    oc_model=$(map_model "$model")
    [[ -n "$oc_model" ]] && echo "model: $oc_model"
    if [[ -n "$tools" ]]; then
      # An allowlist stays an allowlist: everything not granted is denied.
      echo "permission:"
      for oc in "${OPENCODE_TOOLS[@]}"; do
        if [[ "$granted" == *" $oc "* ]]; then
          echo "  $oc: allow"
        else
          echo "  $oc: deny"
        fi
      done
    fi
    echo "---"
    echo
    echo "<!-- GENERATED FILE — DO NOT EDIT."
    echo "     Source:    agents/$base"
    echo "     Generator: scripts/build-opencode-agents.sh"
    echo "     Regenerate: make opencode-agents -->"
    echo
    # RELATIVE LINKS MUST BE RE-BASED FOR THE NEW DEPTH.
    #   canonical  agents/<n>.md          -> dir depth 1, so `](../core/x)` = <root>/core/x
    #   generated  .opencode/agent/<n>.md -> dir depth 2, so the SAME text means
    #                                        <root>/.opencode/core/x, which does not exist.
    # One level deeper means one more `../`. Verified: without this, all 24 relative
    # links in agents/*.md resolve nowhere from the generated location; with it, all 24
    # resolve. Only `](../` is touched, so absolute paths, anchors and http(s) URLs are
    # left alone. tests/test-opencode-adapter.sh resolves every link against the
    # filesystem, so this stays honest if the destination depth ever changes.
    #
    # KNOWN LIMITATION: this is not fence-aware. A `](../x)` inside a fenced code
    # block — a doc example rather than a real link — would be rewritten too. There
    # is no such case today (measured: 24 relative links in agents/*.md, 0 inside
    # fences), and the failure would be LOUD rather than silent: the link check
    # resolves every target, so a corrupted example fails the suite. Left simple
    # deliberately; if a canonical agent ever gains such an example, make the
    # rewrite skip fenced regions rather than loosening the check.
    tail -n "+$body_start" "$f" | sed 's|](\.\./|](../../|g'
  } > "$DEST/$base"

  generated+=("$base")
  count=$((count + 1))
done

# Prune adapters whose canonical source is gone, so a deleted agent does not linger.
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

if ((${#unmapped_report[@]})); then
  echo "note: canonical tools with no OpenCode equivalent (not granted in the adapter):" >&2
  printf '  %s\n' "${unmapped_report[@]}" >&2
fi

if [[ "$CHECK" == true ]]; then
  if ! diff -r -q "$REAL_DEST" "$DEST" >/dev/null 2>&1; then
    {
      echo "ERROR: .opencode/agent/ is out of sync with agents/."
      echo "       These files are GENERATED — fix agents/*.md, then run: make opencode-agents"
      echo
      diff -r -u "$REAL_DEST" "$DEST" || true
    } >&2
    exit 1
  fi
  echo "OpenCode agent adapters in sync ($count agent(s))"
  exit 0
fi

echo "Generated $count OpenCode agent adapter(s) in .opencode/agent/${pruned:+ (pruned $pruned stale)}"
