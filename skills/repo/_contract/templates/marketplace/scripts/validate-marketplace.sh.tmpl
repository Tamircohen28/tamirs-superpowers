#!/usr/bin/env bash
# validate-marketplace.sh — validate every plugin-marketplace manifest this repo ships.
#
# Usage:
#   validate-marketplace.sh [repo-root]
#   validate-marketplace.sh -h | --help
#
# One catalog, three spellings. The platforms that have a marketplace each read their own
# manifest (doc-cited 2026-11-05; the per-platform research lives in the plugin that
# scaffolded this repo, docs/engineering/research/marketplace-standards.md):
#
#   Claude Code / Desktop   .claude-plugin/marketplace.json     claude plugin validate <root>
#   Cursor                  .cursor-plugin/marketplace.json     no validator documented — jq checks here
#   Codex                   .agents/plugins/marketplace.json    no validator documented — jq checks here
#   OpenCode                no marketplace concept              nothing to validate; says so below
#
# Checks: JSON syntax, required fields, name rules, source shapes, `..` escapes, that every
# local source directory exists, that a local plugin's own manifest name equals its catalog
# entry name, duplicates within a manifest, and that the three catalogs agree (a plugin in
# the Cursor or Codex catalog but not the Claude one is an error; the reverse is a warning,
# because a Claude-only plugin — hooks, MCP — is a legitimate catalog entry).
# `claude plugin validate` runs on top when the CLI is on PATH; set MARKETPLACE_SKIP_CLI=1
# to skip it (CI runners without Claude Code skip it automatically and say so).
#
# Exit 0 if every check passes; 1 on the first manifest with errors (all errors are listed).
set -euo pipefail

usage() { sed -n '2,24p' "$0" | sed -E 's/^# ?//'; exit "${1:-0}"; }
[[ "${1:-}" == "-h" || "${1:-}" == "--help" ]] && usage 0

ROOT="$(cd "${1:-.}" && pwd)"
FAILED=0
WARNED=0

err()  { echo "ERROR: $*" >&2; FAILED=$(( FAILED + 1 )); }
warn() { echo "WARN:  $*" >&2; WARNED=$(( WARNED + 1 )); }
ok()   { echo "ok:    $*"; }

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required by validate-marketplace.sh" >&2; exit 1; }

CLAUDE_MANIFEST="$ROOT/.claude-plugin/marketplace.json"
CURSOR_MANIFEST="$ROOT/.cursor-plugin/marketplace.json"
CODEX_MANIFEST="$ROOT/.agents/plugins/marketplace.json"

# parse_or_fail <file> <label> — JSON syntax gate; a manifest that does not parse gets one
# error and no further checks, so the list stays about the manifest and not the parser.
parse_or_fail() {
  local f="$1" label="$2"
  if [[ ! -f "$f" ]]; then err "$label: missing ${f#"$ROOT"/}"; return 1; fi
  if ! jq empty "$f" 2>/dev/null; then err "$label: ${f#"$ROOT"/} is not valid JSON"; return 1; fi
  return 0
}

# Every local path a manifest supplies — an entry's source, and the metadata.pluginRoot
# prefix that is joined in front of it — goes through the same two gates. The textual rule
# is the platforms' own ("relative, no '..', forward slashes"); the real-path rule is what
# makes it hold: a prefix joined after the entry was checked, or a symlink under plugins/,
# can point outside the checkout, and a catalog that validates locally but whose files do
# not accompany a clone is exactly the failure the validator exists to catch.
ROOT_REAL="$(cd "$ROOT" && pwd -P)"

