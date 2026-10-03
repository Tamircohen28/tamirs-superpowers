#!/usr/bin/env bash
# check-agent-drift.sh — verify thin adapters reference AGENTS.md (no policy duplication check).
#
# Usage:
#   check-agent-drift.sh [repo-root]
#   check-agent-drift.sh -h | --help
#
# Exit 0 if checks pass; 1 if drift detected.
set -euo pipefail

usage() { sed -n '2,9p' "$0" | sed 's/^# \?//'; exit "${1:-0}"; }
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage 0; fi

ROOT="${1:-.}"
ROOT="$(cd "$ROOT" && pwd)"
FAILED=0

err() { echo "ERROR: $*" >&2; FAILED=1; }

# AGENTS.md must exist
if [[ ! -f "$ROOT/AGENTS.md" ]]; then
  err "AGENTS.md missing at repo root"
fi

# CLAUDE.md must reference AGENTS.md when present
if [[ -f "$ROOT/CLAUDE.md" ]]; then
  if ! grep -qE '@AGENTS\.md|AGENTS\.md' "$ROOT/CLAUDE.md"; then
    err "CLAUDE.md must reference AGENTS.md (use @AGENTS.md import or explicit pointer)"
  fi
fi

# Primary Cursor rule must reference AGENTS.md
CURSOR_RULES="$ROOT/.cursor/rules"
if [[ -d "$CURSOR_RULES" ]]; then
  FOUND_REF=false
  # Prefer 000-project.mdc; else any always-on rule; else any .mdc
  for candidate in \
    "$CURSOR_RULES/000-project.mdc" \
    $(find "$CURSOR_RULES" -maxdepth 1 -name '*.mdc' 2>/dev/null | head -20); do
    [[ -f "$candidate" ]] || continue
    if grep -qE 'AGENTS\.md' "$candidate" 2>/dev/null; then
      FOUND_REF=true
      break
    fi
  done
  if [[ "$FOUND_REF" == false ]] && [[ -n "$(find "$CURSOR_RULES" -maxdepth 1 -name '*.mdc' 2>/dev/null | head -1)" ]]; then
    err "No .cursor/rules/*.mdc file references AGENTS.md"
  fi
  # .md files in rules dir are ignored by Cursor
  if find "$CURSOR_RULES" -maxdepth 1 -name '*.md' 2>/dev/null | grep -q .; then
    err ".cursor/rules/ contains .md files — Cursor ignores them; rename to .mdc"
  fi
fi

# Warn on too many always-on rules (not a hard fail)
if [[ -d "$CURSOR_RULES" ]]; then
  ALWAYS=0
  while IFS= read -r f; do
    grep -qE '^alwaysApply:\s*true' "$f" 2>/dev/null && ALWAYS=$((ALWAYS + 1)) || true
  done < <(find "$CURSOR_RULES" -maxdepth 1 -name '*.mdc' 2>/dev/null)
  if (( ALWAYS > 2 )); then
    echo "WARN: $ALWAYS rules have alwaysApply: true (recommended max: 2)" >&2
  fi
fi

if (( FAILED > 0 )); then
  echo "Agent drift check failed ($FAILED error(s))" >&2
  exit 1
fi

echo "Agent drift check passed"
