#!/usr/bin/env bash
# objective-timeline.sh — rebuild an objective's timeline from its state files and
# name the failure classes the files show. Deterministic, offline, read-only.
#
# Usage:
#   objective-timeline.sh <objective-dir> [--repo <path>] [--markdown]
#   objective-timeline.sh -h | --help
#
# <objective-dir> is .dev-files/objectives/<id>/ (objective.json, tasks/, handoffs/).
# Output is one JSON document on stdout:
#   objective     id, title, status, branches, created/updated, delivery
#   tasks[]       each task merged with its handoff (present or not) and file mtimes
#   timeline[]    objective/task/handoff/snapshot events sorted by time
#   snapshots     the pre-compaction snapshot, when one names this objective
#   findings[]    detected failure classes: class, severity, task, at, detail, evidence[]
#   first_cause   the earliest high-severity finding (or the earliest finding)
#   next_command  the one command that moves the objective forward
# --markdown renders the same facts as a report skeleton instead of JSON.
#
# Failure classes (references/failure-classes.md has the reasoning for each):
#   task-completed-without-handoff   task marked completed, no handoff file (invariant 6)
#   worker-stopped-without-handoff   task still running, no handoff — a worker that returned
#                                    early, or a session that died without a rate-limit record
#   rate-limit-death                 the same, with a .dev-files/handoffs/rate-limit-*.json record
#                                    (written by hooks/rate-limit-handoff.sh) naming this objective
#   completed-without-validation     handoff says completed with an empty validation[]
#   completed-with-failing-validation handoff says completed but a validation entry failed
#   integrated-around-partial        a partial/failed/blocked handoff was treated as done
#   shared-branch                    two tasks name the same branch
#   dependency-order-violation       a task ran before a dependency completed
#   integration-behind-workers       a completed task's branch has commits the integration
#                                    branch lacks (needs git; skipped otherwise)
#   task-state-stale                 a handoff exists but the task status never moved
#   stuck-running                    one task still running while every other is terminal
#   scope-escape                     files_changed outside the task's scope[]
#   objective-blocked                objective.status is blocked
#   handoff-without-task             a handoff for a task id that has no task file
#
# Also read: .dev-files/compaction/latest.md (hooks/precompact-snapshot.sh) and
# .dev-files/handoffs/rate-limit-*.json, both relative to the repo root (--repo, else git).
#
# Environment: none. Timestamps come from the files (created/updated/completed) and from
# file mtimes where the schema records no time — a task file's mtime is its LAST change.
#
# Exit codes: 0 ok (with or without findings) · 1 usage · 2 objective not found · 3 jq missing
set -euo pipefail

usage() {
  if [[ "${1:-0}" == "0" ]]; then
    sed -n '2,45p' "$0" | sed 's/^# \?//'
  else
    sed -n '2,45p' "$0" | sed 's/^# \?//' >&2
  fi
  exit "${1:-0}"
}

die() { printf 'ERROR: %s\n' "$1" >&2; exit "${2:-1}"; }

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then usage 0; fi
[[ $# -gt 0 ]] || usage 1

DIR=""
REPO=""
MARKDOWN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --markdown) MARKDOWN=true; shift ;;
    -*) die "unknown option '$1'" ;;
    *) [[ -z "$DIR" ]] || die "exactly one objective directory expected"; DIR="$1"; shift ;;
  esac
done
[[ -n "$DIR" ]] || die "an objective directory is required (.dev-files/objectives/<id>)"
[[ -f "$DIR/objective.json" ]] || die "no objective.json under $DIR" 2
command -v jq >/dev/null 2>&1 || die "jq is required" 3
DIR="$(cd "$DIR" && pwd)"

if [[ -z "$REPO" ]]; then
  REPO="$(git -C "$DIR" rev-parse --show-toplevel 2>/dev/null || true)"
  [[ -n "$REPO" ]] || REPO="$(cd "$DIR/../../.." 2>/dev/null && pwd || printf '%s' "$DIR")"
fi

# --- helpers ---------------------------------------------------------------

# mtime_iso <file> — ISO 8601 UTC from the file's mtime. GNU and BSD stat/date.
mtime_iso() {
  local s
  s="$(stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0)"
  date -u -d "@$s" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -r "$s" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || printf '1970-01-01T00:00:00Z\n'
}

