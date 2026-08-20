#!/usr/bin/env bash
# setup-rules-common.sh — shared renderers for the four non-Claude setup targets
# (codex, cursor, gemini, opencode).
#
# Sourced by scripts/lib/setup-<target>.sh, never executed. Sourcing twice is a
# no-op, which matters because scripts/setup.sh sources one writer per target and
# four of them want these helpers.
#
# WHY A SHARED FILE
#   Three of the four targets render the SAME canonical markdown into a different
#   filename, and all four have to answer "did anything actually change" the same
#   way. Four copies of the marker-block editor would be four chances to get
#   idempotence subtly wrong in one of them.
#
# WHAT LIVES HERE
#   * the canonical source lookup (core/global-rules.md) and its body extraction
#   * marker-block editing for markdown (HTML comments) and TOML (# comments)
#   * capability-honesty notes generated from core/capabilities/platforms.json
#   * JSON fragment loading with `_`-prefixed metadata keys stripped, and the
#     inverse un-merge used by `setup.sh remove`
#
# PORTABILITY: bash 3.2, POSIX awk/sed, jq. See scripts/lib/setup-common.sh.

# shellcheck shell=bash

if [ -n "${SETUP_RULES_COMMON_LOADED:-}" ]; then return 0; fi
SETUP_RULES_COMMON_LOADED=1

# Markdown markers are HTML comments, not the `# >>>` shell form used elsewhere:
# a line starting with `#` in a markdown rules file renders as a heading, and the
# agent reading it would treat our bookkeeping as an instruction.
SETUP_MD_OPEN='<!-- >>> tamirs-superpowers >>> -->'
SETUP_MD_CLOSE='<!-- <<< tamirs-superpowers <<< -->'
SETUP_TOML_OPEN="$SETUP_MARKER_OPEN"
SETUP_TOML_CLOSE="$SETUP_MARKER_CLOSE"

# Capabilities worth reporting on, in a FIXED order so the rendered file is
# byte-stable across runs and machines. Only these; the registry has rows that
# say nothing to a person reading their own rules file.
RULES_NOTE_CAPS="skill_auto_invocation slash_commands subagents parallel_subagents agent_teams hooks statusline background_tasks worktree_isolation ask_user_question artifacts session_transcripts"

rules_source() { printf '%s/core/global-rules.md' "$SETUP_REPO_ROOT"; }

# Availability answer shared by every rules module.
rules_available() {
  if [ -f "$(rules_source)" ]; then printf 'yes'
  else printf 'no:core/global-rules.md not found in this checkout'; fi
}

# rules_body — the canonical file minus its own leading HTML-comment header.
# That header explains the file to a REPO reader; a user's ~/.codex/AGENTS.md is
# not the place for instructions about how the repo is laid out.
rules_body() {
  awk '
    NR == 1 && $0 ~ /^<!--/ { inc = 1 }
    inc == 1 { if ($0 ~ /-->/) inc = 0; next }
    !started && $0 ~ /^[[:space:]]*$/ { next }
    { started = 1; print }
  ' "$(rules_source)"
}

