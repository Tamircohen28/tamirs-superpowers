#!/usr/bin/env bash
# check-github-policy.sh — validate the canonical GitHub repository policy.
#
# Usage:
#   check-github-policy.sh [repo-root]
#   check-github-policy.sh -h | --help
#
# OFFLINE BY CONSTRUCTION. This runs inside `make validate`, so it must pass on
# a laptop with no network, no `gh`, and no GitHub credential. It never invokes
# gh and never opens a socket; everything it asserts is a property of the file.
#
# Checks, in order:
#   1. config/github/repository-policy.json and core/schemas/repository-policy.json
#      are valid JSON.
#   2. The policy validates against the schema (JSON Schema draft 2020-12) when
#      python3 + jsonschema are installed. When they are not, the run degrades to
#      the jq-based invariants below and says so — a missing contributor
#      dependency must never be reported as a policy failure.
#   3. Invariants jq can prove without the schema library:
#      - no literal branch name anywhere in the document;
#      - every ruleset targets ~DEFAULT_BRANCH and is actively enforced;
#      - both canonical rulesets are present with their required rules;
#      - strict status checks are OFF and flagged as intentional;
#      - the canonical required_status_checks context array is empty, because
#        contexts are per repository and never global;
#      - every per-repository context is a usable, unique, non-empty job name;
#      - every classification regex compiles and no pattern claims both classes.
#
# Exit 0 if checks pass; 1 on failure.
set -euo pipefail

usage() { sed -n '2,30p' "$0" | sed -E 's/^# ?//'; exit "${1:-0}"; }
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage 0

ROOT="$(cd "${1:-.}" && pwd)"
POLICY="$ROOT/config/github/repository-policy.json"
SCHEMA="$ROOT/core/schemas/repository-policy.json"
FAILED=0

err() { echo "ERROR: $*" >&2; FAILED=$(( FAILED + 1 )); }

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required by check-github-policy.sh" >&2; exit 1; }

# --- 1. Both files parse ---
for f in "$POLICY" "$SCHEMA"; do
  [[ -f "$f" ]] || { echo "ERROR: missing $f" >&2; exit 1; }
  jq empty "$f" 2>/dev/null || { echo "ERROR: ${f#"$ROOT"/} is not valid JSON" >&2; exit 1; }
done
echo "ok:    policy and schema parse as JSON"

# --- 2. Schema validation (optional dependency) ---
if command -v python3 >/dev/null 2>&1 && python3 -c 'import jsonschema' 2>/dev/null; then
  if python3 - "$SCHEMA" "$POLICY" <<'PY'
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
    echo "ok:    repository-policy.json validates against its schema (jsonschema)"
  else
    err "repository-policy.json does not validate against core/schemas/repository-policy.json"
  fi
else
  echo "skip:  jsonschema not installed — schema validation skipped, invariants still run"
  echo "       remedy: python3 -m pip install -r scripts/requirements-validate.txt"
fi

# --- 3a. No literal branch name, anywhere ---
# The fleet mixes both default-branch spellings, so a literal is wrong on one of
# them and stops matching the day a branch is renamed. Prose is exempt by
# construction: this matches whole string values, not words inside a sentence.
before=$FAILED
while IFS= read -r bad; do
  [[ -n "$bad" ]] || continue
  err "policy contains the literal ref '$bad' — target the default branch with ~DEFAULT_BRANCH"
done < <(jq -r '[.. | strings | select(test("^(main|master)$") or test("^refs/heads/"))] | unique[]' "$POLICY")
(( FAILED == before )) && echo "ok:    no literal branch name appears as a value anywhere in the policy"

# --- 3b. Every ruleset targets the default branch and is enforced ---
before=$FAILED
while IFS=$'\t' read -r key include enforcement target; do
  [[ -n "$key" ]] || continue
  [[ "$include" == '["~DEFAULT_BRANCH"]' ]] \
    || err "ruleset '$key' includes $include, not exactly [\"~DEFAULT_BRANCH\"]"
  [[ "$enforcement" == "active" ]] \
    || err "ruleset '$key' has enforcement '$enforcement' — an unenforced ruleset protects nothing"
  [[ "$target" == "branch" ]] \
    || err "ruleset '$key' targets '$target'; branch governance must target 'branch'"
