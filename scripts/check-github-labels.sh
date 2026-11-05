#!/usr/bin/env bash
# check-github-labels.sh — validate the canonical GitHub label set.
#
# Usage:
#   check-github-labels.sh [repo-root]
#   check-github-labels.sh -h | --help
#
# OFFLINE BY CONSTRUCTION. This runs inside `make validate`, so it must pass on
# a laptop with no network, no `gh`, and no GitHub credential. It never invokes
# gh and never opens a socket; everything it asserts is a property of the tree.
#
# Checks, in order:
#   1. config/github/labels.json and core/schemas/github-labels.json are valid JSON.
#   2. The label set validates against the schema (JSON Schema draft 2020-12) when
#      python3 + jsonschema are installed. When they are not, the run degrades to
#      the jq-based invariants below and says so — a missing contributor
#      dependency must never be reported as a label failure.
#   3. Invariants jq can prove without the schema library:
#      - names are unique case-insensitively (GitHub's uniqueness rule), trimmed,
#        1..50 characters; colours are six lowercase hex digits; descriptions
#        are at most 100 characters (GitHub truncates longer ones, so the
#        comparison would never converge);
#      - every github-default label is one of GitHub's nine, and all nine are
#        present, so a repository that lost one is repaired;
#      - every non-default label carries a _comment naming who depends on it;
#      - no listed label name starts with the agent prefix except agent:any —
#        the per-platform labels are rendered from the capability registry, and
#        a hardcoded agent:<platform> here is the platform list the registry
#        exists to replace;
#      - the registry has at least one platform, each with a display_name.
#   4. The repository's own consumers name labels the set provides:
#      .github/dependabot.yml `labels:` and .github/ISSUE_TEMPLATE/*.yml
#      `labels:` (parsed with PyYAML when importable, otherwise skipped with
#      a note) — a template that labels an issue with a name no repository
#      has is a template that silently fails.
#
# Exit 0 if checks pass; 1 on failure.
set -euo pipefail

usage() { sed -n '2,36p' "$0" | sed -E 's/^# ?//'; exit "${1:-0}"; }
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage 0

ROOT="$(cd "${1:-.}" && pwd)"
LABELS="$ROOT/config/github/labels.json"
SCHEMA="$ROOT/core/schemas/github-labels.json"
REGISTRY="$ROOT/core/capabilities/platforms.json"
FAILED=0

err() { echo "ERROR: $*" >&2; FAILED=$(( FAILED + 1 )); }

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required by check-github-labels.sh" >&2; exit 1; }

# --- 1. Both files parse ---
for f in "$LABELS" "$SCHEMA"; do
  [[ -f "$f" ]] || { echo "ERROR: missing $f" >&2; exit 1; }
  jq empty "$f" 2>/dev/null || { echo "ERROR: ${f#"$ROOT"/} is not valid JSON" >&2; exit 1; }
done
echo "ok:    label set and schema parse as JSON"

# --- 2. Schema validation (optional dependency) ---
if command -v python3 >/dev/null 2>&1 && python3 -c 'import jsonschema' 2>/dev/null; then
  if python3 - "$SCHEMA" "$LABELS" <<'PY'
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
    echo "ok:    labels.json validates against its schema (jsonschema)"
  else
    err "labels.json does not validate against core/schemas/github-labels.json"
  fi
else
  echo "skip:  jsonschema not installed — schema validation skipped, invariants still run"
  echo "       remedy: python3 -m pip install -r scripts/requirements-validate.txt"
fi