# rules_platform_notes <registry-key> <display> — capability honesty.
# Every capability the rules lean on that is NOT native on this platform is named
# here with its recorded fallback, so nothing is silently dropped on the way from
# the canonical source to a platform that cannot express it.
rules_platform_notes() {
  local key="$1" display="$2" reg cap st fb surf any=no
  reg="${SETUP_REPO_ROOT}/core/capabilities/platforms.json"
  [ -f "$reg" ] || return 0
  # Registry lookups are by SURFACE id (claude_code, cursor, ...), which now lives one
  # level down under its platform. This prefix resolves a surface id under either shape,
  # so a schema_version 1 registry in an older checkout still reads. Model: scripts/lib/registry.sh.
  surf='(first(.platforms[]?.surfaces[$p]? | select(. != null)) // .platforms[$p]?)'
  jq -e --arg p "$key" "$surf" "$reg" >/dev/null 2>&1 || return 0

  printf '\n## Platform notes — %s\n\n' "$display"
  printf 'Generated from `core/capabilities/platforms.json`. The rules above assume\n'
  printf 'capabilities this platform does not provide natively; each line says what to do\n'
  printf 'instead, so nothing above is silently unenforceable here.\n\n'

  for cap in $RULES_NOTE_CAPS; do
    st="$(jq -r --arg p "$key" --arg c "$cap" "$surf.capabilities[\$c].status // empty" "$reg" 2>/dev/null)"
    [ -n "$st" ] || continue
    case "$st" in native) continue ;; esac
    fb="$(jq -r --arg p "$key" --arg c "$cap" "$surf.capabilities[\$c].fallback // \"\"" "$reg" 2>/dev/null \
          | tr '\n' ' ' | sed "s|${HOME}|~|g" | cut -c1-200 | sed 's/[[:space:]]*$//')"
    any=yes
    if [ -n "$fb" ]; then
      printf -- '- `%s` — %s. %s\n' "$cap" "$st" "$fb"
    else
      printf -- '- `%s` — %s.\n' "$cap" "$st"
    fi
  done
  [ "$any" = yes ] || printf -- '- Every capability these rules rely on is native here.\n'
}

# rules_md_block <display> <registry-key> — the managed block, markers included.
# Deterministic: no timestamps, no hostnames, no absolute paths. A timestamp here
# would make every run a diff and idempotence a lie.
rules_md_block() {
  local display="$1" key="$2"
  printf '%s\n' "$SETUP_MD_OPEN"
  printf '<!-- Rendered from core/global-rules.md by scripts/setup.sh. Edits inside this\n'
  printf '     block are overwritten on the next `setup.sh apply`; change the canonical\n'
  printf '     file instead. Anything OUTSIDE the markers is yours and is preserved. -->\n\n'
  rules_body
  rules_platform_notes "$key" "$display"
  printf '\n%s\n' "$SETUP_MD_CLOSE"
}

# The awk marker variables are `mopen`/`mclose`, not `open`/`close`: `close` is an
# awk BUILTIN and using it as a variable is a syntax error — one that only fires on
# the replace path, i.e. on the second run, which is exactly the run idempotence
# depends on.
#
# rules_md_render <existing-file> <display> <registry-key>
#   marker present  -> replace the block in place, everything else untouched
#   marker absent   -> append the block after the user's content
#   file absent     -> the block alone
# The two write paths converge: appending produces a file whose next render takes
# the replace path and yields identical bytes. That is what makes the engine's
# `old == new` check report "already up to date" on the second run.
rules_md_render() {
  local existing="$1" display="$2" key="$3" blockf
  blockf="$(mktemp)"
  rules_md_block "$display" "$key" > "$blockf"
  if [ -f "$existing" ] && grep -qF "$SETUP_MD_OPEN" "$existing" 2>/dev/null; then
    awk -v mopen="$SETUP_MD_OPEN" -v mclose="$SETUP_MD_CLOSE" -v bf="$blockf" '
      $0 == mopen { inblock = 1; while ((getline line < bf) > 0) print line; close(bf); next }
      $0 == mclose { inblock = 0; next }
      inblock { next }
      { print }
    ' "$existing"
  elif [ -f "$existing" ] && [ -s "$existing" ]; then
    cat "$existing"
    printf '\n'
    cat "$blockf"
  else
    cat "$blockf"
  fi
  rm -f "$blockf"
}