done < <(jq -r '.rulesets[] | [.key, (.conditions.ref_name.include | tojson), .enforcement, .target] | @tsv' "$POLICY")
(( FAILED == before )) && echo "ok:    every ruleset is an active branch ruleset scoped to ~DEFAULT_BRANCH"

# --- 3c. The two canonical rulesets and their rules are present ---
before=$FAILED
require_rule() {
  jq -e --arg k "$1" --arg t "$2" \
    '[.rulesets[] | select(.key == $k) | .rules[] | .type] | index($t) != null' "$POLICY" >/dev/null \
    || err "ruleset '$1' is missing the '$2' rule"
}
for k in safety pr_ci; do
  jq -e --arg k "$k" '[.rulesets[].key] | index($k) != null' "$POLICY" >/dev/null \
    || err "policy declares no ruleset with key '$k'"
done
require_rule safety deletion
require_rule safety non_fast_forward
require_rule pr_ci required_linear_history
require_rule pr_ci required_status_checks
require_rule pr_ci pull_request
(( FAILED == before )) && echo "ok:    both canonical rulesets carry their required rules"

# --- 3c2. The pull_request gate says what it means ---
# Zero required approvals is right for a single-author account — a self-approval
# requirement is only ever satisfied by --admin bypasses, which defeat the whole
# ruleset — but it is only safe BECAUSE thread resolution is required. The two
# are one decision and are asserted together so neither can drift alone.
before=$FAILED
while IFS=$'\t' read -r key approvals threads owner lastpush stale; do
  [[ -n "$key" ]] || continue
  [[ "$approvals" == "0" ]] \
    || err "ruleset '$key' requires $approvals approving review(s); on a single-author account that is satisfiable only by an admin bypass, which defeats the ruleset"
  [[ "$threads" == "true" ]] \
    || err "ruleset '$key' does not require review-thread resolution; with zero required approvals it is the only merge gate left"
  [[ "$owner" == "false" ]] \
    || err "ruleset '$key' requires code-owner review; there is no second owner to give it"
  [[ "$lastpush" == "false" ]] \
    || err "ruleset '$key' requires last-push approval; a solo author cannot approve their own last push"
  [[ "$stale" == "false" ]] \
    || err "ruleset '$key' dismisses stale reviews on push; with zero required approvals this only churns state"
