#!/usr/bin/env bash
# test-worktree-install-gate.sh — the hook-run dependency install in
# hooks/lib/worktree-common.sh runs only script-free installs, and only when
# the permission resolver allows deps.install (ADR 004 D1, SR S-08).
#
# WHAT IS HELD
#   - allow: npm, pnpm, classic yarn and bun run with lifecycle scripts off
#     (--ignore-scripts; pnpm also --ignore-pnpmfile), cargo fetch runs, and the
#     log names the command that would run the skipped scripts;
#   - a repository-pinned yarn (.yarnrc.yml, .yarnrc yarn-path), a package.json
#     with no lockfile, uv, poetry, pipenv, go, deno, bundler and composer are
#     NEVER run, at any verdict: the log prints the command for the user;
#   - ask, deny, a missing resolver, a non-zero exit and unreadable output:
#     nothing runs, every command is printed, no install stamp is written;
#   - the resolver is asked for deps.install, --headless, on the worktree.
#
# HOW
#   A COPY of worktree-common.sh inside a temp plugin tree whose
#   scripts/resolve-permission.sh is a stub (tests/test-merge-policy.sh Part A):
#   the library finds the resolver from its own location, never from the
#   environment. Every installer is a stub on PATH that records its argv, so
#   nothing is downloaded and no toolchain on the machine matters.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$ROOT/tests/lib/harness.sh"

harness_require jq

TMP="$(harness_tmpdir)"
export HOME="$TMP/home"; mkdir -p "$HOME"
export SUPERPOWERS_PKG_CACHE_DIR="$TMP/pkgcache"
unset SUPERPOWERS_WORKTREE_INSTALL_DEPS 2>/dev/null || true

PLUG="$TMP/plugin"
mkdir -p "$PLUG/hooks/lib" "$PLUG/scripts"
cp "$ROOT/hooks/lib/worktree-common.sh" "$PLUG/hooks/lib/worktree-common.sh"
LIB="$PLUG/hooks/lib/worktree-common.sh"
RES="$PLUG/scripts/resolve-permission.sh"

STUB_LOG="$TMP/stub.log"; CALLS="$TMP/calls.log"
export STUB_LOG CALLS
cat > "$RES" <<'STUB'
#!/usr/bin/env bash
printf 'ARGV %s\n' "$*" >> "$STUB_LOG"
case "${STUB_MODE:-ask}" in
  garbage) printf 'not json\n'; exit 0 ;;
  exit3)   printf '{"verdict":"deny"}\n'; exit 3 ;;
  allow-exit1) printf '{"verdict":"allow"}\n'; exit 1 ;;
esac
printf '{"action":"deps.install","verdict":"%s"}\n' "${STUB_MODE:-ask}"
STUB
chmod +x "$RES"

STUBBIN="$TMP/stubbin"; mkdir -p "$STUBBIN"
for b in npm pnpm yarn bun cargo uv poetry pipenv go deno bundle composer; do
  # shellcheck disable=SC2016  # $* and $CALLS expand when the stub runs
  printf '#!/bin/sh\nprintf "%%s %%s\\n" "%s" "$*" >> "$CALLS"\nexit 0\n' "$b" > "$STUBBIN/$b"
  chmod +x "$STUBBIN/$b"
done