# rules_md_unrender <existing-file> — strip our block and the blank line the
# append introduced. A file that held nothing but our block is reported for
# deletion via the engine's sentinel rather than left behind empty.
rules_md_unrender() {
  local existing="$1" out
  [ -f "$existing" ] || return 0
  if ! grep -qF "$SETUP_MD_OPEN" "$existing" 2>/dev/null; then cat "$existing"; return 0; fi
  out="$(awk -v mopen="$SETUP_MD_OPEN" -v mclose="$SETUP_MD_CLOSE" '
      $0 == mopen { inblock = 1; next }
      $0 == mclose { inblock = 0; next }
      inblock { next }
      { print }
    ' "$existing" | awk '{ lines[NR] = $0 } END {
      last = NR
      while (last > 0 && lines[last] ~ /^[[:space:]]*$/) last--
      for (i = 1; i <= last; i++) print lines[i]
    }')"
  if [ -z "$out" ]; then printf '%s' "$SETUP_DELETE_SENTINEL"; else printf '%s\n' "$out"; fi
}

rules_md_summary() {
  local existing="$1"
  if [ -f "$existing" ] && grep -qF "$SETUP_MD_OPEN" "$existing" 2>/dev/null; then
    printf 'refreshes the managed block; your own text is untouched'
  elif [ -f "$existing" ]; then
    printf 'appends a managed block; your existing content is kept above it'
  else
    printf 'new file — fill in the <PLACEHOLDER> values'
  fi
}

# rules_md_destructive — never. The block is delimited, so nothing a user wrote
# outside it can be lost, and the whole-file overwrite prompt would be a lie.
rules_md_destructive() { printf 'no'; }

# --- TOML ------------------------------------------------------------------
# rules_toml_render <existing-file> <block-body-fn>
# Same marker discipline, `#` comments instead of HTML ones. Appending is at EOF,
# which is safe ONLY because every line we write is a comment: under TOML v1.0.0
# a bare `key = value` at the end of a file binds to the last `[table]` header,
# not to the document root. See scripts/lib/setup-codex.sh for why that rules out
# writing real settings from here.
rules_toml_render() {
  local existing="$1" bodyfn="$2" blockf
  blockf="$(mktemp)"
  { printf '%s\n' "$SETUP_TOML_OPEN"; "$bodyfn"; printf '%s\n' "$SETUP_TOML_CLOSE"; } > "$blockf"
  if [ -f "$existing" ] && grep -qF "$SETUP_TOML_OPEN" "$existing" 2>/dev/null; then
    awk -v mopen="$SETUP_TOML_OPEN" -v mclose="$SETUP_TOML_CLOSE" -v bf="$blockf" '
      $0 == mopen { inblock = 1; while ((getline line < bf) > 0) print line; close(bf); next }
      $0 == mclose { inblock = 0; next }
      inblock { next }
      { print }
    ' "$existing"
  elif [ -f "$existing" ] && [ -s "$existing" ]; then
    cat "$existing"
    printf '\n'
    cat "$blockf"
  else
    cat "$blockf"
  fi
  rm -f "$blockf"
}

rules_toml_unrender() {
  local existing="$1" out
  [ -f "$existing" ] || return 0
  if ! grep -qF "$SETUP_TOML_OPEN" "$existing" 2>/dev/null; then cat "$existing"; return 0; fi
  out="$(awk -v mopen="$SETUP_TOML_OPEN" -v mclose="$SETUP_TOML_CLOSE" '
      $0 == mopen { inblock = 1; next }
      $0 == mclose { inblock = 0; next }
      inblock { next }
      { print }
    ' "$existing" | awk '{ lines[NR] = $0 } END {
      last = NR
      while (last > 0 && lines[last] ~ /^[[:space:]]*$/) last--
      for (i = 1; i <= last; i++) print lines[i]
    }')"
  if [ -z "$out" ]; then printf '%s' "$SETUP_DELETE_SENTINEL"; else printf '%s\n' "$out"; fi
}

# --- JSON fragments --------------------------------------------------------
# `_`-prefixed keys are documentation for the next repo reader and must never
# reach a user's config file. Stripped recursively at render time so the
# fragments under platforms/*/templates/ stay self-explaining.
RULES_JQ_STRIPMETA='
def stripmeta:
  if type == "object" then with_entries(select(.key | startswith("_") | not)) | map_values(stripmeta)
  elif type == "array" then map(stripmeta)
  else . end;
