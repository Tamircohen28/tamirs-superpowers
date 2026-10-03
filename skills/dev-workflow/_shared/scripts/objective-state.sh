#!/usr/bin/env bash
# objective-state.sh — create, read and update objective/task state on disk.
#
# The orchestration state model (REFACTOR-SPEC section 7). No database, no
# service: plain JSON under .dev-files/objectives/<objective-id>/, validated
# against core/workflow/{objective,task}-schema.json.
#
# Validation tier: 0 (edit-time). This script never runs project tests.
#
# Usage:
#   objective-state.sh init <id> --title T [--base-branch B] [--integration-branch IB]
#   objective-state.sh active                  # active objective id; empty + exit 1 when none
#   objective-state.sh show <id>
#   objective-state.sh path <id>
#   objective-state.sh list
#   objective-state.sh set <id> <dotted.key> <value>      # in-place field update
#   objective-state.sh add-task <id> <task.json>          # register a task from a JSON file
#   objective-state.sh set-status <id> <status>
#   objective-state.sh set-delivery <id> [--strategy S] [--reason R] [--auto-merge true|false] [--pr-url U]
#   objective-state.sh task-add <id> --role R --scope 'GLOB[,GLOB]' [--depends-on task-001,task-002]
#                                    [--tier edit|worker|integration|delivery] [--title T] [--task-id task-NNN]
#   objective-state.sh task-show <id> <task-id>
#   objective-state.sh task-set <id> <task-id> [--status S] [--branch B] [--worktree W]
#                                              [--provider P] [--notes N] [--bump-attempts]
#   objective-state.sh tasks <id>
#   objective-state.sh ready <id>              # task ids whose dependencies are all completed
#   objective-state.sh next <id>               # first ready task id, or empty
#   objective-state.sh integrate-ready <id>    # {"ready":bool,"blocking":[...]}
#   objective-state.sh validate <id>           # structural + graph validation
#   objective-state.sh -h | --help
#
# Environment:
#   OBJECTIVES_ROOT   override state root (default: <repo root>/.dev-files/objectives)
#
# Exit codes: 0 ok · 1 usage/argument error · 2 not found · 3 dependency missing
#             4 validation failed
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./default-branch.sh
. "$SCRIPT_DIR/default-branch.sh"

usage() {
  sed -n '2,40p' "$0" | sed 's/^# \?//'
  exit "${1:-0}"
}

die() { printf 'ERROR: %s\n' "$1" >&2; exit "${2:-1}"; }