# setup <mode> <dir> — run the copy's post-setup on <dir> with the stub answering <mode>.
setup() {
  : > "$STUB_LOG"; : > "$CALLS"
  rm -f "$2/session-files/worktree-setup.log"
  ( cd "$TMP" && PATH="$STUBBIN:$PATH" STUB_MODE="$1" \
      bash -c 'source "$1"; run_worktree_post_setup "$2"' _ "$LIB" "$2" >/dev/null 2>&1 )
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
section "allow: script-free installs run, lifecycle scripts off"
# =============================================================================
d="$(fixture npm package.json package-lock.json)"
setup allow "$d"
judge "npm ci runs with --ignore-scripts" "npm ci --ignore-scripts" "$(calls)"
judge "  ... the log says how to run the skipped scripts" yes "$(has "$(wlog "$d")" "npm rebuild")"
judge "  ... a clean run writes the install stamp" yes "$(stamped "$d")"
judge "  ... the resolver was asked for deps.install, headless, on the worktree" yes \
  "$(has "$(cat "$STUB_LOG")" "deps.install --target $d --repo $d --headless")"

d="$(fixture pnpm package.json pnpm-lock.yaml)"
setup allow "$d"
judge "pnpm install runs with scripts and the pnpmfile off" \
  "pnpm install --frozen-lockfile --ignore-scripts --ignore-pnpmfile" "$(calls)"

d="$(fixture bun package.json bun.lock)"
setup allow "$d"
judge "bun install runs with --ignore-scripts" "bun install --frozen-lockfile --ignore-scripts" "$(calls)"

d="$(fixture yarn1 package.json yarn.lock)"
setup allow "$d"
judge "classic yarn runs with --ignore-scripts" \
  "yarn install --frozen-lockfile --ignore-scripts --non-interactive" "$(calls)"

d="$(fixture cargo Cargo.toml)"
setup allow "$d"
judge "cargo fetch runs" "cargo fetch" "$(calls)"

# =============================================================================
section "never run by a hook, even when allowed: printed for the user"
# =============================================================================
d="$(fixture berry package.json yarn.lock .yarnrc.yml)"
setup allow "$d"
judge "a repo-configured yarn (.yarnrc.yml) is not run" "" "$(calls)"
judge "  ... its command is printed" yes "$(has "$(wlog "$d")" "yarn install --immutable --mode=skip-build")"

d="$(fixture yarnpath package.json yarn.lock)"
printf 'yarn-path "./.yarn/releases/yarn-1.22.js"\n' > "$d/.yarnrc"
setup allow "$d"
judge "a .yarnrc yarn-path is not run" "" "$(calls)"

d="$(fixture nolock package.json)"
setup allow "$d"
judge "package.json without a lockfile is not installed" "" "$(calls)"
judge "  ... the log keeps its label and prints the command" yes \
  "$(has "$(wlog "$d")" "npm install (no lockfile present): NOT run by the hook")"
judge "  ... and no stamp claims the deps are in place" no "$(stamped "$d")"

for pair in "uv:uv.lock:uv sync" "poetry:poetry.lock:poetry install" "pipenv:Pipfile.lock:pipenv sync" \
            "go:go.mod:go mod download" "deno:deno.json:deno install" \
            "ruby:Gemfile:bundle install" "php:composer.json:composer install"; do
  name="${pair%%:*}"; rest="${pair#*:}"; f="${rest%%:*}"; want="${rest#*:}"
  d="$(fixture "$name" "$f")"
  setup allow "$d"
  judge "$name: '$want' is not run" "" "$(calls)"
  judge "  ... and is printed for the user" yes "$(has "$(wlog "$d")" "cd $d && $want")"
done

# =============================================================================
section "not allowed: nothing runs (fail closed)"
# =============================================================================
for mode in ask deny exit3 allow-exit1 garbage; do
  d="$(fixture "m-$mode" package.json package-lock.json Cargo.toml)"
  setup "$mode" "$d"
  judge "resolver '$mode': no installer runs" "" "$(calls)"
  judge "  ... the log says deps.install is not allowed" yes "$(has "$(wlog "$d")" "deps.install is not allowed")"
  judge "  ... and prints the script-free command" yes "$(has "$(wlog "$d")" "npm ci --ignore-scripts")"
  judge "  ... no stamp" no "$(stamped "$d")"
done

mv "$RES" "$RES.off"
d="$(fixture missing package.json package-lock.json)"
setup allow "$d"
judge "resolver missing: no installer runs" "" "$(calls)"
judge "  ... and the log says so" yes "$(has "$(wlog "$d")" "deps.install is not allowed")"
mv "$RES.off" "$RES"

d="$(fixture off package.json package-lock.json)"
: > "$STUB_LOG"
( PATH="$STUBBIN:$PATH" STUB_MODE=allow SUPERPOWERS_WORKTREE_INSTALL_DEPS=0 \
    bash -c 'source "$1"; run_worktree_post_setup "$2"' _ "$LIB" "$d" >/dev/null 2>&1 )
judge "the opt-out still wins: no resolver call, no install" "" "$(cat "$STUB_LOG")$(calls)"

# =============================================================================
section "the in-tree library finds the in-tree resolver"
# =============================================================================
judge "WORKTREE_PERMISSION_RESOLVER is <plugin>/scripts/resolve-permission.sh" \
  "$(cd "$ROOT" && pwd -P)/scripts/resolve-permission.sh" \
  "$(bash -c 'source "$1"; printf "%s" "$WORKTREE_PERMISSION_RESOLVER"' _ "$ROOT/hooks/lib/worktree-common.sh")"

harness_summary
