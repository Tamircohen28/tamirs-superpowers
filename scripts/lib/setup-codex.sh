#!/usr/bin/env bash
# setup-codex.sh — module writers for the `codex` setup target.
#
# Sourced by scripts/setup.sh after platforms/codex/setup.conf. Never executed.
# The module contract is documented in full in scripts/lib/setup-claude.sh.
#
# WHAT THIS TARGET MANAGES
#   ~/.codex/AGENTS.md      the canonical global rules, in a marker block
#   ~/.codex/config.toml    a marker block of COMMENTS ONLY (see below)
#
# WHAT IT DELIBERATELY DOES NOT TOUCH — read before adding a module here
#   1. `[hooks]` and every `[hooks.state."..."] trusted_hash` entry. Codex stores
#      a per-hook trust hash there; it is invalidated whenever the hook's content
#      or path changes, and re-trusting is a user action. Rewriting, reordering
#      or reformatting that table would silently break wiring this repo does not
#      own (cmux, gortex, other plugins) with no error the user would ever see.
#      Upstream considers the key a private implementation detail
#      (openai/codex#21615), which is a second reason not to build on it.
#      Our block is appended at EOF and touches nothing above it.
#   2. Real settings of any kind. Under TOML v1.0.0 a bare `key = value` appended
#      at the end of a file binds to the LAST `[table]` header, not to the
#      document root — and config.toml always has tables. Writing `model` or
#      `approval_policy` from here would land them inside `[hooks.state...]`.
#      Every line we write is therefore a comment, which is position-independent.
#      Codex needs no key to load ~/.codex/AGENTS.md; it reads it automatically.

# shellcheck shell=bash

# shellcheck source=scripts/lib/setup-rules-common.sh
. "${SETUP_REPO_ROOT}/scripts/lib/setup-rules-common.sh"

CODEX_REGISTRY_KEY="codex"
# Display name is a CONSTANT here, not $SETUP_DISPLAY. The engine re-renders during
# `apply`, after the plan loop has finished and left the target globals pointing at
# whichever target was loaded last — a renderer that reads them writes another
# platform's name into this file.
CODEX_DISPLAY="Codex CLI"

# ---------------------------------------------------------------------------
# agents-md — ~/.codex/AGENTS.md
# ---------------------------------------------------------------------------

codex_agents_md_kind()  { printf 'file'; }
codex_agents_md_label() { printf 'AGENTS.md'; }
codex_agents_md_path()  { printf '%s/AGENTS.md' "$SETUP_TARGET_DIR"; }
codex_agents_md_available() { rules_available; }

codex_agents_md_render()   { rules_md_render "$1" "$CODEX_DISPLAY" "$CODEX_REGISTRY_KEY"; }
codex_agents_md_unrender() { rules_md_unrender "$1"; }
codex_agents_md_destructive() { rules_md_destructive; }
codex_agents_md_summary()  { rules_md_summary "$1"; }

# ---------------------------------------------------------------------------
# config — the comment-only anchor in ~/.codex/config.toml
# ---------------------------------------------------------------------------

codex_config_kind()  { printf 'file'; }
codex_config_label() { printf 'config.toml'; }
codex_config_path()  { printf '%s/config.toml' "$SETUP_TARGET_DIR"; }
codex_config_available() { printf 'yes'; }

codex_config_block_body() {
  cat <<'BODY'
# Global agent rules for Codex live in AGENTS.md next to this file, rendered from
# core/global-rules.md by `bash scripts/setup.sh apply --targets codex`. Codex
# loads that file automatically — no key here enables it.
#
# This block is comments only, on purpose:
#   * Codex records a per-hook `trusted_hash` under [hooks.state.*]. Editing hook
#     content or rewriting that table invalidates the hashes and silently breaks
#     wiring this installer does not own. We never read or write those keys.
#   * Under TOML v1.0.0 a bare `key = value` appended at EOF binds to the last
#     [table] header rather than to the document root, so appending real settings
#     to a file that already has tables is unsafe by construction.
# Your model, approval policy, sandbox and hook settings are left untouched.
BODY
}

codex_config_render()   { rules_toml_render "$1" codex_config_block_body; }
codex_config_unrender() { rules_toml_unrender "$1"; }
codex_config_destructive() { printf 'no'; }
codex_config_summary() { printf 'appends a comment-only block; hooks and trusted_hash untouched'; }
