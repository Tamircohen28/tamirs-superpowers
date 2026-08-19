# Policy: git — branches and worktrees

Work identity is the **objective and task**. The harness that happens to run
the work is not part of that identity.

## Branch model

```text
<default-branch>              # the objective's base_branch — resolved, never assumed
└── objective/<slug>          # integration branch — one per objective
    ├── worker/<slug>/001     # one per task, numbered to match task-001
    ├── worker/<slug>/002
    └── worker/<slug>/003
```

- `<slug>` is the objective `id`: `^[a-z0-9][a-z0-9-]*$`.
- The worker suffix is the task's three-digit number, so `worker/auth/002`
  pairs unambiguously with `task-002.json`.
- Worker branches merge **into the integration branch**, never into
  `base_branch` directly. The integration branch is what gets delivered.

## Worktree model

```text
.agent-worktrees/
└── <objective>/
    ├── integration/
    ├── task-001/
    ├── task-002/
    └── task-003/
```

A user-level equivalent outside the repository is equally valid and is
preferred when the repository must stay clean — for example
`~/.agent-worktrees/<repo>/<objective>/task-001`. Both layouts are supported;
resolution code must handle either.

`.agent-worktrees/` is gitignored.

## Provider is metadata

The provider (claude, codex, cursor, gemini, opencode) is recorded in
`task.provider` and nowhere else. It **must not** appear in:

- a branch name,
- a worktree path,
- a state directory name.

The old layout did the opposite — `.claude/.worktrees/...`,
`.cursor/.worktrees/...`, `.codex/.worktrees/...` — which made the harness part
of the work identity and meant the same task resumed under a different provider
looked like different work. Provider may still be appended to a *log line* or a
debug label; that is annotation, not identity.

## Migration — old worktrees are never orphaned

Existing platform-shaped worktrees stay understood. Worktree resolution
(`resolve-worktree.sh` and anything that calls it) must:

1. **Recognize both shapes.** Search the new objective layout *and* the legacy
   platform layouts (`.claude/.worktrees/`, `.cursor/.worktrees/`,
   `.codex/.worktrees/`, and the user-level equivalents) when locating an
   existing worktree for a branch or task.
2. **Never orphan existing work.** A worktree in the legacy layout with commits
   or uncommitted changes is live work. It is not deleted, not moved out from
   under its session, and not "cleaned up" as stale.
3. **Provide a list command** that enumerates every worktree found in either
   layout, with its branch, its layout shape, and whether it has uncommitted
   changes — so a user can see the whole picture before deciding anything.
4. **Provide an opt-in migration command** that moves a legacy worktree to the
   objective layout. Migration is explicit and per-worktree. There is no
   automatic bulk rewrite, and no destructive directory migration (spec §2.8).
5. **Prefer new, accept old.** New work is created in the objective layout.
   Work already living in the legacy layout continues there until the user
   migrates it.

## Rules

- The integration branch is created from `base_branch` at objective start and
  recorded in `objective.json`.
- A worker never merges, rebases onto, or pulls `base_branch` into its task
  branch — that is the integrator's decision, taken once, at integration
  (`core/roles/implementer.md`).
- The integrator does not rewrite worker branch history.
- No force-push to `base_branch` or to a branch another task is working on.
- Uncommitted work in any worktree is never discarded to make an operation
  succeed (`safety.md`, invariant 4).
- Worktree removal requires that the worktree is clean, or that the user
  explicitly authorized the loss.
