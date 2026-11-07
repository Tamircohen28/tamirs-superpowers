#!/usr/bin/env bash
# check-token-budget.sh — hold the plugin's always-on context cost to a committed budget.
# Validation tier: 3 for the live measurement (needs the Claude Code CLI; CI's
# plugin-validate job); --offline is tier 1 (python3 + PyYAML only; every CI shard).
#
# Usage:
#   check-token-budget.sh [repo-root] [--update] [--from <details-output-file>]
#                         [--cross-check] [--plugin <name>] [--budget <file>]
#   check-token-budget.sh [repo-root] --offline [--budget <file>]
#   check-token-budget.sh -h | --help
#
# WHAT IT MEASURES
#   `claude --plugin-dir <repo-root> plugin details <plugin>` prints, for the checkout
#   (never the installed copy), a "Projected token cost" block whose "Always-on"
#   figure is the context every session pays before any skill fires: the
#   name + description + when_to_use of every skill and agent. The official marketplace
#   highlights that figure to users pre-install once it reaches 2,000 tokens, so it is a
#   number that decides whether people install the plugin at all. This script reads it
#   and compares it to evals/budget.json:
#     always_on_tokens   the committed baseline (last accepted measurement)
#     ceiling            the hard cap; measured > ceiling fails regardless of baseline
#     tolerance_percent  how far above the baseline a measurement may drift before
#                        failing (a few tokens of description tuning is noise; a new
#                        skill is not)
#     chars_per_token    characters of always-on text per tokenizer token, set a little
#                        below the observed ratio so the offline estimate reads high
#     measured_on        the `claude --version` the baseline was taken with
#     measured_at        the UTC date of that measurement
#     note               free text; records why the ceiling sits where it does
#
# THE CLI'S SILENT FALLBACK, AND THE OFFLINE ESTIMATE
#   The CLI counts the always-on text with the count_tokens API. With no credentials (a
#   CI runner) it prints ceil(characters / 4) instead, without saying so, and for this
#   plugin's prose that reads about 30% low (issue #401: CI saw ~5,945 while a signed-in
#   machine saw ~8,668 for the same tree). scripts/always-on-cost.py rebuilds the exact
#   text the CLI measures from the checkout and divides its length by chars_per_token.
#     --offline      use that estimate; no CLI, no network. tests/test-skill-budget.sh
#                    runs it, so every CI shard holds the checkout to the ceiling.
#     live / --from --cross-check
#                    after reading the CLI figure, compare it with the checkout: a figure
#                    equal to the checkout's chars/4 fallback is replaced by the offline
#                    estimate (and says so); a real tokenizer count that the offline
#                    estimate under-reads by more than 1% fails, naming the
#                    chars_per_token to set. The live run always cross-checks; --from
#                    only with --cross-check (a saved figure may describe another tree).
#
# FAIL CONDITIONS (exit 1)
#   - measured > ceiling
#   - measured > always_on_tokens * (1 + tolerance_percent/100)
#   - the CLI output does not contain exactly one "Always-on: ~N tok" line, or N is not
#     a number. A shape change in the CLI fails loudly; nothing is ever parsed as 0.
#   - the CLI did not load the plugin from <repo-root> (its Source line is not
#     "<plugin>@inline"), so the figure would describe another copy.
#   - a cross-check that cannot run (no python3/PyYAML), or a tokenizer count the offline
#     estimate under-reads by more than 1% (chars_per_token is stale).
#
# UPDATING THE BASELINE
#   --update rewrites always_on_tokens, measured_on and measured_at from the current
#   measurement and keeps ceiling, tolerance_percent, chars_per_token and note. Use it
#   in the same PR that legitimately changes the figure, so the diff shows the cost next
#   to its cause. Run it live on a signed-in machine: it refuses an offline estimate or
#   a fallback figure. It does not raise the ceiling; edit that by hand, with a note.
#
# --from <file> reads a saved `claude plugin details` output instead of running the
#   CLI, for tests and for reviewing a figure someone pasted into a PR. The checkout
#   match is not verified in that mode (there is no live install to compare).
#
# Exit 0 when within budget; 1 on any failure.
set -euo pipefail

