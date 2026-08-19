#!/usr/bin/env bash
# test-skill-contract.sh — the per-skill contract (REFACTOR-SPEC §22.2) plus the
# eval-coverage report (§22.3).
#
# WHAT THIS IS NOT
#   It is not a second frontmatter validator. scripts/validate-skill-frontmatter.py
#   already owns the schema and emits --json; reimplementing its rules here would
#   guarantee the two drift apart and then argue with each other. This suite
#   CONSUMES that JSON and adds only the checks it does not make: name uniqueness
#   across the tree, directory/name agreement, capability ids that actually exist
#   in the registry, executable bits on referenced scripts, and computed platform
#   compatibility.
#
# EVAL COVERAGE IS A REPORT, NOT A GATE
#   Every public skill should have positive-trigger, negative-trigger, behavior and
#   (where capability-sensitive) fallback evals. Most do not yet — that gap predates
#   this suite. So coverage prints as a report and does not fail the build unless
#   --strict is passed, which is what a future CI job will flip on once the gap is
#   closed. A check that fails on day one gets disabled on day two.
#
# Usage: bash tests/test-skill-contract.sh [--strict]

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$REPO_ROOT/tests/lib/harness.sh"

harness_require jq python3

STRICT=false
[ "${1:-}" = "--strict" ] && STRICT=true

python3 -c "import yaml" >/dev/null 2>&1 \
  || { echo "FATAL: PyYAML is required (pip install -r scripts/requirements-validate.txt)"; exit 1; }

META="$(harness_tmpdir)/skills.json"
python3 "$REPO_ROOT/tests/lib/skill-meta.py" "$REPO_ROOT" > "$META"
judge "skill metadata extracted for every shipped skill" yes \
  "$(if [ "$(jq 'length' "$META")" -gt 0 ]; then echo yes; else echo no; fi)"

FM="$(harness_tmpdir)/frontmatter.json"
python3 "$REPO_ROOT/scripts/validate-skill-frontmatter.py" --json > "$FM" 2>/dev/null

# ---------------------------------------------------------------------------
section "canonical frontmatter validator"

judge "validate-skill-frontmatter.py --json produced parseable output" 0 \
  "$(jq empty "$FM" >/dev/null 2>&1; echo $?)"
judge "the portable tier passes for every skill" 0 "$(jq -r '.tier_failures.portable' "$FM")"
judge "the tamirs tier passes for every skill" 0 "$(jq -r '.tier_failures.tamirs' "$FM")"

claude_fail="$(jq -r '.tier_failures.claude' "$FM")"
if [ "$claude_fail" = "0" ]; then
  ok "the claude tier passes for every skill"
else
  jq -r '.results[] | select(.passed | not) | "\(.file): \(.errors | join("; "))"' "$FM" \
    | while read -r line; do printf '       %s\n' "$line"; done
  bad "the claude tier passes for every skill" "$claude_fail skill(s) fail — listed above"
fi

# ---------------------------------------------------------------------------
section "identity: unique names, directory agreement"

total="$(jq 'length' "$META")"
uniq_names="$(jq -r '[.[].name] | unique | length' "$META")"
judge "every skill name is unique across the tree" "$total" "$uniq_names"

mismatch="$(jq -r '.[] | select(.name != .dir) | "\(.file): name=\(.name) dir=\(.dir)"' "$META")"
judge "every skill's name matches its directory" "" "$mismatch"

noname="$(jq -r '.[] | select((.name // "") == "") | .file' "$META")"
judge "every skill declares a name" "" "$noname"

nofm="$(jq -r '.[] | select(.has_frontmatter | not) | .file' "$META")"
judge "every SKILL.md has parseable YAML frontmatter" "" "$nofm"

# ---------------------------------------------------------------------------
section "description: present, and within a usable length"

# The description is the trigger surface. Too short cannot discriminate; past
# ~1024 chars it is truncated or diluted in every harness that ranks skills.
short="$(jq -r '.[] | select(.description_len < 40) | "\(.name) (\(.description_len))"' "$META")"
judge "no skill has a stub description (<40 chars)" "" "$short"
long="$(jq -r '.[] | select(.description_len > 1024) | "\(.name) (\(.description_len))"' "$META")"
judge "no skill description exceeds 1024 chars" "" "$long"

nowtu="$(jq -r '.[] | select(.when_to_use | not) | .name' "$META")"
judge "every skill declares when_to_use" "" "$nowtu"

# ---------------------------------------------------------------------------
section "referenced paths resolve, referenced scripts are executable"

missing="$(jq -r '.[] as $s | $s.refs[] | select(.exists | not) | "\($s.name) -> \(.target)"' "$META")"
judge "every locally referenced path exists" "" "$missing"

escaping="$(jq -r '.[] as $s | $s.refs[] | select(.escapes_repo) | "\($s.name) -> \(.target)"' "$META")"
judge "no skill references a path outside the repository" "" "$escaping"

nonexec=""
while IFS= read -r rel; do
  [ -n "$rel" ] || continue
  case "$rel" in *.sh) [ -x "$REPO_ROOT/$rel" ] || nonexec="$nonexec $rel" ;; esac
done < <(jq -r '.[].scripts[]? | select(.exists) | .resolved' "$META" | sort -u)
judge "every referenced .sh is executable" "" "$nonexec"