# check_rel_path <label> <path> — the documented textual rule. Calls err() and returns 1.
check_rel_path() {
  local label="$1" p="$2"
  # An empty path would resolve to the marketplace root (or to metadata.pluginRoot itself)
  # and pass every later check while naming no plugin (#375).
  if [[ -z "$p" ]]; then err "$label is empty; name the plugin's directory"; return 1; fi
  if [[ "$p" == /* ]]; then err "$label '$p' is absolute; relative paths only"; return 1; fi
  if [[ "$p" == *\\* ]]; then err "$label '$p' uses backslashes; forward slashes only"; return 1; fi
  if [[ "$p" == *..* ]]; then err "$label '$p' contains '..'"; return 1; fi
  return 0
}

# check_local_dir <label> <path-relative-to-root> [why-it-matters] — exists, and its real
# path is inside the marketplace root. Calls err() and returns 1.
check_local_dir() {
  local label="$1" rel="$2" why="${3:-}" real
  if [[ ! -d "$ROOT/$rel" ]]; then err "$label directory '$rel' does not exist${why:+ ($why)}"; return 1; fi
  real="$(cd "$ROOT/$rel" 2>/dev/null && pwd -P)" || { err "$label directory '$rel' is not readable"; return 1; }
  if [[ "$real" != "$ROOT_REAL" && "$real" != "$ROOT_REAL"/* ]]; then
    err "$label directory '$rel' resolves to '$real', outside the marketplace root — a symlink or prefix escape; those files will not accompany a clone"
    return 1
  fi
  return 0
}

# check_manifest_names <label> <dir-rel> <entry-name> <manifest-rel>... — the plugin's own
# name must equal the catalog entry name in EVERY documented manifest location that exists
# under the plugin directory, because each platform reads a different one and install by
# name resolves whichever its reader finds: Codex reads the root plugin.json (its portable
# entry point) and falls back to .codex-plugin/plugin.json; Cursor reads .cursor-plugin/
# plugin.json (Cursor Plugins) or a root plugin.json (Agent Plugins); Claude Code reads
# .claude-plugin/plugin.json. Checking only one location let a root manifest with a
# different name pass. Calls err() per mismatch; returns 1 when any mismatched.
check_manifest_names() {
  local label="$1" dir="$2" entry="$3" m mname bad=0
  shift 3
  for m in "$@"; do
    [[ -f "$ROOT/$dir/$m" ]] || continue
    mname="$(jq -r '.name // empty' "$ROOT/$dir/$m" 2>/dev/null || true)"
    if [[ "$mname" != "$entry" ]]; then
      err "$label entry '$entry' but $dir/$m says '$mname' — install by name would resolve a different plugin"
      bad=1
    fi
  done
  return $bad
}

# resolve_plugin_root <manifest> <label> — metadata.pluginRoot, validated as a local
# directory BEFORE any entry is resolved under it. Sets PLUGIN_ROOT to "" (none), the
# stripped prefix, or "!" after an err() when the prefix is invalid, so callers skip
# resolution instead of joining it. A global, not a command substitution: err() must
# count in this shell, or an invalid prefix would print and still exit 0.
resolve_plugin_root() {
  local f="$1" label="$2" pr
  PLUGIN_ROOT=""
  pr="$(jq -r '.metadata.pluginRoot // empty' "$f")"
  [[ -n "$pr" ]] || return 0
  if ! check_rel_path "$label metadata.pluginRoot" "$pr" || ! check_local_dir "$label metadata.pluginRoot" "${pr#./}"; then
    PLUGIN_ROOT="!"
    return 0
  fi
  PLUGIN_ROOT="${pr#./}"
}

# duplicates <file> — plugin names that appear more than once.
duplicates() { jq -r '[.plugins[]?.name // empty] | group_by(.) | map(select(length > 1) | .[0]) | .[]' "$1"; }

# --- 1. Claude Code: .claude-plugin/marketplace.json ------------------------------------
# Reference: https://code.claude.com/docs/en/plugins/marketplace-reference (read 2026-11-05).
if parse_or_fail "$CLAUDE_MANIFEST" "claude"; then
  rel="${CLAUDE_MANIFEST#"$ROOT"/}"
  name="$(jq -r '.name // empty' "$CLAUDE_MANIFEST")"
  [[ -n "$name" ]] || err "$rel: top-level 'name' is required"
  if [[ -n "$name" ]] && ! [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ && "$name" != *..* ]]; then
    err "$rel: name '$name' — letters, digits, '.', '_' and '-' only, starting with a letter or digit, no '..' (kebab-case)"
  fi
  jq -e '.owner | type == "object" and (.name | type == "string" and length > 0)' "$CLAUDE_MANIFEST" >/dev/null 2>&1 \
    || err "$rel: 'owner.name' is required"
  jq -e '.plugins | type == "array" and length > 0' "$CLAUDE_MANIFEST" >/dev/null 2>&1 \
    || err "$rel: 'plugins' must be a non-empty array"
  jq -e '(.description // .metadata.description // "") | length > 0' "$CLAUDE_MANIFEST" >/dev/null 2>&1 \
    || warn "$rel: no 'description' — claude plugin validate warns on this too"
  resolve_plugin_root "$CLAUDE_MANIFEST" "$rel:"; plugin_root="$PLUGIN_ROOT"

  while IFS= read -r dup; do err "$rel: duplicate plugin name '$dup'"; done < <(duplicates "$CLAUDE_MANIFEST")

  n="$(jq -r '.plugins | length' "$CLAUDE_MANIFEST")"
  for (( i = 0; i < n; i++ )); do
    pname="$(jq -r --argjson i "$i" '.plugins[$i].name // empty' "$CLAUDE_MANIFEST")"
    [[ -n "$pname" ]] || { err "$rel: plugins[$i] has no 'name'"; continue; }
    [[ "$pname" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] \
      || err "$rel: plugin '$pname' — letters, digits, '.', '_' and '-' only, starting with a letter or digit"
    stype="$(jq -r --argjson i "$i" '.plugins[$i].source | type' "$CLAUDE_MANIFEST")"
    case "$stype" in
      string)
        src="$(jq -r --argjson i "$i" '.plugins[$i].source' "$CLAUDE_MANIFEST")"
        check_rel_path "$rel: plugin '$pname' source" "$src" || continue
        if [[ "$src" == ./* ]]; then
          local_path="${src#./}"
        elif [[ "$plugin_root" == "!" ]]; then
          continue   # pluginRoot already reported; nothing to resolve under it
        elif [[ -n "$plugin_root" ]]; then
          local_path="$plugin_root/$src"
        else
          err "$rel: plugin '$pname' source '$src' must start with './' (or be a bare name under metadata.pluginRoot)"; continue
        fi
        check_local_dir "$rel: plugin '$pname' source" "$local_path" "install would fail with 'Source path does not exist'" || continue
        check_manifest_names "$rel:" "$local_path" "$pname" .claude-plugin/plugin.json || true
        if [[ -f "$ROOT/$local_path/.claude-plugin/plugin.json" ]]; then
          ever="$(jq -r --argjson i "$i" '.plugins[$i].version // empty' "$CLAUDE_MANIFEST")"
          mver="$(jq -r '.version // empty' "$ROOT/$local_path/.claude-plugin/plugin.json" 2>/dev/null || true)"
          if [[ -n "$ever" && -n "$mver" && "$ever" != "$mver" ]]; then
            warn "$rel: entry '$pname' declares version '$ever' but plugin.json says '$mver' — at install time plugin.json wins"
          fi
        fi
        ;;
      object)
        skind="$(jq -r --argjson i "$i" '.plugins[$i].source.source // empty' "$CLAUDE_MANIFEST")"
        case "$skind" in
          github)     jq -e --argjson i "$i" '.plugins[$i].source.repo | type == "string" and test("^[^/]+/[^/]+$")' "$CLAUDE_MANIFEST" >/dev/null 2>&1 || err "$rel: plugin '$pname' github source needs 'repo' as owner/repo" ;;
          url)        jq -e --argjson i "$i" '.plugins[$i].source.url | type == "string" and test("^(https?://|file://|git@)")' "$CLAUDE_MANIFEST" >/dev/null 2>&1 || err "$rel: plugin '$pname' url source needs 'url' (https://, http://, file:// or git@)" ;;
          git-subdir) jq -e --argjson i "$i" '.plugins[$i].source | (.url | type == "string") and (.path | type == "string")' "$CLAUDE_MANIFEST" >/dev/null 2>&1 || err "$rel: plugin '$pname' git-subdir source needs 'url' and 'path'" ;;
          npm)        jq -e --argjson i "$i" '.plugins[$i].source.package | type == "string" and length > 0' "$CLAUDE_MANIFEST" >/dev/null 2>&1 || err "$rel: plugin '$pname' npm source needs 'package'" ;;
          archive)    jq -e --argjson i "$i" '.plugins[$i].source | (.url | type == "string" and startswith("https://")) and (.sha256 | type == "string" and test("^[0-9a-f]{64}$"))' "$CLAUDE_MANIFEST" >/dev/null 2>&1 || err "$rel: plugin '$pname' archive source needs an https 'url' and a 64-hex 'sha256'" ;;
          command)    jq -e --argjson i "$i" '.plugins[$i].source.command | type == "string" and length > 0' "$CLAUDE_MANIFEST" >/dev/null 2>&1 || err "$rel: plugin '$pname' command source needs 'command'" ;;
          *)          err "$rel: plugin '$pname' source.source '$skind' is not one of github, url, git-subdir, npm, archive, command" ;;
        esac
        sha="$(jq -r --argjson i "$i" '.plugins[$i].source.sha // empty' "$CLAUDE_MANIFEST")"
        if [[ -n "$sha" ]] && ! [[ "$sha" =~ ^[0-9a-f]{40}$ ]]; then err "$rel: plugin '$pname' source.sha must be a full 40-char lowercase SHA"; fi
        ;;
      *) err "$rel: plugin '$pname' has no 'source'" ;;
    esac
    hk="$(jq -r --argjson i "$i" '.plugins[$i].hooks | type' "$CLAUDE_MANIFEST")"
    [[ "$hk" == "null" || "$hk" == "object" ]] \
      || err "$rel: plugin '$pname' entry 'hooks' must be an inline object (a file path or array passes validation but never runs)"
  done
  (( FAILED == 0 )) && ok "claude: $rel — $n plugin(s)"
fi

# --- 2. Cursor: .cursor-plugin/marketplace.json ----------------------------------------
# Reference: https://cursor.com/docs/reference/plugins#marketplace-manifest-format (read 2026-11-05).
CURSOR_BEFORE=$FAILED
if parse_or_fail "$CURSOR_MANIFEST" "cursor"; then
  rel="${CURSOR_MANIFEST#"$ROOT"/}"
  size="$(wc -c < "$CURSOR_MANIFEST" | tr -d ' ')"
  (( size <= 10485760 )) || err "$rel: ${size} bytes — Cursor caps the marketplace manifest at 10 MB"
  name="$(jq -r '.name // empty' "$CURSOR_MANIFEST")"
  [[ -n "$name" ]] || err "$rel: top-level 'name' is required"
  if [[ -n "$name" ]] && ! [[ "$name" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]]; then
    err "$rel: name '$name' must be kebab-case (lowercase alphanumerics, hyphens, periods; alphanumeric at both ends)"
  fi
  jq -e '.owner | type == "object" and (.name | type == "string" and length > 0)' "$CURSOR_MANIFEST" >/dev/null 2>&1 \
    || err "$rel: 'owner.name' is required"
  jq -e '.plugins | type == "array" and length > 0' "$CURSOR_MANIFEST" >/dev/null 2>&1 \
    || err "$rel: 'plugins' must be a non-empty array"
  resolve_plugin_root "$CURSOR_MANIFEST" "$rel:"; plugin_root="$PLUGIN_ROOT"
  while IFS= read -r dup; do err "$rel: duplicate plugin name '$dup' (the submission checklist requires unique names)"; done < <(duplicates "$CURSOR_MANIFEST")

  n="$(jq -r '.plugins | length' "$CURSOR_MANIFEST")"
  for (( i = 0; i < n; i++ )); do
    pname="$(jq -r --argjson i "$i" '.plugins[$i].name // empty' "$CURSOR_MANIFEST")"
    [[ -n "$pname" ]] || { err "$rel: plugins[$i] has no 'name'"; continue; }
    [[ "$pname" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?$ ]] || err "$rel: plugin '$pname' must be kebab-case"
    src="$(jq -r --argjson i "$i" '.plugins[$i].source | if type == "object" then (.path // "") else (. // "") end' "$CURSOR_MANIFEST")"
    [[ -n "$src" ]] || { err "$rel: plugin '$pname' needs 'source' (a path, or an object with 'path')"; continue; }
    check_rel_path "$rel: plugin '$pname' source" "$src" || continue
    [[ "$plugin_root" == "!" ]] && continue   # pluginRoot already reported; nothing to resolve under it
    local_path="${src#./}"
    [[ -n "$plugin_root" ]] && local_path="$plugin_root/$local_path"
    check_local_dir "$rel: plugin '$pname' source" "$local_path" || continue
    # Cursor Plugins carry .cursor-plugin/plugin.json; Agent Plugins carry plugin.json at
    # the plugin root. Either is what Cursor merges with the entry, so both must agree.
    check_manifest_names "$rel:" "$local_path" "$pname" .cursor-plugin/plugin.json plugin.json || true
  done
  (( FAILED == CURSOR_BEFORE )) && ok "cursor: $rel — $n plugin(s)"
fi

# --- 3. Codex: .agents/plugins/marketplace.json ----------------------------------------
# Reference: https://developers.openai.com/plugins/build/plugins (read 2026-11-05).
CODEX_BEFORE=$FAILED
if parse_or_fail "$CODEX_MANIFEST" "codex"; then
  rel="${CODEX_MANIFEST#"$ROOT"/}"
  name="$(jq -r '.name // empty' "$CODEX_MANIFEST")"
  [[ -n "$name" ]] || err "$rel: top-level 'name' is required"
  jq -e '.interface.displayName | type == "string" and length > 0' "$CODEX_MANIFEST" >/dev/null 2>&1 \
    || warn "$rel: no 'interface.displayName' — the documented example carries one"
  jq -e '.plugins | type == "array" and length > 0' "$CODEX_MANIFEST" >/dev/null 2>&1 \
    || err "$rel: 'plugins' must be a non-empty array"
  while IFS= read -r dup; do err "$rel: duplicate plugin name '$dup'"; done < <(duplicates "$CODEX_MANIFEST")

  n="$(jq -r '.plugins | length' "$CODEX_MANIFEST")"
  for (( i = 0; i < n; i++ )); do
    pname="$(jq -r --argjson i "$i" '.plugins[$i].name // empty' "$CODEX_MANIFEST")"
    [[ -n "$pname" ]] || { err "$rel: plugins[$i] has no 'name'"; continue; }
    inst="$(jq -r --argjson i "$i" '.plugins[$i].policy.installation // empty' "$CODEX_MANIFEST")"
    case "$inst" in
      AVAILABLE|INSTALLED_BY_DEFAULT|NOT_AVAILABLE) ;;
      "") err "$rel: plugin '$pname' needs 'policy.installation' (AVAILABLE, INSTALLED_BY_DEFAULT or NOT_AVAILABLE)" ;;
      *)  err "$rel: plugin '$pname' policy.installation '$inst' is not AVAILABLE, INSTALLED_BY_DEFAULT or NOT_AVAILABLE" ;;
    esac
    jq -e --argjson i "$i" '.plugins[$i].policy.authentication | type == "string" and length > 0' "$CODEX_MANIFEST" >/dev/null 2>&1 \
      || err "$rel: plugin '$pname' needs 'policy.authentication' (the documented value is ON_INSTALL)"
    jq -e --argjson i "$i" '.plugins[$i].category | type == "string" and length > 0' "$CODEX_MANIFEST" >/dev/null 2>&1 \
      || err "$rel: plugin '$pname' needs 'category'"
    stype="$(jq -r --argjson i "$i" '.plugins[$i].source | type' "$CODEX_MANIFEST")"
    # A local source is either a plain "./path" string or {"source":"local","path":"./path"}.
    # Both forms get the same checks — the directory exists and the plugin's own manifest
    # name equals the entry name — so a mismatch cannot slip through the string spelling.
    codex_local_src=""
    case "$stype" in
      string)
        codex_local_src="$(jq -r --argjson i "$i" '.plugins[$i].source' "$CODEX_MANIFEST")"
        [[ -n "$codex_local_src" ]] || { err "$rel: plugin '$pname' source is an empty string; name the plugin's directory"; continue; }
        ;;
      object)
        skind="$(jq -r --argjson i "$i" '.plugins[$i].source.source // empty' "$CODEX_MANIFEST")"
        case "$skind" in
          local)
            codex_local_src="$(jq -r --argjson i "$i" '.plugins[$i].source.path // empty' "$CODEX_MANIFEST")"
            [[ -n "$codex_local_src" ]] || err "$rel: plugin '$pname' local source needs 'path'"
            ;;
          url)        jq -e --argjson i "$i" '.plugins[$i].source.url | type == "string" and length > 0' "$CODEX_MANIFEST" >/dev/null 2>&1 || err "$rel: plugin '$pname' url source needs 'url'" ;;
          git-subdir) jq -e --argjson i "$i" '.plugins[$i].source | (.url | type == "string") and (.path | type == "string")' "$CODEX_MANIFEST" >/dev/null 2>&1 || err "$rel: plugin '$pname' git-subdir source needs 'url' and 'path'" ;;
          npm)
            jq -e --argjson i "$i" '.plugins[$i].source.package | type == "string" and length > 0' "$CODEX_MANIFEST" >/dev/null 2>&1 || err "$rel: plugin '$pname' npm source needs 'package'"
            reg="$(jq -r --argjson i "$i" '.plugins[$i].source.registry // empty' "$CODEX_MANIFEST")"
            if [[ -n "$reg" ]] && ! [[ "$reg" =~ ^https://[^@?#]*$ ]]; then err "$rel: plugin '$pname' npm registry must be an https URL with no credentials, query or fragment"; fi
            ;;
          *) err "$rel: plugin '$pname' source.source '$skind' is not one of local, url, git-subdir, npm" ;;
        esac
        ;;
      *) err "$rel: plugin '$pname' has no 'source'" ;;
    esac
    if [[ -n "$codex_local_src" ]]; then
      check_rel_path "$rel: plugin '$pname' local source" "$codex_local_src" || continue
      [[ "$codex_local_src" == ./* ]] \
        || { err "$rel: plugin '$pname' local source '$codex_local_src' must start with './' and stay inside the marketplace root"; continue; }
      check_local_dir "$rel: plugin '$pname' source" "${codex_local_src#./}" "Codex would skip the entry" || continue
      # The root plugin.json is Codex's portable entry point; .codex-plugin/plugin.json is
      # the documented compatibility fallback. Whichever exists is what Codex resolves by.
      check_manifest_names "$rel:" "${codex_local_src#./}" "$pname" plugin.json .codex-plugin/plugin.json || true
    fi
  done
  (( FAILED == CODEX_BEFORE )) && ok "codex: $rel — $n plugin(s)"
fi

# --- 4. OpenCode: no marketplace ------------------------------------------------------
# https://opencode.ai/docs/plugins/ (read 2026-11-05) defines plugins as JS/TS modules or
# npm packages named in opencode.json's `plugin` array. There is no catalog manifest to
# write, so there is none to validate. Saying so is the check.
ok "opencode: no marketplace manifest exists for OpenCode (plugins are npm packages named in opencode.json) — nothing to validate"

# --- 5. Cross-catalog agreement --------------------------------------------------------
if [[ -f "$CLAUDE_MANIFEST" && -f "$CURSOR_MANIFEST" && -f "$CODEX_MANIFEST" ]] \
   && jq empty "$CLAUDE_MANIFEST" "$CURSOR_MANIFEST" "$CODEX_MANIFEST" 2>/dev/null; then
  claude_names="$(jq -r '.plugins[]?.name // empty' "$CLAUDE_MANIFEST" | sort -u)"
  for other in "$CURSOR_MANIFEST" "$CODEX_MANIFEST"; do
    orel="${other#"$ROOT"/}"
    while IFS= read -r pn; do
      [[ -n "$pn" ]] || continue
      grep -qxF "$pn" <<<"$claude_names" || err "$orel lists '$pn' but .claude-plugin/marketplace.json does not — the Claude catalog is the canonical list (Codex reads it as a legacy-compatible marketplace too)"
    done < <(jq -r '.plugins[]?.name // empty' "$other" | sort -u)
    while IFS= read -r pn; do
      [[ -n "$pn" ]] || continue
      jq -e --arg n "$pn" '[.plugins[]?.name] | index($n) != null' "$other" >/dev/null 2>&1 \
        || warn "'$pn' is in .claude-plugin/marketplace.json but not in $orel — fine for a Claude-only plugin; otherwise add it"
    done <<<"$claude_names"
  done
fi

# --- 6. claude plugin validate (the platform's own validator, when present) -------------
if [[ "${MARKETPLACE_SKIP_CLI:-0}" == "1" ]]; then
  echo "skip:  claude plugin validate (MARKETPLACE_SKIP_CLI=1)"
elif command -v claude >/dev/null 2>&1; then
  if out="$(claude plugin validate "$ROOT" 2>&1)"; then
    ok "claude plugin validate $ROOT"
  else
    err "claude plugin validate failed:"
    printf '%s\n' "$out" >&2
  fi
else
  echo "skip:  claude plugin validate — the claude CLI is not on PATH (the jq checks above ran; install Claude Code to run the platform validator too)"
fi

if (( FAILED > 0 )); then
  echo "validate-marketplace: FAILED ($FAILED error(s), $WARNED warning(s))" >&2
  exit 1
fi
echo "validate-marketplace: passed ($WARNED warning(s))"