if [[ $# -eq 0 || "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage 0
fi

# --- state root ------------------------------------------------------------

resolve_root() {
  if [[ -n "${OBJECTIVES_ROOT:-}" ]]; then
    printf '%s\n' "$OBJECTIVES_ROOT"
    return 0
  fi
  local repo
  if repo="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    printf '%s/.dev-files/objectives\n' "$repo"
  else
    printf '%s/.dev-files/objectives\n' "$PWD"
  fi
}

ROOT="$(resolve_root)"

have_jq() { command -v jq >/dev/null 2>&1; }

require_jq() {
  have_jq || die "jq is required for '$1'. Install jq, or edit the JSON under $ROOT by hand." 3
}

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

obj_dir() { printf '%s/%s\n' "$ROOT" "$1"; }

require_obj() {
  [[ -f "$(obj_dir "$1")/objective.json" ]] || die "no objective '$1' under $ROOT" 2
}

valid_id() { [[ "$1" =~ ^[a-z0-9][a-z0-9-]*$ ]]; }
valid_task_id() { [[ "$1" =~ ^task-[0-9]{3}$ ]]; }

OBJ_STATUSES="draft active integrating reviewing delivering completed blocked abandoned"
# An objective is "active" until it is finished or abandoned.
ACTIVE_STATUSES="draft active integrating reviewing delivering blocked"
TASK_STATUSES="pending ready running blocked completed failed cancelled"
ROLES="planner orchestrator implementer test-engineer reviewer security-reviewer performance-reviewer debugger integrator research-agent"
TIERS="edit worker integration delivery"

in_list() {
  local needle="$1" item
  shift
  for item in $1; do
    if [[ "$item" == "$needle" ]]; then return 0; fi
  done
  return 1
}

# --- commands --------------------------------------------------------------

cmd_init() {
  local id="${1:-}"; shift || true
  [[ -n "$id" ]] || die "init requires an objective id"
  valid_id "$id" || die "objective id must match ^[a-z0-9][a-z0-9-]*$ (got '$id')"
  local title="" base="" integ=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --title) title="${2:-}"; shift 2 ;;
      --base-branch) base="${2:-}"; shift 2 ;;
      --integration-branch) integ="${2:-}"; shift 2 ;;
      *) die "init: unknown option '$1'" ;;
    esac
  done
  [[ -n "$title" ]] || die "init requires --title"
  if [[ -z "$base" ]]; then
    # Never default to a literal: base_branch is recorded in objective.json and
    # every worker branch is cut from it, so a wrong name is wrong for the whole
    # objective. Fail and let the caller pass --base-branch instead.
    base="$(resolve_default_branch ".")" \
      || die "cannot resolve the default branch — pass --base-branch <branch>" 1
  fi
  [[ -n "$integ" ]] || integ="objective/$id"

  local dir; dir="$(obj_dir "$id")"
  if [[ -f "$dir/objective.json" ]]; then die "objective '$id' already exists at $dir"; fi
  mkdir -p "$dir/tasks" "$dir/handoffs"

  require_jq init
  jq -n --arg id "$id" --arg title "$title" --arg base "$base" \
        --arg integ "$integ" --arg now "$(now_iso)" '{
    schema_version: 1, id: $id, title: $title, base_branch: $base,
    integration_branch: $integ, status: "draft", tasks: [],
    delivery: { strategy: "single-pr" }, created: $now, updated: $now
  }' > "$dir/objective.json"
  cat "$dir/objective.json"
}

cmd_path() { require_obj "$1"; obj_dir "$1"; }

cmd_show() { require_obj "$1"; cat "$(obj_dir "$1")/objective.json"; }

cmd_list() {
  local dir id
  if [[ ! -d "$ROOT" ]]; then printf '[]\n'; return 0; fi
  if ! have_jq; then
    # Degraded: ids only, one per line, on stderr-flagged plain output.
    printf 'jq absent — listing ids only\n' >&2
    for dir in "$ROOT"/*/; do
      [[ -f "$dir/objective.json" ]] || continue
      basename "$dir"
    done
    return 0
  fi
  local out="[]"
  for dir in "$ROOT"/*/; do
    [[ -f "${dir}objective.json" ]] || continue
    id="$(basename "$dir")"
    out="$(jq -n --argjson acc "$out" --slurpfile o "${dir}objective.json" \
      '$acc + [{ id: $o[0].id, title: $o[0].title, status: $o[0].status,
                 tasks: ($o[0].tasks | length),
                 integration_branch: $o[0].integration_branch }]')"
  done
  printf '%s\n' "$out" | jq .
}

cmd_set_status() {
  local id="${1:-}" status="${2:-}"
  require_obj "$id"
  in_list "$status" "$OBJ_STATUSES" || die "status must be one of: $OBJ_STATUSES"
  require_jq set-status
  local f; f="$(obj_dir "$id")/objective.json"
  jq --arg s "$status" --arg now "$(now_iso)" '.status = $s | .updated = $now' "$f" > "$f.tmp"
  mv "$f.tmp" "$f"
  cat "$f"
}

