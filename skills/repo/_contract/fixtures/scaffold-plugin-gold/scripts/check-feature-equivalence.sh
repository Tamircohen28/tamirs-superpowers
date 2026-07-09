#!/usr/bin/env bash
# check-feature-equivalence.sh — skill/manifest/MCP/hook capability parity across platforms.
#
# Usage:
#   check-feature-equivalence.sh [repo-root]
#   check-feature-equivalence.sh -h | --help
#
# Exit 0 if checks pass; 1 on failure.
set -euo pipefail

usage() { sed -n '2,10p' "$0" | sed 's/^# \?//'; exit "${1:-0}"; }
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage 0; fi

ROOT="${1:-.}"
ROOT="$(cd "$ROOT" && pwd)"
FAILED=0

err() { echo "ERROR: $*" >&2; FAILED=1; }

count_skills() {
  local n=0
  if [[ -d "$1" ]]; then
    n=$(find "$1" -name 'SKILL.md' 2>/dev/null | wc -l | tr -d ' ')
  fi
  echo "$n"
}

skill_dir_names() {
  local base="$1"
  [[ -d "$base" ]] || return 0
  find "$base" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; 2>/dev/null | sort
}

# --- repo type ---
repo_type="app"
if [[ -d "$ROOT/canonical/rules" ]]; then
  repo_type="agent-kit"
elif [[ -f "$ROOT/.claude-plugin/plugin.json" ]]; then
  if [[ -f "$ROOT/package.json" || -f "$ROOT/pyproject.toml" ]]; then
    repo_type="hybrid"
  else
    repo_type="claude-plugin"
  fi
elif [[ -d "$ROOT/skills" ]] && [[ "$(count_skills "$ROOT/skills")" -gt 0 ]]; then
  repo_type="claude-plugin"
fi

# --- app / hybrid: skill bridge ---
if [[ "$repo_type" == "app" || "$repo_type" == "hybrid" ]]; then
  has_agents=false
  has_claude=false
  [[ -d "$ROOT/.agents/skills" ]] && has_agents=true
  [[ -d "$ROOT/.claude/skills" ]] && has_claude=true

  if [[ "$has_agents" != true && "$has_claude" == true ]]; then
    bridge_doc=false
    for f in "$ROOT/AGENTS.md" "$ROOT/docs/agent-guidelines/platform-equivalence.md"; do
      if [[ -f "$f" ]] && grep -qE '\.agents/skills|skill bridge|skills bridge' "$f" 2>/dev/null; then
        bridge_doc=true
        break
      fi
    done
    if [[ "$bridge_doc" != true ]]; then
      err "App repo: .claude/skills/ exists without .agents/skills/ and no bridge documented in AGENTS.md or platform-equivalence.md"
    fi
  fi

  if [[ "$has_agents" == true && "$has_claude" == true ]]; then
    agents_names=$(skill_dir_names "$ROOT/.agents/skills")
    claude_names=$(skill_dir_names "$ROOT/.claude/skills")
    if [[ "$agents_names" != "$claude_names" ]]; then
      err "Skill bridge mismatch: .agents/skills and .claude/skills directory names differ"
      echo "  .agents: $(echo "$agents_names" | tr '\n' ' ')" >&2
      echo "  .claude: $(echo "$claude_names" | tr '\n' ' ')" >&2
    fi
  fi
fi

# --- plugin: manifest parity ---
manifest_skills_json() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  jq -c '.skills // [] | if type == "string" then [.] else . end | map(tostring) | sort' "$f" 2>/dev/null || echo "[]"
}

manifest_field() {
  local f="$1" field="$2"
  [[ -f "$f" ]] || { echo ""; return; }
  jq -r ".$field // empty" "$f" 2>/dev/null || echo ""
}

if [[ "$repo_type" == "claude-plugin" || "$repo_type" == "hybrid" || "$repo_type" == "agent-kit" ]]; then
  skill_count=$(count_skills "$ROOT/skills")
  if [[ "$repo_type" == "agent-kit" ]]; then
    skill_count=$(count_skills "$ROOT/canonical/skills")
  fi

  if (( skill_count > 0 )) || [[ -f "$ROOT/.claude-plugin/plugin.json" ]]; then
    for m in .claude-plugin/plugin.json .cursor-plugin/plugin.json .codex-plugin/plugin.json; do
      [[ -f "$ROOT/$m" ]] || err "Plugin repo: missing $m (skills or claude manifest present)"
    done

    if [[ -f "$ROOT/.claude-plugin/plugin.json" && -f "$ROOT/.cursor-plugin/plugin.json" && -f "$ROOT/.codex-plugin/plugin.json" ]]; then
      c_skills=$(manifest_skills_json "$ROOT/.claude-plugin/plugin.json")
      u_skills=$(manifest_skills_json "$ROOT/.cursor-plugin/plugin.json")
      x_skills=$(manifest_skills_json "$ROOT/.codex-plugin/plugin.json")
      if [[ "$c_skills" != "$u_skills" ]] || [[ "$c_skills" != "$x_skills" ]]; then
        err "Manifest skills paths disagree across .claude/.cursor/.codex plugin.json"
        echo "  claude: $c_skills" >&2
        echo "  cursor: $u_skills" >&2
        echo "  codex:  $x_skills" >&2
      fi
    fi
  fi

  # MCP refs
  if [[ -f "$ROOT/.mcp.json" ]]; then
    for m in .claude-plugin/plugin.json .cursor-plugin/plugin.json .codex-plugin/plugin.json; do
      [[ -f "$ROOT/$m" ]] || continue
      ref=$(manifest_field "$ROOT/$m" "mcpServers")
      if [[ -z "$ref" ]]; then
        err "$m: .mcp.json exists but mcpServers not declared"
      fi
    done
  fi

  # Hooks
  if [[ -f "$ROOT/hooks/hooks.json" ]]; then
    codex_hooks=$(manifest_field "$ROOT/.codex-plugin/plugin.json" "hooks")
    equiv="$ROOT/docs/agent-guidelines/platform-equivalence.md"
    if [[ -z "$codex_hooks" ]]; then
      err ".codex-plugin/plugin.json missing hooks field while hooks/hooks.json exists"
    fi
    if [[ ! -f "$equiv" ]] || ! grep -qiE 'cursor|hook' "$equiv" 2>/dev/null; then
      err "hooks/hooks.json present but docs/agent-guidelines/platform-equivalence.md missing Cursor/hook mapping"
    fi
  fi
fi

# MCP + codex config
if [[ -f "$ROOT/.mcp.json" ]]; then
  mcp_doc=false
  for f in "$ROOT/README.md" "$ROOT/AGENTS.md"; do
    if [[ -f "$f" ]] && grep -qiE 'mcp|MCP' "$f" 2>/dev/null; then mcp_doc=true; break; fi
  done
  if [[ "$mcp_doc" == true && ! -f "$ROOT/.codex/config.toml" ]]; then
    echo "WARN: MCP documented but .codex/config.toml missing (P2 — add stub for Codex project config)" >&2
  fi
fi

if (( FAILED > 0 )); then
  echo "Feature equivalence check failed ($FAILED error(s))" >&2
  exit 1
fi

echo "Feature equivalence check passed"
