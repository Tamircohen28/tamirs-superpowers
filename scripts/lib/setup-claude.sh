#!/usr/bin/env bash
# setup-claude.sh — module writers for the `claude` setup target.
#
# Sourced by scripts/setup.sh after platforms/claude/setup.conf. Never executed.
#
# THE MODULE CONTRACT
#   Every module is a pure RENDERER, not a writer. Given the file as it exists on
#   disk, it prints the file as it SHOULD exist. The engine does the comparing,
#   diffing, prompting, backing up and writing — once, generically, for every
#   module of every target. That is what makes idempotence a property of the
#   engine rather than a promise each module has to keep: `old == new` is a
#   content comparison the module cannot get wrong.
#
#   Functions, named `claude_<module>_<verb>` with `-` mapped to `_`:
#     _kind                    file | dir
#     _label                   short human name for the plan table
#     _path                    the absolute path the module manages (kind=file)
#     _available               "yes", or "no:<reason>" — env/data prerequisites
#     _render      <existing>  desired content       (kind=file)
#     _unrender    <existing>  desired content after `remove` (kind=file)
#     _destructive <existing>  "yes" when applying would discard user content
#     _summary     <existing> <new>   one-line "what changes" for the plan table
#     _postwrite   <path>      optional; permissions, chmod, etc.
#     _dir_pairs               "<src>\t<dest>" lines (kind=dir)
#
#   `_unrender` returning the same content as the file already has means `remove`
#   reports "nothing to remove" through the exact same comparison as `apply`.
#   apply and remove are therefore symmetric by construction, not by discipline.

# shellcheck shell=bash

CLAUDE_SETTINGS_D=""   # resolved in claude_target_init

claude_target_init() {
  CLAUDE_SETTINGS_D="${SETUP_REPO_ROOT}/platforms/claude/settings.d"
}

# ---------------------------------------------------------------------------
# settings — everything in platforms/claude/settings.d/ except enabledPlugins
# ---------------------------------------------------------------------------

claude_settings_kind()  { printf 'file'; }
claude_settings_label() { printf 'settings.json'; }
claude_settings_path()  { printf '%s/settings.json' "$SETUP_TARGET_DIR"; }

claude_settings_available() {
  if [ ! -d "$CLAUDE_SETTINGS_D" ]; then
    printf 'no:platforms/claude/settings.d/ not found in this checkout'
    return 0
  fi
  if [ -z "$(find "$CLAUDE_SETTINGS_D" -maxdepth 1 -name '*.json' 2>/dev/null)" ]; then
    printf 'no:platforms/claude/settings.d/ contains no JSON fragments'
    return 0
  fi
  printf 'yes'
}

# Every fragment in settings.d is a full settings.json-shaped OBJECT — the shape
# is fixed by platforms/claude/settings.d/README.md and verified by the data
# owner. There is deliberately no fallback that guesses at a bare array or a
# bare payload: a guess in a merge function is a trap for whoever edits it next,
# and a fragment that is not an object is a data bug we want to hear about
# loudly rather than silently reinterpret.
#
# `_`-prefixed keys are repo-side metadata and are stripped at this boundary —
# see setup_json_strip_meta in scripts/lib/setup-common.sh.
claude_settings_fragment() {
  local f="$1" t
  t="$(jq -r 'type' "$f" 2>/dev/null || printf 'null')"
  if [ "$t" != object ]; then
    setup_warn "$(basename "$f") is a JSON $t, expected an object — skipping it"
    printf '{}\n'
    return 0
  fi
  setup_json_strip_meta < "$f"
}

claude_settings_render() {
  local existing="$1" merged frag f
  merged="$(setup_json_read "$existing")"
  # Sorted so the merge order is deterministic across machines and filesystems.
  for f in $(find "$CLAUDE_SETTINGS_D" -maxdepth 1 -name '*.json' 2>/dev/null | LC_ALL=C sort); do
    case "$(basename "$f")" in
      plugins.json) continue ;;   # owned by the `plugins` module
    esac
    jq empty "$f" >/dev/null 2>&1 || { setup_warn "skipping unparseable fragment $f"; continue; }
    frag="$(claude_settings_fragment "$f")"
    merged="$(setup_json_merge "$merged" "$frag")"
  done
  printf '%s' "$merged" | setup_json_normalize
}

