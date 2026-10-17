#!/usr/bin/env bash
# test-diagnose-objective.sh — the diagnose-objective skill's deterministic layer.
#
# Builds fixture objectives in a temp dir with the real state scripts
# (objective-state.sh, handoff.sh), so every fixture is schema-shaped by
# construction, then pins what scripts/objective-timeline.sh must detect:
#
#   clean          a completed objective yields no finding and a status-driven next command
#   nohandoff      a worker that returned without a handoff; the same with a rate-limit record
#   unevidenced    a `completed` handoff with validation: [] plus a task stuck running
#   messy (git)    partial integrated around, shared branch, dependency order, scope escape,
#                  stale task state, orphan handoff, integration branch behind a worker
#
# Also asserts the SKILL.md frontmatter validates and the generated Cursor/OpenCode command
# files exist, so a renamed skill or a skipped generator run fails here.
#
# Usage: bash tests/test-diagnose-objective.sh

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=tests/lib/harness.sh
source "$REPO_ROOT/tests/lib/harness.sh"

harness_require jq git python3

SKILL_DIR="$REPO_ROOT/skills/dev-workflow/diagnose-objective"
X="$SKILL_DIR/scripts/objective-timeline.sh"
S="$REPO_ROOT/skills/dev-workflow/_shared/scripts/objective-state.sh"
H="$REPO_ROOT/skills/dev-workflow/_shared/scripts/handoff.sh"

[ -f "$X" ] || { echo "FATAL: $X missing"; exit 1; }

# run <objective-dir> <repo> [extra args] — the script's JSON on stdout
run() { bash "$X" "$1" --repo "$2" "${@:3}"; }
classes() { jq -r '[.findings[].class] | join(" ")'; }

