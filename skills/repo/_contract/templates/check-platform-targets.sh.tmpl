#!/usr/bin/env bash
# check-platform-targets.sh — platform tool version documentation and badge sync.
#
# Usage:
#   check-platform-targets.sh [repo-root] [--sync] [--sync-capabilities]
#                             [--assert-current] [--require-co-change]
#   check-platform-targets.sh -h | --help
#
# platform-targets.json answers "which version of each harness did we actually validate
# against, and how do we know". It does NOT answer "what can each harness do" — that is
# core/capabilities/platforms.json, and the per-target `capabilities` / `capability_gaps`
# fields here are a DERIVED mirror of it. --sync-capabilities regenerates them; a normal
# run asserts they still match, so the registry cannot be edited without this file
# following.
#
# A target whose validated_against is "unknown" is declared but not yet validated. Its
# README badge and platform-sync sub-skill are warnings rather than errors until a real
# version lands — evidence over declarations, and no fake version number to make a
# checker happy.
#
# Exit 0 if checks pass; 1 on failure.
set -euo pipefail

usage() {
  sed -n '2,21p' "$0" | sed -E 's/^# ?//'
  exit "${1:-0}"
}
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage 0; fi

ROOT="."
SYNC=false
SYNC_CAPABILITIES=false
ASSERT_CURRENT=false
REQUIRE_CO_CHANGE=false

for arg in "$@"; do
  case "$arg" in
    --sync) SYNC=true ;;
    --sync-capabilities) SYNC_CAPABILITIES=true ;;
    --assert-current) ASSERT_CURRENT=true ;;
    --require-co-change) REQUIRE_CO_CHANGE=true ;;
    -*) echo "Unknown flag: $arg" >&2; exit 1 ;;
    *) ROOT="$arg" ;;
  esac
done

ROOT="$(cd "$ROOT" && pwd)"
FAILED=0
TARGETS_JSON="$ROOT/docs/engineering/build-and-release/platform-targets.json"
TARGETS_MD="$ROOT/docs/engineering/build-and-release/platform-targets.md"
REGISTRY="$ROOT/core/capabilities/platforms.json"
README="$ROOT/README.md"

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

err() { echo "ERROR: $*" >&2; FAILED=$(( FAILED + 1 )); }
warn() { echo "WARN: $*" >&2; }

# --- require-co-change (CI) ---
if [[ "$REQUIRE_CO_CHANGE" == true ]]; then
  WATCH_PATHS=(
    'skills/repo/multi-agent-repo/'
    'skills/repo/repo-standards/'
    'skills/repo/_contract/references/platform-specs.md'
    'skills/repo/_contract/feature-equivalence.json'
    'core/capabilities/platforms.json'
    'skills/documentation/platform-sync/'
    'skills/documentation/platform-sync/references/platforms/'
    'skills/documentation/platform-sync-claude/'
    'skills/documentation/platform-sync-cursor/'
    'skills/documentation/platform-sync-codex/'
    'skills/documentation/platform-sync-gemini/'
    'skills/documentation/platform-sync-opencode/'
    'docs/user/install/'
  )
  changed=false
  targets_changed=false
  if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    for p in "${WATCH_PATHS[@]}"; do
      if git -C "$ROOT" diff --name-only HEAD~1 HEAD 2>/dev/null | grep -q "^${p}"; then
        changed=true
        break
      fi
    done
    if git -C "$ROOT" diff --name-only HEAD~1 HEAD 2>/dev/null | grep -q 'platform-targets.json'; then
      targets_changed=true
    fi
    if [[ "$changed" == true && "$targets_changed" != true ]]; then
      err "PR changes repo skills/platform-specs but not docs/engineering/build-and-release/platform-targets.json"
    fi
  fi
  if (( FAILED > 0 )); then exit 1; fi
  echo "Platform targets co-change check passed"
  exit 0
fi

# --- multi-platform gate ---
multi_platform=false
ai_count=0
[[ -f "$ROOT/AGENTS.md" ]] && ai_count=$((ai_count + 1))
[[ -f "$ROOT/CLAUDE.md" ]] && ai_count=$((ai_count + 1))
[[ -d "$ROOT/.cursor/rules" ]] && ai_count=$((ai_count + 1))
[[ -f "$ROOT/.claude-plugin/plugin.json" ]] && ai_count=$((ai_count + 1))
[[ -f "$ROOT/.cursor-plugin/plugin.json" ]] && ai_count=$((ai_count + 1))
[[ -f "$ROOT/.codex-plugin/plugin.json" ]] && ai_count=$((ai_count + 1))
[[ -f "$ROOT/gemini-extension.json" ]] && ai_count=$((ai_count + 1))
[[ -f "$ROOT/opencode.json" ]] && ai_count=$((ai_count + 1))
(( ai_count >= 2 )) && multi_platform=true

