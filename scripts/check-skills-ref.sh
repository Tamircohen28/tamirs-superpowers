#!/usr/bin/env bash
# check-skills-ref.sh — run the Agent Skills reference validator over every shipped skill.
# Validation tier: 2 (static; shells out to the spec's own validator, no test execution).
#
# Usage:
#   check-skills-ref.sh [repo-root] [--spec-strict]
#   check-skills-ref.sh -h | --help
#
# WHAT THIS ADDS OVER scripts/validate-skill-frontmatter.py
#   That script is the executable form of core/schemas/skill-frontmatter.json: it knows
#   this repo's three tiers and its Claude extension fields. It is NOT the Agent Skills
#   spec. `skills-ref` (the reference library behind agentskills.io/specification) is,
#   and it checks three things ours does not, or does differently:
#     - `name` MUST equal the parent directory name, 1-64 chars, lowercase a-z 0-9 and
#       hyphens, no leading/trailing/consecutive hyphens (ours checks name<->dir only on
#       the claude tier and accepts the schema's own pattern);
#     - `description` is 1-1024 chars and `compatibility` 1-500 chars, measured by the
#       spec's own rules rather than by the listing cap ours applies;
#     - the frontmatter is CLOSED to the portable set `name`, `description`, `license`,
#       `compatibility`, `metadata`, `allowed-tools` — every other key is rejected.
#
# KNOWN, DOCUMENTED DIVERGENCES (reported as `div`, never silently dropped)
#   Two findings are expected on this tree today and do not fail the run unless
#   --spec-strict is passed. Both are recorded, per skill, on every run so a reviewer
#   can see exactly how far from the spec the tree is:
#     1. "Unexpected fields in frontmatter" — this repo ships Claude's documented
#        extension fields (`effort`, `user-invocable`, `context`, ...). The finding is
#        accepted ONLY when every named field is a top-level property declared in
#        core/schemas/skill-frontmatter.json; a field the schema does not know fails.
#     2. "Field 'compatibility' must be a string" — the spec says free text (<=500
#        chars); our schema deliberately makes it a platform -> support-level map (see
#        the $comment on $defs.compatibility). Closing this needs a schema decision, not
#        a per-skill edit, so it is reported, not patched here.
#   Everything else `skills-ref` reports — name/directory mismatch, name format or
#   length, a missing or over-long description, an unreadable path — fails the run.
#
# RESOLVING THE TOOL
#   `npx --yes skills-ref@<pinned> validate <dir>`. The version is pinned so a registry
#   release cannot change the gate's verdict under us. When npm cannot reach the registry
#   the script prints `skills-ref: SKIP (offline)` and exits 0 — a missing network must
#   never read as a passing validation, but it must not block a contributor on a train
#   either. The SKIP is printed only when `npm ping` fails; any other failure to resolve
#   or run the tool is an error (exit 1). This script names a package launcher, so it is
#   pruned from the Claude distribution (the directory's checker rejects `npx` in shipped
#   scripts) — it is a contributor/CI tool, not a user-facing one.
#
# Output: one line per skill (`ok`, `div`, `FAIL`), then a machine-readable summary line
#   skills-ref: <n> skills, <ok> ok, <div> with known divergences, <fail> failed
# Exit 0 when nothing failed; 1 otherwise; 0 with the SKIP line when offline.
set -euo pipefail

SKILLS_REF_VERSION="0.1.5"
PORTABLE_FIELDS="name description license compatibility metadata allowed-tools"

usage() { sed -n '2,45p' "$0" | sed -E 's/^# ?//'; exit "${1:-0}"; }

ROOT=""
SPEC_STRICT=0
for arg in "$@"; do
  case "$arg" in
    -h|--help) usage 0 ;;
    --spec-strict) SPEC_STRICT=1 ;;
    -*) echo "ERROR: unknown option: $arg" >&2; usage 2 ;;
    *) ROOT="$arg" ;;
  esac
done
ROOT="$(cd "${ROOT:-.}" && pwd)"
SCHEMA="$ROOT/core/schemas/skill-frontmatter.json"

for tool in npx npm jq; do
  command -v "$tool" >/dev/null 2>&1 || { echo "ERROR: $tool is required by check-skills-ref.sh" >&2; exit 1; }
done
[[ -f "$SCHEMA" ]] || { echo "ERROR: missing $SCHEMA (needed to know which extension fields are documented)" >&2; exit 1; }
[[ -d "$ROOT/skills" ]] || { echo "ERROR: no skills/ directory under $ROOT" >&2; exit 1; }

