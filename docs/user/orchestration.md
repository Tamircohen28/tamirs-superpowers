# Orchestration

How one request becomes one pull request — with or without parallel agents.

Prerequisite reading: [Concepts](concepts.md).

---

## The flow

```text
you: "implement the auth system"
        │
        ▼
  /orchestrate-dev
        │  decide: orchestrate, or fall through to /start-dev
        │  resolve objective → task graph (disjoint write scopes)
        │  check capabilities → pick a mode
        ▼
  workers (/worker-dev, one per task)
        │  implement inside scope → Tier 1 validation → commit → handoff
        ▼
  integration  (objective/<slug>)
        │  merge worker branches in dependency order, resolve conflicts here
        │  combined-diff review → fix loop
        │  Tier 2 validation
        ▼
  /deliver-dev  → ONE pull request
        ▼
  /pr-dev       → review threads, CI, merge
```

The two rules that shape all of it: a task ends at **commit + handoff**, and an objective
ends at **one PR**.

---

## Step by step

**1. Decide whether to orchestrate.** Orchestration costs branches, worktrees, state files,
and an integration pass. A one-file fix should not pay it. `/orchestrate-dev` falls through
to `/start-dev` when the request is one coherent change, in one write scope, with no ordering
constraint and no genuinely separate specialist pass. It says which way it decided, in one
line, before doing anything.

**2. Resolve the objective.** Free text is slugified into an objective id; a spec or plan
file becomes the source of tasks; an issue number is fetched; an existing objective id means
*resume*. It always checks for an existing objective first.

**3. Read the repo's own rules.** `CLAUDE.md`, `AGENTS.md`, the project's rules files, and
the test/lint commands that actually exist. Those commands get handed to every worker;
guessing them wastes every worker's run.

**4. Check capabilities before promising concurrency.**

```bash
jq -r '.platforms | to_entries[] | "\(.key): subagents=\(.value.capabilities.subagents.status) parallel=\(.value.capabilities.parallel_subagents.status)"' \
  core/capabilities/platforms.json
```

**5. Build the task graph.** Tasks get disjoint write scopes and explicit dependencies.
`objective-state.sh validate` fails the graph when two concurrent tasks share a scope — that
is fixed by re-planning, not by overriding.

**6. Create branches and worktrees.** `objective/<slug>` cut from the base branch, then
`worker/<slug>/NNN` per task.

**7. Dispatch.** Each worker — subagent or your own next turn — runs `/worker-dev` and is
given its objective and task ids, its scope globs, its branch and worktree, the repo's Tier 1
command, and the prohibitions verbatim.

**8. Collect handoffs and integrate.** Worker branches merge into the objective branch in
dependency order. Conflicts are resolved *here*, by the integrator, nowhere else.

**9. Review the combined diff**, not the worker diffs — completeness against the stated
objective, coherence across workers (duplicated helpers, two names for one concept),
leftovers, unresolved handoff followups, and files no task declared.

**10. Tier 2 validation, then `/deliver-dev`** — full gates, push, one PR, handed to
`/pr-dev`.

---

## Execution modes

`/orchestrate-dev` picks a mode from the capability registry and **says which one and why**.

| `subagents` | `parallel_subagents` | Mode | Behavior |
|---|---|---|---|
| native | native | **Concurrent** | Independent tasks dispatched together |
| native | unknown / partial / unsupported | **Serialized dispatch** | One subagent at a time |
| unsupported / unknown | — | **Sequential** | No subagents at all |

Missing registry entry, or no entry for your platform ⇒ **sequential**, stated out loud.
Today the registry records `parallel_subagents` as `native` only on Claude Code; everywhere
else it is `unknown`, which means serialized or sequential. That is the honest reading, not
a limitation invented here — see [platform-differences.md](platform-differences.md).

---

## The sequential path is a first-class option

Sequential is not a degraded consolation mode. It is the same workflow with the concurrency
removed:

```text
objective → task-001 → handoff → task-002 → handoff → task-003 → handoff → integration → one PR
```

Same task graph. Same disjoint scopes. Same handoff files. Same integration branch, same
combined-diff review, same Tier 2 gate, same single PR. Only wall-clock time changes.

It runs when:

- your platform has no subagents (most of them — check the registry);
- you asked for a single-threaded run;
- the task graph is a straight dependency chain anyway, so concurrency would buy nothing;
- you want every step in one readable transcript.

In sequential mode you may skip per-task worktrees and commit task by task directly onto the
objective branch — `/orchestrate-dev` says when it is doing that. Between tasks, context
hygiene matters more than in concurrent mode: each task starts from its dependencies'
handoff files rather than from whatever is left in the window.

To force it, say so: *"run this sequentially"* / *"one task at a time, no subagents."*

---

## Resuming an interrupted objective

Objective state is files on disk, so a crash, a `/clear`, a closed laptop, or a switch to a
different tool loses nothing.

```bash
S=skills/dev-workflow/_shared/scripts/objective-state.sh

bash $S list                       # every objective, with status
bash $S show <objective-id>        # the objective
bash $S tasks <objective-id>       # per-task status, branch, worktree
bash $S integrate-ready <objective-id>
bash skills/dev-workflow/_shared/scripts/handoff.sh list <objective-id>
```

Then re-invoke with the objective id: `/orchestrate-dev <objective-id>`. It re-reads state,
skips everything already `completed`, and picks up at the first task that is `ready`.

**Never re-run a task whose handoff already exists — read the handoff.** Re-running
duplicates commits and invalidates the integration plan the other tasks were built against.

Resume also works across platforms, because nothing in the state names a provider: an
objective started under Claude Code resumes under Codex or Gemini CLI from the same files
and the same branches.

---

## When things go sideways

| Situation | What happens |
|---|---|
| A worker fails | One retry (`--bump-attempts`). A second failure means **re-plan** the task, not re-run it. |
| A handoff is `partial` or `failed` | The orchestrator decides — re-plan, drop the task, or narrow the objective. It never quietly integrates around it. |
| A worker wrote outside scope | `handoff.sh emit` refuses it. The work becomes a followup or a new task. |
| Two tasks conflicted | The graph was wrong. Fix the graph, then re-integrate. |
| A worker opened a PR | That is a bug in the dispatch prompt, and gets reported as one. |
| No `gh` available | Delivery ends at a pushed integration branch and says exactly that — never a claim that a PR exists. |

---

## Related

- [`core/policies/delivery.md`](../../core/policies/delivery.md) — one-PR default and its exceptions
- [`core/policies/validation.md`](../../core/policies/validation.md) — the tiers
- [`core/policies/git.md`](../../core/policies/git.md) — branch and worktree model
- [Engineering: orchestration state machine](../engineering/architecture/orchestration-state-machine.md)
