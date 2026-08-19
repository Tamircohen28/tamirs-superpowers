---
alwaysApply: false
globs:
  - "tooling/**/*"
  - ".github/**/*"
  - "skills/dev-workflow/**/*"
  - "scripts/**/*"
  - "hooks/**/*"
---

# GitHub Transport Policy

This rule governs **how** a tool talks to GitHub, and **whether** GitHub is required at all. It is a transport policy — not a core orchestration requirement.

---

## 1. GitHub is an optional feature dependency

`gh` is an **optional feature dependency**, not a required runtime dependency (see [`user-facing-script-standards.md`](user-facing-script-standards.md) for the dependency tiers).

Required to use the core workflow: **git**, a POSIX shell, and the provider's own CLI. Nothing else.

Objectives, tasks, worktrees, handoffs, integration, and Tier 0–2 validation all work with no GitHub account, no network, and no `gh` installed. Local state under `.dev-files/objectives/` is the primary store ([`dev-files-workspace.md`](dev-files-workspace.md)).

### Degradation rule

A skill or script that touches GitHub **must** detect `gh` and degrade explicitly:

```bash
if command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  gh pr create --fill
else
  printf 'gh unavailable — skipping PR creation. Branch %s is pushed; open the PR manually.\n' "$branch" >&2
fi
```

Three acceptable behaviors when `gh` is missing or unauthenticated:

1. **Skip the optional step** and say so plainly (issue mirroring, label sync, auto-merge, remote branch delete).
2. **Fall back to plain git** where git can do the job (default-branch detection, fetching, pushing, branch cleanup).
3. **Stop with a clear message** naming `gh` as the missing dependency and what the user should install or run.

Never silently pretend a GitHub step succeeded. Never fail an entire objective because an optional mirror was unavailable.

**The one exception:** when a GitHub action *is* the requested operation — "open a PR", "merge PR #12", "create an issue", "read review comments" — a missing or unauthenticated `gh` is a hard, reportable failure. Say which command is missing and stop; do not invent a local substitute for a remote action the user asked for.

### Things that must never require `gh`

- Resolving the default branch (`git symbolic-ref refs/remotes/origin/HEAD`, falling back to `main`)
- Creating, listing, or migrating worktrees
- Reading or writing objective/task/handoff state
- Tier 0, Tier 1, and Tier 2 validation
- Any handoff between providers

---

## 2. Use `gh`, not GitHub MCP, in development context

When GitHub *is* being used, dev-time tooling uses the `gh` CLI. Do not reach for GitHub MCP tools in contributor tooling, CI scripts, hooks, or skill scripts.

| Context | Use |
|---------|-----|
| CI scripts, governance checks, build tooling | `gh` CLI |
| `rules/` and skill scripts | `gh` CLI examples |
| Plugin runtime agents investigating a production issue | GitHub MCP |

### Why

GitHub MCP tools are authenticated by a runtime credential tied to an investigation session. Using them in dev scripts would require a live MCP session for work that should be self-contained, mix runtime and dev-time auth paths, and produce brittle scripts.

`gh` reads `~/.config/gh/hosts.yml` — a stable developer credential. Derive tokens with `gh auth token`; never prompt a user to paste one.

```bash
# CORRECT — dev context
gh pr list --repo Tamircohen28/tamirs-superpowers --state open
gh api repos/anthropics/claude-code/releases/latest

# WRONG — dev context (MCP tools are runtime-only)
# githubSearchPullRequests(...)
```

### Exceptions

- A plugin agent investigating a GitHub repo during a production investigation uses GitHub MCP — that is runtime, not dev context.
- `docs/engineering/` prose describing how a runtime agent works may reference MCP tools.

---

## 3. Declaring the dependency

Any skill whose full behavior needs `gh` must declare it — in its `SKILL.md` (per [`skill-quality-standards.md`](skill-quality-standards.md)) and in [`core/capabilities/platforms.json`](../../core/capabilities/platforms.json) where the capability is platform-shaped. `scripts/doctor.sh` reports `gh` presence and auth state so a user can see which optional features are live before hitting a failure.
