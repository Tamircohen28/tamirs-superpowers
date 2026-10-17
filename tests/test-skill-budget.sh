#!/usr/bin/env bash
# test-skill-budget.sh — the three measurable trust gates added in V5 Phase 4:
#   scripts/check-skills-ref.sh      the Agent Skills reference validator over every skill
#   scripts/check-token-budget.sh    the always-on token cost held to evals/budget.json
#   tests/test-skill-contract.sh     --strict eval coverage (exercised here only through
#                                    the budget file; strict itself is its own CI step)
#
# WHY THIS FILE EXISTS
#   A gate that has never been seen to fail is a gate nobody can trust. Each case here
#   plants the condition the gate exists to catch — a lower committed baseline, a
#   crossed ceiling, a CLI output of the wrong shape, a skill whose `name` disagrees
#   with its folder — and asserts the gate fires, next to the clean case that asserts it
#   does not. The budget script is driven through `--from <file>` with a captured copy
#   of the real `claude plugin details` output, so the parsing and comparison are tested
#   hermetically on a machine with no claude CLI; the live measurement runs only when the
#   CLI and the plugin are both present, and is reported as skipped (with the reason)
#   otherwise, never as passing.
#
# Usage: bash tests/test-skill-budget.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$REPO_ROOT/tests/lib/harness.sh"

harness_require jq bash

BUDGET="$REPO_ROOT/evals/budget.json"
BUDGET_SH="$REPO_ROOT/scripts/check-token-budget.sh"
REF_SH="$REPO_ROOT/scripts/check-skills-ref.sh"
TMP="$(harness_tmpdir)"

# ---------------------------------------------------------------------------
section "evals/budget.json: the committed baseline is well-formed"

judge "evals/budget.json exists" yes "$(exists "$BUDGET")"
judge "evals/budget.json parses" 0 "$(jq empty "$BUDGET" >/dev/null 2>&1; echo $?)"
for key in always_on_tokens ceiling tolerance_percent; do
  judge "budget.$key is a non-negative integer" true \
    "$(jq -r --arg k "$key" '(.[$k] | type == "number") and (.[$k] >= 0) and (.[$k] == (.[$k] | floor))' "$BUDGET")"
done
for key in measured_on measured_at; do
  judge "budget.$key is a non-empty string" true \
    "$(jq -r --arg k "$key" '(.[$k] | type == "string") and ((.[$k] | length) > 0)' "$BUDGET")"
done
judge "budget.measured_at is an ISO date" yes \
  "$(if jq -r '.measured_at' "$BUDGET" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then echo yes; else echo no; fi)"
judge "budget.ceiling is not below the committed baseline" true \
  "$(jq -r '.ceiling >= .always_on_tokens' "$BUDGET")"
judge "a ceiling above the 2,000-token marketplace highlight carries a note saying why" yes \
  "$(if [ "$(jq -r '.ceiling' "$BUDGET")" -le 2000 ] || [ "$(jq -r '(.note // "") | length' "$BUDGET")" -gt 0 ]; then echo yes; else echo no; fi)"

judge "scripts/check-token-budget.sh is executable" yes "$(if [ -x "$BUDGET_SH" ]; then echo yes; else echo no; fi)"
judge "scripts/check-skills-ref.sh is executable" yes "$(if [ -x "$REF_SH" ]; then echo yes; else echo no; fi)"

# ---------------------------------------------------------------------------
section "check-token-budget.sh: parsing and comparison (hermetic, via --from)"

# A verbatim copy of the shape `claude plugin details` prints (2.1.302). The figure is
# chosen so it sits inside the committed tolerance but above a planted lower baseline.
baseline="$(jq -r '.always_on_tokens' "$BUDGET")"
DETAILS="$TMP/details.txt"
cat > "$DETAILS" <<EOF
Tamir's Superpowers (tamirs-superpowers) 0.0.0
  Description: fixture

Component inventory
  Skills (29)  a, b
  Hooks (13)  PreToolUse  (harness-only — no model context cost)

Projected token cost
  Always-on:   ~$(printf '%d' "$baseline" | sed -E ':a;s/([0-9])([0-9]{3})($|,)/\1,\2\3/;ta') tok   added to every session

Per-component (rounded)
  component              always-on  on-invoke
  a                           ~250      ~5.5k
EOF

# Clean case: committed budget, committed figure -> within budget.
out="$(bash "$BUDGET_SH" "$REPO_ROOT" --from "$DETAILS" 2>&1)"; rc=$?
judge "committed figure against the committed budget passes" 0 "$rc"
judge "the summary line reports the parsed figure" yes "$(has "$out" "measured $baseline always-on tokens")"
judge "the summary echoes the CLI's own Always-on line" yes "$(has "$out" "cli line: Always-on:")"

