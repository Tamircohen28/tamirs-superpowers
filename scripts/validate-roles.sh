#!/usr/bin/env bash
# validate-roles.sh — role / agent / workflow-schema consistency check.
#
# Asserts:
#   1. every canonical role has a core/roles/<role>.md;
#   2. every agents/*.md declares a role: that exists in core/roles/;
#   3. the three core/workflow/*.json schemas parse;
#   4. reviewer-role agents declare no write tools.
#
# Validation tier: 0 (static parse + consistency; runs no tests).
#
# Usage: bash scripts/validate-roles.sh [repo-root]
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT"

# Canonical role list (spec §2.3). Keep in sync with core/roles/README.md.
ROLES=(
  planner
  orchestrator
  implementer
  test-engineer
  reviewer
  security-reviewer
  performance-reviewer
  debugger
  integrator
  research-agent
)

# Roles that must be read-only (spec §11).
REVIEWER_ROLES="reviewer security-reviewer performance-reviewer"

# Tools that grant write access to the repository.
WRITE_TOOLS="Edit Write NotebookEdit MultiEdit"

fail=0
err() { echo "ERROR: $*" >&2; fail=1; }

echo "=== validate-roles ==="

# --- 1. every canonical role has a definition file -------------------------
for role in "${ROLES[@]}"; do
  if [[ -f "core/roles/$role.md" ]]; then
    echo "  role ok: $role"
  else
    err "missing core/roles/$role.md for canonical role '$role'"
  fi
done

# Flag stray role files not in the canonical list.
for f in core/roles/*.md; do
  [[ -e "$f" ]] || continue
  base="$(basename "$f" .md)"
  [[ "$base" == "README" ]] && continue
  found=0
  for role in "${ROLES[@]}"; do
    [[ "$base" == "$role" ]] && found=1
  done
  [[ "$found" -eq 1 ]] || err "core/roles/$base.md is not a canonical role"
done

# --- 2. every agent declares an existing role ------------------------------
agent_count=0
for f in agents/*.md; do
  [[ -e "$f" ]] || continue
  agent_count=$((agent_count + 1))
  name="$(basename "$f" .md)"
  role="$(sed -n 's/^role:[[:space:]]*//p' "$f" | head -1)"

  if [[ -z "$role" ]]; then
    err "$f declares no 'role:' in its frontmatter"
    continue
  fi
  if [[ ! -f "core/roles/$role.md" ]]; then
    err "$f declares role '$role' with no core/roles/$role.md"
    continue
  fi
  echo "  agent ok: $name -> $role"

  # --- 4. reviewer-role agents must be read-only ---------------------------
  case " $REVIEWER_ROLES " in
    *" $role "*)
      tools="$(sed -n 's/^tools:[[:space:]]*//p' "$f" | head -1)"
      for wt in $WRITE_TOOLS; do
        case ",${tools// /}," in
          *",$wt,"*)
            err "$f has reviewer role '$role' but declares write tool '$wt'"
            ;;
        esac
      done
      ;;
  esac
done
[[ "$agent_count" -gt 0 ]] || err "no agents/*.md found"

# --- 3. workflow schemas parse ---------------------------------------------
command -v jq >/dev/null 2>&1 || { err "jq is required"; exit 1; }
for schema in objective task handoff; do
  path="core/workflow/$schema-schema.json"
  if [[ ! -f "$path" ]]; then
    err "missing $path"
  elif jq empty "$path" >/dev/null 2>&1; then
    echo "  schema ok: $path"
  else
    err "$path is not valid JSON"
  fi
done

# The task schema's role enum must match the canonical role list exactly.
if [[ -f core/workflow/task-schema.json ]]; then
  enum_roles="$(jq -r '.properties.role.enum[]' core/workflow/task-schema.json 2>/dev/null | sort | tr '\n' ' ')"
  canon_roles="$(printf '%s\n' "${ROLES[@]}" | sort | tr '\n' ' ')"
  if [[ "$enum_roles" == "$canon_roles" ]]; then
    echo "  schema ok: task-schema role enum matches canonical roles"
  else
    err "task-schema.json role enum does not match the canonical role list"
    echo "    enum:      $enum_roles" >&2
    echo "    canonical: $canon_roles" >&2
  fi
fi

if [[ "$fail" -ne 0 ]]; then
  echo "FAIL — role/agent validation found problems" >&2
  exit 1
fi

echo "PASS — ${#ROLES[@]} roles, $agent_count agents, 3 workflow schemas"