usage() { sed -n '2,67p' "$0" | sed -E 's/^# ?//'; exit "${1:-0}"; }

ROOT=""
UPDATE=0
FROM=""
OFFLINE=0
CROSS=0
PLUGIN="tamirs-superpowers"
BUDGET=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help) usage 0 ;;
    --update) UPDATE=1 ;;
    --from) FROM="${2:?--from needs a file}"; shift ;;
    --offline) OFFLINE=1 ;;
    --cross-check) CROSS=1 ;;
    --plugin) PLUGIN="${2:?--plugin needs a name}"; shift ;;
    --budget) BUDGET="${2:?--budget needs a file}"; shift ;;
    -*) echo "ERROR: unknown option: $1" >&2; usage 2 ;;
    *) ROOT="$1" ;;
  esac
  shift
done
ROOT="$(cd "${ROOT:-.}" && pwd)"
BUDGET="${BUDGET:-$ROOT/evals/budget.json}"
if [[ "$OFFLINE" -eq 1 && -n "$FROM" ]]; then
  echo "ERROR: --offline and --from are two different sources of the figure; pass one" >&2; exit 2
fi
if [[ "$OFFLINE" -eq 1 && "$UPDATE" -eq 1 ]]; then
  echo "ERROR: --update records a tokenizer measurement; run it live on a signed-in machine, not with --offline" >&2; exit 2
fi
[[ -z "$FROM" ]] && CROSS=1

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
jq -e '.chars_per_token | type == "number" and . > 0' "$BUDGET" >/dev/null 2>&1 \
  || { echo "ERROR: $BUDGET: 'chars_per_token' must be a positive number (got '$(jq -c '.chars_per_token' "$BUDGET")')" >&2; exit 1; }
ratio="$(jq -r '.chars_per_token' "$BUDGET")"
baseline="$(jq -r '.always_on_tokens' "$BUDGET")"
ceiling="$(jq -r '.ceiling' "$BUDGET")"
tolerance="$(jq -r '.tolerance_percent' "$BUDGET")"

# --- the offline estimate from the checkout ----------------------------------------
# Sets est_chars, est_tokens (ceil(chars / chars_per_token)) and est_fallback (what the
# CLI prints with no credentials: ceil(per-component chars summed / 4)).
estimate_checkout() {
  command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' >/dev/null 2>&1 \
    || { echo "ERROR: the checkout estimate needs python3 + PyYAML (pip install -r scripts/requirements-validate.txt)" >&2; exit 1; }
  local est
  est="$(python3 "$(dirname "${BASH_SOURCE[0]}")/always-on-cost.py" "$ROOT" --chars-per-token "$ratio" --json)" \
    || { echo "ERROR: scripts/always-on-cost.py could not read $ROOT" >&2; exit 1; }
  est_chars="$(jq -r '.chars' <<<"$est")"
  est_tokens="$(jq -r '.tokens' <<<"$est")"
  est_fallback="$(jq -r '.cli_fallback_tokens' <<<"$est")"
}

claude_version="unknown"
source_kind="tokenizer"   # tokenizer | offline | fallback
if [[ "$OFFLINE" -eq 1 ]]; then
  estimate_checkout
  measured="$est_tokens"
  source_kind="offline"
  lines="offline estimate: $est_chars always-on chars / $ratio chars per token = ~$est_tokens tok (scripts/always-on-cost.py)"