# Planted lower baseline (half the committed figure) -> fails on tolerance.
LOW="$TMP/low.json"
jq '.always_on_tokens = ((.always_on_tokens / 2) | floor)' "$BUDGET" > "$LOW"
out="$(bash "$BUDGET_SH" "$REPO_ROOT" --from "$DETAILS" --budget "$LOW" 2>&1)"; rc=$?
judge "a figure more than tolerance_percent above the baseline fails" 1 "$rc"
judge "the tolerance failure names the baseline and the --update remedy" yes \
  "$(if [ "$(has "$out" "above the committed baseline")" = yes ] && [ "$(has "$out" "--update")" = yes ]; then echo yes; else echo no; fi)"

# Planted ceiling below the figure -> fails on the ceiling even though the baseline is fine.
CEIL="$TMP/ceil.json"
jq '.ceiling = (.always_on_tokens - 1)' "$BUDGET" > "$CEIL"
out="$(bash "$BUDGET_SH" "$REPO_ROOT" --from "$DETAILS" --budget "$CEIL" 2>&1)"; rc=$?
judge "a figure above the ceiling fails regardless of the baseline" 1 "$rc"
judge "the ceiling failure says 'ceiling'" yes "$(has "$out" "exceeds the ceiling")"

# Figure inside the tolerance -> passes. (baseline + 5% when tolerance is 10%.)
MID="$TMP/mid.txt"
sed -E "s/~[0-9,]+ tok/~$(( baseline + baseline * 5 / 100 )) tok/" "$DETAILS" > "$MID"
HIGHCEIL="$TMP/highceil.json"
jq '.ceiling = 1000000' "$BUDGET" > "$HIGHCEIL"
rc="$(bash "$BUDGET_SH" "$REPO_ROOT" --from "$MID" --budget "$HIGHCEIL" >/dev/null 2>&1; echo $?)"
judge "a figure within tolerance_percent of the baseline passes" 0 "$rc"

# --update into a temp copy rewrites the three measurement fields and nothing else.
UPD="$TMP/upd.json"
jq '.always_on_tokens = 1 | .measured_on = "0.0.0" | .measured_at = "1970-01-01" | .ceiling = 1000000' "$BUDGET" > "$UPD"
rc="$(bash "$BUDGET_SH" "$REPO_ROOT" --from "$DETAILS" --budget "$UPD" --update >/dev/null 2>&1; echo $?)"
judge "--update accepting a figure far above the old baseline exits 0 (the tolerance is recomputed from the new baseline)" 0 "$rc"
rc="$(bash "$BUDGET_SH" "$REPO_ROOT" --from "$DETAILS" --budget "$UPD" >/dev/null 2>&1; echo $?)"
judge "the updated budget passes a plain run" 0 "$rc"
judge "--update rewrites always_on_tokens to the measured figure" "$baseline" "$(jq -r '.always_on_tokens' "$UPD")"
judge "--update stamps measured_at with today's UTC date" "$(date -u +%Y-%m-%d)" "$(jq -r '.measured_at' "$UPD")"
judge "--update replaces the placeholder measured_on" no "$(has "$(jq -r '.measured_on' "$UPD")" "0.0.0")"
judge "--update leaves ceiling, tolerance_percent and note alone" "$(jq -c '{ceiling: 1000000, tolerance_percent, note}' "$BUDGET")" \
  "$(jq -c '{ceiling, tolerance_percent, note}' "$UPD")"
judge "--update does not touch the committed evals/budget.json" "$baseline" "$(jq -r '.always_on_tokens' "$BUDGET")"

# Wrong-shape CLI output fails loudly instead of reading 0.
GARBAGE="$TMP/garbage.txt"
printf 'Projected token cost\n  Always-on: lots\n' > "$GARBAGE"
out="$(bash "$BUDGET_SH" "$REPO_ROOT" --from "$GARBAGE" 2>&1)"; rc=$?
judge "CLI output without an 'Always-on: ~N tok' line fails" 1 "$rc"
judge "the parse failure says the shape may have changed" yes "$(has "$out" "shape may have changed")"
judge "the parse failure never reports a measured figure of 0" no "$(has "$out" "measured 0 always-on")"

TWICE="$TMP/twice.txt"
cat "$DETAILS" "$DETAILS" > "$TWICE"
rc="$(bash "$BUDGET_SH" "$REPO_ROOT" --from "$TWICE" >/dev/null 2>&1; echo $?)"
judge "two Always-on lines (ambiguous output) fail rather than picking one" 1 "$rc"

BADBUDGET="$TMP/bad-budget.json"
jq 'del(.ceiling)' "$BUDGET" > "$BADBUDGET"
rc="$(bash "$BUDGET_SH" "$REPO_ROOT" --from "$DETAILS" --budget "$BADBUDGET" >/dev/null 2>&1; echo $?)"
judge "a budget file missing one of the five fields fails" 1 "$rc"