cmd_set_delivery() {
  local id="${1:-}"; shift || true
  require_obj "$id"
  require_jq set-delivery
  local f; f="$(obj_dir "$id")/objective.json"
  local filter='.updated = $now' strategy="" reason="" automerge="" prurl=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --strategy) strategy="${2:-}"; shift 2 ;;
      --reason) reason="${2:-}"; shift 2 ;;
      --auto-merge) automerge="${2:-}"; shift 2 ;;
      --pr-url) prurl="${2:-}"; shift 2 ;;
      *) die "set-delivery: unknown option '$1'" ;;
    esac
  done
  if [[ -n "$strategy" ]]; then
    in_list "$strategy" "single-pr multi-pr direct-commit none" \
      || die "strategy must be one of: single-pr multi-pr direct-commit none"
    filter="$filter | .delivery.strategy = \$strategy"
    if [[ "$strategy" != "single-pr" && -z "$reason" ]]; then
      local existing; existing="$(jq -r '.delivery.exception_reason // ""' "$f")"
      [[ -n "$existing" ]] || die "strategy '$strategy' needs --reason naming an exception from core/policies/delivery.md" 4
    fi
  fi
  if [[ -n "$reason" ]]; then filter="$filter | .delivery.exception_reason = \$reason"; fi
  if [[ -n "$automerge" ]]; then
    in_list "$automerge" "true false" || die "--auto-merge takes true or false"
    filter="$filter | .delivery.auto_merge = (\$automerge == \"true\")"
  fi
  if [[ -n "$prurl" ]]; then filter="$filter | .delivery.pr_url = \$prurl"; fi
  jq --arg now "$(now_iso)" --arg strategy "$strategy" --arg reason "$reason" \
     --arg automerge "$automerge" --arg prurl "$prurl" "$filter" "$f" > "$f.tmp"
  mv "$f.tmp" "$f"
  cat "$f"
}

next_task_id() {
  local dir="$1" n=1 candidate
  while :; do
    candidate="$(printf 'task-%03d' "$n")"
    [[ -f "$dir/tasks/$candidate.json" ]] || { printf '%s\n' "$candidate"; return 0; }
    n=$((n + 1))
  done
}

cmd_task_add() {
  local id="${1:-}"; shift || true
  require_obj "$id"
  require_jq task-add
  local dir; dir="$(obj_dir "$id")"
  local role="" scope="" deps="" tier="worker" title="" tid=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --role) role="${2:-}"; shift 2 ;;
      --scope) scope="${2:-}"; shift 2 ;;
      --depends-on) deps="${2:-}"; shift 2 ;;
      --tier) tier="${2:-}"; shift 2 ;;
      --title) title="${2:-}"; shift 2 ;;
      --task-id) tid="${2:-}"; shift 2 ;;
      *) die "task-add: unknown option '$1'" ;;
    esac
  done
  [[ -n "$role" ]] || die "task-add requires --role"
  in_list "$role" "$ROLES" || die "role must be one of: $ROLES"
  [[ -n "$scope" ]] || die "task-add requires --scope (globs this task may write)"
  in_list "$tier" "$TIERS" || die "--tier must be one of: $TIERS"
  if [[ -n "$tid" ]]; then
    valid_task_id "$tid" || die "--task-id must match ^task-[0-9]{3}$"
    if [[ -f "$dir/tasks/$tid.json" ]]; then die "$tid already exists"; fi
  else
    tid="$(next_task_id "$dir")"
  fi

  local dep
  for dep in ${deps//,/ }; do
    valid_task_id "$dep" || die "depends_on entry '$dep' must match ^task-[0-9]{3}$"
    [[ -f "$dir/tasks/$dep.json" ]] || die "depends_on references unknown task '$dep'" 2
  done

  local status="pending"
  if [[ -z "$deps" ]]; then status="ready"; fi

  jq -n --arg id "$tid" --arg oid "$id" --arg title "$title" --arg role "$role" \
        --arg tier "$tier" --arg status "$status" \
        --arg scope "$scope" --arg deps "$deps" '{
    schema_version: 1, id: $id, objective_id: $oid, role: $role,
    depends_on: ($deps | if . == "" then [] else split(",") end),
    scope: ($scope | split(",") | map(select(length > 0))),
    validation_tier: $tier, status: $status, attempts: 0
  } | if $title == "" then . else .title = $title end' > "$dir/tasks/$tid.json"

  local f="$dir/objective.json"
  jq --arg t "$tid" --arg now "$(now_iso)" \
     '.tasks = (.tasks + [$t] | unique) | .updated = $now' "$f" > "$f.tmp"
  mv "$f.tmp" "$f"
  cat "$dir/tasks/$tid.json"
}

require_task() {
  [[ -f "$(obj_dir "$1")/tasks/$2.json" ]] || die "no task '$2' in objective '$1'" 2
}

cmd_task_show() { require_obj "$1"; require_task "$1" "$2"; cat "$(obj_dir "$1")/tasks/$2.json"; }

