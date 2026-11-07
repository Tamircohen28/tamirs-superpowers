# ADR 005 — Session worktrees live outside `~/.claude`, at a configurable root

**Status:** Accepted — 2026-11-07 ([issue #404](https://github.com/Tamircohen28/tamirs-superpowers/issues/404))

## Context

The single-task worktree model gives every session one worktree, `<root>/<repo>/<slug>`
on branch `wt/<slug>`, and `hooks/enforce-worktree-edits.sh` denies repo edits anywhere
else. Through 5.6.13 the root was hard-coded as `~/.claude/worktrees`
(`hooks/lib/worktree-common.sh`, no override).

Claude Code treats every `.claude` directory as a **protected path**. In `default` and
`acceptEdits` mode each write there prompts, and a `permissions.allow` rule cannot
pre-approve it, because "the safety check runs before Claude Code evaluates allow rules"
([permission modes, Protected paths](https://code.claude.com/docs/en/permission-modes.md)).
The exemption for Claude's own `.claude/worktrees/` covers the repo-root native layout
(`<repo>/.claude/worktrees/<name>`), not `~/.claude/worktrees/<repo>/<slug>`. The plugin's
own policy sends every edit into the session worktree, so any session outside
`bypassPermissions` met a prompt on almost every edit.

## Decision

1. **The root is configurable**, resolved once per hook in `worktree-common.sh`:
   `SUPERPOWERS_WORKTREE_ROOT` (every host) > the `worktree_root` plugin option
   (Claude Code exports it as `CLAUDE_PLUGIN_OPTION_WORKTREE_ROOT`) > the default. A leading
   `~` or `$HOME` is expanded; a relative value or `/` is ignored and the next source wins.
2. **The default is `~/.session-worktrees`.** The issue proposed `~/.agent-worktrees`; that
   name was rejected because it is already the objective layout's marker.
   `is_objective_worktree_path` matches any path containing `/.agent-worktrees/`, the
   OpenCode guard and `resolve-worktree.sh` do the same, and
   [`core/policies/git.md`](../../../core/policies/git.md) documents
   `~/.agent-worktrees/<repo>/<objective>/task-NNN` as the user-level objective location. A
   session worktree there would read as an objective worktree to every one of those
   consumers. The retention pass also deletes clean worktrees older than
   `WORKTREE_RETENTION_DAYS` under the session root, so that root must hold session worktrees
   and nothing else. A name the objective model and people's hand-made worktrees do not
   already use keeps the two layouts apart by construction, not by check order.
3. **A new classification, `session-global`**, for a worktree under the configured root.
   `legacy-global` keeps meaning `~/.claude/worktrees/<repo>/<slug>`. `classify_worktree_path`
   checks an explicit objective root (`SUPERPOWERS_AGENT_WORKTREE_ROOT`) first, then the
   session root, then the `/.agent-worktrees/` name match. A user who points `worktree_root`
   at a path containing `.agent-worktrees` therefore still gets session worktrees there, and
   objective worktrees keep their meaning. Logical and physical spellings of the root are
   both matched, because git reports physical paths (`/private/var/…` on macOS).
4. **The legacy root is recognised, never created.** Edits under `~/.claude/worktrees` stay
   allowed, and so do native `<repo>/.claude/worktrees/<name>` worktrees. When a session's
   worktree is live at the legacy root and not at the new one,
   `session_worktree_path_for` returns the legacy path, so a session that started on an
   older plugin version is pointed at its real worktree. It is not reported as removed and
   does not get a second worktree whose `git worktree add` would fail on the checked-out
   branch. Every creation path (prompt hook, `WorktreeCreate`, rebuild-on-edit) uses the
   configured root. The retention pass sweeps both roots, the legacy one under the same
   `.cleanup.lock` an older version takes.
5. **Migration is a separate, opt-in script.** `scripts/worktrees-migrate.sh` (dry run by
   default, `--yes` to act) moves only idle legacy worktrees, with `git worktree move` and
   never `--force`. It skips a worktree that is dirty, claimed (`~/.agent-work-claims`), owned
   by an unfinished objective task, the working directory of a running process, modified in
   the last 60 minutes, or whose destination already exists. After a move it rewrites the
   session-state records that name the old path. Nothing migrates automatically, for the
   reason [`branch-worktree-model.md`](../architecture/branch-worktree-model.md) gives:
   moving a worktree out from under a running agent is the destructive migration this
   repository forbids.

## Consequences

- Sessions in `default` and `acceptEdits` mode stop prompting on every edit, with no allow
  rule to maintain.
- `worktree_root` and `SUPERPOWERS_WORKTREE_ROOT` are now an interface. Renaming either is
  a breaking change.
- Two roots exist for as long as legacy worktrees do. Recognising both costs one extra
  prefix check per edit, and the classification has one more kind. `scripts/worktrees-migrate.sh`
  is how a user gets back to one.
- The `worktree_root` option reaches hooks only. A script run from a shell does not see it,
  so the migration script's `--to` must be given when the option, not the env var, set the
  root. The user docs say so.
- Hosts without plugin options (Codex, Cursor, Gemini CLI, OpenCode) use the env var or the
  default. The OpenCode guard mirrors the resolution in `sessionWorktreeRoot`
  (`platforms/opencode/plugin/rules.ts`).

---

<p align="center"><a href="https://github.com/Tamircohen28">Have a Question?</a>&nbsp;·&nbsp;<a href="https://github.com/Tamircohen28/tamirs-superpowers/issues/new/choose">Open an Issue</a></p>
