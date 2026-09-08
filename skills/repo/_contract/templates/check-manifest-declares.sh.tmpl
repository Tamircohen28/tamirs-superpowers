#!/usr/bin/env bash
# check-manifest-declares.sh — assert a plugin manifest really declares a capability,
# and that everything it points at exists.
#
# Usage:
#   check-manifest-declares.sh <manifest.json> <key> [<key>...]
#   check-manifest-declares.sh --or-discovers <dir> <manifest.json> <key>
#   check-manifest-declares.sh --root <dir> <manifest.json> <key> [<key>...]
#   check-manifest-declares.sh --self-test
#   check-manifest-declares.sh -h | --help
#
# WHY THIS EXISTS
#   core/capabilities/platforms.json requires a `validation` command for every capability
#   claimed native — the schema demands one so the claim is evidence rather than
#   assertion. Nine of those commands were `jq empty <manifest>`, which proves the file is
#   syntactically valid JSON and nothing whatever about the capability: delete every skill
#   directory, drop the `skills` key entirely, and `jq empty` still exits 0. A validation
#   that cannot tell "the capability is here" from "the file is a file" turns the claim
#   back into an assertion while looking rigorous. Same family as the `jq -e '.mcp // {}'`
#   row check-capability-registry.sh already rejects, one step further out: there the
#   command could not fail, here it can only fail for a reason unrelated to the claim.
#
# WHAT IT ASSERTS, per key
#   1. the manifest exists and parses as JSON;
#   2. the key is present and not null — a capability the manifest never mentions is not
#      delivered by that manifest, whatever the registry says;
#   3. the value is non-empty. An empty array, empty object or empty string declares
#      nothing, and `jq -e '.skills'` would pass on all three;
#   4. every repo path the value names exists. Manifest paths are plugin-root relative and
#      this repo's plugin root is the repo root, so they resolve against --root (default
#      $PWD, where the registry's other validation commands already run).
#      `${CLAUDE_PLUGIN_ROOT}/x` is that same path spelled for a runtime that has already
#      installed the plugin, so the prefix is stripped before resolving.
#
# --or-discovers <dir>
#   Some hosts fall back to a conventional folder when the manifest stays silent about a
#   component. Cursor: "When the manifest does not specify explicit paths for a component
#   type, the parser uses automatic folder-based discovery" — and, conversely, "If a
#   manifest field IS specified ... it REPLACES folder discovery for that component. The
#   default folder is not also scanned."
#   (https://cursor.com/docs/reference/plugins)
#
#   So the component is delivered by exactly one of two routes, and which one is in force
#   is decided by the manifest. This mode checks whichever route actually applies:
#     key present  -> the normal declared-paths check above;
#     key absent   -> <dir> must exist and be non-empty, and the run says so.
#   `test -d agents` alone cannot do this. It passes just as happily after someone adds
#   `"agents": "./somewhere-else"` to the manifest — the edit that switches off discovery
#   and makes the directory it is testing irrelevant. The failure this catches is a
#   capability that silently stops being delivered while its evidence stays green.
#
# WHAT IT DOES NOT ASSERT
#   That the host actually honours the key. No command run in this repo can prove what
#   Codex or Cursor does with a manifest field; that is what the row's `since` and
#   doc_urls are for. This proves the repo's half: the declaration is present, non-empty,
#   and its referents exist. A row whose manifest carries no such key at all cannot be
#   rescued by a cleverer command here — it needs a different status.
#
# Exit 0 if every key checks out; 1 on any failure; 2 on a usage error.
set -euo pipefail

usage() { sed -n '2,10p' "$0" | sed -E 's/^# ?//'; exit "${1:-0}"; }

