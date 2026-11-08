#!/usr/bin/env bash
# test-worktree-install-gate.sh — the hook-run dependency install in
# hooks/lib/worktree-common.sh runs only script-free installs (security review
# S-08). There is no permission gate in front of it since 6.0.0 (ADR 006).
#
# WHAT IS HELD
#   - npm, pnpm, classic yarn and bun run with lifecycle scripts off
#     (--ignore-scripts; pnpm also --ignore-pnpmfile), cargo fetch runs, and the
#     log names the command that would run the skipped scripts;
#   - a repository-pinned yarn (.yarnrc.yml, .yarnrc yarn-path), a package.json
#     with no lockfile, uv, poetry, pipenv, go, deno, bundler and composer are
#     NEVER run: the log prints the command for the user;
#   - SUPERPOWERS_WORKTREE_INSTALL_DEPS=0 still turns installs off.
#
# HOW
#   Every installer is a stub on PATH that records its argv, so nothing is
#   downloaded and no toolchain on the machine matters.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$ROOT/tests/lib/harness.sh"

harness_require jq

TMP="$(harness_tmpdir)"
export HOME="$TMP/home"; mkdir -p "$HOME"
export SUPERPOWERS_PKG_CACHE_DIR="$TMP/pkgcache"
unset SUPERPOWERS_WORKTREE_INSTALL_DEPS 2>/dev/null || true

LIB="$ROOT/hooks/lib/worktree-common.sh"
CALLS="$TMP/calls.log"
export CALLS

STUBBIN="$TMP/stubbin"; mkdir -p "$STUBBIN"
for b in npm pnpm yarn bun cargo uv poetry pipenv go deno bundle composer; do
  # shellcheck disable=SC2016  # $* and $CALLS expand when the stub runs
  printf '#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >> "$CALLS"\nexit 0\n' "$b" > "$STUBBIN/$b"
  chmod +x "$STUBBIN/$b"
done

# setup <dir> — run the library's post-setup on <dir>.
setup() {
  : > "$CALLS"
  rm -f "$1/session-files/worktree-setup.log"
  ( cd "$TMP" && PATH="$STUBBIN:$PATH" \
      bash -c 'source "$1"; run_worktree_post_setup "$2"' _ "$LIB" "$1" >/dev/null 2>&1 )
}
wlog()  { cat "$1/session-files/worktree-setup.log" 2>/dev/null; }
calls() { cat "$CALLS" 2>/dev/null; }
# fixture <name> <file>... — a fresh worktree dir holding the named files.
fixture() {
  local d="$TMP/wt-$1"; shift
  rm -rf "$d"; mkdir -p "$d"
  local f; for f in "$@"; do printf 'x\n' > "$d/$f"; done
  printf '%s' "$d"
}
stamped() { if [ -e "$1/.superpowers-deps" ]; then echo yes; else echo no; fi; }

# =============================================================================
section "script-free installs run, lifecycle scripts off"
# =============================================================================
d="$(fixture npm package.json package-lock.json)"
setup "$d"
judge "npm ci runs with --ignore-scripts" "npm ci --ignore-scripts" "$(calls)"
judge "  ... the log says how to run the skipped scripts" yes "$(has "$(wlog "$d")" "npm rebuild")"
judge "  ... a clean run writes the install stamp" yes "$(stamped "$d")"

d="$(fixture pnpm package.json pnpm-lock.yaml)"
setup "$d"
judge "pnpm install runs with scripts and the pnpmfile off" \
  "pnpm install --frozen-lockfile --ignore-scripts --ignore-pnpmfile" "$(calls)"

d="$(fixture bun package.json bun.lock)"
setup "$d"
judge "bun install runs with --ignore-scripts" "bun install --frozen-lockfile --ignore-scripts" "$(calls)"

d="$(fixture yarn1 package.json yarn.lock)"
setup "$d"
judge "classic yarn runs with --ignore-scripts" \
  "yarn install --frozen-lockfile --ignore-scripts --non-interactive" "$(calls)"

d="$(fixture cargo Cargo.toml)"
setup "$d"
judge "cargo fetch runs" "cargo fetch" "$(calls)"

# =============================================================================
section "never run by a hook: printed for the user"
# =============================================================================
d="$(fixture berry package.json yarn.lock .yarnrc.yml)"
setup "$d"
judge "a repo-configured yarn (.yarnrc.yml) is not run" "" "$(calls)"
judge "  ... its command is printed" yes "$(has "$(wlog "$d")" "yarn install --immutable --mode=skip-build")"

d="$(fixture yarnpath package.json yarn.lock)"
printf 'yarn-path "./.yarn/releases/yarn-1.22.js"\n' > "$d/.yarnrc"
setup "$d"
judge "a .yarnrc yarn-path is not run" "" "$(calls)"

d="$(fixture nolock package.json)"
setup "$d"
judge "package.json without a lockfile is not installed" "" "$(calls)"
judge "  ... the log keeps its label and prints the command" yes \
  "$(has "$(wlog "$d")" "npm install (no lockfile present): NOT run by the hook")"
judge "  ... and no stamp claims the deps are in place" no "$(stamped "$d")"

for pair in "uv:uv.lock:uv sync" "poetry:poetry.lock:poetry install" "pipenv:Pipfile.lock:pipenv sync" \
            "go:go.mod:go mod download" "deno:deno.json:deno install" \
            "ruby:Gemfile:bundle install" "php:composer.json:composer install"; do
  name="${pair%%:*}"; rest="${pair#*:}"; f="${rest%%:*}"; want="${rest#*:}"
  d="$(fixture "$name" "$f")"
  setup "$d"
  judge "$name: '$want' is not run" "" "$(calls)"
  judge "  ... and is printed for the user" yes "$(has "$(wlog "$d")" "cd $d && $want")"
done

# =============================================================================
section "the opt-out"
# =============================================================================
d="$(fixture off package.json package-lock.json)"
: > "$CALLS"
( PATH="$STUBBIN:$PATH" SUPERPOWERS_WORKTREE_INSTALL_DEPS=0 \
    bash -c 'source "$1"; run_worktree_post_setup "$2"' _ "$LIB" "$d" >/dev/null 2>&1 )
judge "SUPERPOWERS_WORKTREE_INSTALL_DEPS=0: no install" "" "$(calls)"

harness_summary
