#!/usr/bin/env bash
# plugin-state.sh — resolve the directory this plugin keeps its own state in.
#
# WHY THIS EXISTS
#   Claude Code exports `CLAUDE_PLUGIN_DATA` to hook processes: a per-plugin
#   directory that, in the host's words, is a "persistent directory that survives
#   plugin updates, created on first reference" (~/.claude/plugins/data/<id>/).
#   That is exactly the right home for state a hook needs to remember between
#   sessions, and it is a property the hand-rolled locations here did not have —
#   `~/.claude/cache/` is a cache path, so anything that treats it as one is free
#   to clear it, and nothing tied it to this plugin's identity.
#
# WHY THERE IS A FALLBACK, AND WHY IT IS NOT OPTIONAL
#   `hooks/hooks.json` is loaded by Claude Code AND the Codex CLI. Codex does not
#   export `CLAUDE_PLUGIN_DATA`, so a hook that assumed it would resolve to an
#   empty path and write to the filesystem root or silently no-op. The fallback is
#   the previous location, unchanged, so behaviour on Codex is exactly what it was.
#
# WHAT DOES NOT BELONG HERE
#   Deliberately NOT migrated: `SESSION_STATE_DIR` (per-session, not per-plugin —
#   it should not survive anything) and `PKG_CACHE_DIR` (pip/poetry caches, shared
#   with other tools on purpose; moving them under a plugin id would fragment a
#   cache whose whole value is being shared).
#
# Usage:
#   source "${SCRIPT_DIR}/lib/plugin-state.sh"
#   dir="$(plugin_state_dir skill-suggest)"   # created on demand, never fails
plugin_state_dir() {
  local name="${1:-state}" base
  if [ -n "${CLAUDE_PLUGIN_DATA:-}" ]; then
    base="${CLAUDE_PLUGIN_DATA%/}"
  else
    base="${HOME}/.claude/cache"
  fi
  local dir="${base}/${name}"
  mkdir -p "$dir" 2>/dev/null || true
  printf '%s' "$dir"
}