cmd_tasks() {
  require_obj "$1"
  require_jq tasks
  local dir; dir="$(obj_dir "$1")"
  find "$dir/tasks" -name 'task-*.json' -print0 2>/dev/null \
    | sort -z | xargs -0 -r jq -s '.' | jq 'map({id, role, status, depends_on, validation_tier, branch: (.branch // null)})'
}

cmd_task_set() {
  local id="${1:-}" tid="${2:-}"; shift 2 || true
  require_obj "$id"; require_task "$id" "$tid"
  require_jq task-set
  local f; f="$(obj_dir "$id")/tasks/$tid.json"
  local filter='.' status="" branch="" worktree="" provider="" notes="" bump=0
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --status) status="${2:-}"; shift 2 ;;
      --branch) branch="${2:-}"; shift 2 ;;
      --worktree) worktree="${2:-}"; shift 2 ;;
      --provider) provider="${2:-}"; shift 2 ;;
      --notes) notes="${2:-}"; shift 2 ;;
      --bump-attempts) bump=1; shift ;;
      *) die "task-set: unknown option '$1'" ;;
    esac
  done
  if [[ -n "$status" ]]; then
    in_list "$status" "$TASK_STATUSES" || die "task status must be one of: $TASK_STATUSES"
    filter="$filter | .status = \$status"
  fi
  if [[ -n "$branch" ]]; then filter="$filter | .branch = \$branch"; fi
  if [[ -n "$worktree" ]]; then filter="$filter | .worktree = \$worktree"; fi
  if [[ -n "$provider" ]]; then
    in_list "$provider" "current claude codex cursor gemini opencode" \
      || die "provider must be one of: current claude codex cursor gemini opencode"
    filter="$filter | .provider = \$provider"
  fi
  if [[ -n "$notes" ]]; then filter="$filter | .notes = \$notes"; fi
  if [[ $bump -eq 1 ]]; then filter="$filter | .attempts = ((.attempts // 0) + 1)"; fi
  jq --arg status "$status" --arg branch "$branch" --arg worktree "$worktree" \
     --arg provider "$provider" --arg notes "$notes" "$filter" "$f" > "$f.tmp"
  mv "$f.tmp" "$f"
  # A completed task can unblock dependents: promote pending -> ready.
  refresh_ready "$id"
  cat "$f"
}

# Promote every pending task whose dependencies are all completed to ready.
refresh_ready() {
  local dir; dir="$(obj_dir "$1")"
  local tf tid deps dep all_done status
  for tf in "$dir"/tasks/task-*.json; do
    [[ -f "$tf" ]] || continue
    status="$(jq -r '.status' "$tf")"
    [[ "$status" == "pending" ]] || continue
    tid="$(jq -r '.id' "$tf")"
    deps="$(jq -r '.depends_on[]?' "$tf")"
    all_done=1
    for dep in $deps; do
      [[ -f "$dir/tasks/$dep.json" ]] || { all_done=0; break; }
      [[ "$(jq -r '.status' "$dir/tasks/$dep.json")" == "completed" ]] || { all_done=0; break; }
    done
    if [[ $all_done -eq 1 ]]; then
      jq '.status = "ready"' "$tf" > "$tf.tmp" && mv "$tf.tmp" "$tf"
      printf 'promoted %s to ready\n' "$tid" >&2
    fi
  done
}

cmd_ready() {
  require_obj "$1"
  require_jq ready
  refresh_ready "$1"
  local dir; dir="$(obj_dir "$1")"
  find "$dir/tasks" -name 'task-*.json' -print0 2>/dev/null \
    | sort -z | xargs -0 -r jq -s 'map(select(.status == "ready") | {id, role, scope, validation_tier})'
}

cmd_next() {
  local out; out="$(cmd_ready "$1")"
  printf '%s\n' "$out" | jq -r '.[0].id // empty'
}

cmd_integrate_ready() {
  require_obj "$1"
  require_jq integrate-ready
  local dir; dir="$(obj_dir "$1")"
  find "$dir/tasks" -name 'task-*.json' -print0 2>/dev/null \
    | sort -z | xargs -0 -r jq -s --arg dir "$dir" '
      [ .[] | select(.status != "completed" and .status != "cancelled") ] as $open
      | { ready: ($open | length == 0),
          blocking: ($open | map({id, status})) }'
}

