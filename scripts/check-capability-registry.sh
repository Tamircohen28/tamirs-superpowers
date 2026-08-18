#!/usr/bin/env bash
# check-capability-registry.sh — validate the platform capability registry.
#
# Usage:
#   check-capability-registry.sh [repo-root]
#   check-capability-registry.sh -h | --help
#
# Checks, in order:
#   1. core/capabilities/schema.json and core/capabilities/platforms.json are valid JSON.
#   2. platforms.json validates against schema.json (JSON Schema draft 2020-12) when
#      python3 + jsonschema are installed. When they are not, the run degrades to a
#      jq-based structural check and says so — a missing contributor dependency must
#      never be reported as a registry failure.
#   3. Structural invariants jq can prove without the schema library: every platform
#      covers every declared capability key, every status is in the enum, native claims
#      carry a validation command, and non-native statuses carry a fallback or a note.
#   4. Every target in docs/engineering/build-and-release/platform-targets.json
#      supported_targets has a registry entry. A platform that ships without a
#      capability row is a platform whose gaps are invisible.
#
# Exit 0 if checks pass; 1 on failure.
set -euo pipefail

usage() { sed -n '2,21p' "$0" | sed -E 's/^# ?//'; exit "${1:-0}"; }
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage 0

ROOT="$(cd "${1:-.}" && pwd)"
SCHEMA="$ROOT/core/capabilities/schema.json"
REGISTRY="$ROOT/core/capabilities/platforms.json"
TARGETS="$ROOT/docs/engineering/build-and-release/platform-targets.json"
FAILED=0

err() { echo "ERROR: $*" >&2; FAILED=$(( FAILED + 1 )); }

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required by check-capability-registry.sh" >&2; exit 1; }

for f in "$SCHEMA" "$REGISTRY"; do
  [[ -f "$f" ]] || { echo "ERROR: missing $f" >&2; exit 1; }
  jq empty "$f" 2>/dev/null || { echo "ERROR: ${f#"$ROOT"/} is not valid JSON" >&2; exit 1; }
done
echo "ok:    both registry files parse as JSON"

# --- 2. Schema validation (optional dependency) ---
if command -v python3 >/dev/null 2>&1 && python3 -c 'import jsonschema' 2>/dev/null; then
  if python3 - "$SCHEMA" "$REGISTRY" <<'PY'
import json, sys
import jsonschema

schema = json.load(open(sys.argv[1]))
data = json.load(open(sys.argv[2]))
validator = jsonschema.Draft202012Validator(schema)
errors = sorted(validator.iter_errors(data), key=lambda e: list(e.absolute_path))
for e in errors:
    path = "/".join(str(p) for p in e.absolute_path) or "<root>"
    print(f"  {path}: {e.message}", file=sys.stderr)
sys.exit(1 if errors else 0)
PY
  then
    echo "ok:    platforms.json validates against schema.json (jsonschema)"
  else
    err "platforms.json does not validate against schema.json"
  fi
else
  echo "skip:  jsonschema not installed — schema validation skipped, structural checks still run"
  echo "       remedy: python3 -m pip install -r scripts/requirements-validate.txt"
fi

# --- 3. Structural invariants (always run) ---
STATUSES="native native-experimental partial emulated adapter unsupported unknown"
before_structural=$FAILED

keys="$(jq -r '.capability_definitions | keys_unsorted[]' "$REGISTRY")"
platforms="$(jq -r '.platforms | keys_unsorted[]' "$REGISTRY")"

for p in $platforms; do
  for k in $keys; do
    entry="$(jq -c --arg p "$p" --arg k "$k" '.platforms[$p].capabilities[$k] // empty' "$REGISTRY")"
    if [[ -z "$entry" ]]; then
      err "platform '$p' declares no entry for capability '$k' (use status 'unknown', never omission)"
      continue
    fi
    status="$(jq -r '.status // empty' <<<"$entry")"
    if [[ " $STATUSES " != *" $status "* ]]; then
      err "platform '$p' capability '$k' has status '$status', which is not in the enum"
      continue
    fi
    case "$status" in
      native|native-experimental)
        [[ "$(jq -r '.validation // empty' <<<"$entry")" != "" ]] \
          || err "platform '$p' capability '$k' claims '$status' with no validation command — evidence over declarations"
        ;;
      *)
        [[ "$(jq -r '(.fallback // "") + (.notes // "")' <<<"$entry")" != "" ]] \
          || err "platform '$p' capability '$k' is '$status' with neither fallback nor notes"
        ;;
    esac
  done

  for field in display_name install validation; do
    [[ "$(jq -r --arg p "$p" --arg f "$field" '.platforms[$p][$f] // empty' "$REGISTRY")" != "" ]] \
      || err "platform '$p' is missing adapter metadata field '$field'"
  done
