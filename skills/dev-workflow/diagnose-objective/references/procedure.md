# Procedure — long form

`SKILL.md` is the short version. This is the same procedure with the reasoning, the file
map, and the `diagnosis.md` template with a worked example.

## What is on disk, and what each file can prove

```text
.dev-files/
├── objectives/<id>/
│   ├── objective.json       status, base/integration branch, created, updated, task ids
│   ├── plan.md              the planner's rationale (prose; read it for intent, not state)
│   ├── tasks/task-NNN.json  role, depends_on, scope[], status, branch, worktree, attempts
│   ├── handoffs/task-NNN.json  status, summary, commits[], files_changed[], validation[],
│   │                        risks[], followups[], completed — the task's ENTIRE output
│   ├── integration.json     integration branch state, when the integrator wrote one
│   └── diagnosis.md         this skill's report (the only file it writes)
├── compaction/latest.md     hooks/precompact-snapshot.sh: when, trigger, branch, open
│                            objective, uncommitted files, recent commits
└── handoffs/rate-limit-<ts>.json  hooks/rate-limit-handoff.sh: written_at, branch,
                             objective, uncommitted, resume, session_id
```

Two things the schemas do **not** record, which shapes what the timeline can claim:

- **Task files carry no timestamps.** `objective-state.sh task-set` rewrites the file, so its
  mtime is the task's *last* state change, not its creation or claim time. The timeline
  labels it that way ("last change of tasks/task-002.json"). Do not present it as "task
  started at".
- **Handoffs carry `completed`** (set by `handoff.sh emit`), which is a real timestamp. A
  hand-written handoff may lack it; the script falls back to the file's mtime and the
  report should say "(file mtime)" when it matters.

`.dev-files/` is gitignored by default, so the state is local to the machine the objective
ran on. A diagnosis on another machine sees only what `/switch-dev handoff` mirrored.

## Step 1 — locate

`objective-state.sh active` answers "the objective the current branch names
(`objective/<id>` or `worker/<id>/NNN`), else the most recently updated *open* one". A
`completed` or `abandoned` objective is not open, so for a post-mortem of one of those, pass
the id or pick the newest directory by `updated` in `objective.json`.

When several are open and no argument was given, list them and ask. The cost of diagnosing
the wrong objective is a confident wrong report.

## Step 2 — the script

`objective-timeline.sh <dir>` is the whole deterministic layer. Reasons it is a script and
not a prompt: the same state must yield the same findings on every run and every platform;
the glob matching for `scope-escape`, the branch arithmetic for `integration-behind-workers`,
and the severity/time ordering for `first_cause` are all things a model gets subtly wrong
under context pressure; and a reviewer can re-run it.

What it does *not* do: read summaries for meaning, judge whether a `partial` was reasonable,
or decide that a later finding is the real root. That is Step 3.

Useful projections while reading:

```bash
X=skills/dev-workflow/diagnose-objective/scripts/objective-timeline.sh
bash $X "$D" | jq '.findings[] | {class, severity, task, at}'
bash $X "$D" | jq -r '.timeline[] | "\(.at)  \(.event)\t\(.task // "-")\t\(.detail)"'
bash $X "$D" | jq '.tasks[] | {id, status, handoff: .handoff.status, validation: .handoff.validation}'
bash $X "$D" --markdown > "$D/diagnosis.md"    # the skeleton; then edit the prose sections
```

## Step 3 — confirm against the files

For each finding, open its `evidence[]` and check the class's "evidence must show" line in
[`failure-classes.md`](failure-classes.md). Three outcomes per finding:

| Outcome | Write |
|---|---|
| Confirmed | the class, the task, the line in the file that proves it |
| Refuted | why the files do not support it (rare — the rules are structural) and drop it |
| Reclassified | the finding stands but a different class explains it better (a `stuck-running` that is really `task-state-stale`) |

