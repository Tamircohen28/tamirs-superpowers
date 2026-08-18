#!/usr/bin/env bash
# handoff.sh — emit and validate the structured handoff a worker task returns.
#
# A work unit ends at commit + handoff, never at a PR (REFACTOR-SPEC 2.4).
# This script writes .dev-files/objectives/<id>/handoffs/<task-id>.json against
# core/workflow/handoff-schema.json.
#
# Validation tier: 0 (edit-time). It records what a Tier 1 run produced; it
# never runs the project's tests itself.
#
# Usage:
#   handoff.sh emit <objective-id> <task-id> --status completed|partial|failed|blocked|cancelled
#              [--summary TEXT] [--branch NAME]
#              [--commit SHA]...
#              [--file 'path:added|modified|deleted|renamed']...
#              [--validation 'command|tier|pass|fail|skipped[|note]']...
#              [--decision 'decision|rationale']...
#              [--risk 'risk|critical|high|medium|low[|mitigation]']...
#              [--followup 'item[|blocking][|role]']...
#              [--force]            write even when scope checks fail
#   handoff.sh write <objective-id> <task-id> <handoff.json> [--force]
#   handoff.sh read  <objective-id> <task-id>
#   handoff.sh validate <objective-id> <task-id>
#   handoff.sh show <objective-id> <task-id>
#   handoff.sh list <objective-id>
#   handoff.sh -h | --help
#
# Environment:
#   OBJECTIVES_ROOT   override state root (default: <repo root>/.dev-files/objectives)
#
# Exit codes: 0 ok · 1 usage/argument error · 2 not found · 3 dependency missing
#             4 validation failed
set -euo pipefail