done < <(jq -r '.rulesets[] | .key as $k | .rules[] | select(.type == "pull_request")
                | [$k,
                   (.parameters.required_approving_review_count | tostring),
                   (.parameters.required_review_thread_resolution | tostring),
                   (.parameters.require_code_owner_review | tostring),
                   (.parameters.require_last_push_approval | tostring),
                   (.parameters.dismiss_stale_reviews_on_push | tostring)] | @tsv' "$POLICY")
(( FAILED == before )) && echo "ok:    the pull_request gate is 0 approvals + required thread resolution, consistently"

# --- 3d. Strict status checks are off, and the file says so on purpose ---
# Two assertions, not one. The boolean alone reads as a default someone forgot
# to set; the acknowledgement flag plus a rationale is what stops a well-meaning
# "fix" from landing as a one-character diff.
before=$FAILED
strict="$(jq -r '.required_checks.strict_required_status_checks_policy' "$POLICY")"
[[ "$strict" == "false" ]] \
  || err "required_checks.strict_required_status_checks_policy is '$strict'; it must be false — see the rationale in the policy's _comment"
[[ "$(jq -r '.required_checks.strict_is_intentional' "$POLICY")" == "true" ]] \
  || err "required_checks.strict_is_intentional must be true — the false above has to be an acknowledged decision, not an omission"
jq -e '(.required_checks._comment // "") | test("deliberate|intentional|on purpose|DO NOT"; "i")' "$POLICY" >/dev/null \
  || err "required_checks._comment must say in words that strict is off deliberately; the next reader needs the reason, not just the value"
while IFS=$'\t' read -r key rstrict; do
  [[ -n "$key" ]] || continue
  [[ "$rstrict" == "false" ]] \
    || err "ruleset '$key' sets strict_required_status_checks_policy=$rstrict, contradicting the account policy"
done < <(jq -r '.rulesets[] | .key as $k | .rules[] | select(.type == "required_status_checks")
                | [$k, (.parameters.strict_required_status_checks_policy | tostring)] | @tsv' "$POLICY")
(( FAILED == before )) && echo "ok:    strict/up-to-date checks are off and flagged as intentional in every place they appear"

# --- 3e. Contexts are per repository, never global ---
before=$FAILED
[[ "$(jq -r '.required_checks.default_contexts | length' "$POLICY")" == "0" ]] \
  || err "required_checks.default_contexts is non-empty — a global context list blocks every PR in any repo whose CI job names differ"
while IFS=$'\t' read -r key n; do
  [[ -n "$key" ]] || continue
  [[ "$n" == "0" ]] \
    || err "ruleset '$key' hardcodes $n status-check context(s); contexts belong under repositories.<owner/repo>.required_checks"
done < <(jq -r '.rulesets[] | .key as $k | .rules[] | select(.type == "required_status_checks")
                | [$k, (.parameters.required_status_checks | length | tostring)] | @tsv' "$POLICY")
iid="$(jq -r '.required_checks.integration_id' "$POLICY")"
[[ "$iid" =~ ^[0-9]+$ ]] \
  || err "required_checks.integration_id must be a number; contexts without it can be satisfied by any app"
(( FAILED == before )) && echo "ok:    status-check contexts are resolved per repository (integration_id $iid)"

# --- 3f. Per-repository overrides are usable ---
before=$FAILED
while IFS= read -r repo; do
  [[ -n "$repo" ]] || continue
  n="$(jq -r --arg r "$repo" '.repositories[$r].required_checks.contexts // [] | length' "$POLICY")"
  u="$(jq -r --arg r "$repo" '.repositories[$r].required_checks.contexts // [] | unique | length' "$POLICY")"
  [[ "$n" == "$u" ]] || err "repository '$repo' lists a duplicate required context"
  while IFS= read -r ctx; do
    [[ -n "$ctx" ]] || err "repository '$repo' lists an empty required context — it would never be satisfied"
    [[ "$ctx" != "$(printf '%s' "$ctx" | sed 's/^ *//;s/ *$//')" ]] \
      && err "repository '$repo' context '$ctx' has leading or trailing whitespace; it would never match a job name"
  done < <(jq -r --arg r "$repo" '.repositories[$r].required_checks.contexts // [] | .[]' "$POLICY")
  while IFS= read -r t; do
    [[ -n "$t" ]] || continue
    jq -e --arg t "$t" '[.rulesets[].rules[].type] | index($t) != null' "$POLICY" >/dev/null \
      || err "repository '$repo' disables rule '$t', which no canonical ruleset declares"
  done < <(jq -r --arg r "$repo" '.repositories[$r].rules.disable // [] | .[]' "$POLICY")
done < <(jq -r '.repositories | keys[] | select(. != "_comment")' "$POLICY")
(( FAILED == before )) && echo "ok:    every per-repository override names contexts and rules that can actually take effect"

# --- 3f2. Parameter overrides: closed set, and a raise is not a weakening ---
# Two separate jobs here.
#
# First, the set of overridable parameters is declared in TWO places — the
# `overridable_parameters` registry (which carries the strictness direction) and
# the schema's parameterOverride properties (which enforce the type). Two
# spellings of one set is a standing drift risk, so they are asserted mutually
# derivable, exactly as the capability registry does for its two vocabularies.
#
# Second, and the reason the registry carries `stricter` at all: an override that
# RAISES a control above canonical is a repository choosing to be stricter, and
# applies cleanly. An override that LOWERS one is a weakening — still allowed,
# because repositories genuinely differ, but never silently. It must carry
# acknowledged_weakening plus a reason, and it is printed on every single run.
before=$FAILED
reg_names="$(jq -r '.overridable_parameters | keys[] | select(. != "_comment")' "$POLICY")"
schema_names="$(jq -r '.["$defs"].parameterOverride.properties | keys[]
                       | select(. != "_comment" and . != "acknowledged_weakening")' "$SCHEMA")"
while IFS= read -r n; do
  [[ -n "$n" ]] || continue
  grep -qxF "$n" <<<"$schema_names" \
    || err "overridable_parameters declares '$n', which the schema's parameterOverride does not accept — the override could never validate"
done <<<"$reg_names"
while IFS= read -r n; do
  [[ -n "$n" ]] || continue
  grep -qxF "$n" <<<"$reg_names" \
    || err "the schema accepts an override for '$n', which overridable_parameters does not declare — its strictness direction is unknown, so a weakening could not be detected"
done <<<"$schema_names"

# Every registry entry must name a rule the canonical rulesets actually declare,
# or an override against it would validate and then be silently ignored.
while IFS=$'\t' read -r name rule; do
  [[ -n "$name" ]] || continue
  jq -e --arg t "$rule" '[.rulesets[].rules[].type] | index($t) != null' "$POLICY" >/dev/null \
    || err "overridable parameter '$name' is declared on rule '$rule', which no canonical ruleset carries"
done < <(jq -r '.overridable_parameters | to_entries[] | select(.key != "_comment")
                | [.key, .value.rule] | @tsv' "$POLICY")

# Compare each override against canonical, in the direction the registry declares.
# Booleans are folded to 0/1 so this generalizes when a boolean dial is added.
while IFS=$'\t' read -r repo rule name canon over stricter ack has_comment; do
  [[ -n "$repo" ]] || continue
  if [[ -z "$stricter" || "$stricter" == "null" ]]; then
    err "repository '$repo' overrides '$name', which is not declared in overridable_parameters"
    continue
  fi
  declared_rule="$(jq -r --arg n "$name" '.overridable_parameters[$n].rule' "$POLICY")"
  if [[ "$declared_rule" != "$rule" ]]; then
    err "repository '$repo' attaches '$name' to rule '$rule', but it belongs to '$declared_rule' — the override would be silently ignored"
    continue
  fi
  if [[ "$canon" == "null" ]]; then
    err "repository '$repo' overrides '$name' on rule '$rule', which declares no such parameter canonically"
    continue
  fi
  weakens=no
  case "$stricter" in
    higher) (( over <  canon )) && weakens=yes ;;
    lower)  (( over >  canon )) && weakens=yes ;;
  esac
  if [[ "$weakens" == "no" ]]; then
    if (( over == canon )); then
      echo "note:  $repo overrides $name to $over, which equals canonical — the override is a no-op and could be deleted"
    else
      echo "ok:    $repo raises $name to $over (canonical $canon) — stricter than policy, applies cleanly"
    fi
  else
    # Visible on every run, acknowledged or not. That is the whole contract.
    echo "WEAKENS: $repo lowers $name to $over, below canonical $canon"
    [[ "$ack" == "true" ]] \
      || err "repository '$repo' lowers '$name' below canonical without acknowledged_weakening: true — a repository may be weaker than the standard, but never silently"
    [[ "$has_comment" == "yes" ]] \
      || err "repository '$repo' lowers '$name' below canonical with no _comment saying why"
  fi
done < <(jq -r '
  . as $p
  | $p.repositories | to_entries[] | select(.key != "_comment")
  | .key as $repo | .value.rules.parameters // {} | to_entries[] | select(.key != "_comment")
  | .key as $rule | .value | to_entries[]
  | select(.key != "_comment" and .key != "acknowledged_weakening")
  | .key as $name | .value as $over
  | ($p.rulesets[].rules[] | select(.type == $rule) | .parameters[$name]) as $canon
  | ($p.overridable_parameters[$name].stricter // "") as $stricter
  | ($p.repositories[$repo].rules.parameters[$rule].acknowledged_weakening // false) as $ack
  | (if ($p.repositories[$repo].rules.parameters[$rule]._comment // "") == "" then "no" else "yes" end) as $hc
  | [$repo, $rule, $name,
     (if $canon == null then "null" else ($canon | if type=="boolean" then (if . then 1 else 0 end) else . end | tostring) end),
     ($over | if type=="boolean" then (if . then 1 else 0 end) else . end | tostring),
     $stricter, ($ack | tostring), $hc] | @tsv' "$POLICY")
(( FAILED == before )) && echo "ok:    parameter overrides are a closed set, and every one is a raise or an acknowledged weakening"

# --- 3g. Actions concurrency classification is actionable ---
# The classification exists so a script can decide where a cancelling
# concurrency block belongs. A regex that does not compile, or a pattern
# claiming both classes, turns that decision into a coin flip.
before=$FAILED
while IFS= read -r re; do
  [[ -n "$re" ]] || continue
  jq -n --arg re "$re" '"probe" | test($re)' >/dev/null 2>&1 \
    || err "classification regex does not compile: $re"
done < <(jq -r '.actions.workflow_classification.classes[]
                | (.name_patterns[], (.content_signals[] | .pattern))' "$POLICY")

while IFS= read -r dupe; do
  [[ -n "$dupe" ]] || continue
  err "pattern '$dupe' appears in both workflow classes — a workflow matching it has no determinate class"
done < <(jq -r '.actions.workflow_classification.classes
                | [.cancellable.name_patterns[], (.cancellable.content_signals[] | .pattern)] as $c
                | [.never_cancel.name_patterns[], (.never_cancel.content_signals[] | .pattern)] as $n
                | ($c - ($c - $n))[]' "$POLICY")

[[ "$(jq -r '.actions.workflow_classification.classes.cancellable.apply_concurrency' "$POLICY")" == "true" ]] \
  || err "the cancellable class must set apply_concurrency=true; that is the entire point of the class"
[[ "$(jq -r '.actions.workflow_classification.classes.never_cancel.apply_concurrency' "$POLICY")" == "false" ]] \
  || err "the never_cancel class must set apply_concurrency=false — cancelling a deploy mid-run leaves external state half-written"
[[ "$(jq -r '.actions.concurrency["cancel-in-progress"]' "$POLICY")" == "true" ]] \
  || err "actions.concurrency must cancel in progress; otherwise it is the serializing block, not the cancelling one"
[[ "$(jq -r '.actions.serialize_concurrency["cancel-in-progress"]' "$POLICY")" == "false" ]] \
  || err "actions.serialize_concurrency must NOT cancel in progress"
jq -e '.actions.concurrency.group | test("github\\.workflow")' "$POLICY" >/dev/null \
  || err "actions.concurrency.group must include \${{ github.workflow }}; without it, unrelated workflows cancel each other"
(( FAILED == before )) && echo "ok:    workflow classification compiles, is unambiguous, and never cancels a stateful workflow"

# --- 3h. Version discipline ---
before=$FAILED
ver="$(jq -r '.version' "$POLICY")"
[[ "$ver" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || err "version '$ver' is not semver; the _contract pattern requires a bump on every content change"
[[ "$(jq -r '.schema_version' "$POLICY")" == "1" ]] \
  || err "schema_version must be 1"
(( FAILED == before )) && echo "ok:    policy version $ver, schema_version 1"

if (( FAILED > 0 )); then
  echo "GitHub repository policy check FAILED ($FAILED error(s))." >&2
  exit 1
fi
echo "GitHub repository policy check passed."
