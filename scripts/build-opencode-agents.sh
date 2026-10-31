#!/usr/bin/env bash
# build-opencode-agents.sh — generate .opencode/agents/*.md from canonical agents/*.md.
#
# Usage:
#   bash scripts/build-opencode-agents.sh [repo-root] [--check]
#   bash scripts/build-opencode-agents.sh -h | --help
#
# --check regenerates into a temp dir and diffs, so CI can fail on drift without
# writing to the working tree. Drift includes adapters whose canonical source was
# deleted, and a stale `.opencode/agent/` (singular) tree left by an older release; a
# normal run prunes both.
#
# WHY THIS EXISTS
#   OpenCode validates config strictly and refuses to start on a bad field, and its
#   agent frontmatter genuinely differs from the canonical Claude-shaped one:
#     - canonical `tools: Read, Grep, Bash` is a comma string; OpenCode 2 has no such
#       field at all (`tools` is a deprecated legacy key the published schema lists
#       only under `AgentConfig`, not under `Config.AgentEncoded`).
#     - canonical `model: sonnet` is an alias; OpenCode wants a provider-prefixed id.
#     - canonical `name:` is not an agent property at all — OpenCode derives the
#       agent id from the FILENAME.
#   So the canonical files cannot be copied, they are translated. The translation is
#   committed so a user installing from a clone needs no build step.
#
# OUTPUT SHAPE
#   The output is the OpenCode 2 shape (https://opencode.ai/config.json, $defs.Config.AgentEncoded,
#   read 2026-10-17 against @opencode/cli 2.0.32):
#     - directory `.opencode/agents/` (plural). OpenCode 2 also reads a singular
#       `agent/` dir, so a stale copy there would load a SECOND set of the same ids —
#       the generator prunes it and --check fails while it exists.
#     - `mode: subagent` always explicit. The default mode for a custom agent
#       is `primary`; an adapter that omitted it would become a
#       primary agent the user can select, which none of these roles is.
#     - `permissions:` — an ORDERED RULE LIST of {action, resource, effect}, where
#       "the last matching rule wins". A `permission:` map (the deprecated legacy
#       form) is never emitted, and scripts/check-opencode-permission-keys.sh
#       fails if one, or any non-Core action name, ever appears.
#
# WHY `permissions:` RULES AND NOT A BARE ALLOWLIST
#   The canonical `tools:` list is an ALLOWLIST — an agent declaring `Read, Grep, Glob`
#   is read-only. OpenCode's base policy for every agent starts with
#   `{action: "*", resource: "*", effect: allow}` (https://opencode.ai/v2/docs/permissions/
#   "Defaults"), so emitting only the granted actions does NOT say that: every
#   unlisted action stays ALLOWED. That silent widening is the documented
#   default policy behaviour.
#   This generator therefore emits a `deny` rule for every action in OPENCODE_ACTIONS
#   the canonical file does NOT grant, plus an explicit `external_directory: ask`
#   rule for every agent.
#
# WHY NO `allow` RULES FOR THE GRANTED ACTIONS
#   Measured on @opencode/cli 2.0.32 (`opencode debug agents`): an agent's rules are
#   appended AFTER the base policy, and the base policy is
#     *  * allow / read *.env ask / read *.env.* ask / read *.env.example allow
#   With "last matching rule wins", an emitted `read * allow` lands after
#   `read *.env ask` and silently switches off the host's own secrets prompt; an
#   emitted `shell * allow` likewise overrides a `shell * ask` the user put in
#   their global opencode.json, because global rules load before agent rules. A
#   granted action needs no rule at all — the base policy already allows it — so
#   emitting one can only ever WIDEN what the user and host configured. The
#   allowlist is expressed purely as denies, which can only narrow.
#
# WHY `external_directory` IS ALWAYS `ask`
#   OpenCode 2 ALLOWS a path outside the project by default
#   ("The default policy allows external_directory, so external paths are not
#   prompted unless you add a rule"). This repo's worktree invariant — a worker
#   edits inside its own worktree, nothing else — depends on that prompt, so the
#   rule is restored explicitly. `ask`, not `deny`: an objective worktree may sit
#   outside the repo (SUPERPOWERS_AGENT_WORKTREE_ROOT), and a deny would strand it.
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
REAL_DEST="$ROOT/.opencode/agents"
LEGACY_DEST="$ROOT/.opencode/agent"
[[ -d "$SRC" ]] || { echo "No agents/ directory — nothing to build"; exit 0; }

DEST="$REAL_DEST"
if [[ "$CHECK" == true ]]; then
  DEST="$(mktemp -d)"
  trap 'rm -rf "$DEST"' EXIT
fi
mkdir -p "$DEST"

# Every OpenCode 2 Core permission ACTION a canonical tool can map onto. Anything
# not granted by the canonical file is denied explicitly, so an allowlist stays an
# allowlist. Source: https://opencode.ai/v2/docs/permissions/ ("Built-in tools
# currently use these actions"), read 2026-10-17. The published schema does not
# enumerate actions — `Permission.Rule.action` is a free string, "so plugins may
# define more" — which is exactly why the list is pinned here and in
# scripts/check-opencode-permission-keys.sh rather than fetched: a misspelt action
# is a deny rule that denies nothing, and nothing would notice.
#
# Deliberately absent: `external_directory` (emitted separately, always `ask`),
# `execute` (Code Mode; "nested tools enforce their rules", so the per-action
# rules above already govern what it can reach), the MCP `<server>_<tool>` family
# (no canonical equivalent — see map_tool), and every name that is NOT a Core action: `bash`
# (the tool alias runs as `shell`), `task` (`subagent`), `doom_loop`, `lsp`, `list`,
# `todowrite`, `write`.
OPENCODE_ACTIONS=(read edit glob grep shell subagent skill question webfetch websearch)