Then the handoffs, in task order, for `summary`, `risks[]` and blocking `followups[]`. This
is where the mechanism lives: *why* task-002 was `partial`, *what* the worker said it needed.
The report's First cause paragraph quotes the summary line that explains the mechanism.

Promote a later finding to first cause only when the earlier one follows from it. Write the
promotion down ("the script's first cause was X at 10:02; the root is Y at 10:04 because …").

## Step 4 — the report

```markdown
# Diagnosis: auth-system

- title: Add JWT auth
- status: integrating (base main, integration objective/auth-system)
- state dir: /repo/.dev-files/objectives/auth-system
- diagnosed: 2026-10-17T13:05:00Z

## What happened

| When (UTC) | Event | Task | Detail |
|---|---|---|---|
| 2026-10-17T09:00:12Z | objective-created | - | objective auth-system created (base main, integration objective/auth-system) |
| 2026-10-17T09:41:03Z | handoff | task-001 | status=completed validation=2 (pass 2, fail 0, skipped 0) commits=3 |
| 2026-10-17T10:02:44Z | handoff | task-002 | status=partial validation=1 (pass 0, fail 1, skipped 0) commits=1 |
| 2026-10-17T10:03:10Z | task-state | task-002 | status=completed branch=worker/auth-system/002 … |
| 2026-10-17T10:05:00Z | objective-updated | - | status=integrating |

## First cause

**integrated-around-partial** (critical) — task-002. Its handoff is `partial`: the summary
says "token refresh endpoint done; revocation list not wired, `npm test -- revoke` fails
(1 of 1)". Thirty seconds later `tasks/task-002.json` was set to `completed` and the
objective moved to `integrating`. The orchestrator advanced the task list without reading
the handoff; everything after this row was integrated on top of a known-failing test.

## All findings

- `integrated-around-partial` (critical, task-002, 2026-10-17T10:02:44Z): …
- `completed-with-failing-validation` — not raised: the handoff honestly said `partial`.

## Evidence

- `handoffs/task-002.json` — status partial; validation[0] `npm test -- revoke` → fail
- `tasks/task-002.json` — status completed (file mtime 10:03:10Z)
- `objective.json` — status integrating, updated 10:05:00Z
- `.dev-files/compaction/latest.md` — none found
- git: integration branch `objective/auth-system` is not behind any worker branch

## Next command

```text
/orchestrate-dev auth-system   # decide: re-plan task-002 (revocation list) or narrow the objective, then re-integrate
```

After it: `handoffs/task-002.json` should be `completed` with `npm test -- revoke` → pass
before `set-status auth-system reviewing` runs again.
```

Section rules:

- **What happened** is the script's table, unedited except to drop `task-state` rows that
  add nothing (a task whose only event is "created, still pending").
- **First cause** is one paragraph: class, task, the quoted evidence, the mechanism in one
  sentence, the consequence in one sentence.
- **All findings** lists every finding the script raised, each on one line, including the
  ones that follow from the first cause. "none" when clean.
- **Evidence** is a file list a reviewer can re-open. Name what was *not* checked
  (no git, no snapshot) explicitly.
- **Next command** is one line of command plus one line of what to look for afterwards.

## Step 5 — chat

Two sentences on the first cause, the next command, the path. The report is the deliverable,
the chat message is the pointer to it.

## Where the next commands lead

| Next command | What it does with the diagnosis |
|---|---|
| `/switch-dev handoff objective=<id> <task>` | Writes the handoff record for work that exists without one — uncommitted worktree changes, a rate-limit death — so the task can resume or be re-run from a record instead of from memory |
| `/worker-dev <id> <task>` | Re-runs one task inside its scope and ends at commit + handoff. Only for a task with **no** handoff; a task whose handoff exists is never re-run |
| `/orchestrate-dev <id>` | Resumes the objective from the state files: reads every handoff, decides on partial/failed ones, fixes the graph, integrates onto one branch |
