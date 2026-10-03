#!/usr/bin/env bash
# check-gemini-adapter.sh — structural guard for the Gemini CLI adapter.
#
# Usage:
#   check-gemini-adapter.sh [repo-root]
#   check-gemini-adapter.sh -h | --help
#
# Gemini CLI installs an extension from the REPO ROOT, so gemini-extension.json
# shares a directory with every other platform's manifest and with the canonical
# skills/, agents/, and hooks/ trees. That co-tenancy is the whole risk surface:
# a path in the manifest can rot, the version can drift away from
# plugin-version.json, or someone can quietly add a Node dependency to a repo
# that has deliberately never had one.
#
# `gemini extensions validate` does NOT cover any of that — measured against
# Gemini CLI 0.55.1, it parses the manifest and stops. It reports success on an
# extension whose contextFileName points at a missing file. So the checks below
# always run, and the CLI is only an opportunistic extra.
#
# Exit 0 if checks pass; 1 on failure.
set -euo pipefail

usage() {
  # -E so `?` is portable: BSD sed ignores GNU's `\?`, which prints a literal "# " prefix.
  sed -n '2,20p' "$0" | sed -E 's/^# ?//'
  exit "${1:-0}"
}
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage 0; fi

ROOT="$(cd "${1:-.}" && pwd)"
FAILED=0

err() { echo "ERROR: $*" >&2; FAILED=$(( FAILED + 1 )); }
note() { echo "  $*"; }

MANIFEST="$ROOT/gemini-extension.json"
ADAPTER="$ROOT/platforms/gemini/adapter.yaml"
INSTALL_DOC="$ROOT/docs/user/install/gemini.md"

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required" >&2; exit 1; }

# --- 1. Manifest parses and carries the fields Gemini actually reads ---
if [[ ! -f "$MANIFEST" ]]; then
  err "gemini-extension.json is missing from the repo root — 'gemini extensions install <git-url>' resolves the manifest there and nowhere else"