done
if (( FAILED == before_structural )); then
  echo "ok:    $(wc -w <<<"$platforms" | tr -d ' ') platforms x $(wc -w <<<"$keys" | tr -d ' ') capabilities, all rows explicit"
fi

# --- 3b. Alias namespace is unambiguous ---
# Consumers normalize an incoming id by matching it against ids and aliases. If two
# platforms claimed the same alias, that normalization would be non-deterministic.
dupes="$(jq -r '.platforms | to_entries | map([.key] + (.value.aliases // [])) | flatten | .[]' "$REGISTRY" \
         | sort | uniq -d)"
if [[ -n "$dupes" ]]; then
  while IFS= read -r d; do
    err "id/alias '$d' is claimed by more than one platform — normalization would be ambiguous"
  done <<<"$dupes"
else
  echo "ok:    platform ids and aliases are collision-free"
fi

# --- 3c. Frontmatter platform ids resolve into the registry ---
# Skill frontmatter `compatibility:` keys are kebab-case by frontmatter convention, while
# registry ids are snake_case. Two namespaces for one concept is a standing drift risk, so
# assert every frontmatter id resolves through the id+alias table. Read-only on a file
# owned by the skill-schema contract; absent file is a skip.
FM_SCHEMA="$ROOT/core/schemas/skill-frontmatter.json"
if [[ -f "$FM_SCHEMA" ]] && jq -e '.["$defs"].compatibility.propertyNames.enum' "$FM_SCHEMA" >/dev/null 2>&1; then
  before_fm=$FAILED
  resolvable="$(jq -r '.platforms | to_entries | map([.key] + (.value.aliases // [])) | flatten | .[]' "$REGISTRY")"
  while IFS= read -r fid; do
    grep -qxF "$fid" <<<"$resolvable" \
      || err "skill frontmatter allows platform id '$fid', which matches no registry id or alias"
  done < <(jq -r '.["$defs"].compatibility.propertyNames.enum[]' "$FM_SCHEMA")
  if (( FAILED == before_fm )); then
    echo "ok:    every skill-frontmatter platform id resolves to a registry entry"
  fi
else
  echo "skip:  core/schemas/skill-frontmatter.json absent or has no compatibility enum"
fi

# --- 3d. The two vocabularies remain derivable from one another ---
# Registry status answers "how does platform P implement capability C?" (a mechanism
# claim). Skill frontmatter `compatibility:` answers "does skill S work on platform P?"
# (an outcome claim). They are deliberately different enums; what must hold is that a
# skill's compatibility is DERIVABLE from the registry, so per-skill tables can be
# generated rather than hand-asserted. That derivation is this map, and it must stay
# total in both directions — if either enum grows a value with no counterpart, the
# derivation is silently undefined, which is exactly the drift this check exists to stop.
DERIVATION="supported:native,native-experimental,adapter
partial:partial
emulated:emulated
unsupported:unsupported
unknown:unknown"

