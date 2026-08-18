#!/usr/bin/env bash
# _common.sh — helpers shared by the per-platform contract suites.
#
# Every platform suite is split in two halves, deliberately:
#
#   SCHEMA/CONTRACT half — always runs, anywhere, with no platform CLI. It asserts
#   the things this repo controls: the manifest parses and declares what the
#   capability registry says it declares, every skill path it points at exists,
#   adapters are not stale.
#
#   CLI half — needs the actual vendor CLI. It SKIPS with a named reason when the
#   CLI is absent and is flagged for the nightly job. A skip that says which
#   command was missing is useful; a silent pass is a lie (REFACTOR-SPEC §22.4).
# shellcheck shell=bash

# Fragment, not an entrypoint: sourced by tests/contract/run.sh. Run standalone it would die on
# the first helper call with an opaque 127, so say what to run instead.
if ! declare -f judge >/dev/null 2>&1; then
  printf 'This file is a test fragment, not an entrypoint.\nRun: bash tests/contract/run.sh\n' >&2
  exit 2
fi

REG="$REPO_ROOT/core/capabilities/platforms.json"

# reg <platform-key> <jq-filter>
reg() { jq -r "$2" <<<"$(jq -c --arg k "$1" '.platforms[$k]' "$REG")"; }

# contract_registry_entry <platform-key> <display-name>
# The registry is the single source of truth for what a target claims. If a claim
# is not in here, no doc or manifest is allowed to make it.
contract_registry_entry() {
  local key="$1" want="$2"
  judge "registry has an entry for $key" yes \
    "$(if [ "$(jq -r --arg k "$key" '.platforms | has($k)' "$REG")" = true ]; then echo yes; else echo no; fi)"
  judge "$key display_name is '$want'" "$want" "$(reg "$key" '.display_name')"
  judge "$key declares an install path" yes \
    "$(if [ -n "$(reg "$key" '.install.command // .install.type // ""')" ]; then echo yes; else echo no; fi)"
  judge "$key declares a validation command" yes \
    "$(if [ -n "$(reg "$key" '.validation.command // ""')" ]; then echo yes; else echo no; fi)"

  # Every capability the registry DEFINES must have an explicit status here.
  # "Never silently pretend" (REFACTOR-SPEC §2.5) means absence is a bug, and
  # 'unsupported' with a fallback is the correct way to say no.
  local missing=""
  while IFS= read -r cap; do
    [ -n "$cap" ] || continue
    local st
    st="$(jq -r --arg k "$key" --arg c "$cap" '.platforms[$k].capabilities[$c].status // ""' "$REG")"
    [ -n "$st" ] || missing="$missing $cap"
  done < <(jq -r '.capability_definitions | keys[]' "$REG")
  judge "$key states a status for every defined capability" "" "$missing"

  local nofallback
  nofallback="$(jq -r --arg k "$key" '
    .platforms[$k].capabilities | to_entries[]
    | select(.value.status == "unsupported")
    | select((.value.fallback // .value.notes // "") == "")
    | .key' "$REG")"
  judge "$key gives a fallback or a reason for every unsupported capability" "" "$nofallback"
}

# contract_manifest <label> <path> — exists and parses.
contract_manifest() {
  local label="$1" path="$2"
  judge "$label manifest exists ($path)" yes "$(exists "$REPO_ROOT/$path")"
  [ -f "$REPO_ROOT/$path" ] || return 0
  case "$path" in
    *.json) judge "$label manifest parses" 0 "$(jq empty "$REPO_ROOT/$path" >/dev/null 2>&1; echo $?)" ;;
    *.toml) judge "$label manifest is non-empty" yes \
              "$(if [ -s "$REPO_ROOT/$path" ]; then echo yes; else echo no; fi)" ;;
  esac
}

# contract_skill_paths <label> <path-list...> — every declared skill root must
# exist and contain at least one SKILL.md. A manifest pointing at a directory
# that was renamed is the classic silent "zero skills loaded" failure.
contract_skill_paths() {
  local label="$1"; shift
  local missing="" empty="" p abs
  for p in "$@"; do
    abs="$REPO_ROOT/${p#./}"
    if [ ! -d "$abs" ]; then missing="$missing $p"; continue; fi
    [ -n "$(find "$abs" -name SKILL.md -print -quit 2>/dev/null)" ] || empty="$empty $p"
  done
  judge "$label: every declared skill path exists" "" "$missing"
  judge "$label: every declared skill path contains a SKILL.md" "" "$empty"
}

# contract_cli <label> <cli> <cmd...> — the CLI half. Skips, loudly, when absent.
#
# Run under portable_timeout: a vendor CLI that waits on auth, a prompt, or a
# network call would otherwise hang the suite forever, and `timeout` is not
# installed on the development machine. Exit 124 is the watchdog's expiry code.
CONTRACT_CLI_TIMEOUT="${CONTRACT_CLI_TIMEOUT:-120}"
contract_cli() {
  local label="$1" cli="$2"; shift 2
  if ! harness_have "$cli"; then
    skip "$label" "$cli not on PATH — nightly job territory"
    return 0
  fi
  local rc=0 out
  out="$(portable_timeout "$CONTRACT_CLI_TIMEOUT" "$@" 2>&1)" || rc=$?
  if [ "$rc" -eq 124 ]; then
    bad "$label" "timed out after ${CONTRACT_CLI_TIMEOUT}s (watchdog: $(portable_timeout_impl))"
    return 0
  fi
  if [ "$rc" -eq 0 ]; then ok "$label"; else
    printf '%s\n' "$out" | sed 's/^/       /' | head -10
    bad "$label" "exit $rc"
  fi
}

# contract_peer_suite <label> <path> — a peer-owned suite (gemini/opencode
# adapters). Called, never duplicated; absent means the peer has not landed yet.
contract_peer_suite() {
  local label="$1" path="$2"
  if [ ! -f "$REPO_ROOT/$path" ]; then skip "$label" "$path not present"; return 0; fi
  local rc=0 out
  out="$(portable_timeout "${PEER_SUITE_TIMEOUT:-300}" bash "$REPO_ROOT/$path" 2>&1)" || rc=$?
  if [ "$rc" -eq 124 ]; then
    bad "$label" "timed out (watchdog: $(portable_timeout_impl))"
    return 0
  fi
  if [ "$rc" -eq 0 ]; then ok "$label"; else
    printf '%s\n' "$out" | tail -8 | sed 's/^/       /'
    bad "$label" "exit $rc"
  fi
}
