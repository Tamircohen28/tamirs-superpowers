#!/usr/bin/env bash
# registry.sh — read the platform capability registry.
#
# The registry (core/capabilities/platforms.json) is rooted at the PLATFORM — Claude,
# Codex, Cursor, Gemini, OpenCode — because that is how a user names the thing they use.
# Underneath each platform sit its runtime SURFACES: the terminal client, the desktop
# app, the editor extension. The split exists because those surfaces do not agree: the
# Claude Code CLI runs this repo's hook bundle and Claude Desktop's support for it has
# never been verified; Cursor's measurements were taken through an IDE plugin install,
# not through its CLI. One row per vendor could not state both, so it stated the CLI and
# left the rest implied.
#
# Almost every consumer, though, asks a per-SURFACE question — "can the thing I am
# installed into run a subagent?" — and validation commands run against a surface, never
# against a vendor. So rather than teach each consumer to walk two levels, this helper
# flattens the registry into the one-entry-per-surface shape those consumers already
# expect, keyed by surface id (claude_code, claude_desktop, codex, ...).
#
# UNVERIFIED SURFACES ARE OMITTED from the flat view, deliberately. A surface marked
# support: "unverified" carries no capabilities block at all — nobody measured it — so
# including it would force every consumer to invent a reading for a missing block, and
# the most likely invention ("absent means no") is the one thing the registry exists to
# prevent. Consumers that want to *list* those surfaces (docs, install guides) read
# core/capabilities/platforms.json directly.
#
# Usage:
#   source scripts/lib/registry.sh
#   registry_flat <registry.json> <dest.json>   # write the flat per-surface view
#   registry_flat_tmp <registry.json>           # ... to a temp file, echo its path

# Write the flat per-surface view of REGISTRY ($1) to DEST ($2).
#
# Each entry keeps every field the surface declared, plus:
#   platform              — the platform id it belongs to (claude, cursor, ...)
#   platform_display_name — that platform's display name ("Claude")
registry_flat() {
  local src="$1" dest="$2"
  jq '{
    schema_version: .schema_version,
    last_reviewed: .last_reviewed,
    capability_definitions: .capability_definitions,
    platforms: (
      .platforms
      | to_entries
      | map(
          .key as $pid
          | .value as $p
          | ($p.surfaces // {})
          | to_entries
          | map(select(.value.support == "supported"))
          | map({
              key: .key,
              value: (.value + {
                platform: $pid,
                platform_display_name: $p.display_name
              })
            })
        )
      | flatten
      | from_entries
    )
  }' "$src" >"$dest"
}

# As registry_flat, but to a temp file whose path is echoed. The caller owns cleanup.
registry_flat_tmp() {
  local src="$1" dest
  dest="$(mktemp)"
  registry_flat "$src" "$dest"
  printf '%s\n' "$dest"
}