usage() {
  sed -n '2,31p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

die() { printf 'ERROR: %s\n' "$1" >&2; exit "${2:-1}"; }

if [[ $# -eq 0 || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage 0
fi

resolve_root() {
  if [[ -n "${OBJECTIVES_ROOT:-}" ]]; then printf '%s\n' "$OBJECTIVES_ROOT"; return 0; fi
  local repo
  if repo="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    printf '%s/.dev-files/objectives\n' "$repo"
  else
    printf '%s/.dev-files/objectives\n' "$PWD"
  fi
}

ROOT="$(resolve_root)"

require_jq() {
  command -v jq >/dev/null 2>&1 \
    || die "jq is required for '$1'. Install jq, or hand-write the handoff JSON under $ROOT." 3
}

obj_dir() { printf '%s/%s\n' "$ROOT" "$1"; }
handoff_file() { printf '%s/handoffs/%s.json\n' "$(obj_dir "$1")" "$2"; }
task_file() { printf '%s/tasks/%s.json\n' "$(obj_dir "$1")" "$2"; }

require_obj() { [[ -d "$(obj_dir "$1")" ]] || die "no objective '$1' under $ROOT" 2; }
valid_task_id() { [[ "$1" =~ ^task-[0-9]{3}$ ]]; }

STATUSES="completed partial failed blocked cancelled"
CHANGES="added modified deleted renamed"
RESULTS="pass fail skipped"
TIERS="edit worker integration delivery"
SEVERITIES="critical high medium low"

in_list() {
  local needle="$1" item
  shift
  for item in $1; do
    if [[ "$item" == "$needle" ]]; then return 0; fi
  done
  return 1
}

# field 'a|b|c' N  ->  Nth pipe-separated field, empty when absent
field() { printf '%s' "$1" | cut -d'|' -f"$2"; }

# scope_escapes <task-file> <newline-separated paths>  -> escaping paths on stdout
scope_escapes() {
  local tf="$1" paths="$2"
  local scope_globs path glob matched
  scope_globs="$(jq -r '.scope[]' "$tf")"
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    matched=0
    while IFS= read -r glob; do
      [[ -n "$glob" ]] || continue
      # shellcheck disable=SC2053
      if [[ "$path" == $glob ]]; then matched=1; break; fi
    done <<<"$scope_globs"
    [[ $matched -eq 1 ]] || printf '%s\n' "$path"
  done <<<"$paths"
}

# write <objective-id> <task-id> <handoff.json> [--force]
# Accepts a caller-authored handoff document, validates it the way `emit`
# validates the one it builds, and installs it at the canonical path.
cmd_write() {
  local oid="${1:-}" tid="${2:-}" src="${3:-}"
  [[ -n "$oid" && -n "$tid" && -n "$src" ]] || die "write requires <objective-id> <task-id> <handoff.json>"
  shift 3
  local force=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --force) force=1; shift ;;
      *) die "write: unknown option '$1'" ;;
    esac
  done
  require_obj "$oid"
  valid_task_id "$tid" || die "task id must match ^task-[0-9]{3}$"
  [[ -f "$src" ]] || die "no such handoff file: $src" 2
  require_jq write
  jq -e . "$src" >/dev/null 2>&1 || die "$src is not valid JSON" 4

  local status; status="$(jq -r '.status // ""' "$src")"
  [[ -n "$status" ]] || die "$src has no status ($STATUSES)" 4
  in_list "$status" "$STATUSES" || die "status must be one of: $STATUSES" 4

  local bad
  bad="$(jq -r '.commits[]? | select(test("^[0-9a-f]{7,40}$") | not)' "$src")"
  [[ -z "$bad" ]] || die "commit(s) not sha-shaped: $bad. Never fabricate one." 4
  bad="$(jq -r '.validation[]? | select(.result == "skipped" and ((.skip_reason // "") == "")) | .command' "$src")"
  [[ -z "$bad" ]] || die "skipped validation without skip_reason: $bad" 4

  local tf; tf="$(task_file "$oid" "$tid")"
  if [[ -f "$tf" ]]; then
    local escapes
    escapes="$(scope_escapes "$tf" "$(jq -r '.files_changed[]?.path' "$src")")"
    if [[ -n "$escapes" ]]; then
      printf 'scope violation: path(s) outside task scope: %s\n' "$(tr '\n' ' ' <<<"$escapes")" >&2
      if [[ $force -eq 0 ]]; then
        die "refusing to write. Move the change into scope, record it as a followup, or pass --force." 4
      fi
      printf -- '--force given: writing anyway. The integrator must review this.\n' >&2
    fi
  else
    printf 'note: %s has no task file — scope not checked.\n' "$tid" >&2
  fi

  mkdir -p "$(obj_dir "$oid")/handoffs"
  local out; out="$(handoff_file "$oid" "$tid")"
  # Normalise: the canonical task_id wins over whatever the document claimed.
  jq --arg tid "$tid" '. + { schema_version: (.schema_version // 1), task_id: $tid }' "$src" > "$out"
  cat "$out"
}

cmd_emit() {
  local oid="${1:-}" tid="${2:-}"
  [[ -n "$oid" && -n "$tid" ]] || die "emit requires <objective-id> <task-id>"
  shift 2
  require_obj "$oid"
  valid_task_id "$tid" || die "task id must match ^task-[0-9]{3}$"
  require_jq emit

  local status="" summary="" branch="" force=0
  local commits="[]" files="[]" validations="[]" decisions="[]" risks="[]" followups="[]"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --status) status="${2:-}"; shift 2 ;;
      --summary) summary="${2:-}"; shift 2 ;;
      --branch) branch="${2:-}"; shift 2 ;;
      --force) force=1; shift ;;
      --commit)
        [[ "${2:-}" =~ ^[0-9a-f]{7,40}$ ]] || die "--commit '$2' is not a commit sha. Never fabricate one."
        commits="$(jq -n --argjson acc "$commits" --arg c "$2" '$acc + [$c]')"; shift 2 ;;
      --file)
        local fpath fchange
        fpath="${2%%:*}"; fchange="${2##*:}"
        [[ -n "$fpath" && "$fpath" != "$2" ]] || die "--file expects 'path:change'"
        in_list "$fchange" "$CHANGES" || die "--file change must be one of: $CHANGES"
        files="$(jq -n --argjson acc "$files" --arg p "$fpath" --arg c "$fchange" \
          '$acc + [{path: $p, change: $c}]')"; shift 2 ;;
      --validation)
        local vcmd vtier vres vnote
        vcmd="$(field "$2" 1)"; vtier="$(field "$2" 2)"; vres="$(field "$2" 3)"; vnote="$(field "$2" 4)"
        [[ -n "$vcmd" ]] || die "--validation expects 'command|tier|result[|note]'"
        in_list "$vres" "$RESULTS" || die "--validation result must be one of: $RESULTS"
        [[ -z "$vtier" ]] || in_list "$vtier" "$TIERS" || die "--validation tier must be one of: $TIERS"
        if [[ "$vres" == "skipped" && -z "$vnote" ]]; then die "a skipped validation must give a skip reason as the 4th field"; fi
        validations="$(jq -n --argjson acc "$validations" --arg c "$vcmd" --arg t "$vtier" \
          --arg r "$vres" --arg n "$vnote" '$acc + [ {command: $c, result: $r}
            | if $t == "" then . else .tier = $t end
            | if $n == "" then . elif $r == "skipped" then .skip_reason = $n else .output_excerpt = $n end ]')"
        shift 2 ;;
      --decision)
        decisions="$(jq -n --argjson acc "$decisions" --arg d "$(field "$2" 1)" --arg r "$(field "$2" 2)" \
          '$acc + [ {decision: $d} | if $r == "" then . else .rationale = $r end ]')"; shift 2 ;;
      --risk)
        local rsev; rsev="$(field "$2" 2)"
        [[ -z "$rsev" ]] || in_list "$rsev" "$SEVERITIES" || die "--risk severity must be one of: $SEVERITIES"
        risks="$(jq -n --argjson acc "$risks" --arg r "$(field "$2" 1)" --arg s "$rsev" \
          --arg m "$(field "$2" 3)" '$acc + [ {risk: $r}
            | if $s == "" then . else .severity = $s end
            | if $m == "" then . else .mitigation = $m end ]')"; shift 2 ;;
      --followup)
        followups="$(jq -n --argjson acc "$followups" --arg i "$(field "$2" 1)" \
          --arg b "$(field "$2" 2)" --arg role "$(field "$2" 3)" '$acc + [ {item: $i}
            | if $b == "" then . else .blocking = ($b == "true" or $b == "blocking") end
            | if $role == "" then . else .suggested_role = $role end ]')"; shift 2 ;;
      *) die "emit: unknown option '$1'" ;;
    esac
  done

  [[ -n "$status" ]] || die "emit requires --status ($STATUSES)"
  in_list "$status" "$STATUSES" || die "--status must be one of: $STATUSES"

  # Scope check: every changed path must fall inside the task's declared scope.
  local tf; tf="$(task_file "$oid" "$tid")"
  if [[ -f "$tf" ]]; then
    local escapes
    escapes="$(scope_escapes "$tf" "$(jq -r '.[].path' <<<"$files")")"
    if [[ -n "$escapes" ]]; then
      printf 'scope violation: path(s) outside task scope: %s\n' "$(tr '\n' ' ' <<<"$escapes")" >&2
      printf 'Declared scope: %s\n' "$(jq -r '.scope[]' "$tf" | tr '\n' ' ')" >&2
      if [[ $force -eq 0 ]]; then
        die "refusing to emit. Move the change into scope, or record it as a followup, or pass --force." 4
      fi
      printf '--force given: emitting anyway. The integrator must review this.\n' >&2
    fi
  else
    printf 'note: %s has no task file — scope not checked.\n' "$tid" >&2
  fi

  mkdir -p "$(obj_dir "$oid")/handoffs"
  local out; out="$(handoff_file "$oid" "$tid")"
  jq -n --arg tid "$tid" --arg status "$status" --arg summary "$summary" --arg branch "$branch" \
        --argjson commits "$commits" --argjson files "$files" --argjson validation "$validations" \
        --argjson decisions "$decisions" --argjson risks "$risks" --argjson followups "$followups" \
        --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '{
    schema_version: 1, task_id: $tid, status: $status,
    commits: $commits, files_changed: $files, validation: $validation,
    decisions: $decisions, risks: $risks, followups: $followups, completed: $now
  } | if $summary == "" then . else .summary = $summary end
    | if $branch == "" then . else .branch = $branch end' > "$out"
  cat "$out"
}