if [[ -f "$FM_SCHEMA" ]] && jq -e '.["$defs"].compatibility.additionalProperties.enum' "$FM_SCHEMA" >/dev/null 2>&1; then
  before_vocab=$FAILED
  compat_values="$(jq -r '.["$defs"].compatibility.additionalProperties.enum[]' "$FM_SCHEMA")"
  registry_statuses="$(jq -r '.["$defs"].status.enum[]' "$SCHEMA")"
  mapped_targets="$(cut -d: -f1 <<<"$DERIVATION")"
  mapped_sources="$(cut -d: -f2 <<<"$DERIVATION" | tr ',' '\n')"

  # (a) every compatibility value is produced by the derivation
  while IFS= read -r v; do
    grep -qxF "$v" <<<"$mapped_targets" \
      || err "skill compatibility allows '$v', which the derivation table never produces — the mapping in this script needs updating"
  done <<<"$compat_values"

  # (b) every registry status derives to something
  while IFS= read -r st; do
    grep -qxF "$st" <<<"$mapped_sources" \
      || err "registry status '$st' maps to no compatibility value — a skill on such a platform could not state its compatibility"
  done <<<"$registry_statuses"

  # (c) the derivation never produces a value the frontmatter schema rejects
  while IFS= read -r t; do
    grep -qxF "$t" <<<"$compat_values" \
      || err "derivation produces compatibility value '$t', which the frontmatter schema does not allow"
  done <<<"$mapped_targets"

  if (( FAILED == before_vocab )); then
    echo "ok:    capability statuses and skill-compatibility values are mutually derivable"
  fi
else
  echo "skip:  no compatibility value enum in core/schemas/skill-frontmatter.json"
fi

# --- 3e. Every command the registry names is actually runnable ---
# `validation` is the evidence field: it is the answer to "how do you know?" for every
# native claim, and fallback/notes strings get copy-pasted by users straight off the row.
# A command naming a Makefile target that does not exist is worse than no command at all
# — it reads as evidence and fails with "No rule to make target". Nothing checked this
# until a row shipped `make gemini-adapter-check` against a Makefile whose real target is
# `gemini-extension-check`.
#
# Two passes, because the fields differ in kind. `validation` values ARE commands, so any
# `make X` in one is a target reference and is checked strictly. Prose fields are not, and
# a bare-word match there hits ordinary English ("Never make a skill depend on it"), so
# prose is held to hyphenated targets only — the shape every real target here has.
before_cmds=$FAILED
MAKEFILE="$ROOT/Makefile"

check_make_target() {
  grep -qE "^$1:" "$MAKEFILE" || err "registry names 'make $1' ($2), which is not a target in Makefile"
}

if [[ -f "$MAKEFILE" ]]; then
  # Pass 1 — validation fields, strict.
  while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    check_make_target "$target" "a validation command"
  done < <(
    jq -r '[ (.platforms[] | .validation.command),
             (.platforms[].capabilities[] | .validation // empty) ] | .[]' "$REGISTRY" \
      | grep -oE 'make [a-z][a-z0-9-]*' | awk '{print $2}' | sort -u
  )

  # Pass 2 — prose fields, hyphenated targets only.
  while IFS= read -r target; do
    [[ -n "$target" ]] || continue
    check_make_target "$target" "named in notes or fallback"
  done < <(
    jq -r '[ (.capability_definitions[] | .summary, .degradation // empty),
             (.platforms[].capabilities[] | .notes // empty, .fallback // empty) ] | .[]' "$REGISTRY" \
      | grep -oE 'make [a-z][a-z0-9]*(-[a-z0-9]+)+' | awk '{print $2}' | sort -u
  )
else
  echo "skip:  no Makefile — 'make' target references not checked"
fi

# Script paths are repo-relative; a renamed or unwritten script silently guts the evidence.
while IFS= read -r script; do
  [[ -n "$script" ]] || continue
  [[ -f "$ROOT/$script" ]] || err "registry names '$script', which does not exist in this tree"
done < <(grep -oE '(scripts|hooks|tests)/[A-Za-z0-9._/-]+\.sh' "$REGISTRY" | sort -u)

if (( FAILED == before_cmds )); then
  echo "ok:    every make target and script path the registry names exists"
fi

# --- 4. Every shipped target has a registry entry ---
if [[ -f "$TARGETS" ]]; then
  before_targets=$FAILED
  for t in $(jq -r '(.supported_targets // [])[]' "$TARGETS"); do
    jq -e --arg t "$t" '.platforms | has($t)' "$REGISTRY" >/dev/null \
      || err "platform-targets.json ships target '$t' with no entry in core/capabilities/platforms.json"
  done
  if (( FAILED == before_targets )); then
    echo "ok:    every supported_target in platform-targets.json has a registry entry"
  fi
else
  echo "skip:  $TARGETS not found — target cross-check skipped"
fi

if (( FAILED > 0 )); then
  echo "Capability registry check FAILED ($FAILED error(s))." >&2
  exit 1
fi
echo "Capability registry check passed."