# wrap <kind> <file> — {kind, path (relative to DIR), mtime, doc} or nothing when unparseable.
wrap() {
  local kind="$1" f="$2" rel="${2#"$DIR"/}" m
  m="$(mtime_iso "$f")"
  if jq -e . "$f" >/dev/null 2>&1; then
    jq -c --arg k "$kind" --arg p "$rel" --arg m "$m" '{kind: $k, path: $p, mtime: $m, doc: .}' "$f"
  else
    jq -nc --arg k "$kind" --arg p "$rel" --arg m "$m" '{kind: $k, path: $p, mtime: $m, doc: null, unparseable: true}'
  fi
}

collect() {
  local kind="$1" sub="$2" f
  printf '['
  local first=1
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    [[ $first -eq 1 ]] || printf ','
    first=0
    wrap "$kind" "$f"
  done < <(find "$DIR/$sub" -maxdepth 1 -name 'task-*.json' -print 2>/dev/null | sort)
  printf ']'
}

TASKS_JSON="$(collect task tasks)"
HANDOFFS_JSON="$(collect handoff handoffs)"
OBJ_JSON="$(jq -c . "$DIR/objective.json")"
OBJ_MTIME="$(mtime_iso "$DIR/objective.json")"

# --- compaction snapshot ---------------------------------------------------

SNAP_JSON='null'
SNAP="$REPO/.dev-files/compaction/latest.md"
if [[ -f "$SNAP" ]]; then
  when="$(sed -n 's/^- when: //p' "$SNAP" | head -1)"
  snap_obj="$(sed -n 's/^- open objective: //p' "$SNAP" | head -1)"
  snap_branch="$(sed -n 's/^- branch: //p' "$SNAP" | head -1)"
  [[ -n "$when" ]] || when="$(mtime_iso "$SNAP")"
  SNAP_JSON="$(jq -nc --arg p ".dev-files/compaction/latest.md" --arg w "$when" \
    --arg o "$snap_obj" --arg b "$snap_branch" \
    '{path: $p, when: $w, objective: ($o | select(. != "")), branch: ($b | select(. != ""))}')"
fi

# --- rate-limit records (written by hooks/rate-limit-handoff.sh) -------------

RL_JSON='[]'
if [[ -d "$REPO/.dev-files/handoffs" ]]; then
  RL_JSON="$(
    printf '['
    first=1
    while IFS= read -r f; do
      [[ -n "$f" ]] || continue
      [[ $first -eq 1 ]] || printf ','
      first=0
      rel="${f#"$REPO"/}"
      if jq -e . "$f" >/dev/null 2>&1; then
        jq -c --arg p "$rel" --arg m "$(mtime_iso "$f")" '{path: $p, mtime: $m, doc: .}' "$f"
      else
        jq -nc --arg p "$rel" --arg m "$(mtime_iso "$f")" '{path: $p, mtime: $m, doc: null}'
      fi
    done < <(find "$REPO/.dev-files/handoffs" -maxdepth 1 -name 'rate-limit-*.json' -print 2>/dev/null | sort)
    printf ']'
  )"
fi

# --- git facts (optional) --------------------------------------------------

