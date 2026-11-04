#!/usr/bin/env bash
# test-repo-gates.sh — the L1 permission gates of the repo skills (ADR 004 item 10).
#
# WHAT IS HELD
#   enable-repo-merge-settings.sh (repo.settings.merge, R3, audit A1 D-4):
#     * the default is a dry run that prints the exact PATCH and sends nothing,
#       and never asks the resolver;
#     * --apply asks the resolver: allow sends the PATCH; ask with no terminal
#       stops (exit 3) with the setting and the command to run yourself; deny,
#       a resolver exit 3, unparseable output and a missing resolver all stop
#       (exit 3) and send nothing.
#   repo-scaffold/scripts/repo-create-gate.sh (repo.create, R4, audit A1 D-3):
#     * it prints the exact owner/name and visibility it gates;
#     * allow exits 0; ask exits 10 (confirm in chat); ask with --headless, deny
#       and every resolver failure exit 3 with the reason; it never creates a
#       repository itself (no gh call at all).
#
# HOW
#   Each script finds the resolver from its own path, never from env, so each is
#   COPIED into a temp plugin tree whose scripts/resolve-permission.sh is a stub
#   answering per STUB_MODE (the tests/test-merge-policy.sh Part A pattern).
#   Every gh call goes to tests/lib/fake-gh.sh. stdout is a file, so no run here
#   has a terminal: the ask path is the headless one by construction.
#
# Hermetic: temp dirs, fake gh, no network, no logins.
set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$REPO_ROOT/tests/lib/harness.sh"
# shellcheck source=tests/lib/fake-gh.sh
source "$REPO_ROOT/tests/lib/fake-gh.sh"

harness_require jq python3

TMP="$(harness_tmpdir)"
export HOME="$TMP/home"; mkdir -p "$HOME"
unset GH_TOKEN GITHUB_TOKEN GH_REPO 2>/dev/null || true
OUT="$TMP/out"
RC=0

# --- fake gh -----------------------------------------------------------------
FX="$TMP/fx"
mkdir -p "$FX"
printf '{"nameWithOwner":"acme/widget"}\n' >"$FX/repo-view.json"
printf '{"full_name":"acme/widget","allow_auto_merge":true,"delete_branch_on_merge":true}\n' >"$FX/repo.json"
fake_gh_install "$TMP/bin" "$TMP/gh.log" "$FX"
export PATH="$TMP/bin:$PATH"

# --- temp plugin tree with a stub resolver -----------------------------------
PLUG="$TMP/plugin"
mkdir -p "$PLUG/scripts" "$PLUG/skills/repo/_contract/scripts" "$PLUG/skills/repo/repo-scaffold/scripts"
cp "$REPO_ROOT/skills/repo/_contract/scripts/enable-repo-merge-settings.sh" "$PLUG/skills/repo/_contract/scripts/"
cp "$REPO_ROOT/skills/repo/repo-scaffold/scripts/repo-create-gate.sh" "$PLUG/skills/repo/repo-scaffold/scripts/"
MERGE="$PLUG/skills/repo/_contract/scripts/enable-repo-merge-settings.sh"
GATE="$PLUG/skills/repo/repo-scaffold/scripts/repo-create-gate.sh"
STUB="$PLUG/scripts/resolve-permission.sh"
STUB_LOG="$TMP/resolver.log"
export STUB_LOG
# The stub records argv, then answers per STUB_MODE: allow | ask | deny (exit
# 0), exit3 (deny, exit 3), garbage (not JSON), noverdict ({}). With --headless
# an ask becomes deny, as the real resolver does (D2).
cat >"$STUB" <<'STUB'
#!/usr/bin/env bash
printf 'ARGV %s\n' "$*" >>"$STUB_LOG"
mode="${STUB_MODE:-ask}"
case "$mode" in
  garbage)   printf 'not json\n'; exit 0 ;;
  noverdict) printf '{}\n'; exit 0 ;;
  exit3)     printf '{"verdict":"deny","reason":"stub internal error"}\n'; exit 3 ;;
esac
case " $* " in *" --headless "*) [ "$mode" = ask ] && mode=deny ;; esac
printf '{"verdict":"%s","reason":"stub %s","setting_that_would_allow":{"once":null,"durable":["stub-durable-setting"],"note":"stub note"}}\n' "$mode" "$mode"
STUB
chmod +x "$STUB"