if [[ "$multi_platform" != true ]]; then
  echo "Single-platform repo — platform-targets check skipped"
  exit 0
fi

# --- --sync: fetch latest_known (best-effort) ---
if [[ "$SYNC" == true && -f "$TARGETS_JSON" ]] && command -v curl >/dev/null 2>&1; then
  codex_latest=""
  codex_latest=$(curl -fsSL "https://api.github.com/repos/openai/codex/releases/latest" 2>/dev/null \
    | jq -r '.tag_name // empty' 2>/dev/null | sed 's/^v//' || true)
  # Codex GitHub releases use rust-v* tags — only sync semver-style versions.
  if [[ -n "$codex_latest" && "$codex_latest" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]]; then
    tmp=$(mktemp)
    jq --arg v "$codex_latest" '.targets.codex.latest_known = $v' "$TARGETS_JSON" >"$tmp"
    mv "$tmp" "$TARGETS_JSON"
    echo "Updated codex.latest_known to $codex_latest"
  fi

  # npm-distributed targets. Cursor has no public version endpoint — bump it by hand.
  # Gemini CLI ships as @google/gemini-cli; the entry stays "unknown" until a real
  # `gemini --version` is recorded, so only latest_known is ever synced here.
  sync_npm_latest() {
    local key="$1" pkg="$2" latest tmpf
    jq -e ".targets.$key" "$TARGETS_JSON" >/dev/null 2>&1 || return 0
    latest=$(curl -fsSL "https://registry.npmjs.org/${pkg}/latest" 2>/dev/null \
      | jq -r '.version // empty' 2>/dev/null || true)
    [[ "$latest" =~ ^[0-9]+\.[0-9]+\.[0-9]+ ]] || return 0
    tmpf=$(mktemp)
    jq --arg v "$latest" ".targets.$key.latest_known = \$v" "$TARGETS_JSON" >"$tmpf"
    mv "$tmpf" "$TARGETS_JSON"
    echo "Updated $key.latest_known to $latest"
  }
  sync_npm_latest opencode opencode-ai
  sync_npm_latest claude_code @anthropic-ai/claude-code
  sync_npm_latest gemini_cli @google/gemini-cli
fi

# --- offline validation ---
if [[ ! -f "$TARGETS_JSON" ]]; then
  err "Missing $TARGETS_JSON (required for multi-platform repos)"
  exit 1
fi

if ! jq empty "$TARGETS_JSON" 2>/dev/null; then
  err "Invalid JSON: $TARGETS_JSON"
  exit 1
fi

# --- derived capabilities: regenerate or assert against the registry ---
# Statuses that mean "the platform provides this, possibly via an adapter". Anything
# marked unknown appears in neither list: an unverified capability must never read as
# either a supported feature or a confirmed gap.
derive_capabilities() {
  python3 - "$TARGETS_JSON" "$REGISTRY" "${1:-assert}" <<'PY'
import collections, json, sys

targets_path, registry_path, mode = sys.argv[1], sys.argv[2], sys.argv[3]
d = json.loads(open(targets_path).read(), object_pairs_hook=collections.OrderedDict)
reg = json.loads(open(registry_path).read())
PROVIDED = {"native", "native-experimental", "partial", "emulated", "adapter"}

problems = []
changed = False
for key in d.get("supported_targets", []):
    t = d.get("targets", {}).get(key)
    plat = reg.get("platforms", {}).get(key)
    if t is None or plat is None:
        continue
    caps = plat["capabilities"]
    want_caps = sorted(k for k, v in caps.items() if v["status"] in PROVIDED)
    want_gaps = collections.OrderedDict(
        (k, caps[k].get("notes") or caps[k].get("fallback") or "unsupported")
        for k in sorted(caps)
        if caps[k]["status"] == "unsupported"
    )
    if mode == "sync":
        if t.get("capabilities") != want_caps:
            t["capabilities"] = want_caps
            changed = True
        if want_gaps:
            if t.get("capability_gaps") != want_gaps:
                t["capability_gaps"] = want_gaps
                changed = True
        elif "capability_gaps" in t:
            del t["capability_gaps"]
            changed = True
    else:
        if t.get("capabilities") != want_caps:
            problems.append(
                f"targets.{key}.capabilities is stale: registry derives "
                f"{want_caps} but the file says {t.get('capabilities')}"
            )
        have_gaps = t.get("capability_gaps") or collections.OrderedDict()
        if have_gaps != want_gaps:
            # Report the actual difference. Printing only the key lists is useless when the
            # keys match and a note's text moved, which is the common case: the registry is
            # edited far more often than a status flips.
            added = [k for k in want_gaps if k not in have_gaps]
            removed = [k for k in have_gaps if k not in want_gaps]
            retext = [k for k in want_gaps if k in have_gaps and want_gaps[k] != have_gaps[k]]
            detail = []
            if added:
                detail.append(f"gap(s) added by the registry: {added}")
            if removed:
                detail.append(f"gap(s) no longer in the registry: {removed}")
            for k in retext:
                detail.append(
                    f"text for '{k}' changed:\n"
                    f"      registry: {want_gaps[k]}\n"
                    f"      file:     {have_gaps[k]}"
                )
            problems.append(
                f"targets.{key}.capability_gaps is stale: " + "; ".join(detail)
            )

if mode == "sync":
    if changed:
        open(targets_path, "w").write(json.dumps(d, indent=2, ensure_ascii=False) + "\n")
        print("Regenerated capabilities/capability_gaps from the capability registry")
    else:
        print("capabilities/capability_gaps already match the capability registry")
    sys.exit(0)

for p in problems:
    print(p, file=sys.stderr)
sys.exit(1 if problems else 0)
PY
}

