#!/usr/bin/env bash
# check-opencode-permission-keys.sh — every key the OpenCode agent generator emits
# must be a real PermissionConfig key.
#
# Usage:
#   bash scripts/check-opencode-permission-keys.sh [repo-root]
#
# WHY THIS EXISTS
#   scripts/build-opencode-agents.sh translates a canonical `tools:` ALLOWLIST into
#   an explicit OpenCode `permission:` map, emitting `deny` for every tool the agent
#   was not granted. That design has one unstated dependency: every emitted key must
#   actually exist. A key that does not is a deny-list line that denies nothing, and
#   it fails silently in the direction that looks safe.
#
#   That is not hypothetical. `write` was emitted for every agent until 2026-09-23
#   and is NOT a PermissionConfig key (file modification is governed by `edit`). No
#   agent was over-permitted in practice, because the read-only agents deny `edit`
#   too — but the guarantee was resting on a line that matched nothing, and no check
#   in this repo could have told you.
#
# WHY THE KEY LIST IS PINNED RATHER THAN FETCHED
#   CI must not depend on network access to https://opencode.ai/config.json, and a
#   silent fetch failure degrading to "pass" would reintroduce exactly the class of
#   bug this guards. The list below is pinned and dated. With network available,
#   --refresh re-reads the published schema and reports drift so the pin can be
#   updated deliberately.
set -euo pipefail

ROOT="${1:-.}"
ROOT="$(cd "$ROOT" && pwd)"
GEN="$ROOT/scripts/build-opencode-agents.sh"
REFRESH=false
for a in "$@"; do [[ "$a" == "--refresh" ]] && REFRESH=true; done

# PermissionConfig keys, https://opencode.ai/config.json, read 2026-09-23.
SCHEMA_KEYS="bash doom_loop edit external_directory glob grep list lsp question read skill task todowrite webfetch websearch"

[[ -f "$GEN" ]] || { echo "ERROR: generator not found at $GEN" >&2; exit 2; }

emitted="$(sed -n 's/^OPENCODE_TOOLS=(\(.*\))$/\1/p' "$GEN")"
[[ -n "$emitted" ]] || { echo "ERROR: could not read OPENCODE_TOOLS from $GEN" >&2; exit 2; }

fail=0
for k in $emitted; do
  case " $SCHEMA_KEYS " in
    *" $k "*) ;;
    *) echo "ERROR: OPENCODE_TOOLS emits '$k', which is not a PermissionConfig key." >&2
       echo "       A non-existent key is a deny-list line that denies nothing." >&2
       fail=1 ;;
  esac
done

if [[ "$REFRESH" == true ]]; then
  if live="$(curl -fsS --max-time 20 https://opencode.ai/config.json 2>/dev/null)"; then
    live_keys="$(printf '%s' "$live" | python3 -c '
import json,sys
d=json.load(sys.stdin)
o=[x for x in d["$defs"]["PermissionConfig"]["anyOf"] if "properties" in x][0]
print(" ".join(sorted(o["properties"].keys())))')"
    if [[ "$live_keys" != "$(echo "$SCHEMA_KEYS" | tr ' ' '\n' | sort | tr '\n' ' ' | sed 's/ $//')" ]]; then
      echo "NOTE: the pinned key list has drifted from the published schema." >&2
      echo "  pinned: $SCHEMA_KEYS" >&2
      echo "  live:   $live_keys" >&2
      echo "  Update SCHEMA_KEYS in this script deliberately, then re-run." >&2
    else
      echo "pinned key list matches the published schema"
    fi
  else
    echo "NOTE: --refresh could not reach the schema; the pinned check above still ran." >&2
  fi
fi

if [[ "$fail" -eq 1 ]]; then exit 1; fi
n=$(printf '%s\n' $emitted | grep -c .)
echo "OpenCode permission keys OK ($n emitted, all present in PermissionConfig)"
