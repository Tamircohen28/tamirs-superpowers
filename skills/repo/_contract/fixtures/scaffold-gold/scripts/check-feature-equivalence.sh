#!/usr/bin/env bash
# check-feature-equivalence.sh — skill/manifest/MCP/hook capability parity across platforms.
#
# Usage:
#   check-feature-equivalence.sh [repo-root]
#   check-feature-equivalence.sh -h | --help
#
# Two layers run here:
#
#   E — structural parity. The artifacts a repo must ship so every supported platform can
#       consume the same canonical skills, MCP config and hooks.
#   C — registry agreement. core/capabilities/platforms.json is the ONE place that says
#       which platforms exist and what each can do. skills/repo/_contract/feature-equivalence.json
#       carries only the repo-contract delta on top of it — which artifact makes a capability
#       reachable — and never restates a status. This check fails loudly whenever the two
#       disagree in either direction, because two lists of platforms that can drift apart are
#       exactly the second source of truth the registry exists to remove.
#
# Exit 0 if checks pass; 1 on failure.
set -euo pipefail

usage() { sed -n '2,20p' "$0" | sed -E 's/^# ?//'; exit "${1:-0}"; }
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage 0; fi

ROOT="${1:-.}"
ROOT="$(cd "$ROOT" && pwd)"
FAILED=0

err() { echo "ERROR: $*" >&2; FAILED=$(( FAILED + 1 )); }
warn() { echo "WARN: $*" >&2; }

REGISTRY="$ROOT/core/capabilities/platforms.json"
TARGETS_JSON="$ROOT/docs/engineering/build-and-release/platform-targets.json"

# --- registry shape -----------------------------------------------------------------
# core/capabilities/platforms.json is rooted at the PLATFORM (Claude, Codex, Cursor,
# Gemini, OpenCode) and lists that platform's runtime SURFACES underneath: the terminal
# client, the desktop app, the editor extension. Every check below asks a per-surface
# question — "can the thing I am installed into do X?" — and every validation command
# runs against a surface, never against a vendor. So flatten to one entry per SUPPORTED
# surface, keyed by surface id, which is the shape the rest of this script expects and
# the shape docs/engineering/build-and-release/platform-targets.json is keyed by.
#
# Unverified surfaces are dropped here on purpose: they carry no capabilities block at
# all, because nobody measured them. Keeping them would force every reader to invent a
# meaning for a missing block, and the obvious invention — absent means no — is exactly
# the silent gap the registry exists to prevent. Docs list them; checkers do not.
#
# schema_version 1 registries are flat already, and a scaffolded repo may still be on
# one, so the flatten is conditional rather than assumed.
registry_flatten() {
  jq '{
    schema_version: .schema_version,
    last_reviewed: .last_reviewed,
    capability_definitions: .capability_definitions,
    platforms: (
      .platforms | to_entries
      | map(
          .key as $pid | .value as $p
          | ($p.surfaces // {}) | to_entries
          | map(select(.value.support == "supported"))
          | map({ key: .key,
                  value: (.value + { platform: $pid,
                                     platform_display_name: $p.display_name }) })
        )
      | flatten | from_entries
    )
  }' "$1" >"$2"
}

if [[ -f "$REGISTRY" ]] && jq -e '(.schema_version // 1) >= 2' "$REGISTRY" >/dev/null 2>&1; then
  REGISTRY_FLAT="$(mktemp)"
  trap 'rm -f "$REGISTRY_FLAT"' EXIT
  registry_flatten "$REGISTRY" "$REGISTRY_FLAT"
  REGISTRY="$REGISTRY_FLAT"
fi

# The contract spec. In this repo it lives under the shared _contract; scaffolded repos
# receive a copy next to their platform targets. Absent in neither place, the structural
# checks below still run from their built-in defaults.
SPEC=""
for cand in \
  "$ROOT/skills/repo/_contract/feature-equivalence.json" \
  "$ROOT/docs/engineering/build-and-release/feature-equivalence.json"; do
  if [[ -f "$cand" ]]; then SPEC="$cand"; break; fi