# ---------------------------------------------------------------------------
section "check-token-budget.sh: live measurement (needs the claude CLI and the installed plugin)"

if harness_have claude && claude plugin details tamirs-superpowers >/dev/null 2>&1; then
  out="$(bash "$BUDGET_SH" "$REPO_ROOT" 2>&1)"; rc=$?
  if [ "$rc" -eq 0 ]; then
    ok "live always-on cost is within evals/budget.json"
  else
    bad "live always-on cost is within evals/budget.json" \
      "$(printf '%s' "$out" | grep -E '^(FAIL|ERROR)' | head -2 | tr '\n' ' ')"
  fi
else
  skip "live always-on cost is within evals/budget.json" \
    "claude CLI absent or tamirs-superpowers not installed — the hermetic cases above cover the logic"
fi

# ---------------------------------------------------------------------------
section "check-skills-ref.sh: the Agent Skills reference validator"

# Offline is a documented SKIP (exit 0 with the SKIP line), never a silent pass. Every
# assertion below branches on which of the two the tree run produced.
tree_out="$(bash "$REF_SH" "$REPO_ROOT" 2>&1)"; tree_rc=$?
if [ "$(has "$tree_out" "skills-ref: SKIP (offline)")" = yes ]; then
  judge "offline run exits 0" 0 "$tree_rc"
  skip "every shipped skill passes skills-ref (modulo documented divergences)" "offline — skills-ref not run"
  skip "a skill whose name differs from its folder fails skills-ref" "offline — skills-ref not run"
else
  judge "every shipped skill passes skills-ref (modulo documented divergences)" 0 "$tree_rc"
  judge "the run ends with the machine-readable summary line" yes \
    "$(if printf '%s\n' "$tree_out" | grep -qE '^skills-ref: [0-9]+ skills, [0-9]+ ok, [0-9]+ with known divergences, 0 failed$'; then echo yes; else echo no; fi)"
  n_skills="$(printf '%s\n' "$tree_out" | sed -nE 's/^skills-ref: ([0-9]+) skills,.*/\1/p')"
  n_tree="$(find "$REPO_ROOT/skills" -mindepth 3 -maxdepth 3 -name SKILL.md -not -path '*/_contract/*' -not -path '*/fixtures/*' | wc -l | tr -d ' ')"
  judge "the validator saw every shipped skill" "$n_tree" "$n_skills"

  # Planted tree: one skill whose name disagrees with its folder, one that is fine
  # apart from a documented extension field. The schema is copied so the extension
  # allow-list resolves the same way it does on the real tree.
  PLANT="$TMP/plant"
  mkdir -p "$PLANT/core/schemas" "$PLANT/skills/x/bad-skill" "$PLANT/skills/x/good-skill"
  cp "$REPO_ROOT/core/schemas/skill-frontmatter.json" "$PLANT/core/schemas/"
  printf -- '---\nname: other-name\ndescription: A skill whose name differs from its folder.\n---\n# Bad\n' > "$PLANT/skills/x/bad-skill/SKILL.md"
  printf -- '---\nname: good-skill\ndescription: A skill with one documented extension field.\neffort: low\n---\n# Good\n' > "$PLANT/skills/x/good-skill/SKILL.md"
  out="$(bash "$REF_SH" "$PLANT" 2>&1)"; rc=$?
  judge "a skill whose name differs from its folder fails skills-ref" 1 "$rc"
  judge "the mismatch is reported against the right skill" yes "$(has "$out" "FAIL skills/x/bad-skill")"
  judge "the mismatch reason is the validator's own words" yes "$(has "$out" "must match skill name")"
  judge "a documented extension field is a divergence, not a failure" yes "$(has "$out" "div  skills/x/good-skill")"
  judge "the planted summary counts one failure" yes "$(has "$out" "2 skills, 0 ok, 1 with known divergences, 1 failed")"

  # An undocumented field is NOT covered by the extension allowance.
  printf -- '---\nname: good-skill\ndescription: A skill with a field the schema does not know.\nmade-up-field: 1\n---\n# Good\n' > "$PLANT/skills/x/good-skill/SKILL.md"
  rm -rf "$PLANT/skills/x/bad-skill"
  out="$(bash "$REF_SH" "$PLANT" 2>&1)"; rc=$?
  judge "a frontmatter field the schema does not declare fails" 1 "$rc"
  judge "the undocumented field is named" yes "$(has "$out" "made-up-field")"

  # --spec-strict promotes divergences to failures.
  printf -- '---\nname: good-skill\ndescription: A skill with one documented extension field.\neffort: low\n---\n# Good\n' > "$PLANT/skills/x/good-skill/SKILL.md"
  rc="$(bash "$REF_SH" "$PLANT" --spec-strict >/dev/null 2>&1; echo $?)"
  judge "--spec-strict fails on a documented divergence" 1 "$rc"
fi

harness_summary
