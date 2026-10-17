#!/usr/bin/env bash
# check-token-budget.sh — hold the plugin's always-on context cost to a committed budget.
# Validation tier: 3 (needs the Claude Code CLI with the plugin installed; CI's
# plugin-validate job, not the skill-contract job).
#
# Usage:
#   check-token-budget.sh [repo-root] [--update] [--from <details-output-file>]
#                         [--plugin <name>] [--budget <file>]
#   check-token-budget.sh -h | --help
#
# WHAT IT MEASURES
#   `claude plugin details <plugin>` prints a "Projected token cost" block whose
#   "Always-on" figure is the context every session pays before any skill fires: the
#   name + description + when_to_use of every skill and agent. The official marketplace
#   highlights that figure to users pre-install once it reaches 2,000 tokens, so it is a
#   number that decides whether people install the plugin at all. This script reads it
#   and compares it to evals/budget.json:
#     always_on_tokens   the committed baseline (last accepted measurement)
#     ceiling            the hard cap; measured > ceiling fails regardless of baseline
#     tolerance_percent  how far above the baseline a measurement may drift before
#                        failing (a few tokens of description tuning is noise; a new
#                        skill is not)
#     measured_on        the `claude --version` the baseline was taken with
#     measured_at        the UTC date of that measurement
#     note               free text; records why the ceiling sits where it does
#
# FAIL CONDITIONS (exit 1)
#   - measured > ceiling
#   - measured > always_on_tokens * (1 + tolerance_percent/100)
#   - the CLI output does not contain exactly one "Always-on: ~N tok" line, or N is not
#     a number. A shape change in the CLI fails loudly; nothing is ever parsed as 0.
#   - the plugin is not installed (exit 1 with the install commands), or the installed
#     copy reads from a different checkout than <repo-root> (then the figure would
#     describe someone else's tree).
#
# UPDATING THE BASELINE
#   --update rewrites always_on_tokens, measured_on and measured_at from the current
#   measurement and keeps ceiling, tolerance_percent and note. Use it in the same PR
#   that legitimately changes the figure, so the diff shows the cost next to its cause.
#   It does not raise the ceiling; edit that by hand, with a note.
#
# --from <file> reads a saved `claude plugin details` output instead of running the
#   CLI, for tests and for reviewing a figure someone pasted into a PR. The checkout
#   match is not verified in that mode (there is no live install to compare).
#
# Exit 0 when within budget; 1 on any failure.
set -euo pipefail

usage() { sed -n '2,44p' "$0" | sed -E 's/^# ?//'; exit "${1:-0}"; }

ROOT=""
UPDATE=0
FROM=""
PLUGIN="tamirs-superpowers"
MARKETPLACE="tamirs-superpowers"
BUDGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --update) UPDATE=1 ;;
    --from) FROM="${2:?--from needs a file}"; shift ;;
    --plugin) PLUGIN="${2:?--plugin needs a name}"; shift ;;
    --budget) BUDGET="${2:?--budget needs a file}"; shift ;;
    -*) echo "ERROR: unknown option: $1" >&2; usage 2 ;;
    *) ROOT="$1" ;;
  esac
  shift
done
ROOT="$(cd "${ROOT:-.}" && pwd)"
BUDGET="${BUDGET:-$ROOT/evals/budget.json}"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required by check-token-budget.sh" >&2; exit 1; }
[[ -f "$BUDGET" ]] || { echo "ERROR: missing budget file $BUDGET" >&2; exit 1; }
jq empty "$BUDGET" 2>/dev/null || { echo "ERROR: $BUDGET is not valid JSON" >&2; exit 1; }

# Every field the comparison depends on must be present and numeric; a missing field
# must not default to something that happens to pass.
for key in always_on_tokens ceiling tolerance_percent; do
  v="$(jq -r --arg k "$key" '.[$k] // empty' "$BUDGET")"
  [[ "$v" =~ ^[0-9]+$ ]] || { echo "ERROR: $BUDGET: '$key' must be a non-negative integer (got '${v:-missing}')" >&2; exit 1; }
done
for key in measured_on measured_at; do
  jq -e --arg k "$key" '.[$k] | type == "string" and length > 0' "$BUDGET" >/dev/null 2>&1 \
    || { echo "ERROR: $BUDGET: '$key' must be a non-empty string" >&2; exit 1; }
done
baseline="$(jq -r '.always_on_tokens' "$BUDGET")"
ceiling="$(jq -r '.ceiling' "$BUDGET")"
tolerance="$(jq -r '.tolerance_percent' "$BUDGET")"

# --- obtain the CLI output -----------------------------------------------------------
claude_version="unknown"
if [[ -n "$FROM" ]]; then
  [[ -f "$FROM" ]] || { echo "ERROR: --from file not found: $FROM" >&2; exit 1; }
  details="$(cat "$FROM")"
  if command -v claude >/dev/null 2>&1; then
    claude_version="$(claude --version 2>/dev/null | awk 'NR==1{print $1}')"
  fi
