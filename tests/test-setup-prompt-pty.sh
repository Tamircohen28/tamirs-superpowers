#!/usr/bin/env bash
# test-setup-prompt-pty.sh — the prompt helpers, exercised at a real terminal.
#
# WHY A PTY
#   Every other suite runs with stdout as a file, where setup_can_prompt is
#   false by construction and every prompt returns its default. That is the
#   right contract for a test, and it is exactly why this bug shipped: eight
#   call sites asked through `ans="$(setup_ask ...)"`, and inside a command
#   substitution fd 1 is the capture pipe, so at a REAL terminal the prompt
#   decided "no terminal", never printed, and handed back "n". A person ran
#   `github-labels.sh apply` at their shell and got "skipped — not confirmed"
#   without ever being asked (PR #374). Only a pty reproduces that, so this
#   suite drives the scripts under `expect`.
#
# WHAT IT HOLDS
#   1. setup_ask_into, called in the main shell, shows its prompt and returns
#      the typed answer. The `$( )` form of setup_ask, at the same pty, returns
#      the default — kept as a planted positive: the trap is real, which is why
#      the helper exists.
#   2. github-labels.sh apply, at a pty, with the fake gh: answering y creates the missing labels; answering n writes
#      nothing and reports "not confirmed".
#
# Skips cleanly (exit 0) when `expect` is not installed.
#
# bash 3.2. `set -uo pipefail`, not -e: the assertions are the control flow.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$REPO_ROOT/tests/lib/harness.sh"
# shellcheck source=tests/lib/fake-gh.sh
source "$REPO_ROOT/tests/lib/fake-gh.sh"

harness_require jq awk

if ! command -v expect >/dev/null 2>&1; then
  skip "prompt helpers at a pty" "expect is not installed (brew install expect / apt-get install expect)"
  harness_summary
fi

TMP="$(harness_tmpdir)"
FIX="$TMP/fixtures"
ROOT="$TMP/root"
OUT="$TMP/out"
RC=0
TARGET_REPO="Tamircohen28/example-repo"
LABELS_PATH="repos/$TARGET_REPO/labels"

# The expect driver (tests/lib/pty-answer.exp): answer every y/N-shaped prompt
# with $answer, echo the session, exit with the child's status.
DRIVER="$REPO_ROOT/tests/lib/pty-answer.exp"

# at_pty <answer> <command...> — run <command> on a pty, answering prompts.
at_pty() {
  local answer="$1"
  shift
  expect -f "$DRIVER" "$answer" "$@" >"$OUT" 2>&1
  RC=$?
}
outhas() { has "$(cat "$OUT")" "$1"; }
prompts_seen() { grep -c 'EXPECT_SAW_PROMPT' "$OUT" | tr -d ' '; }
calls() { awk -F'\t' -v m="$1" -v p="$2" '$2 == m && $3 == p { n++ } END { print n + 0 }' "$FAKE_GH_LOG"; }

export NO_COLOR=1

# ---------------------------------------------------------------------------
section "the pty harness itself"
judge "a trivial command runs on the pty"  0 "$(at_pty y bash -c 'test -t 1 && test -r /dev/tty'; echo $RC)"

# ---------------------------------------------------------------------------
section "setup_ask_into asks; \$(setup_ask) cannot (the planted positive)"
UNIT="$TMP/unit.sh"
cat >"$UNIT" <<'SH'
#!/usr/bin/env bash
. "$1/scripts/lib/setup-common.sh"
setup_ask_into v 'into? [y/N] ' n
printf 'INTO=%s\n' "$v"
c="$(setup_ask 'captured? [y/N] ' n)"
printf 'CAPTURED=%s\n' "$c"
SH
at_pty y bash "$UNIT" "$REPO_ROOT"
judge "the unit script exits 0"                              0   "$RC"
judge "setup_ask_into showed its prompt and got the answer"  yes "$(outhas 'INTO=y')"
judge "exactly one prompt reached the terminal"              1   "$(prompts_seen)"
judge "the \$(setup_ask) form returned the default unasked"  yes "$(outhas 'CAPTURED=n')"
at_pty '' bash "$UNIT" "$REPO_ROOT"
judge "an empty answer is the default"                       yes "$(outhas 'INTO=n')"

# ---------------------------------------------------------------------------
# A hermetic root for github-labels.sh: the real scripts/, config/ and core/
# by symlink, and the fake gh on PATH.
# ---------------------------------------------------------------------------
mkdir -p "$TMP/bin" "$TMP/home" "$ROOT"
cp -R "$REPO_ROOT/tests/fixtures/github" "$FIX"
ln -s "$REPO_ROOT/scripts" "$ROOT/scripts"
ln -s "$REPO_ROOT/config" "$ROOT/config"
ln -s "$REPO_ROOT/core"   "$ROOT/core"
fake_gh_install "$TMP/bin" "$TMP/gh.log" "$FIX/labels-missing"
PATH="$TMP/bin:$PATH"
export PATH
export HOME="$TMP/home" GH_CONFIG_DIR="$TMP/home/gh" GH_TOKEN="" GITHUB_TOKEN=""

REGISTRY="$REPO_ROOT/core/capabilities/platforms.json"
LABELS_FILE="$REPO_ROOT/config/github/labels.json"
N_PLATFORMS="$(jq '.platforms | length' "$REGISTRY")"
N_TAMIRS="$(jq '[.labels[] | select(.origin != "github-default")] | length' "$LABELS_FILE")"
EXPECT_CREATE=$((N_TAMIRS - 1 + N_PLATFORMS))

section "github-labels.sh apply at a terminal — y creates, n writes nothing"
fake_gh_reset
at_pty y bash "$ROOT/scripts/github-labels.sh" apply --repo "$TARGET_REPO"
judge "apply exits 0 after y"                                0   "$RC"
judge "the confirmation prompt reached the terminal"         1   "$(prompts_seen)"
judge "the repository is reported updated"                   yes "$(outhas '· updated')"
judge "  not skipped"                                        no  "$(outhas 'not confirmed')"
judge "one POST per missing label"                           "$EXPECT_CREATE" "$(calls POST "$LABELS_PATH")"
judge "the drifted label was PATCHed"                        1   "$(calls PATCH "$LABELS_PATH/agent%3Aany")"
judge "no DELETE (no --prune)"                               0   "$(awk -F'\t' '$2 == "DELETE" { n++ } END { print n + 0 }' "$FAKE_GH_LOG")"

fake_gh_reset
at_pty n bash "$ROOT/scripts/github-labels.sh" apply --repo "$TARGET_REPO"
judge "n: exits 0 (declining is not a failure)"              0   "$RC"
judge "n: the prompt was shown"                              1   "$(prompts_seen)"
judge "n: reported as not confirmed"                         yes "$(outhas 'skipped — not confirmed')"
judge "n: nothing written"                                   0   "$(gh_mutations)"
judge "n:   but the labels were read"                        1   "$(calls GET "$LABELS_PATH")"

fake_gh_reset
at_pty y bash "$ROOT/scripts/github-labels.sh" apply --repo "$TARGET_REPO" --yes
judge "--yes: no prompt at all"                              0   "$(prompts_seen)"
judge "--yes: still created"                                 "$EXPECT_CREATE" "$(calls POST "$LABELS_PATH")"

harness_summary