if [[ -f "$REGISTRY" ]] && command -v python3 >/dev/null 2>&1; then
  if [[ "$SYNC_CAPABILITIES" == true ]]; then
    derive_capabilities sync
  elif ! derive_capabilities assert; then
    err "platform-targets.json capability mirror has drifted from core/capabilities/platforms.json — run: bash scripts/check-platform-targets.sh . --sync-capabilities"
  fi
elif [[ "$SYNC_CAPABILITIES" == true ]]; then
  err "--sync-capabilities needs core/capabilities/platforms.json and python3"
fi

# Which targets to enforce: the JSON's own supported_targets list when present,
# otherwise the legacy three (keeps schema_version 1 files passing unchanged).
TARGET_KEYS=$(jq -r '(.supported_targets // ["claude_code","cursor","codex"]) | join(" ")' "$TARGETS_JSON")

badge_prefix() {
  case "$1" in
    claude_code) echo "Claude%20Code" ;;
    cursor)      echo "Cursor" ;;
    codex)       echo "Codex" ;;
    gemini_cli)  echo "Gemini%20CLI" ;;
    opencode)    echo "OpenCode" ;;
    *)           echo "" ;;
  esac
}

# /platform-sync resolves its target list from the capability registry and reads one
# reference file per target. A supported target with no reference file is invisible to it:
# the umbrella analyses the other targets and reports success, so the gap reads as "no
# improvements found" rather than "this target was never checked".
#
# Reference basename is derived from the registry id, not enumerated, so adding a target
# stays a data change. The mapping is documented in
# skills/documentation/platform-sync/references/registry.md: underscores become hyphens and
# nothing else (claude_code -> claude-code, gemini_cli -> gemini-cli). Do not "tidy" the
# -cli suffix away — the reference files are named for the registry id verbatim.
platform_ref_name() {
  echo "${1//_/-}"
}

# Legacy layout: one platform-sync-<name> sub-skill per target. Still honoured for repos
# that have not moved to the reference-file engine.
legacy_subskill_name() {
  case "$1" in
    claude_code) echo "platform-sync-claude" ;;
    cursor)      echo "platform-sync-cursor" ;;
    codex)       echo "platform-sync-codex" ;;
    gemini_cli)  echo "platform-sync-gemini" ;;
    opencode)    echo "platform-sync-opencode" ;;
    *)           echo "" ;;
  esac
}

PLATFORM_REF_DIR="$ROOT/skills/documentation/platform-sync/references/platforms"