ROOT="$PWD"
SELF_TEST=false
DISCOVERS=""
args=()
while [ $# -gt 0 ]; do
  case "$1" in
    -h|--help)       usage 0 ;;
    --self-test)     SELF_TEST=true; shift ;;
    --root)          ROOT="${2:?--root needs a directory}"; shift 2 ;;
    --or-discovers)  DISCOVERS="${2:?--or-discovers needs a directory}"; shift 2 ;;
    -*)              echo "Unknown flag: $1" >&2; usage 2 ;;
    *)               args+=("$1"); shift ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required by ${0##*/}" >&2; exit 2; }

# --- the check ----------------------------------------------------------------------
# Prints one line per key and returns 1 on any failure. Every message names the manifest
# and the key, because these run as registry validation commands and the operator reading
# the failure has only that line for context.
declares() {
  local root="$1" manifest="$2"; shift 2
  local rc=0 keys_examined=0 paths_examined=0
  local file="$manifest"
  case "$file" in /*) ;; *) file="$root/$manifest" ;; esac

  if [ ! -f "$file" ]; then
    echo "FAIL $manifest: no such file (looked under $root)" >&2
    return 1
  fi
  if ! jq empty "$file" 2>/dev/null; then
    echo "FAIL $manifest: not valid JSON" >&2
    return 1
  fi

  local key type len
  for key in "$@"; do
    keys_examined=$(( keys_examined + 1 ))

    type="$(jq -r --arg k "$key" 'if has($k) then (.[$k] | type) else "absent" end' "$file")"
    case "$type" in
      absent)
        echo "FAIL $manifest: declares no '$key' — the capability claimed on this row is not in this manifest" >&2
        rc=1; continue ;;
      "null")
        echo "FAIL $manifest: '$key' is null" >&2
        rc=1; continue ;;
    esac

    # Non-empty, measured the way each type can be empty. `jq -e '.k'` passes on [] and
    # {} and "" — all three are a declaration of nothing.
    len="$(jq -r --arg k "$key" '.[$k] | if type == "array" or type == "object" or type == "string" then length else 1 end' "$file")"
    if [ "$len" -eq 0 ]; then
      echo "FAIL $manifest: '$key' is an empty $type — declares nothing" >&2
      rc=1; continue
    fi

    # Every repo path reachable from the value, at any depth: array of skill dirs, a bare
    # string path, or an mcpServers object whose args name a script. Only strings that are
    # written as paths are treated as paths; a description or a licence id is not one.
    local p resolved found=0
    while IFS= read -r p; do
      [ -n "$p" ] || continue
      found=$(( found + 1 ))
      paths_examined=$(( paths_examined + 1 ))
      resolved="${p#\$\{CLAUDE_PLUGIN_ROOT\}/}"
      resolved="${resolved#./}"
      if [ ! -e "$root/$resolved" ]; then
        echo "FAIL $manifest: '$key' names '$p', which does not exist in this tree" >&2
        rc=1
      fi
    done < <(jq -r --arg k "$key" '
      [ .[$k] | .. | strings | select(test("^(\\./|\\$\\{CLAUDE_PLUGIN_ROOT\\}/)")) ] | .[]' "$file")

    # `len` is an element count for a container and a character count for a string;
    # reporting "11 entries" for the 11-character path "./.mcp.json" would be a number
    # that looks like evidence and measures something else.
    local size
    case "$type" in
      array|object) size="$len entr$( [ "$len" = 1 ] && echo y || echo ies )" ;;
      *)            size="non-empty $type" ;;
    esac
    printf 'ok:    %s declares %s (%s, %s path%s checked)\n' \
      "$manifest" "$key" "$size" "$found" "$( [ "$found" = 1 ] && echo '' || echo s )"
  done

  # Cardinality. A run that examined nothing must not report success: that is the whole
  # defect this script replaces, and it would be absurd to reintroduce it here.
  if [ "$keys_examined" -eq 0 ]; then
    echo "FAIL $manifest: no keys were examined — a check that looked at nothing is not a pass" >&2
    return 1
  fi
  return "$rc"
}

# --- the check, discovery-aware variant -----------------------------------------------
# Exactly one route delivers the component, and the manifest decides which. Check the one
# that is actually in force; never both, and never the wrong one.
discovers() {
  local root="$1" manifest="$2" key="$3" dir="$4"
  local file="$manifest"
  case "$file" in /*) ;; *) file="$root/$manifest" ;; esac

  if [ ! -f "$file" ]; then
    echo "FAIL $manifest: no such file (looked under $root)" >&2
    return 1
  fi
  if ! jq empty "$file" 2>/dev/null; then
    echo "FAIL $manifest: not valid JSON" >&2
    return 1
  fi

  if jq -e --arg k "$key" 'has($k)' "$file" >/dev/null 2>&1; then
    echo "note:  $manifest specifies '$key', so folder discovery of '$dir' is switched off — checking the declared paths instead"
    declares "$root" "$manifest" "$key"
    return $?
  fi

  # Discovery route. The count is the point: a directory that exists and holds nothing
  # delivers nothing, and is the state a green `test -d` is least able to distinguish.
  local target="$root/$dir" n
  if [ ! -d "$target" ]; then
    echo "FAIL $manifest omits '$key', so the host falls back to '$dir/' — which does not exist, so nothing is delivered" >&2
    return 1
  fi
  n="$(find "$target" -maxdepth 2 -type f ! -name '.*' 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$n" -eq 0 ]; then
    echo "FAIL $manifest omits '$key', so the host falls back to '$dir/' — which is empty, so nothing is delivered" >&2
    return 1
  fi
  printf "ok:    %s omits '%s', so '%s/' is discovered — %s file%s present\n" \
    "$manifest" "$key" "$dir" "$n" "$( [ "$n" = 1 ] && echo '' || echo s )"
  return 0
}

# --- self-test ----------------------------------------------------------------------
# Fixtures encode what the author thought of; the live manifests below encode what the
# repo actually ships. Both run, and the live half pins the path counts so a manifest
# quietly losing entries fails here rather than passing with fewer.
self_test() {
  local rc=0 tmp
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' RETURN

  mkdir -p "$tmp/skills/a" "$tmp/skills/b" "$tmp/scripts"
  : > "$tmp/scripts/srv.sh"
  : > "$tmp/.mcp.json"

  cat > "$tmp/good.json" <<'JSON'
{ "skills": ["./skills/a", "./skills/b"], "mcpServers": "./.mcp.json",
  "license": "MIT", "empty_arr": [], "empty_obj": {}, "empty_str": "",
  "nulled": null, "missing_path": ["./skills/a", "./skills/nope"],
  "nested": { "github": { "args": ["${CLAUDE_PLUGIN_ROOT}/scripts/srv.sh"] } },
  "nested_bad": { "github": { "args": ["${CLAUDE_PLUGIN_ROOT}/scripts/gone.sh"] } } }
JSON
  printf 'not json' > "$tmp/broken.json"

  # expect <code> <label> -- <command...>
  # An exact code, never `if cmd; then`: 1 is a finding and 2 is a usage error or a
  # syntax error, and a test that accepts "any non-zero" cannot tell them apart.
  expect() {
    local want="$1" label="$2"; shift 3
    local got=0
    "$@" >/dev/null 2>&1 || got=$?
    if [ "$got" != "$want" ]; then
      echo "  self-test: $label — expected exit $want, got $got" >&2
      rc=1
    fi
  }

  expect 0 "two existing skill dirs pass"        -- declares "$tmp" good.json skills
  expect 0 "a string path that exists passes"    -- declares "$tmp" good.json mcpServers
  expect 0 "a non-path string value passes"      -- declares "$tmp" good.json license
  expect 0 "nested \${CLAUDE_PLUGIN_ROOT} path"  -- declares "$tmp" good.json nested
  expect 1 "an absent key fails"                 -- declares "$tmp" good.json subagents
  expect 1 "a null value fails"                  -- declares "$tmp" good.json nulled
  expect 1 "an empty array fails"                -- declares "$tmp" good.json empty_arr
  expect 1 "an empty object fails"               -- declares "$tmp" good.json empty_obj
  expect 1 "an empty string fails"               -- declares "$tmp" good.json empty_str
  expect 1 "a path that does not exist fails"    -- declares "$tmp" good.json missing_path
  expect 1 "a nested missing path fails"         -- declares "$tmp" good.json nested_bad
  expect 1 "a non-JSON manifest fails"           -- declares "$tmp" broken.json skills
  expect 1 "a missing manifest fails"            -- declares "$tmp" absent.json skills
  expect 1 "zero keys is not a pass"             -- declares "$tmp" good.json

  # One failing key among passing ones must still fail the run — the `for` loop's exit
  # status is the last iteration's, which is exactly how a middle failure goes missing.
  expect 1 "a failure in a middle key still fails" -- declares "$tmp" good.json skills nulled license

  # --or-discovers: both routes, and the switch between them.
  mkdir -p "$tmp/agents" "$tmp/emptydir"
  : > "$tmp/agents/role.md"
  cat > "$tmp/silent.json" <<'JSON'
{ "skills": ["./skills/a"] }
JSON
  cat > "$tmp/overrides.json" <<'JSON'
{ "skills": ["./skills/a"], "agents": ["./skills/b"], "elsewhere": ["./nope"] }
JSON
  expect 0 "discovery route: absent key, populated dir" \
    -- discovers "$tmp" silent.json agents agents
  expect 1 "discovery route: absent key, empty dir"     \
    -- discovers "$tmp" silent.json agents emptydir
  expect 1 "discovery route: absent key, missing dir"   \
    -- discovers "$tmp" silent.json agents no-such-dir
  # The case a bare `test -d agents` cannot see: the manifest names the component, so the
  # conventional folder is no longer scanned and its contents are irrelevant. The check
  # must follow the manifest, and must fail when what the manifest names is missing.
  expect 0 "override route: declared path exists"       \
    -- discovers "$tmp" overrides.json agents agents
  expect 1 "override route: declared path missing"      \
    -- discovers "$tmp" overrides.json elsewhere agents

  # The live manifests, with their path counts pinned. `declares` prints one ok: line per
  # key naming the count; grep for the exact number so a manifest losing four of its seven
  # skill entries is a failure here and not a quieter pass.
  local out
  local repo="${SELF_TEST_ROOT:-$PWD}"
  check_live() { # <manifest> <key> <expected paths>
    local m="$1" k="$2" want="$3"
    if ! out="$(declares "$repo" "$m" "$k" 2>&1)"; then
      echo "  self-test: live $m/$k failed: $out" >&2; rc=1; return
    fi
    case "$out" in
      *"$want path"*) ;;
      *) echo "  self-test: live $m/$k checked the wrong number of paths (wanted $want): $out" >&2; rc=1 ;;
    esac
  }
  check_live .codex-plugin/plugin.json  skills      7
  check_live .cursor-plugin/plugin.json skills      7
  check_live .codex-plugin/plugin.json  mcpServers  1
  check_live .cursor-plugin/plugin.json mcpServers  1
  check_live .codex-plugin/plugin.json  hooks       1
  check_live .mcp.json                  mcpServers  1

  if [ "$rc" -eq 0 ]; then
    echo "ok:    self-test passed (20 fixture cases, 6 live manifest rows)"
  else
    echo "Manifest-declares self-test FAILED." >&2
  fi
  return "$rc"
}

if [ "$SELF_TEST" = true ]; then
  self_test
  exit $?
fi

if [ -n "$DISCOVERS" ]; then
  [ "${#args[@]}" -eq 2 ] || { echo "ERROR: --or-discovers takes exactly one manifest and one key" >&2; usage 2; }
  discovers "$ROOT" "${args[0]}" "${args[1]}" "$DISCOVERS"
  exit $?
fi

[ "${#args[@]}" -ge 2 ] || usage 2
declares "$ROOT" "${args[@]}"
