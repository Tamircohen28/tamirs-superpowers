---
name: diagnose-objective
description: 'Use when an orchestrated objective failed, stalled or looks wrong and you need to know why from its state files — ''why did objective X fail'', ''diagnose the objective'', ''what happened to task-003'', ''the orchestration stalled'', ''a worker never handed off'', ''the integration branch is missing work'', ''explain this failed objective'', ''post-mortem the objective'', a task stuck running after the others finished, a handoff that says completed with no validation, or a session that died on a rate limit mid-objective. Reads .dev-files/objectives/<id>/ and writes diagnosis.md; never re-runs, re-plans or integrates anything. Not for a stack trace (targeted-debug), a refused request (diagnose-refusal) or a session retro (retro).'
when_to_use: 'why did objective auth-system fail; diagnose objective <id>; what happened to task-002, it never handed off; the orchestration stalled, which task is stuck; explain the failed objective and tell me the next command.'
argument-hint: '[objective-id]'
arguments: []
disable-model-invocation: false
user-invocable: true
allowed-tools:
- Read
- Glob
- Grep
- Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/dev-workflow/diagnose-objective/scripts/objective-timeline.sh:*)
- Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/dev-workflow/_shared/scripts/objective-state.sh:*)
- Bash(bash ${CLAUDE_PLUGIN_ROOT}/skills/dev-workflow/_shared/scripts/handoff.sh:*)
disallowed-tools: []
effort: medium
context: ''
agent: ''
metadata:
  tamirs:
    visibility: public
    category: dev-workflow
    role: debugger
    validation-tier: 0
    updated-date: '2026-10-17'
    capabilities:
      required:
      - skills
      - shell
      optional:
      - git
    tags:
    - diagnosis
    - objective
    - handoff
    - orchestration
    - post-mortem
    - workflow
---

# diagnose-objective

Explain why an objective failed or stalled, from the files the orchestration already wrote.
Output is one report, `.dev-files/objectives/<id>/diagnosis.md`, ending in one next command.

Role contract: [`core/roles/debugger.md`](../../../core/roles/debugger.md). State model:
[`docs/engineering/architecture/orchestration-state-machine.md`](../../../docs/engineering/architecture/orchestration-state-machine.md).

## Why this skill exists

An objective leaves a complete paper trail — `objective.json`, one task file per task, one
handoff per finished task, a compaction snapshot, a rate-limit record — and every transition
is a file write. When it dies, the explanation is already on disk; what is missing is the
reading. Without this skill the reader is a human paging through JSON, or an orchestrator
that resumes by guessing and re-runs a task whose handoff exists (duplicating its commits).
The failure classes are known and finite (see
[`references/failure-classes.md`](references/failure-classes.md)); detecting them is
deterministic, so a script does it and the model explains it.

**Validation tier: 0.** This skill runs no project tests and changes no state. It reads,
and it writes exactly one file: `diagnosis.md`.

## Step 1 — locate the objective

In this order; stop at the first hit:

1. the argument (`/diagnose-objective auth-system`);
2. `$SUPERPOWERS_OBJECTIVE_ID`, when exported;
3. `bash $S active` (the objective the current branch names, else the most recently updated
   open one);
4. the most recently updated directory under `.dev-files/objectives/` — a *completed* or
   *abandoned* objective is still diagnosable.

```bash
S=skills/dev-workflow/_shared/scripts/objective-state.sh
bash $S list
bash $S path <id>          # .dev-files/objectives/<id>
```

No `.dev-files/objectives/` at all: say so and stop. There is nothing to diagnose without
state, and inventing a timeline from the transcript is the one thing this skill must not do.

## Step 2 — run the timeline script first

```bash
D=$(bash $S path <id>)
bash skills/dev-workflow/diagnose-objective/scripts/objective-timeline.sh "$D"
```

It prints one JSON document: `objective`, `tasks[]` (each merged with its handoff or
`handoff.present: false`), `timeline[]` sorted by time, `snapshots`, `git`, `findings[]`,
`first_cause` and `next_command`. It is deterministic and offline — the same files give the
same answer every time, which is what makes the report reviewable.

Where the `git` capability is present it also checks whether the integration branch is
behind a completed worker's branch and whether a task worktree is dirty; without git
(`git.available: false`) those two checks are skipped and the report says so under
Evidence rather than silently reporting "not behind".

`--markdown` renders the same facts as the report skeleton used in Step 4.

## Step 3 — read the evidence the findings name

Every finding carries `evidence[]`: paths relative to the objective directory (or to the repo
root for `.dev-files/compaction/latest.md` and `.dev-files/handoffs/rate-limit-*.json`).
Read those files — all of them, nothing else — and confirm or refute each finding against
[`references/failure-classes.md`](references/failure-classes.md), which gives per class what
the files must show, the usual real-world cause, and the next command.

