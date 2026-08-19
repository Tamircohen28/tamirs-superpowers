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

# TOP-LEVEL KEYS BEGINNING WITH `_` ARE METADATA, NOT SETTINGS. The fragments
# carry `_comment` (and `_tally` in plugins.json) to explain themselves to the
# next reader; those must never reach the user's settings.json, so they are
# stripped here rather than at authoring time — the fragments stay self-documenting.
#
# A settings.d file may be written either as a full settings.json fragment
# (`{"permissions":{"allow":[...]}}`) or as just its payload (a bare array, or
# `{"allow":[...]}`). Both are accepted: the filename says where the payload
# belongs, so guessing wrong is not possible, and the data phase and the engine
# phase were built in parallel by different hands.
claude_settings_fragment() {
  local f="$1" base t
  base="$(basename "$f")"
  t="$(jq -r 'type' "$f" 2>/dev/null || printf 'null')"
  {
    case "$base" in
      permissions-allow.json)
        if [ "$t" = array ]; then jq '{permissions: {allow: .}}' "$f"
        elif jq -e 'has("permissions")' "$f" >/dev/null 2>&1; then cat "$f"
        else jq '{permissions: .}' "$f"; fi ;;
      permissions-ask.json)
        if [ "$t" = array ]; then jq '{permissions: {ask: .}}' "$f"
        elif jq -e 'has("permissions")' "$f" >/dev/null 2>&1; then cat "$f"
        else jq '{permissions: .}' "$f"; fi ;;
      marketplaces.json)
        if jq -e 'has("extraKnownMarketplaces")' "$f" >/dev/null 2>&1; then cat "$f"
        else jq '{extraKnownMarketplaces: .}' "$f"; fi ;;
      *)
        if [ "$t" = object ]; then cat "$f"; else printf '{}\n'; fi ;;
    esac
  } | jq 'with_entries(select(.key | startswith("_") | not))'
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

claude_plugins_canonical() {
  local f="${CLAUDE_SETTINGS_D}/plugins.json"
  if jq -e 'has("enabledPlugins")' "$f" >/dev/null 2>&1; then jq '.enabledPlugins' "$f"
  else jq '.' "$f"; fi
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

claude_plugins_summary() {
  local existing="$1" new="$2" canon n_canon n_keep
  canon="$(claude_plugins_canonical)"
  n_canon="$(printf '%s' "$canon" | jq 'length')"
  n_keep="$(setup_json_read "$existing" | jq --argjson c "$canon" \
    '(.enabledPlugins // {}) | with_entries(. as $e | select($c | has($e.key) | not)) | length')"
  printf '%s canonical (%s enabled), %s local preserved' \
    "$n_canon" "$(printf '%s' "$canon" | jq '[.[] | select(.)] | length')" "$n_keep"
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
# notifications-creds / notifications-hook — both env-gated (`--only notifications`
# selects the pair, since --only matches a module or a `<module>-` prefix)
# ---------------------------------------------------------------------------

claude_notifications_creds_kind()  { printf 'file'; }
claude_notifications_creds_label() { printf 'pushover.env'; }
claude_notifications_creds_path()  { printf '%s/pushover.env' "$SETUP_TARGET_DIR"; }

claude_notifications_creds_available() {
  if [ -n "${PUSHOVER_TOKEN:-}" ] && [ -n "${PUSHOVER_USER:-}" ]; then printf 'yes'
  elif [ -n "${PUSHOVER_TOKEN:-}" ] || [ -n "${PUSHOVER_USER:-}" ]; then
    printf 'no:need BOTH PUSHOVER_TOKEN and PUSHOVER_USER'
  else
    printf 'no:no PUSHOVER_TOKEN/PUSHOVER_USER in env — run /notify-setup'
  fi
}

# Credentials live outside the plugin cache on purpose: that directory is
# version-pathed and replaced wholesale on every update, which would delete them.
claude_notifications_creds_render() {
  printf '# Pushover credentials for scripts/notify-pushover.sh — keep private, never commit.\n'
  printf 'PUSHOVER_TOKEN=%s\n' "${PUSHOVER_TOKEN:-}"
  printf 'PUSHOVER_USER=%s\n' "${PUSHOVER_USER:-}"
}

# Deliberately NOT deleted by `remove`: they are user secrets, and a reinstall
# should not need them re-entered. Documented in docs/user/setup.md.
claude_notifications_creds_unrender() { [ -f "$1" ] && cat "$1"; return 0; }
claude_notifications_creds_destructive() { printf 'no'; }
claude_notifications_creds_postwrite() { chmod 600 "$1" 2>/dev/null || true; }
claude_notifications_creds_summary() { printf 'mode 600, outside the plugin cache'; }

claude_notifications_hook_kind()  { printf 'file'; }
claude_notifications_hook_label() { printf 'pushover hook'; }
claude_notifications_hook_path()  { printf '%s/settings.json' "$SETUP_TARGET_DIR"; }
claude_notifications_hook_available() { claude_notifications_creds_available; }

# shellcheck disable=SC2016  # $HOME must expand at hook-run time, not now
CLAUDE_PUSHOVER_CMD='f=$(ls "$HOME"/.claude/plugins/cache/tamirs-marketplace/tamirs-superpowers/*/scripts/notify-pushover.sh 2>/dev/null | sort -rV | head -1) && [ -n "$f" ] && bash "$f"'

# Drop any previous pushover entry before appending, so this is idempotent, and
# select() rather than assignment so other Notification hooks are untouched.
claude_notifications_hook_render() {
  setup_json_read "$1" | jq --arg cmd "$CLAUDE_PUSHOVER_CMD" '
    .hooks //= {} |
    .hooks.Notification = (
      ((.hooks.Notification // [])
        | map(select([(.hooks // [])[] | .command // "" | test("notify-pushover")] | any | not)))
      + [{hooks: [{type: "command", command: $cmd, timeout: 10}]}])' \
    | setup_json_normalize
}

claude_notifications_hook_unrender() {
  setup_json_read "$1" | jq '
    if (.hooks.Notification // null) == null then . else
      .hooks.Notification = ((.hooks.Notification // [])
        | map(select([(.hooks // [])[] | .command // "" | test("notify-pushover")] | any | not)))
      | if (.hooks.Notification | length) == 0 then del(.hooks.Notification) else . end
      | if (.hooks | length) == 0 then del(.hooks) else . end
    end' | setup_json_normalize
}

claude_notifications_hook_destructive() { printf 'no'; }
claude_notifications_hook_summary() { printf 'one Notification hook, others preserved'; }

# ---------------------------------------------------------------------------
# exit-guard — env-gated proxy exit-node guard (preserved from install.sh)
# ---------------------------------------------------------------------------

claude_exit_guard_kind()  { printf 'file'; }
claude_exit_guard_label() { printf 'ensure-exit.sh'; }
claude_exit_guard_path()  { printf '%s/ensure-exit.sh' "$SETUP_TARGET_DIR"; }

claude_exit_guard_available() {
  if [ ! -f "${SETUP_REPO_ROOT}/hooks/ensure-exit.sh" ]; then
    printf 'no:hooks/ensure-exit.sh not found in this checkout'
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