# A declared-but-unvalidated target (validated_against == "unknown") downgrades its
# discoverability requirements to warnings. It is honest about not being validated yet
# and cannot be mistaken for a supported version.
is_unvalidated() {
  [[ "$(jq -r ".targets.\"$1\".validated_against // empty" "$TARGETS_JSON")" == "unknown" ]]
}

# shellcheck disable=SC2086
for key in $TARGET_KEYS; do
  jq -e ".targets.$key.validated_against" "$TARGETS_JSON" >/dev/null 2>&1 \
    || err "platform-targets.json missing targets.$key.validated_against"

  # Coverage by /platform-sync. Prefer the reference-file engine; fall back to the
  # legacy per-target sub-skill layout when this repo still uses it.
  if [[ -z "$(badge_prefix "$key")" ]]; then
    err "platform-targets.json declares unknown target '$key' — add it to badge_prefix() and legacy_subskill_name() in $(basename "$0")"
  elif [[ -d "$PLATFORM_REF_DIR" ]]; then
    ref="$PLATFORM_REF_DIR/$(platform_ref_name "$key").md"
    if [[ ! -f "$ref" ]]; then
      if is_unvalidated "$key"; then
        warn "declared target '$key' has no ${ref#"$ROOT"/} — /platform-sync cannot audit it (warning only while validated_against is \"unknown\")"
      else
        err "supported target '$key' has no ${ref#"$ROOT"/} — /platform-sync cannot audit it"
      fi
    fi
  elif [[ -d "$ROOT/skills/documentation" ]]; then
    sub=$(legacy_subskill_name "$key")
    if [[ -n "$sub" && ! -d "$ROOT/skills/documentation/$sub" ]]; then
      if is_unvalidated "$key"; then
        warn "declared target '$key' has no skills/documentation/$sub/ — /platform-sync cannot audit it (warning only while validated_against is \"unknown\")"
      else
        err "supported target '$key' has no skills/documentation/$sub/ — /platform-sync cannot audit it"
      fi
    fi
  fi
done

# Each target here is one SURFACE of a platform. `platform` names which one, so this file
# can be read without the registry open beside it — and because a name that is merely
# implied by an id is a name that drifts. The registry owns the answer; this asserts the
# copy still matches it. Only checked when the registry is platform-rooted (schema 2+),
# so a repo still on a flat schema_version 1 registry passes unchanged.
if [[ -f "$REGISTRY" ]] && jq -e 'any(.platforms[]; has("platform"))' "$REGISTRY" >/dev/null 2>&1; then
  before_owner=$FAILED
  # shellcheck disable=SC2086
  for key in $TARGET_KEYS; do
    want=$(jq -r --arg k "$key" '.platforms[$k].platform // empty' "$REGISTRY")
    have=$(jq -r --arg k "$key" '.targets[$k].platform // empty' "$TARGETS_JSON")
    [[ -n "$want" ]] || continue
    if [[ -z "$have" ]]; then
      err "targets.$key declares no 'platform' — the registry says this surface belongs to '$want'"
    elif [[ "$have" != "$want" ]]; then
      err "targets.$key.platform is '$have' but the registry files that surface under '$want'"
    fi
  done
  if (( FAILED == before_owner )); then
    echo "  every target names the platform the registry files it under"
  fi
fi

last_reviewed=$(jq -r '.last_reviewed // empty' "$TARGETS_JSON")
[[ -n "$last_reviewed" ]] || err "platform-targets.json missing last_reviewed"

if [[ ! -f "$TARGETS_MD" ]]; then
  err "Missing human mirror: $TARGETS_MD"
fi

# README badge vs JSON
if [[ -f "$README" ]]; then
  check_badge() {
    local key="$1" prefix
    local validated
    prefix=$(badge_prefix "$key")
    [[ -n "$prefix" ]] || return 0
    validated=$(jq -r ".targets.$key.validated_against // empty" "$TARGETS_JSON")
    [[ -n "$validated" ]] || return 0
    if [[ "$validated" == "unknown" ]]; then
      grep -qF "${prefix}-" "$README" 2>/dev/null \
        || warn "README has no $key badge yet (target declared, validated_against=\"unknown\" — badge required once a version is recorded)"
      return 0
    fi
    if ! grep -qF "${prefix}-${validated}" "$README" 2>/dev/null; then
      err "README missing $key badge for validated_against=$validated (expected ${prefix}-${validated})"
    fi
  }
  # shellcheck disable=SC2086
  for key in $TARGET_KEYS; do check_badge "$key"; done
fi

# stale targets
if [[ "$ASSERT_CURRENT" == true ]]; then
  # shellcheck disable=SC2086
  for key in $TARGET_KEYS; do
    v=$(jq -r ".targets.$key.validated_against // empty" "$TARGETS_JSON")
    l=$(jq -r ".targets.$key.latest_known // empty" "$TARGETS_JSON")
    [[ "$v" == "unknown" || "$l" == "unknown" ]] && continue
    if [[ -n "$v" && -n "$l" && "$v" != "$l" ]]; then
      err "Stale platform target $key: validated_against=$v latest_known=$l"
    fi
  done
fi

# last_reviewed > 90 days (warn only unless assert)
if [[ -n "$last_reviewed" ]]; then
  # shellcheck disable=SC2209
  if date -v-90d +%Y-%m-%d >/dev/null 2>&1; then
    cutoff=$(date -v-90d +%Y-%m-%d)
  else
    cutoff=$(date -d '90 days ago' +%Y-%m-%d 2>/dev/null || echo "")
  fi
  if [[ -n "$cutoff" && "$last_reviewed" < "$cutoff" ]]; then
    warn "platform-targets last_reviewed ($last_reviewed) is older than 90 days"
  fi
fi

if (( FAILED > 0 )); then
  echo "Platform targets check failed ($FAILED error(s))" >&2
  exit 1
fi

echo "Platform targets check passed"