#!/usr/bin/env bash
# setup-cursor.sh — module writers for the `cursor` setup target.
#
# Sourced by scripts/setup.sh after platforms/cursor/setup.conf. Never executed.
# Module contract: scripts/lib/setup-claude.sh.
#
#   ~/.cursor/rules/tamirs-superpowers.mdc  canonical global rules as a Cursor rule
#   ~/.cursor/cli-config.json               deep merge of the permissions fragment
#
# NOT TOUCHED: ~/.cursor/hooks.json, where cmux writes afterAgentResponse /
# afterShellExecution handlers. This target has no hooks module at all — the
# Claude-shaped hook bundle does not run under Cursor anyway (capability registry
# records hooks as `partial`), so there is nothing to merge and nothing to break.
#
# The rule file is ours by filename, but it is still written as a marker block:
# a user who adds their own notes under our rule keeps them across updates, and
# `remove` can tell "only our block is left" from "the user wrote something here".

# shellcheck shell=bash

# shellcheck source=scripts/lib/setup-rules-common.sh
. "${SETUP_REPO_ROOT}/scripts/lib/setup-rules-common.sh"

CURSOR_REGISTRY_KEY="cursor"
# Constant, not $SETUP_DISPLAY — see the note in scripts/lib/setup-codex.sh.
CURSOR_DISPLAY="Cursor"
CURSOR_CLI_CONFIG_FRAGMENT=""

cursor_target_init() {
  CURSOR_CLI_CONFIG_FRAGMENT="${SETUP_REPO_ROOT}/platforms/cursor/templates/cli-config.json"
}

# ---------------------------------------------------------------------------
# rules — ~/.cursor/rules/tamirs-superpowers.mdc
# ---------------------------------------------------------------------------

cursor_rules_kind()  { printf 'file'; }
cursor_rules_label() { printf 'rules/*.mdc'; }
cursor_rules_path()  { printf '%s/rules/tamirs-superpowers.mdc' "$SETUP_TARGET_DIR"; }
cursor_rules_available() { rules_available; }

# `.mdc` is YAML frontmatter followed by markdown. alwaysApply:true is what makes
# it a GLOBAL rule rather than a glob-scoped one — without it the rules would only
# load for files matching `globs`, which is not what a global-rules file means.
cursor_rules_frontmatter() {
  printf -- '---\n'
  printf 'description: Global agent rules — rendered from core/global-rules.md\n'
  printf 'alwaysApply: true\n'
  printf -- '---\n'
}

cursor_rules_render() {
  local existing="$1"
  if [ -f "$existing" ] && [ -s "$existing" ]; then
    rules_md_render "$existing" "$CURSOR_DISPLAY" "$CURSOR_REGISTRY_KEY"
  else
    cursor_rules_frontmatter
    printf '\n'
    rules_md_block "$CURSOR_DISPLAY" "$CURSOR_REGISTRY_KEY"
  fi
}

# A file holding nothing but our frontmatter and our block is ours to delete.
# Anything else the user added below it means the file stays, minus our block.
cursor_rules_unrender() {
  local existing="$1" rest
  [ -f "$existing" ] || return 0
  rest="$(rules_md_unrender "$existing")"
  [ "$rest" = "$SETUP_DELETE_SENTINEL" ] && { printf '%s' "$SETUP_DELETE_SENTINEL"; return 0; }
  # Strip the leading `---` frontmatter block; if nothing survives, the file was
  # entirely ours.
  if [ -z "$(printf '%s\n' "$rest" | awk '
        NR == 1 && $0 == "---" { fm = 1; next }
        fm == 1 { if ($0 == "---") fm = 0; next }
        $0 ~ /^[[:space:]]*$/ { next }
        { print }')" ]; then
    printf '%s' "$SETUP_DELETE_SENTINEL"
  else
    printf '%s\n' "$rest"
  fi
}

cursor_rules_destructive() { rules_md_destructive; }
cursor_rules_summary()  { rules_md_summary "$1"; }

# ---------------------------------------------------------------------------
# cli-config — ~/.cursor/cli-config.json
# ---------------------------------------------------------------------------

cursor_cli_config_kind()  { printf 'file'; }
cursor_cli_config_label() { printf 'cli-config.json'; }
cursor_cli_config_path()  { printf '%s/cli-config.json' "$SETUP_TARGET_DIR"; }

cursor_cli_config_available() {
  if [ -f "$CURSOR_CLI_CONFIG_FRAGMENT" ]; then printf 'yes'
  else printf 'no:platforms/cursor/templates/cli-config.json not found in this checkout'; fi
}

cursor_cli_config_render()   { rules_json_render "$1" "$CURSOR_CLI_CONFIG_FRAGMENT"; }
cursor_cli_config_unrender() { rules_json_unrender "$1" "$CURSOR_CLI_CONFIG_FRAGMENT"; }
cursor_cli_config_destructive() { printf 'no'; }
cursor_cli_config_summary()  { rules_json_summary "$1" "$CURSOR_CLI_CONFIG_FRAGMENT" "$2"; }