'

# rules_json_fragment <file> — the fragment, metadata stripped. `{}` if unusable,
# so a missing template degrades to "nothing to merge" rather than a failed run.
rules_json_fragment() {
  local f="$1"
  if [ -s "$f" ] && jq empty "$f" >/dev/null 2>&1; then
    jq "${RULES_JQ_STRIPMETA} stripmeta" "$f"
  else
    printf '{}\n'
  fi
}

# Array UNION merge — deliberately NOT setup_json_merge.
#
# The engine's shared deepmerge replaces arrays wholesale, which is the right
# policy for ~/.claude/settings.json: platforms/claude/settings.d/permissions-allow.json
# is declared to BE the whole intended allow policy. It is the wrong policy here.
# The files these renderers touch are shared with tools this installer does not
# own — a wholesale array replace on ~/.cursor/cli-config.json deletes cmux's
# `Mcp(cmux:*)` permission, and on a Gemini hooks array it would delete the user's
# hook wiring. Merge-never-clobber is a hard requirement for these four targets,
# so they carry their own semantics rather than depending on an engine policy that
# is free to change for reasons that have nothing to do with them.
RULES_JQ_MERGE_UNION='
def mergeunion($b):
  . as $a
  | reduce ($b | keys_unsorted[]) as $k ($a;
      if ($a[$k] | type) == "object" and ($b[$k] | type) == "object" then
        .[$k] = ($a[$k] | mergeunion($b[$k]))
      elif ($a[$k] | type) == "array" and ($b[$k] | type) == "array" then
        .[$k] = ($a[$k] + ($b[$k] - $a[$k]))
      else
        .[$k] = $b[$k]
      end);
'

# rules_json_render <existing-file> <fragment-file> — deep merge, arrays unioned.
# Third-party wiring in the same file survives untouched.
rules_json_render() {
  local existing="$1" frag
  frag="$(rules_json_fragment "$2")"
  setup_json_read "$existing" \
    | jq --argjson b "$frag" "${RULES_JQ_MERGE_UNION} mergeunion(\$b)" \
    | setup_json_normalize
}

# The precise inverse: remove only the array entries and scalar values that are
# still exactly what we wrote. A value the user has since changed is theirs and
# stays. Emptied containers we created are dropped so `remove` does not leave
# `"permissions": {}` behind.
RULES_JQ_UNMERGE='
def unmerge($b):
  reduce ($b | keys_unsorted[]) as $k (.;
    if (has($k) | not) then .
    elif (.[$k] | type) == "object" and ($b[$k] | type) == "object" then
      .[$k] = (.[$k] | unmerge($b[$k]))
      | (if (.[$k] | length) == 0 then del(.[$k]) else . end)
    elif (.[$k] | type) == "array" and ($b[$k] | type) == "array" then
      .[$k] = (.[$k] - $b[$k])
      | (if (.[$k] | length) == 0 then del(.[$k]) else . end)
    elif .[$k] == $b[$k] then del(.[$k])
    else . end);
'

rules_json_unrender() {
  local existing="$1" frag
  [ -f "$existing" ] || return 0
  frag="$(rules_json_fragment "$2")"
  setup_json_read "$existing" \
    | jq --argjson b "$frag" "${RULES_JQ_UNMERGE} unmerge(\$b)" \
    | setup_json_normalize
}

rules_json_summary() {
  local existing="$1" fragfile="$2" new="$3" frag added
  frag="$(rules_json_fragment "$fragfile")"
  added="$(jq -n --argjson a "$(setup_json_read "$existing")" --argjson b "$(cat "$new")" \
    '[$b | paths(scalars) | join(".")] - [$a | paths(scalars) | join(".")] | length' 2>/dev/null || printf '?')"
  printf '%s key(s) added by merge, %s asserted, existing entries preserved' \
    "$added" "$(printf '%s' "$frag" | jq '[paths(scalars)] | length')"
}