# Canonical Claude tool name -> OpenCode 2 permission action. Unlisted canonical
# tools (notably `mcp__*` server tools, and LS — V2 has no `list` action; `glob`
# is the listing capability) have no OpenCode equivalent and are reported rather
# than silently dropped.
map_tool() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    read)                 echo read ;;
    # `edit` governs edit, write AND patch in V2 ("Target path for edit, write,
    # and patch"), so canonical Write/MultiEdit fold into it.
    edit|multiedit|write) echo edit ;;
    glob)                 echo glob ;;
    grep)                 echo grep ;;
    bash)                 echo shell ;;
    task|agent)           echo subagent ;;
    webfetch)             echo webfetch ;;
    websearch)            echo websearch ;;
    skill)                echo skill ;;
    askuserquestion)      echo question ;;
    *)                    echo "" ;;
  esac
}

# Claude model aliases -> OpenCode provider-prefixed ids. Every id below was
# confirmed present in the models.dev catalogue OpenCode resolves against
# (https://models.dev/api.json, provider `anthropic`) - re-confirmed 2026-09-23,
# when the sonnet and opus entries were repointed off the 4.x line. `haiku` is
# unchanged because Haiku 4.5 is still the current Haiku, not because it was
# skipped. Re-check here whenever a skill or agent `model:` pin moves: PR #156
# repointed 27 SKILL.md pins and missed this map, which is how the sonnet entry
# went stale without any check noticing.
map_model() {
  case "$1" in
    sonnet)     echo "anthropic/claude-sonnet-5" ;;
    opus)       echo "anthropic/claude-opus-5-5" ;;
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

# emit_rule <action> <effect> — one block-style list item of the V2 ruleset.
emit_rule() {
  printf '  - action: %s\n    resource: "*"\n    effect: %s\n' "$1" "$2"
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
      # An allowlist stays an allowlist: everything not granted is denied, and
      # nothing granted gets an allow rule (see the header: an allow placed after
      # the base policy would override the host's own `.env` asks). One rule per
      # denied action, so order among them is irrelevant; external_directory
      # last, as the documented place for the rule that restores the outside-project prompt.
      echo "permissions:"
      for oc in "${OPENCODE_ACTIONS[@]}"; do
        [[ "$granted" == *" $oc "* ]] || emit_rule "$oc" deny
      done
      emit_rule external_directory ask
    fi
    echo "---"
    echo
    echo "<!-- GENERATED FILE — DO NOT EDIT."
    echo "     Source:    agents/$base"
    echo "     Generator: scripts/build-opencode-agents.sh"
    echo "     Regenerate: make opencode-agents -->"
    echo
    # RELATIVE LINKS MUST BE RE-BASED FOR THE NEW DEPTH.
    #   canonical  agents/<n>.md           -> dir depth 1, so `](../core/x)` = <root>/core/x
    #   generated  .opencode/agents/<n>.md -> dir depth 2, so the SAME text means
    #                                         <root>/.opencode/core/x, which does not exist.
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

# Upgrade helper: the singular `agent/` dir an older release wrote into. OpenCode 2
# reads `agent/` AND `agents/`, so a stale tree is not harmless: the same ids would
# load twice, the older copy carrying the deprecated `permission:` map. Remove this
# block (and LEGACY_DEST) after the next release.
# Only files that carry this
# generator's own header are touched — anything else there is the user's.
legacy_stale=()
if [[ -d "$LEGACY_DEST" ]]; then
  for existing in "$LEGACY_DEST"/*.md; do
    [[ -e "$existing" ]] || continue
    grep -q 'Generator: scripts/build-opencode-agents.sh' "$existing" && legacy_stale+=("$existing")
  done
fi

if ((${#unmapped_report[@]})); then
  echo "note: canonical tools with no OpenCode equivalent (not granted in the adapter):" >&2
  printf '  %s\n' "${unmapped_report[@]}" >&2
fi

if [[ "$CHECK" == true ]]; then
  drift=0
  if ! diff -r -q "$REAL_DEST" "$DEST" >/dev/null 2>&1; then
    {
      echo "ERROR: .opencode/agents/ is out of sync with agents/."
      echo "       These files are GENERATED — fix agents/*.md, then run: make opencode-agents"
      echo
      diff -r -u "$REAL_DEST" "$DEST" || true
    } >&2
    drift=1
  fi
  if ((${#legacy_stale[@]})); then
    {
      echo "ERROR: stale adapters from an older release remain in .opencode/agent/ (singular):"
      printf '         %s\n' "${legacy_stale[@]}"
      echo "       OpenCode 2 reads both directories, so these would load a second copy of every"
      echo "       agent. Run: make opencode-agents (it removes them)."
    } >&2
    drift=1
  fi
  [[ "$drift" -eq 0 ]] || exit 1
  echo "OpenCode agent adapters in sync ($count agent(s))"
  exit 0
fi

if ((${#legacy_stale[@]})); then
  rm -f "${legacy_stale[@]}"
  rmdir "$LEGACY_DEST" 2>/dev/null || true
  echo "Removed ${#legacy_stale[@]} stale adapter(s) from .opencode/agent/ (upgrade helper; OpenCode 2 reads .opencode/agents/)"
fi

echo "Generated $count OpenCode agent adapter(s) in .opencode/agents/${pruned:+ (pruned $pruned stale)}"