else
  command -v claude >/dev/null 2>&1 \
    || { echo "ERROR: the claude CLI is required to measure the always-on cost (or pass --from <file>)" >&2; exit 1; }
  claude_version="$(claude --version 2>/dev/null | awk 'NR==1{print $1}')"
  [[ -n "$claude_version" ]] || claude_version="unknown"

  # The installed copy must be THIS checkout, or the figure describes a different tree.
  # `claude plugin list --json` reports readFromFolder for a plugin installed from a
  # local marketplace (`claude plugin marketplace add ./`). No entry at all is handled
  # below by the details call itself.
  if list_json="$(claude plugin list --json 2>/dev/null)" && jq -e 'type == "array"' <<<"$list_json" >/dev/null 2>&1; then
    from_folder="$(jq -r --arg id "$PLUGIN@$MARKETPLACE" '.[] | select(.id == $id) | .readFromFolder // empty' <<<"$list_json")"
    if [[ -n "$from_folder" ]]; then
      want="$(cd "$ROOT" && pwd -P)"
      have="$(cd "$from_folder" 2>/dev/null && pwd -P || printf '%s' "$from_folder")"
      if [[ "$want" != "$have" ]]; then
        echo "ERROR: $PLUGIN@$MARKETPLACE is installed from $have, not from $want — the measurement would not describe this checkout." >&2
        echo "       Reinstall from this checkout:  cd $want && claude plugin marketplace add ./ && claude plugin install $PLUGIN@$MARKETPLACE" >&2
        exit 1
      fi
    fi
  fi

  if ! details="$(claude plugin details "$PLUGIN" 2>&1)"; then
    echo "ERROR: 'claude plugin details $PLUGIN' failed:" >&2
    printf '%s\n' "$details" | sed 's/^/  /' >&2
    if grep -q 'not found' <<<"$details"; then
      echo "       Install the plugin from this checkout first:" >&2
      echo "         cd $ROOT && claude plugin marketplace add ./ && claude plugin install $PLUGIN@$MARKETPLACE" >&2
    fi
    exit 1
  fi
fi

# --- parse "Always-on:   ~7,938 tok" -------------------------------------------------
# Exactly one line, a number with optional thousands separators, the unit "tok". Any
# other shape is a CLI change we have not read and must not guess at.
lines="$(grep -E '^[[:space:]]*Always-on:[[:space:]]+~?[0-9][0-9,]*[[:space:]]+tok\b' <<<"$details" || true)"
count="$(grep -c . <<<"$lines" || true)"
if [[ "${count:-0}" -ne 1 ]]; then
  echo "ERROR: expected exactly one 'Always-on: ~N tok' line in the plugin details output, found ${count:-0}." >&2
  echo "       The CLI output shape may have changed; the relevant block was:" >&2
  { grep -A1 -i 'token cost' <<<"$details" || printf '%s\n' "$details" | head -5; } | sed 's/^/  /' >&2
  exit 1
fi
measured="$(sed -E 's/^[[:space:]]*Always-on:[[:space:]]+~?([0-9,]+)[[:space:]]+tok.*/\1/' <<<"$lines" | tr -d ',')"
[[ "$measured" =~ ^[0-9]+$ ]] || { echo "ERROR: could not read a number out of: $lines" >&2; exit 1; }

# --- compare ---------------------------------------------------------------------------
max_allowed=$(( baseline + (baseline * tolerance + 99) / 100 ))
printf 'token-budget: measured %d always-on tokens; baseline %d, tolerance %d%% (max %d), ceiling %d; measured on claude %s\n' \
  "$measured" "$baseline" "$tolerance" "$max_allowed" "$ceiling" "$claude_version"
printf 'token-budget: cli line: %s\n' "$(sed -E 's/^[[:space:]]+//' <<<"$lines")"

if [[ "$UPDATE" -eq 1 ]]; then
  today="$(date -u +%Y-%m-%d)"
  tmp="$(mktemp)"
  jq --argjson n "$measured" --arg v "$claude_version" --arg d "$today" \
     '.always_on_tokens = $n | .measured_on = $v | .measured_at = $d' "$BUDGET" > "$tmp"
  mv "$tmp" "$BUDGET"
  echo "token-budget: updated ${BUDGET}: always_on_tokens=$measured measured_on=$claude_version measured_at=$today (ceiling and tolerance untouched)"
fi

status=0
if [[ "$measured" -gt "$ceiling" ]]; then
  echo "FAIL: always-on cost $measured exceeds the ceiling of $ceiling tokens (see 'note' in $BUDGET)" >&2
  status=1
fi
if [[ "$measured" -gt "$max_allowed" ]]; then
  echo "FAIL: always-on cost $measured is more than $tolerance% above the committed baseline of $baseline (max $max_allowed). If the growth is intended, run: bash scripts/check-token-budget.sh --update" >&2
  status=1
fi
if [[ "$status" -eq 0 ]]; then
  if [[ "$measured" -lt "$baseline" ]]; then
    echo "token-budget: within budget; measurement is below the baseline — run with --update to lock in the lower figure"
  else
    echo "token-budget: within budget"
  fi
fi
exit "$status"