run() { # run <script> <args...> — fresh logs, stdin from /dev/null, stdout+stderr to $OUT
  fake_gh_reset
  : >"$STUB_LOG"
  bash "$@" </dev/null >"$OUT" 2>&1
  RC=$?
}
outhas()   { has "$(cat "$OUT")" "$1"; }
calls()    { awk '/^ARGV /{n++} END{print n+0}' "$STUB_LOG"; }
saw()      { has "$(cat "$STUB_LOG")" "$1"; }
patches()  { awk -F'\t' '$2 == "PATCH" { n++ } END { print n + 0 }' "$FAKE_GH_LOG"; }

# =============================================================================
section "enable-repo-merge-settings.sh: dry run is the default"
# =============================================================================
STUB_MODE=allow run "$MERGE" acme/widget
judge "dry run: exits 0" "0"                                   "$RC"
judge "dry run: sends no PATCH" "0"                            "$(patches)"
judge "dry run: makes no gh mutation at all" "0"               "$(gh_mutations)"
judge "dry run: prints the PATCH target" "yes"                 "$(outhas 'PATCH repos/acme/widget')"
judge "dry run: prints the PATCH body" "yes"                   "$(outhas '"allow_auto_merge":true,"delete_branch_on_merge":true')"
judge "dry run: names --apply" "yes"                           "$(outhas 're-run with --apply')"
judge "dry run: never asks the resolver" "0"                   "$(calls)"
STUB_MODE=allow run "$MERGE"
judge "dry run, no repo given: reads it from gh repo view" "yes" "$(outhas 'PATCH repos/acme/widget')"
judge "dry run, no repo given: still sends nothing" "0"        "$(gh_mutations)"

# =============================================================================
section "enable-repo-merge-settings.sh --apply: the resolver decides"
# =============================================================================
STUB_MODE=allow run "$MERGE" acme/widget --apply --skill repo-scaffold
judge "allow: exits 0" "0"                                     "$RC"
judge "allow: sends exactly one PATCH" "1"                     "$(patches)"
judge "allow: to the repository" "1"                           "$(gh_calls 'api -X PATCH repos/acme/widget')"
judge "allow: with both settings" '{"allow_auto_merge":"true","delete_branch_on_merge":"true"}' "$(gh_last_body 1)"
judge "allow: asked about repo.settings.merge for this target" "yes" \
  "$(saw '--action repo.settings.merge --target acme/widget --skill repo-scaffold --json')"

STUB_MODE=ask run "$MERGE" acme/widget --apply
judge "ask, no terminal: exits 3" "3"                          "$RC"
judge "ask, no terminal: sends nothing" "0"                    "$(gh_mutations)"
judge "ask, no terminal: says it is blocked" "yes"             "$(outhas 'blocked: repo.settings.merge asks for a person')"
judge "ask, no terminal: names the setting" "yes"              "$(outhas 'allow with: stub-durable-setting')"
judge "ask, no terminal: gives the command to run yourself" "yes" "$(outhas 'enable-repo-merge-settings.sh acme/widget --apply')"

STUB_MODE=deny run "$MERGE" acme/widget --apply
judge "deny: exits 3" "3"                                      "$RC"
judge "deny: sends nothing" "0"                                "$(gh_mutations)"
judge "deny: gives the resolver's reason" "yes"                "$(outhas 'blocked: stub deny')"
judge "deny: names the setting that would allow it" "yes"      "$(outhas 'allow with: stub-durable-setting')"

for mode in exit3 garbage noverdict; do
  STUB_MODE="$mode" run "$MERGE" acme/widget --apply
  judge "$mode: exits 3" "3"                                   "$RC"
  judge "$mode: sends nothing" "0"                             "$(gh_mutations)"
done

mv "$STUB" "$TMP/stub.parked"
STUB_MODE=allow run "$MERGE" acme/widget --apply
judge "resolver missing: exits 3" "3"                          "$RC"
judge "resolver missing: sends nothing" "0"                    "$(gh_mutations)"
judge "resolver missing: fails closed and says so" "yes"       "$(outhas 'permission resolver missing or failed')"
mv "$TMP/stub.parked" "$STUB"

