#!/usr/bin/env bash
# setup-opencode.sh — module writers for the `opencode` setup target.
#
# Sourced by scripts/setup.sh after platforms/opencode/setup.conf. Never executed.
# Module contract: scripts/lib/setup-claude.sh.
#
#   ~/.config/opencode/AGENTS.md     canonical global rules, in a marker block
#   ~/.config/opencode/opencode.json deep merge of the (deliberately tiny) fragment
#
# ~/.opencode/ IS THE BINARY, NOT CONFIG. Nothing here writes there. The config
# root follows XDG_CONFIG_HOME, resolved in platforms/opencode/setup.conf.
#
# NOT TOUCHED: `plugin` (cmux registers ./plugins/cmux-session.js there), `mcp`,
# `provider`, `permission`, `agent`. The fragment asserts none of them, and the
# deep merge unions arrays, so a cmux plugin entry survives verbatim.

# shellcheck shell=bash

# shellcheck source=scripts/lib/setup-rules-common.sh
. "${SETUP_REPO_ROOT}/scripts/lib/setup-rules-common.sh"

OPENCODE_REGISTRY_KEY="opencode"
# Constant, not $SETUP_DISPLAY — see the note in scripts/lib/setup-codex.sh.
OPENCODE_DISPLAY="OpenCode"
OPENCODE_CONFIG_FRAGMENT=""

opencode_target_init() {
  OPENCODE_CONFIG_FRAGMENT="${SETUP_REPO_ROOT}/platforms/opencode/templates/opencode.json"
}

# ---------------------------------------------------------------------------
# agents-md — ~/.config/opencode/AGENTS.md
# ---------------------------------------------------------------------------

opencode_agents_md_kind()  { printf 'file'; }
opencode_agents_md_label() { printf 'AGENTS.md'; }
opencode_agents_md_path()  { printf '%s/AGENTS.md' "$SETUP_TARGET_DIR"; }
opencode_agents_md_available() { rules_available; }

opencode_agents_md_render()   { rules_md_render "$1" "$OPENCODE_DISPLAY" "$OPENCODE_REGISTRY_KEY"; }
opencode_agents_md_unrender() { rules_md_unrender "$1"; }
opencode_agents_md_destructive() { rules_md_destructive; }
opencode_agents_md_summary()  { rules_md_summary "$1"; }

# ---------------------------------------------------------------------------
# config — ~/.config/opencode/opencode.json
# ---------------------------------------------------------------------------

opencode_config_kind()  { printf 'file'; }
opencode_config_label() { printf 'opencode.json'; }
opencode_config_path()  { printf '%s/opencode.json' "$SETUP_TARGET_DIR"; }

opencode_config_available() {
  if [ -f "$OPENCODE_CONFIG_FRAGMENT" ]; then printf 'yes'
  else printf 'no:platforms/opencode/templates/opencode.json not found in this checkout'; fi
}

opencode_config_render()   { rules_json_render "$1" "$OPENCODE_CONFIG_FRAGMENT"; }
opencode_config_unrender() { rules_json_unrender "$1" "$OPENCODE_CONFIG_FRAGMENT"; }
opencode_config_destructive() { printf 'no'; }
opencode_config_summary()  { rules_json_summary "$1" "$OPENCODE_CONFIG_FRAGMENT" "$2"; }