done

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

# Manifests that carry a skills path array and can therefore drift from each other.
# Driven by the spec so adding a platform is a data change, not a code change.
SKILLS_PATH_MANIFESTS=(.claude-plugin/plugin.json .cursor-plugin/plugin.json .codex-plugin/plugin.json)
if [[ -n "$SPEC" ]]; then
  spec_manifests=()
  while IFS= read -r line; do
    [[ -n "$line" ]] && spec_manifests+=("$line")
  done < <(jq -r '
    .repo_types["claude-plugin"].capabilities.skills.skills_path_manifests // [] | .[]' "$SPEC" 2>/dev/null || true)
  if (( ${#spec_manifests[@]} > 0 )); then
    SKILLS_PATH_MANIFESTS=("${spec_manifests[@]}")
  fi
fi

if [[ "$repo_type" == "claude-plugin" || "$repo_type" == "hybrid" || "$repo_type" == "agent-kit" ]]; then
  skill_count=$(count_skills "$ROOT/skills")
  if [[ "$repo_type" == "agent-kit" ]]; then
    skill_count=$(count_skills "$ROOT/canonical/skills")
  fi

  if (( skill_count > 0 )) || [[ -f "$ROOT/.claude-plugin/plugin.json" ]]; then
    for m in "${SKILLS_PATH_MANIFESTS[@]}"; do
      [[ -f "$ROOT/$m" ]] || err "Plugin repo: missing $m (skills or claude manifest present)"
    done

    all_present=true
    for m in "${SKILLS_PATH_MANIFESTS[@]}"; do
      [[ -f "$ROOT/$m" ]] || all_present=false
    done
    if [[ "$all_present" == true ]]; then
      ref_manifest="${SKILLS_PATH_MANIFESTS[0]}"
      ref_skills=$(manifest_skills_json "$ROOT/$ref_manifest")
      for m in "${SKILLS_PATH_MANIFESTS[@]:1}"; do
        this_skills=$(manifest_skills_json "$ROOT/$m")
        if [[ "$ref_skills" != "$this_skills" ]]; then
          err "Manifest skills paths disagree: $ref_manifest vs $m"
          echo "  $ref_manifest: $ref_skills" >&2
          echo "  $m: $this_skills" >&2
        fi
      done
    fi
  fi

  # MCP refs
  if [[ -f "$ROOT/.mcp.json" ]]; then
    for m in "${SKILLS_PATH_MANIFESTS[@]}"; do
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

# ---------------------------------------------------------------------------
# C — capability registry agreement
#
# The registry owns the platform list and the statuses. Everything else that names a
# platform is a derived view, and a derived view that can silently disagree with its
# source is a second source of truth. Each check below turns one possible disagreement
# into a hard failure.
# ---------------------------------------------------------------------------
if [[ ! -f "$REGISTRY" ]]; then
  if [[ -n "$SPEC" ]] && jq -e '.capability_source.registry' "$SPEC" >/dev/null 2>&1; then
    warn "${SPEC#"$ROOT"/} declares core/capabilities/platforms.json as its capability source, but the registry is absent — parity is being asserted against nothing (P2: add the registry)"
  fi
elif ! jq empty "$REGISTRY" 2>/dev/null; then
  err "core/capabilities/platforms.json is not valid JSON — the capability source cannot be read"
else
  {
    # Registry platforms, excluding runtime surfaces (Claude Desktop consumes the Claude
    # Code artifacts; giving it its own artifact set would re-create the duplication).
    reg_ids=$(jq -r '.platforms | to_entries[] | select(.value.runtime_surface_of == null) | .key' "$REGISTRY" | sort)

    if [[ -n "$SPEC" ]] && jq -e '.capability_source.registry' "$SPEC" >/dev/null 2>&1; then
    # Every platform id this contract names, from every platform map and manifest map.
    spec_ids=$(jq -r '
      [ .repo_types[]?.capabilities[]?
        | (.platforms // {} | keys[]), (.manifests // {} | keys[]) ] | unique | .[]' "$SPEC" | sort)

    while IFS= read -r id; do
      [[ -n "$id" ]] || continue
      if ! grep -qx "$id" <<<"$reg_ids"; then
        err "feature-equivalence.json names platform '$id', which has no entry in core/capabilities/platforms.json (or is a runtime surface) — the two platform lists have drifted"
      fi
    done <<<"$spec_ids"

    # Every platform that the registry says can do a thing must have a repo artifact that
    # makes it reachable. A platform added to the registry and forgotten here ships as
    # "supported" with nothing behind it.
    while IFS=$'\t' read -r rt cap regcap; do
      [[ -n "$regcap" ]] || continue
      sev=$(jq -r --arg rt "$rt" --arg c "$cap" '.repo_types[$rt].capabilities[$c].severity // "n/a"' "$SPEC")
      [[ "$sev" == "n/a" ]] && continue
      named=$(jq -r --arg rt "$rt" --arg c "$cap" '
        [ (.repo_types[$rt].capabilities[$c].platforms // {} | keys[]),
          (.repo_types[$rt].capabilities[$c].manifests // {} | keys[]) ] | unique | .[]' "$SPEC")
      # No platform map at all means the capability is expressed as a single shared
      # artifact rather than per-platform — nothing to compare.
      [[ -n "$named" ]] || continue
      while IFS= read -r pid; do
        [[ -n "$pid" ]] || continue
        status=$(jq -r --arg p "$pid" --arg k "$regcap" '.platforms[$p].capabilities[$k].status // "absent"' "$REGISTRY")
        case "$status" in
          unsupported|unknown|absent)
            if grep -qx "$pid" <<<"$named"; then
              # Documented substitutes are allowed to describe a gap; real artifacts are not.
              art=$(jq -r --arg rt "$rt" --arg c "$cap" --arg p "$pid" '
                (.repo_types[$rt].capabilities[$c].platforms[$p] // []) | join("; ")' "$SPEC")
              if [[ "$art" != *"substitute"* ]]; then
                err "repo_types.$rt.$cap requires '$pid' to ship [$art], but the registry records $pid.$regcap as '$status' — the contract demands an artifact the platform cannot consume"
              fi
            fi
            ;;
          *)
            grep -qx "$pid" <<<"$named" || \
              err "registry says $pid.$regcap is '$status', but repo_types.$rt.$cap names no artifact for '$pid' — a supported platform with nothing behind it"
            ;;
        esac
      done <<<"$reg_ids"
    done < <(jq -r '
      .repo_types | to_entries[] | .key as $rt
      | .value.capabilities // {} | to_entries[]
      | select(.value.registry_capability != null)
      | "\($rt)\t\(.key)\t\(.value.registry_capability)"' "$SPEC")
    fi

    # platform-targets.json is the version/provenance view of the same platform set.
    if [[ -f "$TARGETS_JSON" ]] && jq -e '.supported_targets' "$TARGETS_JSON" >/dev/null 2>&1; then
      tgt_ids=$(jq -r '.supported_targets[]' "$TARGETS_JSON" | sort)
      if [[ "$tgt_ids" != "$reg_ids" ]]; then
        err "platform-targets.json supported_targets disagrees with the capability registry"
        echo "  registry (non-surface): $(echo "$reg_ids" | tr '\n' ' ')" >&2
        echo "  supported_targets:      $(echo "$tgt_ids" | tr '\n' ' ')" >&2
      fi
    fi
  }
fi

if (( FAILED > 0 )); then
  echo "Feature equivalence check failed ($FAILED error(s))" >&2
  exit 1
fi

echo "Feature equivalence check passed"