# `remove` restores the pristine backup when one exists — that is the entire
# reason the backup name is fixed. With no backup there is nothing provably ours
# to strip from a merged file, so we leave it and say so.
claude_settings_unrender() {
  local existing="$1" backup
  backup="$(setup_backup_path "$existing")"
  if [ -f "$backup" ]; then setup_json_read "$backup" | setup_json_normalize
  else setup_json_read "$existing" | setup_json_normalize; fi
}

claude_settings_destructive() { printf 'no'; }

claude_settings_summary() {
  local existing="$1" new="$2" added changed
  added="$(jq -n --argjson a "$(setup_json_read "$existing")" --argjson b "$(cat "$new")" \
    '[$b | paths(scalars) | join(".")] - [$a | paths(scalars) | join(".")] | length' 2>/dev/null || printf '?')"
  changed="$(jq -n --argjson a "$(setup_json_read "$existing")" --argjson b "$(cat "$new")" \
    '[$b | paths(scalars) as $p | select(($a | getpath($p)) != null and ($a | getpath($p)) != ($b | getpath($p)))] | length' 2>/dev/null || printf '?')"
  printf '%s keys added, %s changed' "$added" "$changed"
}

# ---------------------------------------------------------------------------
# plugins — enabledPlugins polarity. Canonical wins; local-only entries survive.
# ---------------------------------------------------------------------------

claude_plugins_kind()  { printf 'file'; }
claude_plugins_label() { printf 'enabledPlugins'; }
claude_plugins_path()  { printf '%s/settings.json' "$SETUP_TARGET_DIR"; }

claude_plugins_available() {
  if [ -f "${CLAUDE_SETTINGS_D}/plugins.json" ]; then printf 'yes'
  else printf 'no:platforms/claude/settings.d/plugins.json not found'; fi
}

# Strip metadata BEFORE reaching for .enabledPlugins, not after. Reading the key
# happens to exclude `_tally` today, which is precisely why this was fragile: the
# guarantee has to come from the boundary, not from a lucky key name.
claude_plugins_canonical() {
  local f="${CLAUDE_SETTINGS_D}/plugins.json"
  setup_json_strip_meta < "$f" | jq 'if has("enabledPlugins") then .enabledPlugins else . end'
}

# `+` and not deepmerge: the canonical value must WIN per key, including when it
# is `false`. A plugin the repo records as disabled is disabled on the machine —
# that is the whole point of P1.3. Keys only the machine has are preserved.
claude_plugins_render() {
  local existing="$1" canon
  canon="$(claude_plugins_canonical)"
  setup_json_read "$existing" \
    | jq --argjson canon "$canon" '
        .enabledPlugins = (
          ((.enabledPlugins // {})
            | with_entries(.key |= sub("@tamirs-plugins$"; "@tamirs-marketplace")))
          + $canon)' \
    | setup_json_normalize
}

# Removing the plugin should not silently disable every marketplace plugin the
# user has — it should stop asserting our opinion. We drop only the keys this
# repo publishes, leaving the rest of enabledPlugins as the user left it.
claude_plugins_unrender() {
  local existing="$1" canon
  canon="$(claude_plugins_canonical)"
  setup_json_read "$existing" \
    | jq --argjson canon "$canon" '
        if has("enabledPlugins") then
          .enabledPlugins = (.enabledPlugins | with_entries(. as $e | select($canon | has($e.key) | not)))
          | if (.enabledPlugins | length) == 0 then del(.enabledPlugins) else . end
        else . end' \
    | setup_json_normalize
}

claude_plugins_destructive() { printf 'no'; }

# THE LOUD PART: how many plugins this apply will TURN OFF.
#
# The canonical set records 15 deliberate `false` entries, so applying it to a
# machine whose plugins are all on will disable 15 of them. That is the intended
# fix — the old canonical set was 21 all-true and would have re-enabled plugins
# the user had switched off on purpose — but it is the sharpest behaviour change
# in the whole installer, and a user should read it in the plan rather than
# discover it afterwards. A release note only reaches people who read release
# notes; the plan table reaches everyone.
claude_plugins_summary() {
  local existing="$1" canon n_canon n_on n_keep n_disable
  canon="$(claude_plugins_canonical)"
  n_canon="$(printf '%s' "$canon" | jq 'length')"
  n_on="$(printf '%s' "$canon" | jq '[.[] | select(.)] | length')"
  n_keep="$(setup_json_read "$existing" | jq --argjson c "$canon" \
    '(.enabledPlugins // {}) | with_entries(. as $e | select($c | has($e.key) | not)) | length')"
  # NOT `($c[.key] // null) == false` — jq's `//` treats `false` itself as empty,
  # so every deliberate `false` collapses to null and the count is always 0.
  # Index by a bound variable and compare directly.
  n_disable="$(setup_json_read "$existing" | jq --argjson c "$canon" \
    '[(.enabledPlugins // {}) | to_entries[] | . as $e
       | select($e.value == true)
       | select(($c | has($e.key)) and ($c[$e.key] == false))] | length')"
  if [ "${n_disable:-0}" -gt 0 ]; then
    printf 'WILL DISABLE %s currently-enabled plugin(s); %s canonical (%s on), %s local preserved' \
      "$n_disable" "$n_canon" "$n_on" "$n_keep"
  else
    printf '%s canonical (%s on), %s local preserved' "$n_canon" "$n_on" "$n_keep"
  fi
}

