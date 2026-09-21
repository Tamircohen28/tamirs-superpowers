#!/usr/bin/env bash
# Fire on any Write/Edit targeting a SKILL.md — inject a hard reminder to use /skill-creator.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/hook-output.sh
source "${SCRIPT_DIR}/lib/hook-output.sh"
# shellcheck source=lib/platform-tools.sh
source "${SCRIPT_DIR}/lib/platform-tools.sh"

INPUT="$(hook_read_stdin)"
hook_detect_platform "$INPUT"

# Both extraction routes below only make sense for a tool that actually
# writes/edits a file. Previously the flat file_path/path read ran
# unconditionally and relied entirely on the hooks.json matcher having
# already restricted invocation to Edit|Write|MultiEdit|NotebookEdit|
# StrReplace — fine on a host that enforces that matcher, but this hook is
# also invoked directly/without matcher filtering on at least one platform
# (see the apply_patch fallback below), where a non-edit tool whose payload
# happens to carry a file_path/path key (e.g. Read, Grep) could otherwise
# false-positive on a SKILL.md path it was only reading. Gate on the
# normalized tool name once, up front, so both routes agree on scope.
raw_tool_name="$(echo "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)"
canonical_tool_name="$(normalize_tool_name "$raw_tool_name")"

FILE=""
case "$canonical_tool_name" in
  Edit|Write|MultiEdit|NotebookEdit|StrReplace)
    FILE=$(echo "$INPUT" | python3 -c "
import sys, json
try:
    d = json.load(sys.stdin)
    ti = d.get('tool_input', {}) or {}
    print(ti.get('file_path', '') or ti.get('path', '') or '')
except Exception:
    print('')
" 2>/dev/null)

    # Codex's apply_patch (and any future platform tool with no flat
    # file_path/path key) carries its target inside a patch body instead of
    # a tool_input key the extraction above reads — so FILE comes back
    # empty even though the write is real. Fall back to write-targets.py's
    # own apply_patch parser rather than re-deriving the "*** Update File:"
    # marker format a second time here.
    if [[ -z "$FILE" ]]; then
      while IFS=$'\t' read -r kind detail _fragment; do
        case "$kind" in
          TARGET|DELETE)
            if [[ "$detail" == *"/SKILL.md" ]] || [[ "$detail" == "SKILL.md" ]]; then
              FILE="$detail"
              break
            fi
            ;;
        esac
      done < <(printf '%s' "$INPUT" | python3 "${SCRIPT_DIR}/lib/write-targets.py" 2>/dev/null)
    fi
    ;;
esac

if [[ "$FILE" == *"/SKILL.md" ]] || [[ "$FILE" == "SKILL.md" ]]; then
  hook_additional_context "$(cat <<'EOF'
SKILL QUALITY GATE — action required before proceeding:
You are about to write/edit a SKILL.md file directly. This is ONLY acceptable if you are already executing INSIDE the skill-creator skill. Otherwise you MUST stop and invoke /skill-creator (Skill tool, skill="tamirs-superpowers:skill-creator") with the skill requirements. Hand-crafted SKILL.md files miss evals, reference docs, scripts, and the quality bar that skill-creator enforces. Do not proceed with this Write/Edit — delegate to /skill-creator.
EOF
)"
fi

hook_allow