else
  if ! jq empty "$MANIFEST" 2>/dev/null; then
    err "gemini-extension.json: invalid JSON"
  else
    for field in name version description; do
      value=$(jq -r --arg f "$field" '.[$f] // ""' "$MANIFEST")
      [[ -n "$value" ]] || err "gemini-extension.json: missing required field '$field'"
    done

    # Gemini expects the extension name to match its directory name, and
    # documents lowercase-with-dashes. An uppercase or underscored name installs
    # under a name the user cannot then pass to `gemini extensions disable`.
    name=$(jq -r '.name // ""' "$MANIFEST")
    if [[ -n "$name" && ! "$name" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]]; then
      err "gemini-extension.json: name '$name' must be lowercase alphanumeric with dashes"
    fi

    # --- 2. Every path the manifest names must exist ---
    # ${extensionPath} resolves to the extension root at load time, which is
    # this repo root; strip it and check the file is really there. A dangling
    # path is silent at validate time and fails only when a user runs the tool.
    ctx=$(jq -r '.contextFileName // ""' "$MANIFEST")
    if [[ -n "$ctx" ]]; then
      [[ -f "$ROOT/$ctx" ]] || err "gemini-extension.json: contextFileName '$ctx' does not exist"
    fi

    while IFS= read -r ref; do
      [[ -n "$ref" ]] || continue
      rel="${ref#\$\{extensionPath\}/}"
      # Only check things that look like in-repo paths, not bare executables.
      [[ "$rel" == */* ]] || continue
      [[ -e "$ROOT/$rel" ]] || err "gemini-extension.json: mcpServers references '$ref', which does not exist"
    done < <(jq -r '.mcpServers // {} | to_entries[] | (.value.args // [])[], (.value.cwd // empty), (.value.command // empty)' "$MANIFEST" \
             | grep -F '${extensionPath}' || true)

    # --- 3. Version truth: consumer, never source ---
    if [[ -f "$ROOT/plugin-version.json" ]]; then
      want=$(jq -r '.version' "$ROOT/plugin-version.json")
      got=$(jq -r '.version // ""' "$MANIFEST")
      if [[ "$want" != "$got" ]]; then
        err "gemini-extension.json version '$got' != plugin-version.json '$want' — edit plugin-version.json, then run scripts/check-version-truth.sh --sync"
      fi
    fi
  fi
fi

# --- 4. No Node dependencies ---
# Gemini's own extension templates scaffold an npm package. This repo is
# declarative — Markdown, JSON, and Bash — and adopting the template's runtime
# would make `gemini extensions install` the only target requiring a toolchain.
for nodefile in package.json package-lock.json pnpm-lock.yaml yarn.lock; do
  [[ -e "$ROOT/$nodefile" ]] && err "$nodefile exists — the Gemini adapter must not introduce a Node dependency"
done
if [[ -f "$MANIFEST" ]] && jq -e '.mcpServers // {} | to_entries[] | select(.value.command == "npx" or .value.command == "node")' "$MANIFEST" >/dev/null 2>&1; then
  err "gemini-extension.json: an mcpServers entry runs node/npx — the adapter must stay dependency-free"
fi

# --- 5. Adapter metadata and install doc exist ---
[[ -f "$ADAPTER" ]] || err "platforms/gemini/adapter.yaml is missing (spec §21 adapter contract)"
[[ -f "$INSTALL_DOC" ]] || err "docs/user/install/gemini.md is missing"

# --- 6. The generated skill mirror is present, complete, and in sync ---
# This is the check that matters most. Gemini discovers skills exactly one level
# below a skills root, so the canonical two-level tree resolves to ZERO skills —
# silently, with no error a user would ever see. The flat mirror at
# .gemini/skills/ is the only thing standing between that and a working install,
# and an empty mirror looks identical to a healthy one from the outside.
MIRROR="$ROOT/.gemini/skills"
canonical_count=0
if [[ -d "$ROOT/skills" ]]; then
  canonical_count=$(find "$ROOT/skills" -mindepth 3 -maxdepth 3 -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')
fi

if [[ ! -d "$MIRROR" ]]; then
  err ".gemini/skills/ is missing — run: make gemini-extension"
else
  mirror_count=$(find "$MIRROR" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) 2>/dev/null | wc -l | tr -d ' ')

  # Greater than zero, explicitly: a regression to the two-level layout, a bad
  # glob, or a half-run generator all produce an empty mirror, and every one of
  # them must fail CI rather than ship an adapter that finds nothing.
  if (( mirror_count == 0 )); then
    err ".gemini/skills/ is empty — Gemini would discover zero skills. Run: make gemini-extension"
  elif (( mirror_count != canonical_count )); then
    err ".gemini/skills/ has $mirror_count entries but skills/<domain>/<name>/SKILL.md has $canonical_count — run: make gemini-extension"
  fi

  # Every entry must resolve. A symlink to a renamed or deleted skill still
  # counts above, and Gemini would skip it without a word.
  while IFS= read -r entry; do
    [[ -e "$entry" ]] || err ".gemini/skills/$(basename "$entry") is a dangling symlink — run: make gemini-extension"
  done < <(find "$MIRROR" -mindepth 1 -maxdepth 1 -type l 2>/dev/null)
fi

# Delegate content-level drift to the generator, which owns the comparison.
if [[ -x "$ROOT/scripts/build-gemini-extension.sh" || -f "$ROOT/scripts/build-gemini-extension.sh" ]]; then
  if ! drift_out=$(bash "$ROOT/scripts/build-gemini-extension.sh" "$ROOT" --check 2>&1); then
    err "generated Gemini adapter is out of sync — run: make gemini-extension"
    printf '%s\n' "$drift_out" >&2
  fi
else
  err "scripts/build-gemini-extension.sh is missing — the .gemini/ mirror has no generator"
fi

# --- 7. Opportunistic: the real CLI, when it is here ---
if command -v gemini >/dev/null 2>&1; then
  note "gemini CLI found ($(gemini --version 2>/dev/null || echo 'version unknown')) — running 'gemini extensions validate'"
  # Never let the CLI block on a prompt or a network call in CI.
  if out=$(cd "$ROOT" && gemini extensions validate . 2>&1 </dev/null); then
    note "gemini extensions validate: ${out:-ok}"
  else
    err "gemini extensions validate failed: $out"
  fi
else
  note "SKIP: gemini CLI not on PATH — manifest validated structurally only."
  note "      Install it with 'npm i -g @google/gemini-cli' to run 'gemini extensions validate .' here."
fi

if (( FAILED > 0 )); then
  echo "Gemini adapter check failed ($FAILED error(s))" >&2
  echo "Reference: docs/user/install/gemini.md · platforms/gemini/adapter.yaml" >&2
  exit 1
fi

echo "Gemini adapter check passed"
