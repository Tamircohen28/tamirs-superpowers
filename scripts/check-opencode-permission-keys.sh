#!/usr/bin/env bash
# check-opencode-permission-keys.sh — every permission ACTION the OpenCode agent
# generator emits must be a real OpenCode 2 Core action; anything else is rejected.
#
# Usage:
#   bash scripts/check-opencode-permission-keys.sh [repo-root] [--refresh]
#
# WHY THIS EXISTS
#   scripts/build-opencode-agents.sh translates a canonical `tools:` ALLOWLIST into
#   an explicit OpenCode 2 `permissions:` ruleset, emitting `deny` for every action
#   the agent was not granted. That design has one unstated dependency: every
#   emitted action must actually exist. A rule naming an action that does not is a
#   deny rule that denies nothing, and it fails silently in the direction that
#   looks safe.
#
#   That is not hypothetical. `write` was emitted for every agent until 2026-09-23
#   and was never a permission key (file modification is governed by `edit`). And
#   `bash`/`task`/`doom_loop`/`lsp` are not OpenCode 2 Core actions (`shell` and
#   `subagent` are the names). OpenCode auto-translates the legacy map, so a wrong
#   name breaks nothing visibly — which is precisely the failure shape this guards.
#
# WHY THE ACTION LIST IS PINNED RATHER THAN FETCHED
#   The published schema (https://opencode.ai/config.json) does NOT enumerate
#   actions: `$defs.Permission.Rule.action` is a free string, because "plugins may
#   define more". The only authority is the prose table on
#   https://opencode.ai/v2/docs/permissions/ ("Built-in tools currently use these
#   actions"). CI must not depend on network access to either, and a silent fetch
#   failure degrading to "pass" would reintroduce exactly the class of bug this
#   guards. The list below is pinned and dated. With network available, --refresh
#   re-reads both the schema and the docs page and reports drift so the pin can be
#   updated deliberately.
set -euo pipefail

ROOT="."
REFRESH=false
for a in "$@"; do
  case "$a" in
    --refresh) REFRESH=true ;;
    -*) echo "unknown flag: $a" >&2; exit 2 ;;
    *) ROOT="$a" ;;
  esac
done
ROOT="$(cd "$ROOT" && pwd)"
GEN="$ROOT/scripts/build-opencode-agents.sh"
DEST="$ROOT/.opencode/agents"

# OpenCode 2 Core permission actions, https://opencode.ai/v2/docs/permissions/,
# read 2026-10-17 (docs current for @opencode/cli 2.0.32). The MCP family
# (`<server>_<tool>`, `opencode_list_mcp_resources`, `opencode_read_mcp_resource`)
# is excluded: those are per-server names, not a fixed vocabulary.
V2_ACTIONS="read edit glob grep shell subagent skill question webfetch websearch external_directory execute"

# Names that are not Core actions (legacy `permission` map keys, or never real).
# Any of these in generator output is a regression.
FORBIDDEN="bash task doom_loop lsp list todowrite write"

[[ -f "$GEN" ]] || { echo "ERROR: generator not found at $GEN" >&2; exit 2; }

emitted="$(sed -n 's/^OPENCODE_ACTIONS=(\(.*\))$/\1/p' "$GEN")"
[[ -n "$emitted" ]] || { echo "ERROR: could not read OPENCODE_ACTIONS from $GEN" >&2; exit 2; }

in_list() { case " $2 " in *" $1 "*) return 0 ;; *) return 1 ;; esac; }

fail=0
for k in $emitted; do
  if in_list "$k" "$FORBIDDEN"; then
    echo "ERROR: OPENCODE_ACTIONS emits '$k', not a Core action. The names are shell/subagent; doom_loop, lsp, list, todowrite and write do not exist." >&2
    fail=1
  elif ! in_list "$k" "$V2_ACTIONS"; then
    echo "ERROR: OPENCODE_ACTIONS emits '$k', which is not an OpenCode 2 Core permission action." >&2
    echo "       A non-existent action is a deny rule that denies nothing." >&2
    fail=1
  fi
done