# pin_times <objective-dir> — deterministic timestamps: handoff N completed at 01:0N,
# task file N touched at 01:0N, objective created 01:00 / updated 01:10. `touch -t`
# is the one form GNU and BSD touch share. It reads LOCAL time while the JSON stamps
# above are UTC, so it runs under TZ=UTC: anywhere east or west of UTC the mtimes
# would otherwise land hours away from the stamps and reorder the timeline.
pin_times() {
  local d="$1" f n
  jq '.created = "2026-10-17T01:00:00Z" | .updated = "2026-10-17T01:10:00Z"' "$d/objective.json" > "$d/o.tmp" && mv "$d/o.tmp" "$d/objective.json"
  for f in "$d"/tasks/task-*.json "$d"/handoffs/task-*.json; do
    [ -f "$f" ] || continue
    n="$(basename "$f" .json)"; n="${n#task-}"; n="$((10#$n))"
    if [[ "$f" == */handoffs/* ]]; then
      jq --arg t "2026-10-17T01:0${n}:00Z" '.completed = $t' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
    fi
    TZ=UTC touch -t "20261017010${n}" "$f"
  done
  TZ=UTC touch -t "202610170100" "$d/objective.json"
}

# --------------------------------------------------------------------------
section "script contract"

judge "--help exits 0" 0 "$(bash "$X" --help >/dev/null 2>&1; echo $?)"
judge "no arguments is a usage error (exit 1)" 1 "$(bash "$X" >/dev/null 2>&1; echo $?)"
judge "missing objective dir exits 2" 2 "$(bash "$X" /nonexistent/objective >/dev/null 2>&1; echo $?)"
if harness_have shellcheck; then
  judge "objective-timeline.sh is shellcheck-clean" 0 "$(shellcheck -S warning "$X" >/dev/null 2>&1; echo $?)"
else
  skip "objective-timeline.sh is shellcheck-clean" "shellcheck not installed"
fi
judge "objective-timeline.sh is executable" yes "$(if [ -x "$X" ]; then echo yes; else echo no; fi)"
judge "objective-timeline.sh uses no eval" 0 "$(grep -c -E '(^|[^a-z_])eval ' "$X" | tr -d ' ')"

# --------------------------------------------------------------------------
section "fixture: clean objective"

R1="$(harness_tmpdir)"
export OBJECTIVES_ROOT="$R1/.dev-files/objectives"
bash "$S" init clean --title "Clean" --base-branch main >/dev/null
bash "$S" task-add clean --role implementer --scope 'src/**' --title "A" >/dev/null
bash "$S" task-add clean --role test-engineer --scope 'tests/**' --depends-on task-001 >/dev/null
bash "$S" task-set clean task-001 --status completed --branch worker/clean/001 >/dev/null 2>&1
bash "$H" emit clean task-001 --status completed --summary ok --branch worker/clean/001 \
  --commit abc1234 --file 'src/a.ts:modified' --validation 'npm test|worker|pass' >/dev/null
bash "$S" task-set clean task-002 --status completed --branch worker/clean/002 >/dev/null 2>&1
bash "$H" emit clean task-002 --status completed --summary ok --validation 'npm test|worker|pass' >/dev/null
bash "$S" set-status clean integrating >/dev/null
pin_times "$OBJECTIVES_ROOT/clean"

out="$(run "$OBJECTIVES_ROOT/clean" "$R1")"
judge "output is valid JSON" 0 "$(jq empty <<<"$out" >/dev/null 2>&1; echo $?)"
judge "clean objective has no findings" 0 "$(jq '.findings | length' <<<"$out")"
judge "first_cause is null when clean" null "$(jq -r '.first_cause' <<<"$out")"
judge "next command integrates when every task is terminal" yes "$(has "$(jq -r .next_command <<<"$out")" '/orchestrate-dev clean')"
judge "tasks carry their handoff" "completed completed" "$(jq -r '[.tasks[].handoff.status] | join(" ")' <<<"$out")"
judge "timeline is sorted by time" "$(jq -r '[.timeline[].at] | sort | join(" ")' <<<"$out")" "$(jq -r '[.timeline[].at] | join(" ")' <<<"$out")"
judge "timeline starts with objective-created" objective-created "$(jq -r '.timeline[0].event' <<<"$out")"
judge "git facts are reported absent outside a repo" false "$(jq -r '.git.available' <<<"$out")"

bash "$S" set-status clean completed >/dev/null
out="$(run "$OBJECTIVES_ROOT/clean" "$R1")"
judge "a completed objective needs nothing" yes "$(has "$(jq -r .next_command <<<"$out")" 'nothing')"

# --------------------------------------------------------------------------
section "fixture: a worker returned without a handoff"

R2="$(harness_tmpdir)"
export OBJECTIVES_ROOT="$R2/.dev-files/objectives"
bash "$S" init nohandoff --title "No handoff" --base-branch main >/dev/null
bash "$S" task-add nohandoff --role implementer --scope 'src/**' >/dev/null
bash "$S" task-add nohandoff --role implementer --scope 'docs/**' >/dev/null
bash "$S" task-set nohandoff task-001 --status completed --branch worker/nohandoff/001 >/dev/null 2>&1
bash "$H" emit nohandoff task-001 --status completed --validation 'make test|worker|pass' >/dev/null
bash "$S" task-set nohandoff task-002 --status running --branch worker/nohandoff/002 \
  --worktree .agent-worktrees/nohandoff/task-002 >/dev/null 2>&1
pin_times "$OBJECTIVES_ROOT/nohandoff"

out="$(run "$OBJECTIVES_ROOT/nohandoff" "$R2")"
judge "detects worker-stopped-without-handoff" yes "$(has "$(classes <<<"$out")" worker-stopped-without-handoff)"
judge "the finding names task-002" task-002 "$(jq -r '.findings[] | select(.class == "worker-stopped-without-handoff") | .task' <<<"$out")"
judge "task-002 shows handoff.present false" false "$(jq -r '.tasks[] | select(.id == "task-002") | .handoff.present' <<<"$out")"
judge "first cause is the missing handoff" worker-stopped-without-handoff "$(jq -r '.first_cause.class' <<<"$out")"
judge "next command re-runs the task with worker-dev" yes "$(has "$(jq -r .next_command <<<"$out")" '/worker-dev nohandoff task-002')"
judge "evidence names the task file" yes "$(has "$(jq -r '.first_cause.evidence | join(" ")' <<<"$out")" 'tasks/task-002.json')"
judge "stuck-running is reported alongside" yes "$(has "$(classes <<<"$out")" stuck-running)"
judge "task-001 is not flagged" "" "$(jq -r '.findings[] | select(.task == "task-001") | .class' <<<"$out")"

# The same objective after hooks/rate-limit-handoff.sh recorded the death.
mkdir -p "$R2/.dev-files/handoffs"
cat > "$R2/.dev-files/handoffs/rate-limit-20261017T010500Z.json" <<'EOF'
{"kind":"rate-limit-handoff","schema_version":1,"written_at":"2026-10-17T01:05:00Z","session_id":null,
 "cwd":"/repo","branch":"worker/nohandoff/002","objective":"nohandoff","uncommitted":2,
 "resume":"/switch-dev handoff objective=nohandoff","message":"m","messaging":{"socket":null,"posted":false,"reason":"none"}}
EOF
out="$(run "$OBJECTIVES_ROOT/nohandoff" "$R2")"
judge "a rate-limit record reclassifies the death" yes "$(has "$(classes <<<"$out")" rate-limit-death)"
judge "worker-stopped is replaced, not duplicated" no "$(has "$(classes <<<"$out")" worker-stopped-without-handoff)"
judge "first cause is the rate-limit death" rate-limit-death "$(jq -r '.first_cause.class' <<<"$out")"
judge "evidence names the rate-limit record" yes "$(has "$(jq -r '.first_cause.evidence | join(" ")' <<<"$out")" '.dev-files/handoffs/rate-limit-20261017T010500Z.json')"
judge "next command is switch-dev handoff for the task" yes "$(has "$(jq -r .next_command <<<"$out")" '/switch-dev handoff objective=nohandoff task-002')"
judge "timeline carries the rate-limit event" 1 "$(jq '[.timeline[] | select(.event == "rate-limit")] | length' <<<"$out")"

# A record names one worker's branch: a second running worker without a handoff on
# another branch is still worker-stopped, never a rate-limit death by association.
bash "$S" task-add nohandoff --role implementer --scope 'tests/**' >/dev/null
bash "$S" task-set nohandoff task-003 --status running --branch worker/nohandoff/003 >/dev/null 2>&1
pin_times "$OBJECTIVES_ROOT/nohandoff"
out="$(run "$OBJECTIVES_ROOT/nohandoff" "$R2")"
judge "the record's branch keeps task-002 a rate-limit death" rate-limit-death "$(jq -r '.findings[] | select(.task == "task-002" and (.class | test("handoff|rate-limit"))) | .class' <<<"$out")"
judge "task-003 on another branch stays worker-stopped-without-handoff" worker-stopped-without-handoff "$(jq -r '.findings[] | select(.task == "task-003" and (.class | test("handoff|rate-limit"))) | .class' <<<"$out")"
bash "$S" task-set nohandoff task-003 --status completed >/dev/null 2>&1
bash "$H" emit nohandoff task-003 --status completed --validation 'make test|worker|pass' >/dev/null
pin_times "$OBJECTIVES_ROOT/nohandoff"

# A record for some other objective must not match.
jq '.objective = "other" | .branch = "worker/other/001"' "$R2/.dev-files/handoffs/rate-limit-20261017T010500Z.json" \
  > "$R2/.dev-files/handoffs/x.tmp" && mv "$R2/.dev-files/handoffs/x.tmp" "$R2/.dev-files/handoffs/rate-limit-20261017T010500Z.json"
out="$(run "$OBJECTIVES_ROOT/nohandoff" "$R2")"
judge "another objective's rate-limit record is ignored" no "$(has "$(classes <<<"$out")" rate-limit-death)"

# A compaction snapshot naming the objective lands on the timeline.
mkdir -p "$R2/.dev-files/compaction"
printf '# Pre-compaction snapshot\n\n- when: 2026-10-17T01:04:00Z\n- trigger: auto\n- repo: /repo\n- branch: worker/nohandoff/002\n- open objective: nohandoff\n' \
  > "$R2/.dev-files/compaction/latest.md"
out="$(run "$OBJECTIVES_ROOT/nohandoff" "$R2")"
judge "compaction snapshot is read" 2026-10-17T01:04:00Z "$(jq -r '.snapshots.compaction.when' <<<"$out")"
judge "compaction snapshot is a timeline event" 1 "$(jq '[.timeline[] | select(.event == "compaction-snapshot")] | length' <<<"$out")"

# --------------------------------------------------------------------------
section "fixture: completed without validation + a task stuck running"

R3="$(harness_tmpdir)"
export OBJECTIVES_ROOT="$R3/.dev-files/objectives"
bash "$S" init unevidenced --title "Unevidenced" --base-branch main >/dev/null
bash "$S" task-add unevidenced --role implementer --scope 'src/**' >/dev/null
bash "$S" task-add unevidenced --role implementer --scope 'lib/**' >/dev/null
bash "$S" task-add unevidenced --role reviewer --scope 'review/**' >/dev/null
bash "$S" task-set unevidenced task-001 --status completed --branch worker/u/001 >/dev/null 2>&1
bash "$H" emit unevidenced task-001 --status completed --summary "done, trust me" >/dev/null
bash "$S" task-set unevidenced task-003 --status completed --branch worker/u/003 >/dev/null 2>&1
bash "$H" emit unevidenced task-003 --status completed --validation 'x|worker|pass' >/dev/null
bash "$S" task-set unevidenced task-002 --status running --branch worker/u/002 >/dev/null 2>&1
pin_times "$OBJECTIVES_ROOT/unevidenced"

out="$(run "$OBJECTIVES_ROOT/unevidenced" "$R3")"
judge "detects completed-without-validation" task-001 "$(jq -r '.findings[] | select(.class == "completed-without-validation") | .task' <<<"$out")"
judge "detects the stuck task" task-002 "$(jq -r '.findings[] | select(.class == "stuck-running") | .task' <<<"$out")"
judge "the stuck task also has no handoff" task-002 "$(jq -r '.findings[] | select(.class == "worker-stopped-without-handoff") | .task' <<<"$out")"
judge "first cause is the earliest high-severity finding" completed-without-validation "$(jq -r '.first_cause.class' <<<"$out")"
judge "next command re-runs task-001 for evidence" yes "$(has "$(jq -r .next_command <<<"$out")" '/worker-dev unevidenced task-001')"
judge "evidence names the unevidenced handoff" yes "$(has "$(jq -r '.first_cause.evidence | join(" ")' <<<"$out")" 'handoffs/task-001.json')"
judge "validation counts are exposed per task" 0 "$(jq -r '.tasks[] | select(.id == "task-001") | .handoff.validation.total' <<<"$out")"
judge "evidenced completion is not flagged" "" "$(jq -r '.findings[] | select(.task == "task-003") | .class' <<<"$out")"

md="$(run "$OBJECTIVES_ROOT/unevidenced" "$R3" --markdown)"
judge "--markdown renders the report title" yes "$(has "$md" '# Diagnosis: unevidenced')"
judge "--markdown renders the timeline table" yes "$(has "$md" '| When (UTC) | Event | Task | Detail |')"
judge "--markdown names the first cause" yes "$(has "$md" '**completed-without-validation**')"
judge "--markdown ends with the next command" yes "$(has "$md" '## Next command')"

# --------------------------------------------------------------------------
section "fixture: integration-time classes (git-backed)"

R4="$(harness_tmpdir)"
harness_new_repo "$R4" main
git -C "$R4" branch objective/messy
git -C "$R4" checkout -q -b worker/messy/001
git -C "$R4" commit -q --allow-empty -m "late fix on worker branch"
git -C "$R4" checkout -q main
export OBJECTIVES_ROOT="$R4/.dev-files/objectives"
bash "$S" init messy --title "Messy" --base-branch main >/dev/null
bash "$S" task-add messy --role implementer --scope 'src/**' >/dev/null
bash "$S" task-add messy --role implementer --scope 'lib/**' >/dev/null
bash "$S" task-add messy --role reviewer --scope 'r/**' >/dev/null
bash "$S" task-add messy --role test-engineer --scope 't/**' --depends-on task-003 >/dev/null
bash "$S" task-set messy task-001 --status completed --branch worker/messy/001 >/dev/null 2>&1
bash "$H" emit messy task-001 --status completed --validation 'x|worker|pass' \
  --file 'src/a.ts:modified' --file 'docs/x.md:added' --force >/dev/null 2>&1
bash "$S" task-set messy task-002 --status completed --branch worker/messy/001 >/dev/null 2>&1
bash "$H" emit messy task-002 --status partial --summary "half done" >/dev/null
bash "$S" task-set messy task-003 --status running --branch worker/messy/003 >/dev/null 2>&1
bash "$H" emit messy task-003 --status completed --validation 'y|worker|pass' >/dev/null
jq '.status = "running"' "$OBJECTIVES_ROOT/messy/tasks/task-004.json" > "$OBJECTIVES_ROOT/messy/t.tmp" \
  && mv "$OBJECTIVES_ROOT/messy/t.tmp" "$OBJECTIVES_ROOT/messy/tasks/task-004.json"
echo '{"task_id":"task-009","status":"completed"}' > "$OBJECTIVES_ROOT/messy/handoffs/task-009.json"
bash "$S" set-status messy integrating >/dev/null
pin_times "$OBJECTIVES_ROOT/messy"

out="$(run "$OBJECTIVES_ROOT/messy" "$R4")"
cls="$(classes <<<"$out")"
judge "git facts are available inside a repo" true "$(jq -r '.git.available' <<<"$out")"
judge "detects integrated-around-partial" task-002 "$(jq -r '.findings[] | select(.class == "integrated-around-partial") | .task' <<<"$out")"
judge "detects shared-branch" task-001+task-002 "$(jq -r '.findings[] | select(.class == "shared-branch") | .task' <<<"$out")"
judge "detects dependency-order-violation" task-004 "$(jq -r '.findings[] | select(.class == "dependency-order-violation") | .task' <<<"$out")"
judge "detects scope-escape" task-001 "$(jq -r '.findings[] | select(.class == "scope-escape") | .task' <<<"$out")"
judge "detects task-state-stale" task-003 "$(jq -r '.findings[] | select(.class == "task-state-stale") | .task' <<<"$out")"
judge "detects handoff-without-task" task-009 "$(jq -r '.findings[] | select(.class == "handoff-without-task") | .task' <<<"$out")"
judge "detects integration-behind-workers" task-001 "$(jq -r '.findings[] | select(.class == "integration-behind-workers") | .task' <<<"$out")"
judge "integration lag counts the missing commits" 1 "$(jq -r '.git.behind[0].commits_ahead' <<<"$out")"
judge "a branch that does not exist is reported, not treated as behind" worker/messy/003 "$(jq -r '.git.missing_branches[0].branch' <<<"$out")"
judge "first cause is the earliest high-severity finding" shared-branch "$(jq -r '.first_cause.class' <<<"$out")"
judge "integration problems hand off to orchestrate-dev" yes "$(has "$(jq -r .next_command <<<"$out")" '/orchestrate-dev messy')"
judge "findings are sorted by time" "$(jq -r '[.findings[].at] | sort | join(" ")' <<<"$out")" "$(jq -r '[.findings[].at] | join(" ")' <<<"$out")"
judge "no unexpected class" "" "$(tr ' ' '\n' <<<"$cls" | grep -v -E '^(integrated-around-partial|shared-branch|dependency-order-violation|scope-escape|task-state-stale|handoff-without-task|integration-behind-workers|stuck-running|worker-stopped-without-handoff)$' || true)"

echo '{not json' > "$OBJECTIVES_ROOT/messy/tasks/task-005.json"
out="$(run "$OBJECTIVES_ROOT/messy" "$R4")"
judge "an unparseable state file is a finding, not a crash" yes "$(has "$(classes <<<"$out")" unparseable-state-file)"

unset OBJECTIVES_ROOT

# --------------------------------------------------------------------------
section "skill contract"

judge "SKILL.md frontmatter validates (tamirs tier required)" 0 \
  "$(python3 "$REPO_ROOT/scripts/validate-skill-frontmatter.py" --require-tamirs "$SKILL_DIR/SKILL.md" >/dev/null 2>&1; echo $?)"
judge "SKILL.md stays under the 500-line cap" yes "$(if [ "$(wc -l < "$SKILL_DIR/SKILL.md")" -lt 500 ]; then echo yes; else echo no; fi)"
judge "every reference the skill names exists" yes "$(if [ -f "$SKILL_DIR/references/failure-classes.md" ] && [ -f "$SKILL_DIR/references/procedure.md" ]; then echo yes; else echo no; fi)"
judge "every failure class the script emits is documented" "" \
  "$(grep -o -E 'class: "[a-z-]+"' "$X" | sed -E 's/class: "([a-z-]+)"/\1/' | sort -u \
     | while read -r c; do grep -q -- "\`$c\`" "$SKILL_DIR/references/failure-classes.md" || echo "$c"; done)"
judge "trigger evals have positive cases" yes "$(if jq -e 'any(.[]; .should_trigger == true)' "$SKILL_DIR/evals/trigger-evals.json" >/dev/null; then echo yes; else echo no; fi)"
judge "trigger evals have at least 3 negative cases" yes "$(if [ "$(jq '[.[] | select(.should_trigger == false)] | length' "$SKILL_DIR/evals/trigger-evals.json")" -ge 3 ]; then echo yes; else echo no; fi)"
judge "behaviour evals exist" yes "$(if [ "$(jq '.evals | length' "$SKILL_DIR/evals/evals.json")" -ge 3 ]; then echo yes; else echo no; fi)"
judge "Cursor command file is generated" yes "$(exists "$REPO_ROOT/.cursor/commands/diagnose-objective.md")"
judge "OpenCode command file is generated" yes "$(exists "$REPO_ROOT/.opencode/commands/diagnose-objective.md")"

harness_summary