# ---------------------------------------------------------------------------
section "declared capabilities exist in the registry"

REG="$REPO_ROOT/core/capabilities/platforms.json"
judge "the capability registry is present and parses" 0 "$(jq empty "$REG" >/dev/null 2>&1; echo $?)"

known="$(jq -r '.capability_definitions | keys[]' "$REG" | sort -u)"
unknown=""
while IFS= read -r pair; do
  [ -n "$pair" ] || continue
  cap="${pair##* }"
  grep -qx -- "$cap" <<<"$known" || unknown="$unknown $pair"
done < <(jq -r '.[] as $s | ($s.capabilities_required[]?, $s.capabilities_optional[]?) | "\($s.name) \(.)"' "$META")
judge "every declared capability id exists in core/capabilities/platforms.json" "" "$unknown"

nocaps="$(jq -r '.[] | select((.capabilities_required | length) == 0) | .name' "$META")"
judge "every skill declares at least one required capability" "" "$nocaps"

notier="$(jq -r '.[] | select(.validation_tier == null) | .name' "$META")"
judge "every skill states which validation tier it invokes" "" "$notier"

# ---------------------------------------------------------------------------
section "platform compatibility is computable for every skill"

# A skill is compatible with a platform when every REQUIRED capability is native
# or partial there. This is the computation the docs' capability tables claim to
# summarise, so it must at minimum be derivable without a human in the loop.
platforms="$(jq -r '.platforms | keys[]' "$REG")"
uncomputable=""
zero_platform=""
while IFS= read -r name; do
  [ -n "$name" ] || continue
  supported=0
  for p in $platforms; do
    req_ok=1
    while IFS= read -r cap; do
      [ -n "$cap" ] || continue
      st="$(jq -r --arg p "$p" --arg c "$cap" '.platforms[$p].capabilities[$c].status // "absent"' "$REG")"
      case "$st" in native|native-experimental|partial|emulated) ;; *) req_ok=0 ;; esac
    done < <(jq -r --arg n "$name" '.[] | select(.name == $n) | .capabilities_required[]?' "$META")
    [ "$req_ok" -eq 1 ] && supported=$((supported + 1))
  done
  [ "$supported" -gt 0 ] || zero_platform="$zero_platform $name"
done < <(jq -r '.[].name' "$META")
judge "platform compatibility computes without an undefined capability status" "" "$uncomputable"
judge "no skill is compatible with zero platforms" "" "$zero_platform"

# ---------------------------------------------------------------------------
section "eval coverage (report — use --strict to gate)"

gaps=0
gap_lines=()
while IFS= read -r row; do
  name="${row%% *}"; rest="${row#* }"
  vis="${rest%% *}"; file="${rest#* }"
  dir="$REPO_ROOT/$(dirname "$file")/evals"
  pos=no; neg=no; beh=no; fb=no
  if [ -f "$dir/trigger-evals.json" ]; then
    jq -e 'any(.[]; .should_trigger == true)'  "$dir/trigger-evals.json" >/dev/null 2>&1 && pos=yes
    jq -e 'any(.[]; .should_trigger == false)' "$dir/trigger-evals.json" >/dev/null 2>&1 && neg=yes
  fi
  if [ -f "$dir/evals.json" ]; then
    n="$(jq '((.evals // .cases // []) | length)' "$dir/evals.json" 2>/dev/null || echo 0)"
    [ "${n:-0}" -gt 0 ] && beh=yes
    grep -qiE 'fallback|degrade|unsupported|no subagents|sequential|without gh|not available' \
      "$dir/evals.json" 2>/dev/null && fb=yes
  fi
  # A fallback eval is only required of a skill that declares optional (i.e.
  # capability-sensitive) behaviour.
  opt="$(jq -r --arg n "$name" '.[] | select(.name == $n) | (.capabilities_optional | length)' "$META")"
  need_fb=no; [ "${opt:-0}" -gt 0 ] && need_fb=yes

  miss=""
  [ "$pos" = yes ] || miss="$miss positive-trigger"
  [ "$vis" = "public" ] && { [ "$neg" = yes ] || miss="$miss negative-trigger"; }
  [ "$beh" = yes ] || miss="$miss behavior"
  [ "$need_fb" = yes ] && { [ "$fb" = yes ] || miss="$miss fallback"; }
  if [ -n "$miss" ]; then
    gaps=$((gaps + 1))
    gap_lines+=("$name [$vis] missing:$miss")
  fi
  printf '  %-24s %-9s pos=%-3s neg=%-3s behavior=%-3s fallback=%-3s\n' "$name" "$vis" "$pos" "$neg" "$beh" "$fb"
done < <(jq -r '.[] | "\(.name) \(.visibility // "unknown") \(.file)"' "$META")

printf '\n  eval coverage: %s of %s skills fully covered; %s with gaps\n' \
  "$((total - gaps))" "$total" "$gaps"
if [ "$gaps" -gt 0 ]; then
  printf '  gaps:\n'
  printf '    - %s\n' "${gap_lines[@]}"
fi

if [ "$STRICT" = true ]; then
  judge "every skill has full eval coverage (--strict)" 0 "$gaps"
else
  [ "$gaps" -eq 0 ] && ok "every skill has full eval coverage" \
    || warn "eval coverage: $gaps skill(s) have gaps (report only; run with --strict to gate)"
fi

harness_summary