# --- 3a. Every label is well-formed and names are unique ---
before=$FAILED
while IFS=$'\t' read -r name color desc; do
  [[ -n "$name" ]] || { err "a label has an empty name"; continue; }
  [[ "$name" == "$(printf '%s' "$name" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')" ]] \
    || err "label '$name' has leading or trailing whitespace; GitHub would store it trimmed and it would never match"
  (( ${#name} <= 50 )) || err "label '$name' is longer than GitHub's 50-character limit"
  [[ "$color" =~ ^[0-9a-f]{6}$ ]] \
    || err "label '$name' colour '$color' is not six lowercase hex digits (no leading #)"
  (( ${#desc} <= 100 )) || err "label '$name' description is longer than 100 characters; GitHub truncates it and the comparison never converges"
done < <(jq -r '.labels[] | [.name, .color, .description] | @tsv' "$LABELS")
n="$(jq -r '.labels | length' "$LABELS")"
u="$(jq -r '[.labels[].name | ascii_downcase] | unique | length' "$LABELS")"
[[ "$n" == "$u" ]] || err "label names collide case-insensitively ($n labels, $u distinct); GitHub treats 'Bug' and 'bug' as one label"
(( FAILED == before )) && echo "ok:    $n labels, all well-formed, names unique case-insensitively"

# --- 3b. GitHub's nine defaults are all present and nothing else claims to be one ---
# The nine are a fact about GitHub, not policy: every new repository gets exactly
# these, so a repository missing one has lost it and should get it back.
before=$FAILED
GITHUB_DEFAULTS='["bug","documentation","duplicate","enhancement","good first issue","help wanted","invalid","question","wontfix"]'
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  jq -e --arg n "$name" --argjson d "$GITHUB_DEFAULTS" '$d | index($n) != null' <<<'null' >/dev/null \
    || err "label '$name' is marked github-default but GitHub creates no such label on a new repository"
done < <(jq -r '.labels[] | select(.origin == "github-default") | .name' "$LABELS")
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  jq -e --arg n "$name" '[.labels[] | select(.origin == "github-default") | .name] | index($n) != null' "$LABELS" >/dev/null \
    || err "GitHub default label '$name' is missing from the set; a repository that lost it would never be repaired"
done < <(jq -r '.[]' <<<"$GITHUB_DEFAULTS")
(( FAILED == before )) && echo "ok:    all nine GitHub default labels are listed, and only those are marked github-default"

# --- 3c. Every non-default label says who depends on it ---
before=$FAILED
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  err "label '$name' is not a GitHub default and carries no _comment — the next reader needs to know who depends on it before deleting it"
done < <(jq -r '.labels[] | select(.origin != "github-default") | select((._comment // "") == "") | .name' "$LABELS")
(( FAILED == before )) && echo "ok:    every non-default label carries a one-line reason"

# --- 3d. Platform labels come from the registry, never from this file ---
before=$FAILED
prefix="$(jq -r '.agent_labels.prefix' "$LABELS")"
[[ "$prefix" == "agent:" ]] || err "agent_labels.prefix is '$prefix'; switch-dev and the issue template match on 'agent:'"
while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  [[ "$name" == "${prefix}any" ]] \
    || err "label '$name' hardcodes a platform; agent:<platform> labels are rendered from core/capabilities/platforms.json — delete it from labels.json"
done < <(jq -r --arg p "$prefix" '.labels[] | select(.name | startswith($p)) | .name' "$LABELS")
jq -e --arg p "$prefix" '[.labels[] | select(.name == ($p + "any"))] | length == 1' "$LABELS" >/dev/null \
  || err "the set must list '${prefix}any' exactly once; switch-dev uses it as the unclaimed state"
jq -e '.agent_labels.description_template | test("\\{display_name\\}")' "$LABELS" >/dev/null \
  || err "agent_labels.description_template must contain {display_name}"
reg_rel="$(jq -r '.agent_labels.registry' "$LABELS")"
[[ "$reg_rel" == "core/capabilities/platforms.json" ]] \
  || err "agent_labels.registry is '$reg_rel'; the capability registry lives at core/capabilities/platforms.json"
if [[ -f "$REGISTRY" ]] && jq empty "$REGISTRY" 2>/dev/null; then
  jq -e '.platforms | type == "object" and length > 0' "$REGISTRY" >/dev/null \
    || err "the capability registry declares no platforms; no agent:<platform> label could be rendered"
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    jq -e --arg k "$key" '.platforms[$k].display_name | type == "string" and length > 0' "$REGISTRY" >/dev/null \
      || err "registry platform '$key' has no display_name; its agent label description could not be rendered"
    (( ${#prefix} + ${#key} <= 50 )) || err "agent label '${prefix}${key}' would exceed 50 characters"
  done < <(jq -r '.platforms | keys[]' "$REGISTRY")
  (( FAILED == before )) && echo "ok:    platform labels derive from the registry ($(jq -r '.platforms | keys | join(", ")' "$REGISTRY"))"
else
  err "capability registry missing or invalid: ${REGISTRY#"$ROOT"/}"
fi

# --- 4. The repository's own consumers name labels the set provides ---
before=$FAILED
# The full rendered name list: the file's labels plus one agent label per platform.
known="$(jq -r --slurpfile r "$REGISTRY" '
  ([.labels[].name] + ([.agent_labels.prefix as $p | $r[0].platforms | keys[] | $p + .])) | map(ascii_downcase) | .[]' "$LABELS" 2>/dev/null)"
if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null; then
  while IFS=$'\t' read -r file label; do
    [[ -n "$file" ]] || continue
    grep -qxF "$(printf '%s' "$label" | tr '[:upper:]' '[:lower:]')" <<<"$known" \
      || err "${file#"$ROOT"/} labels with '$label', which the canonical set does not provide — add it to config/github/labels.json or use an existing label"
  done < <(python3 - "$ROOT" <<'PY'
import glob, os, sys
import yaml

root = sys.argv[1]
def emit(path, labels):
    if isinstance(labels, str):
        labels = [labels]
    for l in labels or []:
        print(f"{path}\t{l}")

dep = os.path.join(root, ".github", "dependabot.yml")
if os.path.isfile(dep):
    with open(dep, encoding="utf-8") as fh:
        doc = yaml.safe_load(fh) or {}
    for upd in doc.get("updates") or []:
        emit(dep, (upd or {}).get("labels"))
for tmpl in sorted(glob.glob(os.path.join(root, ".github", "ISSUE_TEMPLATE", "*.yml"))
                   + glob.glob(os.path.join(root, ".github", "ISSUE_TEMPLATE", "*.yaml"))):
    with open(tmpl, encoding="utf-8") as fh:
        doc = yaml.safe_load(fh) or {}
    if isinstance(doc, dict):
        emit(tmpl, doc.get("labels"))
PY
)
  (( FAILED == before )) && echo "ok:    dependabot.yml and every issue template name labels the set provides"
else
  echo "skip:  PyYAML not installed — dependabot/issue-template label check skipped"
  echo "       remedy: python3 -m pip install -r scripts/requirements-validate.txt"
fi

# --- 5. Version discipline ---
before=$FAILED
ver="$(jq -r '.version' "$LABELS")"
[[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || err "version '$ver' is not semver; the _contract pattern requires a bump on every content change"
[[ "$(jq -r '.schema_version' "$LABELS")" == "1" ]] \
  || err "schema_version must be 1"
(( FAILED == before )) && echo "ok:    label set version $ver, schema_version 1"

if (( FAILED > 0 )); then
  echo "GitHub label set check FAILED ($FAILED error(s))." >&2
  exit 1
fi
echo "GitHub label set check passed."