else  # the CLI figure: live, or a saved copy through --from
# --- obtain the CLI output -----------------------------------------------------------
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

  # Measure THIS checkout, not whatever copy is installed: --plugin-dir loads the plugin
  # from the tree for this one command (the details then name the source "<plugin>@inline").
  # Measuring the installed copy is how #401 read an older release than the checkout.
  if ! details="$(claude --plugin-dir "$ROOT" plugin details "$PLUGIN" 2>&1)"; then
    echo "ERROR: 'claude --plugin-dir $ROOT plugin details $PLUGIN' failed:" >&2
    printf '%s\n' "$details" | sed 's/^/  /' >&2
    exit 1
  fi
  if ! grep -qE "^[[:space:]]*Source:[[:space:]]+$PLUGIN@inline[[:space:]]*\$" <<<"$details"; then
    echo "ERROR: the CLI did not load $PLUGIN from --plugin-dir $ROOT, so the figure would describe another copy. Its Source line was:" >&2
    { grep -E '^[[:space:]]*Source:' <<<"$details" || echo "(none)"; } | sed 's/^/  /' >&2
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

# --- cross-check the CLI figure against the checkout ------------------------------------
if [[ "$CROSS" -eq 1 ]]; then
  estimate_checkout
  if [[ "$measured" -eq "$est_fallback" ]]; then
    # Not a tokenizer count: the CLI could not reach count_tokens and printed chars/4.
    echo "token-budget: the CLI figure ~$measured is its no-credentials chars/4 fallback for this checkout, not a tokenizer count; holding the offline estimate ~$est_tokens instead"
    measured="$est_tokens"
    source_kind="fallback"
  elif [[ $(( est_tokens * 100 )) -lt $(( measured * 99 )) ]]; then
    observed="$(awk -v c="$est_chars" -v t="$measured" 'BEGIN { printf "%.3f", c / t }')"
    suggest="$(awk -v c="$est_chars" -v t="$measured" 'BEGIN { printf "%.2f", int(c / t * 100) / 100 - 0.03 }')"
    echo "FAIL: the offline estimate (~$est_tokens tok at $ratio chars/token) under-reads this tokenizer count of $measured by more than 1%: the CLI now counts $observed chars per token. Set chars_per_token to $suggest in $BUDGET so CI's offline check keeps reading high." >&2
    exit 1
  fi
fi
fi  # end of the CLI figure

# --- compare ---------------------------------------------------------------------------
max_allowed=$(( baseline + (baseline * tolerance + 99) / 100 ))
printf 'token-budget: measured %d always-on tokens (%s); baseline %d, tolerance %d%% (max %d), ceiling %d; measured on claude %s\n' \
  "$measured" "$source_kind" "$baseline" "$tolerance" "$max_allowed" "$ceiling" "$claude_version"
if [[ "$source_kind" == "offline" ]]; then
  printf 'token-budget: %s\n' "$lines"
else
  printf 'token-budget: cli line: %s\n' "$(sed -E 's/^[[:space:]]+//' <<<"$lines")"
fi

if [[ "$UPDATE" -eq 1 && "$source_kind" != "tokenizer" ]]; then
  echo "ERROR: --update needs a tokenizer count; this figure is the $source_kind estimate. Run it on a machine where the claude CLI is signed in." >&2
  exit 1
fi
if [[ "$UPDATE" -eq 1 ]]; then
  today="$(date -u +%Y-%m-%d)"
  tmp="$(mktemp)"
  jq --argjson n "$measured" --arg v "$claude_version" --arg d "$today" \
     '.always_on_tokens = $n | .measured_on = $v | .measured_at = $d' "$BUDGET" > "$tmp"
  mv "$tmp" "$BUDGET"
  echo "token-budget: updated ${BUDGET}: always_on_tokens=$measured measured_on=$claude_version measured_at=$today (ceiling and tolerance untouched)"
  # The baseline is now the measurement; the tolerance check below compares against
  # what was just written, not the figure it replaced (the ceiling check still holds).
  baseline="$measured"
  max_allowed=$(( baseline + (baseline * tolerance + 99) / 100 ))
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