run "$MERGE" acme/widget --bogus
judge "unknown flag: exits 1" "1"                              "$RC"
judge "unknown flag: sends nothing" "0"                        "$(gh_mutations)"

# =============================================================================
section "repo-create-gate.sh: repo.create is gated per repository"
# =============================================================================
STUB_MODE=allow run "$GATE" --repo TamirCohen28/new-tool --visibility private --description "a CLI"
judge "allow: exits 0" "0"                                     "$RC"
judge "allow: shows owner/name and visibility" "yes"           "$(outhas 'create the private GitHub repository TamirCohen28/new-tool')"
judge "allow: asked about repo.create for this target" "yes" \
  "$(saw '--action repo.create --skill repo-scaffold --target TamirCohen28/new-tool')"
judge "allow: the gate itself never calls gh" "0"              "$(awk 'END{print NR+0}' "$FAKE_GH_LOG")"

STUB_MODE=ask run "$GATE" --repo TamirCohen28/new-tool --visibility private
judge "ask: exits 10 (confirm in chat)" "10"                   "$RC"
judge "ask: says to get an explicit yes" "yes"                 "$(outhas 'create it only on an explicit yes')"
judge "ask: names the visibility in the confirmation" "yes"    "$(outhas 'approve creating the private repository TamirCohen28/new-tool')"

STUB_MODE=ask run "$GATE" --repo TamirCohen28/new-tool --visibility private --headless
judge "ask, headless: exits 3" "3"                             "$RC"
judge "ask, headless: says why" "yes"                          "$(outhas 'blocked: ')"
judge "ask, headless: passed --headless to the resolver" "yes" "$(saw '--headless')"
judge "ask, headless: names the setting" "yes"                 "$(outhas 'allow with: stub-durable-setting')"

# --headless holds even when the resolver answers ask anyway.
cat >"$TMP/askstub" <<'S'
#!/usr/bin/env bash
printf '{"verdict":"ask","reason":"stub ask regardless"}\n'
S
cp "$STUB" "$TMP/stub.saved"; cp "$TMP/askstub" "$STUB"
run "$GATE" --repo TamirCohen28/new-tool --visibility private --headless
judge "headless overrides a resolver ask: exits 3" "3"         "$RC"
cp "$TMP/stub.saved" "$STUB"

STUB_MODE=deny run "$GATE" --repo TamirCohen28/new-tool --visibility public
judge "deny: exits 3" "3"                                      "$RC"
judge "deny: gives the resolver's reason" "yes"                "$(outhas 'blocked: stub deny')"
judge "deny: names the setting that would allow it" "yes"      "$(outhas 'allow with: stub-durable-setting')"

for mode in exit3 garbage noverdict; do
  STUB_MODE="$mode" run "$GATE" --repo TamirCohen28/new-tool --visibility private
  judge "$mode: exits 3" "3"                                   "$RC"
done

mv "$STUB" "$TMP/stub.parked"
STUB_MODE=allow run "$GATE" --repo TamirCohen28/new-tool --visibility private
judge "resolver missing: exits 3" "3"                          "$RC"
judge "resolver missing: fails closed and says so" "yes"       "$(outhas 'permission resolver missing or failed')"
mv "$TMP/stub.parked" "$STUB"

run "$GATE" --repo new-tool --visibility private
judge "usage: a bare name is refused (exit 2)" "2"             "$RC"
judge "usage: and the resolver is not asked" "0"               "$(calls)"
run "$GATE" --repo TamirCohen28/new-tool --visibility secret
judge "usage: an unknown visibility is refused (exit 2)" "2"   "$RC"

# =============================================================================
section "the real resolver never allows either action unattended"
# =============================================================================
# R4 repo.create and never_auto R3 repo.settings.merge: whatever the user's
# config says, a headless answer is never allow (ADR 004 D2).
for act in repo.create repo.settings.merge; do
  v="$(bash "$REPO_ROOT/scripts/resolve-permission.sh" --action "$act" --target acme/widget --headless --json 2>/dev/null)"
  judge "real resolver: $act headless is not allow" "no" "$( [ "$(jq -r .verdict <<<"$v")" = allow ] && echo yes || echo no)"
done

harness_summary