cmd_validate() {
  local oid="${1:-}" tid="${2:-}"
  [[ -n "$oid" && -n "$tid" ]] || die "validate requires <objective-id> <task-id>"
  require_jq validate
  local f; f="$(handoff_file "$oid" "$tid")"
  [[ -f "$f" ]] || die "no handoff for $tid in objective '$oid'" 2

  local errs=0
  jq -e '.task_id and .status' "$f" >/dev/null || { echo "task_id and status are required" >&2; errs=$((errs + 1)); }
  jq -r '.task_id' "$f" | grep -qE '^task-[0-9]{3}$' || { echo "task_id malformed" >&2; errs=$((errs + 1)); }
  in_list "$(jq -r '.status' "$f")" "$STATUSES" || { echo "status not in enum" >&2; errs=$((errs + 1)); }

  local bad
  bad="$(jq -r '.commits[]? | select(test("^[0-9a-f]{7,40}$") | not)' "$f")"
  [[ -z "$bad" ]] || { echo "commit(s) not sha-shaped: $bad" >&2; errs=$((errs + 1)); }

  bad="$(jq -r '.files_changed[]? | select((.path // "") == "" or ([.change] | inside(["added","modified","deleted","renamed"]) | not)) | .path // "(no path)"' "$f")"
  [[ -z "$bad" ]] || { echo "files_changed entries malformed: $bad" >&2; errs=$((errs + 1)); }

  bad="$(jq -r '.validation[]? | select(.result == "skipped" and ((.skip_reason // "") == "")) | .command' "$f")"
  [[ -z "$bad" ]] || { echo "skipped validation without skip_reason: $bad" >&2; errs=$((errs + 1)); }

  bad="$(jq -r '.validation[]? | select((.command // "") == "" or ([.result] | inside(["pass","fail","skipped"]) | not)) | (.command // "(no command)")' "$f")"
  [[ -z "$bad" ]] || { echo "validation entries malformed: $bad" >&2; errs=$((errs + 1)); }

  # A completed handoff that ran nothing is a red flag, not an error.
  if [[ "$(jq -r '.status' "$f")" == "completed" && "$(jq '.validation | length' "$f")" -eq 0 ]]; then
    echo "warning: status completed with an empty validation[] — Tier 1 evidence is missing" >&2
  fi

  # Cross-check against the task's scope when the task file is present.
  local tf; tf="$(task_file "$oid" "$tid")"
  if [[ -f "$tf" ]]; then
    local escapes
    escapes="$(scope_escapes "$tf" "$(jq -r '.files_changed[]?.path' "$f")")"
    [[ -z "$escapes" ]] || { echo "path(s) outside task scope: $(tr '\n' ' ' <<<"$escapes")" >&2; errs=$((errs + 1)); }
  fi

  if [[ $errs -gt 0 ]]; then
    jq -n --arg t "$tid" --argjson n "$errs" '{task_id: $t, valid: false, errors: $n}'
    exit 4
  fi
  jq -n --arg t "$tid" '{task_id: $t, valid: true, errors: 0}'
}

cmd_show() {
  local f; f="$(handoff_file "${1:-}" "${2:-}")"
  [[ -f "$f" ]] || die "no handoff for '${2:-}' in objective '${1:-}'" 2
  cat "$f"
}

cmd_list() {
  local oid="${1:-}"
  require_obj "$oid"
  require_jq list
  local dir; dir="$(obj_dir "$oid")/handoffs"
  [[ -d "$dir" ]] || { printf '[]\n'; return 0; }
  find "$dir" -name 'task-*.json' -print0 2>/dev/null | sort -z | xargs -0 -r jq -s \
    'map({task_id, status, commits: (.commits | length),
          files: (.files_changed | length),
          validation_failures: ([.validation[]? | select(.result == "fail")] | length),
          blocking_followups: ([.followups[]? | select(.blocking == true)] | length)})'
}

COMMAND="$1"; shift
case "$COMMAND" in
  emit)     cmd_emit "$@" ;;
  write)    cmd_write "$@" ;;
  read)     cmd_show "$@" ;;
  validate) cmd_validate "$@" ;;
  show)     cmd_show "$@" ;;
  list)     cmd_list "$@" ;;
  *) die "unknown command '$COMMAND' (try --help)" ;;
esac