# ---------------------------------------------------------------------------
# statusline — computed here, never stored in settings.d
# ---------------------------------------------------------------------------

claude_statusline_kind()  { printf 'file'; }
claude_statusline_label() { printf 'statusLine'; }
claude_statusline_path()  { printf '%s/settings.json' "$SETUP_TARGET_DIR"; }
claude_statusline_available() { printf 'yes'; }

# Single quotes are load-bearing: $HOME and the glob must expand when Claude Code
# runs the command, not when this script renders it, so the wired path keeps
# finding the newest installed version after every plugin update.
# shellcheck disable=SC2016
CLAUDE_STATUSLINE_CMD='f=$(ls "$HOME"/.claude/plugins/cache/tamirs-marketplace/tamirs-superpowers/*/scripts/statusline.sh 2>/dev/null | sort -rV | head -1) && [ -n "$f" ] && bash "$f"'

claude_statusline_render() {
  setup_json_read "$1" \
    | jq --arg cmd "$CLAUDE_STATUSLINE_CMD" \
        '. + {statusLine: {type: "command", command: $cmd}}' \
    | setup_json_normalize
}

claude_statusline_unrender() {
  setup_json_read "$1" \
    | jq --arg cmd "$CLAUDE_STATUSLINE_CMD" \
        'if (.statusLine.command // "") == $cmd then del(.statusLine) else . end' \
    | setup_json_normalize
}

claude_statusline_destructive() { printf 'no'; }
claude_statusline_summary() { printf 'points at the newest installed plugin version'; }

# ---------------------------------------------------------------------------
# agents — a directory sync, not a file render
# ---------------------------------------------------------------------------

claude_agents_kind()  { printf 'dir'; }
claude_agents_label() { printf 'agents/'; }
claude_agents_path()  { printf '%s/agents' "$SETUP_TARGET_DIR"; }

claude_agents_available() {
  if [ -d "${SETUP_REPO_ROOT}/agents" ]; then printf 'yes'
  else printf 'no:agents/ not found in this checkout'; fi
}

