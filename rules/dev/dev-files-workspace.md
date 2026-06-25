---
alwaysApply: true
---

# Dev-Files Workspace (Auto-Applied)

Applies to **all agents** working in this repo (Claude Code, Cursor, Codex, and shell).

Session-local development artifacts **must** live under **`.dev-files/`** at the repo root. That directory is git-ignored (see `.gitignore`); only `.dev-files/README.md` is tracked.

## Must go in `.dev-files/`

Create new files here — **never** under `skills/`, `docs/engineering/`, or other tracked trees — when the artifact is:

- An implementation, enhancement, or refactor **plan**
- A **review**, comparison, or audit report (e.g. external-repo comparison)
- An ad-hoc investigation **summary** or session notes (not the pipeline’s `report.md`)
- Brainstorm output, option matrices, or other **scratch** meant for the current session

Suggested layout (create subdirs as needed):

| Subdir | Use |
|--------|-----|
| `plans/` | Enhancement plans, phased rollout notes |
| `reviews/` | Repo reviews, skill audits, comparison reports |
| `investigations/` | One-off investigation notes not produced by `/investigate` |
| `scratch/` | Ephemeral drafts |
| `archive/` | Retired trees moved out of `docs/` (e.g. old `app-plans`, `cursor-plans`) — optional local copy |

## Must NOT use `.dev-files/` for

- Shipped plugin content (`skills/`, `hooks/`, plugin manifests)
- Canonical user or engineering documentation (`docs/user/`, `docs/engineering/`)
- Pipeline run directories (`production-master/<slug>-<run>/`, `debug/`, `.pm-investigate/`)
- Files the user explicitly asks to commit as product docs or plugin changes

## Examples (wrong → right)

| Wrong | Right |
|-------|-------|
| `skills/toolkit/SKILL-ENHANCEMENT-PLAN.md` | `.dev-files/plans/skill-enhancement-plan.md` |
| `docs/engineering/external-repo-comparison-report.md` (session report) | `.dev-files/reviews/external-repo-comparison-report.md` |
| `docs/repo-review-2026-05-21.md` | `.dev-files/reviews/repo-review-2026-05-21.md` |

## When moving or cleaning up

If you find session plans or reviews already under `skills/` or `docs/`, **move** them into `.dev-files/` (matching subdir) instead of expanding tracked docs. Do not delete user content without confirming.

## Where this rule is loaded

| Platform | How agents see this rule |
|----------|--------------------------|
| Claude Code | `rules/dev/dev-files-workspace.md` (plugin rules; `alwaysApply: true`) |
| Cursor | `.cursor/rules/dev-files-workspace.mdc` (thin adapter → this file) |
| Codex | `AGENTS.md` (summary) + read this file when editing the repo |

See also: `AGENTS.md`, `CLAUDE.md` (Claude-only addenda), `rules/dev/` (canonical contributor rules).
