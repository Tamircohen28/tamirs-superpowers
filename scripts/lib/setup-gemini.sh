#!/usr/bin/env bash
# setup-gemini.sh — module writers for the `gemini` setup target.
#
# Sourced by scripts/setup.sh after platforms/gemini/setup.conf. Never executed.
# Module contract: scripts/lib/setup-claude.sh.
#
#   ~/.gemini/GEMINI.md       canonical global rules, in a marker block
#   ~/.gemini/settings.json   deep merge of platforms/gemini/templates/settings.json
#
# NOT TOUCHED: `.hooks` and `.mcpServers`/`.mcp` in settings.json. cmux writes
# BeforeAgent/AfterAgent/PreToolUse/SessionEnd handlers there and gortex writes an
# AfterTool handler; the fragment asserts nothing under either key, and the deep
# merge unions arrays rather than replacing them, so re-running `cmux hooks setup`
# after this is a no-op in both directions.

# shellcheck shell=bash

# shellcheck source=scripts/lib/setup-rules-common.sh
. "${SETUP_REPO_ROOT}/scripts/lib/setup-rules-common.sh"

GEMINI_REGISTRY_KEY="gemini_cli"
# Constant, not $SETUP_DISPLAY — see the note in scripts/lib/setup-codex.sh.
GEMINI_DISPLAY="Gemini CLI"
GEMINI_SETTINGS_FRAGMENT=""

gemini_target_init() {
  GEMINI_SETTINGS_FRAGMENT="${SETUP_REPO_ROOT}/platforms/gemini/templates/settings.json"
}

# ---------------------------------------------------------------------------
# gemini-md — ~/.gemini/GEMINI.md
# ---------------------------------------------------------------------------

gemini_gemini_md_kind()  { printf 'file'; }
gemini_gemini_md_label() { printf 'GEMINI.md'; }
gemini_gemini_md_path()  { printf '%s/GEMINI.md' "$SETUP_TARGET_DIR"; }
gemini_gemini_md_available() { rules_available; }

gemini_gemini_md_render()   { rules_md_render "$1" "$GEMINI_DISPLAY" "$GEMINI_REGISTRY_KEY"; }
gemini_gemini_md_unrender() { rules_md_unrender "$1"; }
gemini_gemini_md_destructive() { rules_md_destructive; }
gemini_gemini_md_summary()  { rules_md_summary "$1"; }

# ---------------------------------------------------------------------------
# settings — ~/.gemini/settings.json
# ---------------------------------------------------------------------------

gemini_settings_kind()  { printf 'file'; }
gemini_settings_label() { printf 'settings.json'; }
gemini_settings_path()  { printf '%s/settings.json' "$SETUP_TARGET_DIR"; }

gemini_settings_available() {
  if [ -f "$GEMINI_SETTINGS_FRAGMENT" ]; then printf 'yes'
  else printf 'no:platforms/gemini/templates/settings.json not found in this checkout'; fi
}

gemini_settings_render()   { rules_json_render "$1" "$GEMINI_SETTINGS_FRAGMENT"; }
gemini_settings_unrender() { rules_json_unrender "$1" "$GEMINI_SETTINGS_FRAGMENT"; }
gemini_settings_destructive() { printf 'no'; }
gemini_settings_summary()  { rules_json_summary "$1" "$GEMINI_SETTINGS_FRAGMENT" "$2"; }