claude_agents_dir_pairs() {
  local src
  for src in "${SETUP_REPO_ROOT}"/agents/*.md; do
    [ -f "$src" ] || continue
    printf '%s\t%s/%s\n' "$src" "$(claude_agents_path)" "$(basename "$src")"
  done
}

claude_agents_destructive() { printf 'no'; }

# ---------------------------------------------------------------------------
# claude-md — the one genuinely destructive module
# ---------------------------------------------------------------------------

claude_claude_md_kind()  { printf 'file'; }
claude_claude_md_label() { printf 'CLAUDE.md'; }
claude_claude_md_path()  { printf '%s/CLAUDE.md' "$SETUP_TARGET_DIR"; }

claude_claude_md_available() {
  if [ -f "${SETUP_REPO_ROOT}/templates/global-CLAUDE.md" ]; then printf 'yes'
  else printf 'no:templates/global-CLAUDE.md not found in this checkout'; fi
}

# Markdown has no merge semantics we could trust, so this is a whole-file render.
# That is exactly why it declares itself destructive: the engine then routes it
# through the overwrite / backup-and-write / skip question instead of [y/N].
claude_claude_md_render() { cat "${SETUP_REPO_ROOT}/templates/global-CLAUDE.md"; }

claude_claude_md_unrender() {
  local existing="$1" backup
  backup="$(setup_backup_path "$existing")"
  if [ -f "$backup" ]; then cat "$backup"
  elif [ -f "$existing" ] && diff -q "$existing" "${SETUP_REPO_ROOT}/templates/global-CLAUDE.md" >/dev/null 2>&1; then
    printf '%s' "$SETUP_DELETE_SENTINEL"   # ours and unmodified — delete it
  elif [ -f "$existing" ]; then cat "$existing"
  fi
}

claude_claude_md_destructive() {
  local existing="$1"
  [ -f "$existing" ] || { printf 'no'; return 0; }
  if diff -q "$existing" "${SETUP_REPO_ROOT}/templates/global-CLAUDE.md" >/dev/null 2>&1
  then printf 'no'; else printf 'yes'; fi
}

claude_claude_md_summary() {
  local existing="$1"
  if [ -f "$existing" ]; then printf 'replaces a customised file — fill in <PLACEHOLDER> values after'
  else printf 'new file — fill in the <PLACEHOLDER> values'; fi
}

# ---------------------------------------------------------------------------
# Pushover is NOT a setup module any more. The Notification hook is wired by the
# plugin's own hook manifest, and the credentials are the manifest's sensitive
# `pushover_token`/`pushover_user` userConfig options (the host exports them to
# that hook as CLAUDE_PLUGIN_OPTION_*). A hook in ~/.claude/settings.json never
# receives those options, and a credentials file on disk is what the Anthropic
# directory policy forbids a plugin to read, so both earlier modules are gone.
# `scripts/uninstall.sh` still removes the settings.json hook older installs wrote.
# ---------------------------------------------------------------------------

# ---------------------------------------------------------------------------
# exit-guard — env-gated proxy exit-node guard (preserved from install.sh)
# ---------------------------------------------------------------------------

claude_exit_guard_kind()  { printf 'file'; }
claude_exit_guard_label() { printf 'ensure-exit.sh'; }
claude_exit_guard_path()  { printf '%s/ensure-exit.sh' "$SETUP_TARGET_DIR"; }

claude_exit_guard_available() {
  if [ ! -f "${SETUP_REPO_ROOT}/hooks/ensure-exit.sh" ]; then
    printf 'no:the ensure-exit hook script was not found in this checkout'
  elif [ -n "${CLAUDE_EXIT_PROXY:-}" ] && [ -n "${CLAUDE_EXIT_PUBLIC_IP:-}" ]; then
    printf 'yes'
  else
    printf 'no:no CLAUDE_EXIT_PROXY/CLAUDE_EXIT_PUBLIC_IP in env'
  fi
}

claude_exit_guard_render() {
  sed \
    -e "s|CLAUDE_EXIT_PROXY:-}|CLAUDE_EXIT_PROXY:-${CLAUDE_EXIT_PROXY:-}}|g" \
    -e "s|CLAUDE_EXIT_PUBLIC_IP:-}|CLAUDE_EXIT_PUBLIC_IP:-${CLAUDE_EXIT_PUBLIC_IP:-}}|g" \
    "${SETUP_REPO_ROOT}/hooks/ensure-exit.sh"
}

claude_exit_guard_unrender() { printf '%s' "$SETUP_DELETE_SENTINEL"; }
claude_exit_guard_destructive() { printf 'no'; }
claude_exit_guard_postwrite() { chmod +x "$1" 2>/dev/null || true; }
claude_exit_guard_summary() { printf 'proxy=%s ip=%s' "${CLAUDE_EXIT_PROXY:-}" "${CLAUDE_EXIT_PUBLIC_IP:-}"; }