cmd_validate() {
  local id="${1:-}"
  require_obj "$id"
  require_jq validate
  local dir errs=0
  dir="$(obj_dir "$id")"
  local f="$dir/objective.json"

  jq -e '.id and .title and .base_branch and .integration_branch and .status and (.tasks | type == "array")' "$f" >/dev/null \
    || { echo "objective.json missing a required field" >&2; errs=$((errs + 1)); }

  local status; status="$(jq -r '.status' "$f")"
  in_list "$status" "$OBJ_STATUSES" || { echo "objective status '$status' not in enum" >&2; errs=$((errs + 1)); }

  local strategy; strategy="$(jq -r '.delivery.strategy // "single-pr"' "$f")"
  if [[ "$strategy" != "single-pr" ]]; then
    jq -e '.delivery.exception_reason // empty' "$f" >/dev/null \
      || { echo "delivery.strategy=$strategy without delivery.exception_reason" >&2; errs=$((errs + 1)); }
  fi

  local listed tid tf dep
  listed="$(jq -r '.tasks[]?' "$f")"
  for tid in $listed; do
    [[ -f "$dir/tasks/$tid.json" ]] || { echo "objective lists $tid but tasks/$tid.json is missing" >&2; errs=$((errs + 1)); }
  done

  for tf in "$dir"/tasks/task-*.json; do
    [[ -f "$tf" ]] || continue
    tid="$(jq -r '.id' "$tf")"
    jq -e '.role and (.depends_on|type=="array") and (.scope|type=="array" and length>0) and .validation_tier and .status' "$tf" >/dev/null \
      || { echo "$tid: missing a required field" >&2; errs=$((errs + 1)); }
    in_list "$(jq -r '.status' "$tf")" "$TASK_STATUSES" || { echo "$tid: bad status" >&2; errs=$((errs + 1)); }
    in_list "$(jq -r '.role' "$tf")" "$ROLES" || { echo "$tid: bad role" >&2; errs=$((errs + 1)); }
    in_list "$(jq -r '.validation_tier' "$tf")" "$TIERS" || { echo "$tid: bad validation_tier" >&2; errs=$((errs + 1)); }
    grep -qx -- "$tid" <<<"$listed" || { echo "$tid: not listed in objective.tasks[]" >&2; errs=$((errs + 1)); }
    for dep in $(jq -r '.depends_on[]?' "$tf"); do
      if [[ "$dep" == "$tid" ]]; then echo "$tid: depends on itself" >&2; errs=$((errs + 1)); fi
      [[ -f "$dir/tasks/$dep.json" ]] || { echo "$tid: depends on unknown $dep" >&2; errs=$((errs + 1)); }
    done
  done

  # Concurrent tasks must not share write scope (spec section 11 conflict policy).
  local overlap
  overlap="$(find "$dir/tasks" -name 'task-*.json' -print0 2>/dev/null | sort -z | xargs -0 -r jq -s '
    [ .[] | select(.status != "completed" and .status != "cancelled") ] as $open
    | [ $open[] as $a | $open[] as $b
        | select($a.id < $b.id)
        | select(($a.depends_on | index($b.id)) == null and ($b.depends_on | index($a.id)) == null)
        | select([ $a.scope[] as $s | $b.scope[] | select(. == $s) ] | length > 0)
        | "\($a.id) and \($b.id) share write scope" ] | .[]' -r)"
  if [[ -n "$overlap" ]]; then
    printf '%s\n' "$overlap" >&2
    errs=$((errs + 1))
  fi

  if [[ $errs -gt 0 ]]; then
    jq -n --arg id "$id" --argjson n "$errs" '{objective: $id, valid: false, errors: $n}'
    exit 4
  fi
  jq -n --arg id "$id" '{objective: $id, valid: true, errors: 0}'
}


# --- contract commands: active / set / add-task -----------------------------
#
# These three are deliberately jq-free where they can be (`active` especially):
# start-dev calls `active` to decide whether to suppress PR creation, so it must
# answer on any machine, cheaply, without stdin, and without jq installed.