GIT_JSON='{"available":false}'
if command -v git >/dev/null 2>&1 && git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1; then
  integ="$(jq -r '.integration_branch // ""' <<<"$OBJ_JSON")"
  integ_exists=false
  if [[ -n "$integ" ]] && git -C "$REPO" rev-parse --verify -q "refs/heads/$integ" >/dev/null 2>&1; then
    integ_exists=true
  fi
  behind='[]'
  dirty='[]'
  missing_branches='[]'
  while IFS=$'\t' read -r tid branch worktree hstatus; do
    [[ -n "$tid" ]] || continue
    if [[ -n "$branch" && "$branch" != "null" ]]; then
      if git -C "$REPO" rev-parse --verify -q "refs/heads/$branch" >/dev/null 2>&1; then
        if [[ "$integ_exists" == true && "$hstatus" == "completed" ]]; then
          n="$(git -C "$REPO" rev-list --count "$integ..$branch" 2>/dev/null || echo 0)"
          if [[ "${n:-0}" -gt 0 ]]; then
            behind="$(jq -c --arg t "$tid" --arg b "$branch" --argjson n "$n" '. + [{task: $t, branch: $b, commits_ahead: $n}]' <<<"$behind")"
          fi
        fi
      else
        missing_branches="$(jq -c --arg t "$tid" --arg b "$branch" '. + [{task: $t, branch: $b}]' <<<"$missing_branches")"
      fi
    fi
    if [[ -n "$worktree" && "$worktree" != "null" ]]; then
      wt="$worktree"
      [[ "$wt" == /* ]] || wt="$REPO/$wt"
      if [[ -d "$wt" ]] && [[ -n "$(git -C "$wt" status --porcelain 2>/dev/null || true)" ]]; then
        dirty="$(jq -c --arg t "$tid" '. + [$t]' <<<"$dirty")"
      fi
    fi
  done < <(jq -r --argjson h "$HANDOFFS_JSON" '
      .[] | .doc as $t | select($t != null)
      | ($h | map(select(.doc.task_id == $t.id)) | .[0].doc.status // "") as $hs
      | [$t.id, ($t.branch // "null"), ($t.worktree // "null"), $hs] | @tsv' <<<"$TASKS_JSON")
  GIT_JSON="$(jq -nc --argjson ie "$integ_exists" --argjson b "$behind" --argjson d "$dirty" \
    --argjson m "$missing_branches" --arg i "$integ" \
    '{available: true, integration_branch: $i, integration_branch_exists: $ie,
      behind: $b, dirty_worktrees: $d, missing_branches: $m}')"
fi

# --- the analysis, in one jq program ---------------------------------------

JQ_PROGRAM="$(cat <<'JQ'
  def sevrank: {critical: 0, high: 1, medium: 2, low: 3}[.] // 9;
  def terminal: . as $s | ["completed", "cancelled", "failed"] | index($s) != null;
  def glob_re: gsub("\\."; "\\.") | gsub("\\*\\*/"; "(.*/)?") | gsub("\\*\\*"; ".*") | gsub("\\*"; "[^/]*") | gsub("\\?"; "[^/]");
  def in_scope($scope): . as $p | any($scope[]; . as $g | ($p == $g) or ($p | test("^" + ($g | glob_re) + "$")));
  def objective_terminalish: ["integrating", "reviewing", "delivering", "completed"] | index($obj.status) != null;

  ($handoffs | map(select(.doc != null)) | map({key: .doc.task_id, value: .}) | from_entries) as $hby

  | ($tasks | map(select(.doc != null)) | map(
      .doc as $t | . as $tf
      | ($hby[$t.id]) as $h
      | {
          id: $t.id, title: ($t.title // null), role: $t.role, status: $t.status,
          depends_on: ($t.depends_on // []), scope: ($t.scope // []),
          branch: ($t.branch // null), worktree: ($t.worktree // null),
          attempts: ($t.attempts // 0), validation_tier: $t.validation_tier,
          file: $tf.path, file_mtime: $tf.mtime,
          handoff: (if $h == null then {present: false} else {
            present: true, file: $h.path, file_mtime: $h.mtime,
            status: $h.doc.status, summary: ($h.doc.summary // null),
            branch: ($h.doc.branch // null),
            at: ($h.doc.completed // $h.mtime),
            commits: (($h.doc.commits // []) | length),
            validation: (($h.doc.validation // []) | {
              total: length,
              pass: map(select(.result == "pass")) | length,
              fail: map(select(.result == "fail")) | length,
              skipped: map(select(.result == "skipped")) | length }),
            files_changed: (($h.doc.files_changed // []) | map(.path)),
            blocking_followups: (($h.doc.followups // []) | map(select(.blocking == true) | .item)),
            risks: (($h.doc.risks // []) | map({risk, severity: (.severity // null)}))
          } end)
        })) as $T

  # rate-limit records that name this objective, or name no objective but a branch of it
  | ($ratelimits | map(select(.doc != null and (.doc.kind // "") == "rate-limit-handoff"))
     | map(select(.doc.objective == $obj.id
                  or (.doc.objective == null and .doc.branch != null
                      and (.doc.branch as $b | [$obj.integration_branch] + ($T | map(.branch) | map(select(. != null))) | index($b) != null))))
     | map({path: .path, at: (.doc.written_at // .mtime), branch: (.doc.branch // null),
            uncommitted: (.doc.uncommitted // 0), resume: (.doc.resume // null)})
     | sort_by(.at)) as $RL

  | ([ {at: ($obj.created // $objmtime), order: 0, event: "objective-created", task: null,
        detail: "objective \($obj.id) created (base \($obj.base_branch), integration \($obj.integration_branch))"} ]
     + ($T | map({at: .file_mtime, order: 1, event: "task-state", task: .id,
                  detail: "status=\(.status) branch=\(.branch // "-") worktree=\(.worktree // "-") attempts=\(.attempts) (last change of \(.file))"}))
     + ($T | map(select(.handoff.present) | {at: .handoff.at, order: 2, event: "handoff", task: .id,
                  detail: "status=\(.handoff.status) validation=\(.handoff.validation.total) (pass \(.handoff.validation.pass), fail \(.handoff.validation.fail), skipped \(.handoff.validation.skipped)) commits=\(.handoff.commits)"}))
     + ($RL | map({at: .at, order: 3, event: "rate-limit", task: null,
                  detail: "rate limit ended a session on \(.branch // "?") with \(.uncommitted) uncommitted file(s) — \(.path)"}))
     + (if $snap != null then [{at: $snap.when, order: 3, event: "compaction-snapshot", task: null,
                  detail: "context compacted on \($snap.branch // "?")\(if $snap.objective then ", open objective \($snap.objective)" else "" end) — \($snap.path)"}] else [] end)
     + (if $obj.updated then [{at: $obj.updated, order: 4, event: "objective-updated", task: null,
                  detail: "status=\($obj.status)"}] else [] end)
    | sort_by(.at, .order, .task) | map(del(.order))) as $timeline

  | ([
      # invariant 6: no handoff => the task is failed, never completed
      ($T[] | select(.status == "completed" and (.handoff.present | not))
        | {class: "task-completed-without-handoff", severity: "critical", task: .id, at: .file_mtime,
           detail: "\(.id) is marked completed but handoffs/\(.id).json does not exist. A task with no handoff is failed, never completed; something advanced the state without the worker's output.",
           evidence: [.file]}),
      ($T[] | select(.status == "running" and (.handoff.present | not)) | .id as $id
        | (if (($git.dirty_worktrees // []) | index($id)) != null then " Its worktree \(.worktree) has uncommitted changes: the work exists, the record does not." else "" end) as $dirty_note
        | if ($RL | length) > 0 then
            {class: "rate-limit-death", severity: "high", task: $id, at: .file_mtime,
             detail: "\($id) is still running and has no handoff, and rate-limit-handoff.sh recorded a rate-limit death for this objective at \($RL | map(.at) | join(", ")) (branch \($RL[0].branch // "?")). The session ended before the worker could write its handoff; the work on disk is whatever was committed or left in the worktree.\($dirty_note)",
             evidence: ([.file] + ($RL | map(.path)) + (if .worktree then [.worktree] else [] end))}
          else
            {class: "worker-stopped-without-handoff", severity: "high", task: $id, at: .file_mtime,
             detail: "\($id) is still running and has no handoff. Either the worker returned without writing one, or the session died mid-task with no rate-limit record under .dev-files/handoffs/, so the missing final handoff is the only signal.\($dirty_note)",
             evidence: ([.file] + (if .worktree then [.worktree] else [] end))}
          end),
      ($T[] | select(.handoff.present and .handoff.status == "completed" and .handoff.validation.total == 0)
        | {class: "completed-without-validation", severity: "high", task: .id, at: .handoff.at,
           detail: "\(.id)'s handoff claims completed with an empty validation[] — a claim with no evidence. Only commands that actually ran may appear there, so either nothing ran or the record is incomplete.",
           evidence: [.handoff.file]}),
      ($T[] | select(.handoff.present and .handoff.status == "completed" and .handoff.validation.fail > 0)
        | {class: "completed-with-failing-validation", severity: "high", task: .id, at: .handoff.at,
           detail: "\(.id)'s handoff claims completed while \(.handoff.validation.fail) validation command(s) reported fail. The honest status was partial or failed.",
           evidence: [.handoff.file]}),
      ($T[] | select(.handoff.present) | .handoff.status as $hs
        | select((["partial", "failed", "blocked"] | index($hs) != null)
                 and (.status == "completed" or objective_terminalish))
        | {class: "integrated-around-partial", severity: "critical", task: .id, at: .handoff.at,
           detail: "\(.id)'s handoff is \(.handoff.status) but \(if .status == "completed" then "the task was marked completed" else "the objective moved on to \($obj.status)" end). A partial/failed/blocked handoff means decide — re-plan, drop, or narrow — never integrate around it.",
           evidence: [.handoff.file, .file, "objective.json"]}),
      ($T | group_by(.branch) | map(select(.[0].branch != null and length > 1)) | .[]
        | {class: "shared-branch", severity: "high", task: (map(.id) | join("+")), at: (map(.file_mtime) | min),
           detail: "tasks \(map(.id) | join(", ")) all name branch \(.[0].branch). Concurrent tasks must not share a branch: one worker's commits land on top of another's and the handoff commit lists stop meaning anything.",
           evidence: map(.file)}),
      ($T | map({key: .id, value: .status}) | from_entries) as $st
        | ($T[] | select(.status == "running" or .status == "completed")
           | .id as $id | .file as $f | .file_mtime as $m
           | .depends_on[] | select(($st[.] // "missing") != "completed")
           | {class: "dependency-order-violation", severity: "high", task: $id, at: $m,
              detail: "\($id) is \($st[$id]) but its dependency \(.) is \($st[.] // "missing") — it was dispatched before its dependency completed, so it built on an unfinished foundation.",
              evidence: [$f, "tasks/\(.).json"]}),
      (($git.behind // [])[]
        | {class: "integration-behind-workers", severity: "high", task: .task, at: ($obj.updated // $objmtime),
           detail: "branch \(.branch) (\(.task), handoff completed) has \(.commits_ahead) commit(s) that \($git.integration_branch) lacks — the integration branch is behind its workers, so whatever was reviewed or delivered did not include that work.",
           evidence: ["objective.json", "tasks/\(.task).json", "handoffs/\(.task).json"]}),
      ($T[] | select(.handoff.present)
        | ({completed: "completed", failed: "failed", blocked: "blocked", cancelled: "cancelled", partial: "failed"}[.handoff.status]) as $want
        | select(.status != $want and .status != "completed" and (.status | terminal | not))
        | {class: "task-state-stale", severity: "medium", task: .id, at: .handoff.at,
           detail: "\(.id) has a \(.handoff.status) handoff but its task status is still \(.status). The worker finished; the orchestrator never recorded it, so ready/next/integrate-ready all give the wrong answer.",
           evidence: [.handoff.file, .file]}),
      ($T[] | select(.status == "running") | .id as $id
        | select(($T | map(select(.id != $id)) | length > 0) and ($T | map(select(.id != $id)) | all(.status | terminal)))
        | {class: "stuck-running", severity: "medium", task: $id, at: .file_mtime,
           detail: "\($id) is the only task not in a terminal state; every other task is finished. It is stuck in progress past the others.",
           evidence: [.file]}),
      ($T[] | select(.handoff.present) | . as $t
        | [.handoff.files_changed[] | select(in_scope($t.scope) | not)] | select(length > 0)
        | {class: "scope-escape", severity: "medium", task: $t.id, at: $t.handoff.at,
           detail: "\($t.id) changed \(join(", ")) outside its scope \($t.scope | join(", ")). handoff.sh refuses this unless --force was passed; the integrator must review it.",
           evidence: [$t.handoff.file, $t.file]}),
      (if $obj.status == "blocked" then
        {class: "objective-blocked", severity: "medium", task: null, at: ($obj.updated // $objmtime),
         detail: "objective status is blocked: it cannot proceed without a decision.\(if $obj.notes then " notes: \($obj.notes)" else "" end)",
         evidence: ["objective.json"]} else empty end),
      ($handoffs[] | select(.doc != null) | .doc.task_id as $tid | select(($T | map(.id) | index($tid)) == null)
        | {class: "handoff-without-task", severity: "low", task: $tid, at: .mtime,
           detail: "handoffs/\($tid).json exists but tasks/\($tid).json does not — a record for a task the objective never registered.",
           evidence: [.path]}),
      (($tasks + $handoffs)[] | select(.unparseable == true)
        | {class: "unparseable-state-file", severity: "high", task: null, at: .mtime,
           detail: "\(.path) is not valid JSON; every reader of this objective will fail on it.",
           evidence: [.path]})
    ] | sort_by(.at, (.severity | sevrank), .task)) as $findings

  | ($findings | map(select((.severity | sevrank) <= 1)) | .[0]) as $hc
  | (if $hc != null then $hc else ($findings | .[0]) end) as $first

  | ($T | map(.id)) as $ids
  | (if $first == null then
       (if $obj.status == "completed" then "nothing — the objective completed; no failure class detected"
        elif $obj.status == "abandoned" then "nothing — the objective was abandoned deliberately"
        elif ($T | length > 0) and ($T | all(.status == "completed" or .status == "cancelled")) then "/orchestrate-dev \($obj.id)   # every task is terminal; integrate onto \($obj.integration_branch)"
        else "/orchestrate-dev \($obj.id)   # no failure class detected; resume dispatch from the state files" end)
     else
       (.class = $first.class | .task = $first.task
        | if .class == "rate-limit-death" then
            "/switch-dev handoff objective=\($obj.id) \($first.task)   # write the handoff the dead session could not, then resume or re-run"
          elif .class == "worker-stopped-without-handoff" or .class == "stuck-running" then
            (if ($git.dirty_worktrees // []) | index($first.task) then "/switch-dev handoff objective=\($obj.id) \($first.task)   # write the handoff for the uncommitted work first"
             else "/worker-dev \($obj.id) \($first.task)   # re-run the task; a task without a handoff is failed, never completed" end)
          elif .class == "task-completed-without-handoff" then
            "bash skills/dev-workflow/_shared/scripts/objective-state.sh task-set \($obj.id) \($first.task) --status failed --bump-attempts && /worker-dev \($obj.id) \($first.task)"
          elif .class == "completed-without-validation" or .class == "completed-with-failing-validation" then
            "/worker-dev \($obj.id) \($first.task)   # run the Tier 1 validation and re-emit the handoff honestly"
          elif .class == "task-state-stale" then
            "bash skills/dev-workflow/_shared/scripts/objective-state.sh task-set \($obj.id) \($first.task) --status <status matching the handoff> && /orchestrate-dev \($obj.id)"
          elif .class == "unparseable-state-file" then
            "fix the JSON by hand, then: bash skills/dev-workflow/_shared/scripts/objective-state.sh validate \($obj.id)"
          else "/orchestrate-dev \($obj.id)   # decide: re-plan, drop or narrow, then integrate" end)
     end) as $next

  | {
      objective: {id: $obj.id, title: $obj.title, status: $obj.status, base_branch: $obj.base_branch,
                  integration_branch: $obj.integration_branch, created: ($obj.created // null),
                  updated: ($obj.updated // null), delivery: ($obj.delivery // null),
                  listed_tasks: ($obj.tasks // []), dir: $dir},
      tasks: $T,
      timeline: $timeline,
      snapshots: {compaction: $snap},
      git: $git,
      findings: $findings,
      first_cause: $first,
      next_command: $next
    }
JQ
)"

REPORT="$(jq -n \
  --argjson obj "$OBJ_JSON" --arg objmtime "$OBJ_MTIME" \
  --argjson tasks "$TASKS_JSON" --argjson handoffs "$HANDOFFS_JSON" \
  --argjson snap "$SNAP_JSON" --argjson git "$GIT_JSON" --arg dir "$DIR" \
  --argjson ratelimits "$RL_JSON" \
  "$JQ_PROGRAM")"

if [[ "$MARKDOWN" == false ]]; then
  printf '%s\n' "$REPORT"
  exit 0
fi

# --- markdown skeleton -------------------------------------------------------

jq -r '
  "# Diagnosis: \(.objective.id)",
  "",
  "- title: \(.objective.title)",
  "- status: \(.objective.status) (base \(.objective.base_branch), integration \(.objective.integration_branch))",
  "- state dir: \(.objective.dir)",
  "",
  "## What happened",
  "",
  "| When (UTC) | Event | Task | Detail |",
  "|---|---|---|---|",
  (.timeline[] | "| \(.at) | \(.event) | \(.task // "-") | \(.detail | gsub("\\|"; "\\\\|")) |"),
  "",
  "## First cause",
  "",
  (if .first_cause == null then "No failure class detected."
   else "**\(.first_cause.class)** (\(.first_cause.severity)) — \(.first_cause.task // "objective"): \(.first_cause.detail)" end),
  "",
  "## All findings",
  "",
  (if (.findings | length) == 0 then "- none" else (.findings[] | "- `\(.class)` (\(.severity), \(.task // "objective"), \(.at)): \(.detail)") end),
  "",
  "## Evidence",
  "",
  (if (.findings | length) == 0 then "- objective.json, tasks/*.json, handoffs/*.json read; nothing contradicts the recorded status"
   else ([.findings[].evidence[]] | unique | .[] | "- `\(.)`") end),
  (if .snapshots.compaction then "- `\(.snapshots.compaction.path)` (compaction snapshot, \(.snapshots.compaction.when))" else empty end),
  "",
  "## Next command",
  "",
  "```text",
  .next_command,
  "```"
' <<<"$REPORT"