# The generated files are the thing OpenCode actually reads, so check them too:
# a hand edit, or a generator path this sed did not see, shows up here.
gen_count=0
if [[ -d "$DEST" ]]; then
  for f in "$DEST"/*.md; do
    [[ -e "$f" ]] || continue
    gen_count=$((gen_count + 1))
    if awk 'NR==1&&/^---/{fm=1;next} fm&&/^---/{exit} fm&&/^permission:/{found=1} END{exit !found}' "$f"; then
      echo "ERROR: $(basename "$f") carries the deprecated 'permission:' map; output must be a 'permissions:' ruleset." >&2
      fail=1
    fi
    while IFS= read -r act; do
      [[ -n "$act" ]] || continue
      if in_list "$act" "$FORBIDDEN"; then
        echo "ERROR: $(basename "$f") has a rule for '$act', a non-Core action." >&2; fail=1
      elif ! in_list "$act" "$V2_ACTIONS"; then
        echo "ERROR: $(basename "$f") has a rule for '$act', which is not an OpenCode 2 Core action." >&2; fail=1
      fi
    done < <(awk 'NR==1&&/^---/{fm=1;next} fm&&/^---/{exit} fm&&/^  - action:[[:space:]]*/{sub(/^  - action:[[:space:]]*/,"");print}' "$f")
  done
fi
if [[ -d "$ROOT/.opencode/agent" ]] && compgen -G "$ROOT/.opencode/agent/*.md" >/dev/null; then
  echo "ERROR: .opencode/agent/ (singular, an older release's output dir) still holds agents; OpenCode 2 reads both dirs and would load them twice." >&2
  fail=1
fi

if [[ "$REFRESH" == true ]]; then
  if live="$(curl -fsS --max-time 20 https://opencode.ai/config.json 2>/dev/null)"; then
    schema_note="$(printf '%s' "$live" | python3 -I -c '
import json,sys
d=json.load(sys.stdin); defs=d["$defs"]
rule=defs.get("Permission.Rule")
if not rule:
    print("DRIFT: $defs.Permission.Rule is gone from the published schema"); sys.exit(0)
req=sorted(rule.get("required",[]))
if req!=["action","effect","resource"]:
    print("DRIFT: Permission.Rule required fields are now %s" % req)
enum=rule["properties"].get("action",{}).get("enum")
if enum:
    print("ENUM " + " ".join(sorted(enum)))
eff=defs.get("Permission.Effect",{}).get("enum")
if sorted(eff or [])!=["allow","ask","deny"]:
    print("DRIFT: Permission.Effect enum is now %s" % eff)
if not d["properties"].get("permission",{}).get("deprecated"):
    print("NOTE: top-level legacy `permission` is no longer marked deprecated")
')"
    if [[ -z "$schema_note" ]]; then
      echo "published schema still defines Permission.Rule {action: string, resource, effect: allow|deny|ask} — action stays unenumerated, pin remains the authority"
    else
      while IFS= read -r line; do
        case "$line" in
          "ENUM "*)
            live_actions="${line#ENUM }"
            pinned_sorted="$(printf '%s\n' $V2_ACTIONS | sort | tr '\n' ' ' | sed 's/ $//')"
            if [[ "$live_actions" != "$pinned_sorted" ]]; then
              echo "NOTE: the schema now ENUMERATES Permission.Rule.action and it differs from the pin." >&2
              echo "  pinned: $pinned_sorted" >&2
              echo "  live:   $live_actions" >&2
              echo "  Update V2_ACTIONS in this script (and OPENCODE_ACTIONS in the generator) deliberately." >&2
            else
              echo "published schema now enumerates actions; it matches the pin"
            fi ;;
          *) echo "NOTE: $line" >&2 ;;
        esac
      done <<< "$schema_note"
    fi
  else
    echo "NOTE: --refresh could not reach https://opencode.ai/config.json; the pinned check above still ran." >&2
  fi

  # The docs table is the only enumeration that exists. A plain substring check is
  # deliberately crude: it says "this action is still mentioned", nothing more.
  if page="$(curl -fsSL --max-time 20 https://opencode.ai/v2/docs/permissions/ 2>/dev/null)"; then
    missing=""
    for k in $V2_ACTIONS; do
      printf '%s' "$page" | grep -q "$k" || missing="$missing $k"
    done
    if [[ -n "$missing" ]]; then
      echo "NOTE: the V2 permissions docs page no longer mentions:$missing — re-read https://opencode.ai/v2/docs/permissions/ and update the pin deliberately." >&2
    else
      echo "every pinned action is still named on https://opencode.ai/v2/docs/permissions/"
    fi
    if ! printf '%s' "$page" | grep -q 'doom_loop'; then
      echo "NOTE: the docs page no longer mentions doom_loop at all; the 'not current V2 Core actions' sentence this pin relies on may have moved." >&2
    fi
  else
    echo "NOTE: --refresh could not reach the V2 permissions docs page." >&2
  fi
fi

if [[ "$fail" -eq 1 ]]; then exit 1; fi
n=$(printf '%s\n' $emitted | grep -c .)
echo "OpenCode permission actions OK ($n emitted by the generator, $gen_count generated agent(s) scanned, all OpenCode 2 Core actions)"