# Read one top-level string field out of an objective.json without jq.
obj_field() {
  grep -o "\"$2\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" "$1" 2>/dev/null \
    | head -1 | sed 's/.*"\([^"]*\)"[[:space:]]*$/\1/'
}

is_active_status() { in_list "$1" "$ACTIVE_STATUSES"; }

cmd_active() {
  [[ -d "$ROOT" ]] || return 1

  # 1. The current branch names an objective: objective/<id> or worker/<id>/NNN.
  local cur="" candidate=""
  cur="$(git branch --show-current 2>/dev/null || true)"
  case "$cur" in
    objective/*) candidate="${cur#objective/}" ;;
    worker/*)    candidate="${cur#worker/}"; candidate="${candidate%%/*}" ;;
  esac
  if [[ -n "$candidate" && -f "$ROOT/$candidate/objective.json" ]]; then
    if is_active_status "$(obj_field "$ROOT/$candidate/objective.json" status)"; then
      printf '%s\n' "$candidate"
      return 0
    fi
  fi

  # 2. Otherwise the most recently updated active objective. `updated` is
  #    ISO 8601, so lexicographic order is chronological order.
  local dir id status updated best="" best_updated="" count=0
  for dir in "$ROOT"/*/; do
    [[ -f "${dir}objective.json" ]] || continue
    status="$(obj_field "${dir}objective.json" status)"
    is_active_status "$status" || continue
    id="$(basename "$dir")"
    count=$((count + 1))
    updated="$(obj_field "${dir}objective.json" updated)"
    [[ -n "$updated" ]] || updated="$(obj_field "${dir}objective.json" created)"
    if [[ -z "$best" || "$updated" > "$best_updated" ]]; then
      best="$id"; best_updated="$updated"
    fi
  done

  [[ -n "$best" ]] || return 1
  if [[ $count -gt 1 ]]; then
    printf 'note: %d active objectives; picked the most recently updated (%s). Pass an id explicitly to override.\n' \
      "$count" "$best" >&2
  fi
  printf '%s\n' "$best"
}

# set <id> <dotted.key> <value> — in-place field update on objective.json.
cmd_set() {
  local id="${1:-}" key="${2:-}" value="${3:-}"
  [[ -n "$id" && -n "$key" && $# -ge 3 ]] || die "set requires <id> <dotted.key> <value>"
  require_obj "$id"
  require_jq set
  local f; f="$(obj_dir "$id")/objective.json"

  # Guard the enums the schema constrains, so a typo fails here and not three
  # steps later when something reads the field back.
  case "$key" in
    status)
      in_list "$value" "$OBJ_STATUSES" || die "status must be one of: $OBJ_STATUSES" ;;
    delivery.strategy)
      in_list "$value" "single-pr multi-pr direct-commit none" \
        || die "delivery.strategy must be one of: single-pr multi-pr direct-commit none" ;;
    id)
      die "id is the directory name and cannot be changed with set" ;;
  esac

  # Type inference: true/false -> boolean, integer -> number, valid JSON
  # object/array -> raw, everything else -> string.
  local jsonval=""
  if [[ "$value" == "true" || "$value" == "false" ]]; then
    jsonval="$value"
  elif [[ "$value" =~ ^-?[0-9]+$ ]]; then
    jsonval="$value"
  elif [[ "$value" == '{'* || "$value" == '['* ]] && jq -e . >/dev/null 2>&1 <<<"$value"; then
    jsonval="$value"
  fi
  if [[ -z "$jsonval" ]]; then
    jq --arg k "$key" --arg v "$value" --arg now "$(now_iso)" \
       'setpath($k | split("."); $v) | .updated = $now' "$f" > "$f.tmp"
  else
    jq --arg k "$key" --argjson v "$jsonval" --arg now "$(now_iso)" \
       'setpath($k | split("."); $v) | .updated = $now' "$f" > "$f.tmp"
  fi
  mv "$f.tmp" "$f"
  cat "$f"
}