# The documented extension set: every top-level property the schema declares that is
# not one of the spec's portable six. Read at run time so a field added to the schema
# is accepted and a field someone invents in one SKILL.md is not.
EXT_FIELDS="$(jq -r '.properties | keys[]' "$SCHEMA")"
is_portable()  { case " $PORTABLE_FIELDS " in *" $1 "*) return 0 ;; esac; return 1; }
is_extension() { grep -qx -- "$1" <<<"$EXT_FIELDS"; }

# --- resolve the validator -------------------------------------------------------
# Prefer the npx cache so a cached pin still runs offline; fall back to the registry.
export npm_config_prefer_offline=true
export npm_config_update_notifier=false
export npm_config_fund=false
export npm_config_audit=false
run_ref() { npx --yes "skills-ref@$SKILLS_REF_VERSION" "$@"; }

if ! resolved="$(run_ref --version 2>&1)"; then
  # Could not resolve the tool. Offline is the one excusable reason.
  if npm_config_fetch_retries=0 npm ping >/dev/null 2>&1; then
    echo "ERROR: could not run skills-ref@$SKILLS_REF_VERSION although the registry is reachable:" >&2
    printf '%s\n' "$resolved" | sed 's/^/  /' >&2
    exit 1
  fi
  echo "skills-ref: SKIP (offline) — npm cannot reach the registry; skills-ref@$SKILLS_REF_VERSION not run"
  exit 0
fi
echo "skills-ref $resolved (pinned $SKILLS_REF_VERSION)"

# --- collect the skill directories -------------------------------------------------
# Shipped skills are skills/<category>/<name>/SKILL.md. `_contract/` holds the contract
# fixtures and `fixtures/` the negative test cases; neither ships.
dirs=()
while IFS= read -r f; do
  d="$(dirname "$f")"
  case "$d" in */_contract/*|*/_contract|*/fixtures/*|*/fixtures) continue ;; esac
  dirs+=("$d")
done < <(find "$ROOT/skills" -mindepth 3 -maxdepth 3 -name SKILL.md | sort)
[[ ${#dirs[@]} -gt 0 ]] || { echo "ERROR: no skills/*/*/SKILL.md found under $ROOT" >&2; exit 1; }

# classify_finding <line> -> prints "div" or "fail" plus a reason on stdout
classify_finding() {
  local line="$1" fields f unknown=""
  case "$line" in
    "Unexpected fields in frontmatter: "*)
      fields="${line#Unexpected fields in frontmatter: }"
      fields="${fields%%. Only *}"
      for f in ${fields//,/ }; do
        is_portable "$f" && continue
        is_extension "$f" || unknown="$unknown $f"
      done
      if [[ -n "$unknown" ]]; then
        printf 'fail undocumented frontmatter field(s):%s (not declared in core/schemas/skill-frontmatter.json)\n' "$unknown"
      else
        printf 'div documented Claude extension fields (spec closes frontmatter to the portable set)\n'
      fi ;;
    "Field 'compatibility' must be a string")
      printf 'div compatibility is a platform map by schema design; spec wants a string\n' ;;
    *)
      printf 'fail %s\n' "$line" ;;
  esac
}

n_ok=0; n_div=0; n_fail=0
for d in "${dirs[@]}"; do
  rel="${d#"$ROOT"/}"
  if out="$(run_ref validate "$d" 2>&1)"; then
    n_ok=$((n_ok + 1)); printf '  ok   %s\n' "$rel"; continue
  fi
  skill_fail=0; reasons=()
  found=0
  while IFS= read -r line; do
    [[ "$line" == "  - "* ]] || continue
    found=1
    verdict="$(classify_finding "${line#  - }")"
    kind="${verdict%% *}"; reason="${verdict#* }"
    if [[ "$kind" == "fail" || "$SPEC_STRICT" -eq 1 ]]; then skill_fail=1; fi
    reasons+=("$kind: $reason")
  done <<<"$out"
  if [[ "$found" -eq 0 ]]; then
    # Non-zero exit with no finding lines: the tool itself broke. Never read that as ok.
    skill_fail=1; reasons+=("fail: skills-ref exited non-zero without findings: $(printf '%s' "$out" | head -3 | tr '\n' ' ')")
  fi
  if [[ "$skill_fail" -eq 1 ]]; then
    n_fail=$((n_fail + 1)); printf '  FAIL %s\n' "$rel"
  else
    n_div=$((n_div + 1)); printf '  div  %s\n' "$rel"
  fi
  printf '         - %s\n' "${reasons[@]}"
done

total=$((n_ok + n_div + n_fail))
printf 'skills-ref: %d skills, %d ok, %d with known divergences, %d failed\n' "$total" "$n_ok" "$n_div" "$n_fail"
if [[ "$n_div" -gt 0 && "$SPEC_STRICT" -eq 0 ]]; then
  echo "note: divergences are documented in this script's header; pass --spec-strict to fail on them"
fi
[[ "$n_fail" -eq 0 ]]