Then read every handoff `summary`, `risks[]` and blocking `followups[]` in task order. The
script sees structure; the summaries say what the worker thought was happening, and a
`partial` whose summary names a missing dependency is a different diagnosis from one whose
summary names a flaky test.

Check `first_cause` with one question: *is this the earliest finding that the others follow
from?* The script picks the earliest high-severity finding by timestamp. If a later finding
is the real root (a `shared-branch` that only mattered once the second worker committed), say
so and promote it — the script's choice is evidence, not a verdict.

## Step 4 — write `diagnosis.md`

Write `.dev-files/objectives/<id>/diagnosis.md` with exactly these sections, in this order.
The full template with worked examples is in
[`references/procedure.md`](references/procedure.md).

```markdown
# Diagnosis: <id>
## What happened        — the timeline table, one row per event, as the script printed it
## First cause          — one paragraph: the class, the task, the evidence line, the mechanism
## All findings         — every finding, severity-tagged; "none" when the objective is clean
## Evidence             — the files read, one per line, so a reviewer can re-derive this
## Next command         — one command; what it will do; what to check after it
```

Rules for the report:

- **Prose explains; it never contradicts the files.** A `completed` handoff with an empty
  `validation[]` is "a claim with no evidence", not "probably fine, the summary says it ran".
- **One next command.** Resume with `/switch-dev handoff objective=<id> <task>` when work
  exists without a record; re-run with `/worker-dev <id> <task>` when a task has no handoff
  and nothing to save; decide and integrate with `/orchestrate-dev <id>` for everything that
  is a planning or integration problem. The mapping is fixed in
  [`references/failure-classes.md`](references/failure-classes.md).
- **Say what was not checked.** No git → no integration-lag check. No compaction snapshot →
  say none was found. Absent is a legitimate value; inferred is not.
- `diagnosis.md` is the only write. Overwriting an earlier diagnosis is fine; it is a report,
  not state.

## Step 5 — report

In chat: the first cause in two sentences, the next command, and the path to `diagnosis.md`.
Not the timeline — that is what the file is for.

## Hard rules

1. **Never change objective, task or handoff state.** Not `task-set`, not `set-status`, not a
   hand-written handoff "to unblock things". The next command names who changes state.
2. **Never re-run, re-plan or integrate.** This skill ends at a report. `/worker-dev`,
   `/orchestrate-dev` and `/switch-dev` do the rest, and only when the user runs them.
3. **Never fabricate a timeline from memory.** The state files and the snapshot are the
   record. A fact that is not in them is reported as "not recorded", not reconstructed.
4. **Read only the evidence the findings name, plus the handoffs.** Not the worker branches'
   diffs, not the test output — if a finding needs that to be confirmed, list it under
   Evidence as "not read; would confirm X" and leave the confidence at what the files support.
5. **No handoff ⇒ the task is failed.** Report it as such even when the transcript says the
   worker "finished". The integrator reads files, not summaries, and so does this skill.

## Error handling

| Situation | What to do |
|---|---|
| No `.dev-files/objectives/` | Say nothing is diagnosable and stop; suggest `/orchestrate-dev` or `/switch-dev status` |
| Several active objectives, no argument | List them (`bash $S list`) and ask which; do not pick one silently |
| `jq` missing | The script exits 3. Read `objective.json`, `tasks/*.json`, `handoffs/*.json` by hand in that order and apply the classes manually; say the timeline was hand-built |
| A state file is not valid JSON | The script reports `unparseable-state-file`. Name the file; the next command is to fix it and run `objective-state.sh validate <id>` |
| `git` absent or not a repo | `git.available: false`; integration lag and dirty worktrees are unchecked — say so under Evidence |
| Findings are empty but the user says it failed | Read every handoff summary and the compaction snapshot; if the files still show nothing, the failure happened outside the recorded state (a PR, CI, a human step) and the report says exactly that |

## References

| File | Purpose |
|---|---|
| [`references/procedure.md`](references/procedure.md) | The long-form procedure and the `diagnosis.md` template with a worked example |
| [`references/failure-classes.md`](references/failure-classes.md) | Every failure class: detection rule, what the evidence must show, usual cause, next command |
| `scripts/objective-timeline.sh` | Deterministic timeline + findings as JSON (`--markdown` for the report skeleton) |
| [`../_shared/scripts/objective-state.sh`](../_shared/scripts/objective-state.sh), [`../_shared/scripts/handoff.sh`](../_shared/scripts/handoff.sh) | Locate the objective; read handoffs back |
| [`../switch-dev/SKILL.md`](../switch-dev/SKILL.md), [`../worker-dev/SKILL.md`](../worker-dev/SKILL.md), [`../orchestrate-dev/SKILL.md`](../orchestrate-dev/SKILL.md) | The three next commands this skill hands off to |