# add-task <id> <task.json> — register a task supplied as a JSON file.
cmd_add_task() {
  local id="${1:-}" src="${2:-}"
  [[ -n "$id" && -n "$src" ]] || die "add-task requires <id> <task.json>"
  require_obj "$id"
  [[ -f "$src" ]] || die "no such task file: $src" 2
  require_jq add-task
  jq -e . "$src" >/dev/null 2>&1 || die "$src is not valid JSON" 4

  local dir; dir="$(obj_dir "$id")"
  mkdir -p "$dir/tasks"

  local tid; tid="$(jq -r '.id // ""' "$src")"
  if [[ -z "$tid" || -f "$dir/tasks/$tid.json" ]]; then
    tid="$(next_task_id "$dir")"
  fi
  valid_task_id "$tid" || die "task id '$tid' must match ^task-[0-9]{3}$"

  local role tier status
  role="$(jq -r '.role // ""' "$src")"
  tier="$(jq -r '.validation_tier // "worker"' "$src")"
  status="$(jq -r '.status // ""' "$src")"
  [[ -n "$role" ]] || die "$src has no role"
  in_list "$role" "$ROLES" || die "role must be one of: $ROLES"
  in_list "$tier" "$TIERS" || die "validation_tier must be one of: $TIERS"
  jq -e '(.scope | type == "array") and (.scope | length > 0)' "$src" >/dev/null \
    || die "$src needs a non-empty scope[] — the paths this task may write" 4

  local dep
  for dep in $(jq -r '.depends_on[]?' "$src"); do
    valid_task_id "$dep" || die "depends_on entry '$dep' must match ^task-[0-9]{3}$"
    [[ -f "$dir/tasks/$dep.json" ]] || die "depends_on references unknown task '$dep'" 2
  done

  if [[ -z "$status" ]]; then
    if jq -e '(.depends_on // []) | length == 0' "$src" >/dev/null; then
      status="ready"
    else
      status="pending"
    fi
  fi
  in_list "$status" "$TASK_STATUSES" || die "status must be one of: $TASK_STATUSES"

  jq --arg tid "$tid" --arg oid "$id" --arg tier "$tier" --arg status "$status" '
    . + { schema_version: (.schema_version // 1), id: $tid, objective_id: $oid,
          validation_tier: $tier, status: $status,
          depends_on: (.depends_on // []), attempts: (.attempts // 0) }' \
    "$src" > "$dir/tasks/$tid.json"

  local f="$dir/objective.json"
  jq --arg t "$tid" --arg now "$(now_iso)" \
     '.tasks = (.tasks + [$t] | unique) | .updated = $now' "$f" > "$f.tmp"
  mv "$f.tmp" "$f"
  cat "$dir/tasks/$tid.json"
}

# --- dispatch --------------------------------------------------------------

COMMAND="$1"; shift
case "$COMMAND" in
  init)             cmd_init "$@" ;;
  active)           [[ $# -eq 0 ]] || die "active takes no arguments"; cmd_active ;;
  set)              cmd_set "$@" ;;
  add-task)         [[ $# -eq 2 ]] || die "add-task requires <id> <task.json>"; cmd_add_task "$1" "$2" ;;
  show)             [[ $# -eq 1 ]] || die "show requires <id>"; cmd_show "$1" ;;
  path)             [[ $# -eq 1 ]] || die "path requires <id>"; cmd_path "$1" ;;
  list)             cmd_list ;;
  set-status)       [[ $# -eq 2 ]] || die "set-status requires <id> <status>"; cmd_set_status "$1" "$2" ;;
  set-delivery)     cmd_set_delivery "$@" ;;
  task-add)         cmd_task_add "$@" ;;
  task-show)        [[ $# -eq 2 ]] || die "task-show requires <id> <task-id>"; cmd_task_show "$1" "$2" ;;
  task-set)         cmd_task_set "$@" ;;
  tasks)            [[ $# -eq 1 ]] || die "tasks requires <id>"; cmd_tasks "$1" ;;
  ready)            [[ $# -eq 1 ]] || die "ready requires <id>"; cmd_ready "$1" ;;
  next)             [[ $# -eq 1 ]] || die "next requires <id>"; cmd_next "$1" ;;
  integrate-ready)  [[ $# -eq 1 ]] || die "integrate-ready requires <id>"; cmd_integrate_ready "$1" ;;
  validate)         [[ $# -eq 1 ]] || die "validate requires <id>"; cmd_validate "$1" ;;
  *) die "unknown command '$COMMAND' (try --help)" ;;
esac
