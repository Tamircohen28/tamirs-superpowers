---
alwaysApply: true
---

# Dev-Files Workspace (Auto-Applied)

Applies to **all agents** working in this repo (Claude Code, Cursor, Codex, Gemini CLI, OpenCode, and plain shell).

Session-local development artifacts and workflow state **must** live under **`.dev-files/`** at the repo root. That directory is git-ignored by default (see `.gitignore`); only `.dev-files/README.md` is tracked.

## Must go in `.dev-files/`

Create new files here — **never** under `skills/`, `docs/engineering/`, `core/`, or other tracked trees — when the artifact is:

- An implementation, enhancement, or refactor **plan**
- A **review**, comparison, or audit report
- An ad-hoc investigation **summary** or session notes
- Brainstorm output, option matrices, or other **scratch** meant for the current session
- **Objective/task/handoff state** for in-flight work (below)

| Subdir | Use |
|--------|-----|
| `objectives/` | Multi-agent workflow state — one directory per objective (below) |
| `plans/` | Enhancement plans, phased rollout notes |
| `reviews/` | Repo reviews, skill audits, comparison reports |
| `investigations/` | One-off investigation notes |
| `scratch/` | Ephemeral drafts |
| `archive/` | Retired trees moved out of `docs/` — optional local copy |

---

## Objective state layout

The canonical, machine-readable state of an in-flight objective:

```text
.dev-files/objectives/<objective-id>/
├── objective.json      # core/workflow/objective-schema.json
├── plan.md             # human-readable plan / DAG rationale
├── tasks/
│   ├── task-001.json   # core/workflow/task-schema.json
│   ├── task-002.json
│   └── task-003.json
├── handoffs/
│   ├── task-001.json   # core/workflow/handoff-schema.json
│   └── task-002.json
└── integration.json    # integration branch, composed tasks, Tier 2 results
```

`<objective-id>` is the objective slug — the same slug used for the `objective/<slug>` branch and the `.agent-worktrees/<slug>/` directory. See [`git-worktree-agent-workflow.md`](git-worktree-agent-workflow.md) and [`cross-platform-handoff.md`](cross-platform-handoff.md).

Rules:

- **JSON files are the source of truth**; `plan.md` is commentary. When they disagree, the JSON wins.
- Every file must validate against its schema in [`core/workflow/`](../../core/workflow/).
- No provider name appears in a path. Provider is a field inside the JSON.
- This state is **local-first**. A GitHub issue mirror is optional and generated from these files, never the reverse.

### Where objective state lives

Repo-local `.dev-files/objectives/` is the default. A worktree per task means each worker has its own `.dev-files/`, so the objective state that must be shared belongs in the **integration** worktree (or a user-level path outside the repo). A worker writes its handoff to the integration worktree's `.dev-files/objectives/<id>/handoffs/`, or commits it on its worker branch when the objectives directory is checked in (below).

---

## Gitignore policy

**Gitignored by default. Checking in is opt-in and deliberate.**

`.gitignore` ships:

```gitignore
.dev-files/*
!.dev-files/README.md
```

That covers `objectives/` along with everything else. Do not commit objective state incidentally — a merged PR that carries a stale `task-002.json` is noise, and handoff records may contain paths or notes that were only ever meant to be local.

A project **may** opt in to durable, reviewable workflow state — useful when handoffs cross machines or people and GitHub is not available. To opt in, un-ignore exactly the objectives tree in the consuming repo's `.gitignore`:

```gitignore
.dev-files/*
!.dev-files/README.md
!.dev-files/objectives/
```

Opting in is a per-repo decision, made by the user, recorded in that repo's `.gitignore`. An agent must not flip it on its own. **This repo does not opt in.**

---

## Must NOT use `.dev-files/` for

- Shipped plugin content (`skills/`, `hooks/`, `agents/`, `core/`, plugin manifests)
- Canonical user or engineering documentation (`docs/user/`, `docs/engineering/`)
- Canonical rules (`rules/`)
- Files the user explicitly asks to commit as product docs or plugin changes

## Examples (wrong → right)

| Wrong | Right |
|-------|-------|
| `skills/toolkit/SKILL-ENHANCEMENT-PLAN.md` | `.dev-files/plans/skill-enhancement-plan.md` |
| `docs/engineering/external-repo-comparison-report.md` (session report) | `.dev-files/reviews/external-repo-comparison-report.md` |
| `core/workflow/my-objective.json` (an actual objective) | `.dev-files/objectives/my-objective/objective.json` |

## When moving or cleaning up

If you find session plans or reviews already under `skills/`, `core/`, or `docs/`, **move** them into `.dev-files/` instead of expanding tracked trees. Do not delete user content without confirming — see [`core/policies/safety.md`](../../core/policies/safety.md).

## Where this rule is loaded

| Platform | How agents see this rule |
|----------|--------------------------|
| Claude Code | `rules/dev/dev-files-workspace.md` (plugin rules; `alwaysApply: true`) |
| Cursor | `.cursor/rules/dev-files-workspace.mdc` (thin adapter → this file) |
| Codex / Gemini CLI / OpenCode | `AGENTS.md` links here; read this file when editing the repo |

See also: [`rules/README.md`](../README.md) for the full rule index.
