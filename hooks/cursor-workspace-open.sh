#!/usr/bin/env bash
# cursor-workspace-open.sh — Cursor `workspaceOpen` hook: name plugin paths to load.
#
# WHY THIS EXISTS
#   Cursor's workspaceOpen hook "can return plugin paths to load when a workspace
#   opens" ({"pluginPaths": [...]}, absolute paths). It is the one route by which
#   a checkout of this plugin can be loaded into Cursor automatically, without a
#   marketplace install and without `--plugin-dir` on every CLI invocation —
#   useful to a contributor hacking on the plugin, and to a team that pins a
#   vendored copy.
#
# WHAT IT RETURNS
#   {"pluginPaths": []} unless SUPERPOWERS_CURSOR_PLUGIN_PATH is set. The variable
#   is a colon-separated list; each entry is kept only when it is an ABSOLUTE
#   directory that carries a plugin manifest (.cursor-plugin/plugin.json or a root
#   plugin.json). Anything else is reported on stderr and dropped — a relative
#   path, a typo, or a directory that is not a plugin must not reach Cursor's
#   loader as a path it then fails on silently.
#
# NOT A PLATFORM-DETECTION CASE
#   workspaceOpen is Cursor-only (and desktop-only — cloud agents never fire it)
#   and this script is wired only from platforms/cursor/hooks.json, so there is
#   no Claude dialect to branch on. The payload omits the conversation fields and
#   carries nothing this hook needs; it is read (bounded) only so stdin is drained.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hook-output.sh
source "${SCRIPT_DIR}/lib/hook-output.sh"
# shellcheck source=lib/cursor-output.sh
source "${SCRIPT_DIR}/lib/cursor-output.sh"

_input="$(hook_read_stdin)"
: "$_input"

paths=()
if [ -n "${SUPERPOWERS_CURSOR_PLUGIN_PATH:-}" ]; then
  IFS=':' read -r -a candidates <<< "${SUPERPOWERS_CURSOR_PLUGIN_PATH}"
  for p in "${candidates[@]}"; do
    [ -n "$p" ] || continue
    case "$p" in
      /*) ;;
      *) printf 'cursor-workspace-open: ignoring %s — pluginPaths must be absolute\n' "$p" >&2; continue ;;
    esac
    if [ ! -d "$p" ]; then
      printf 'cursor-workspace-open: ignoring %s — not a directory\n' "$p" >&2
      continue
    fi
    if [ ! -f "$p/.cursor-plugin/plugin.json" ] && [ ! -f "$p/plugin.json" ]; then
      printf 'cursor-workspace-open: ignoring %s — no .cursor-plugin/plugin.json or plugin.json in it\n' "$p" >&2
      continue
    fi
    paths+=("${p%/}")
  done
fi

cursor_plugin_paths ${paths[@]+"${paths[@]}"}
