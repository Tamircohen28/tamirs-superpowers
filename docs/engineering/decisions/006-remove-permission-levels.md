# ADR 006 — Remove the permission levels

**Status:** Accepted — 2026-11-08 (supersedes [ADR 004](004-permission-levels.md))

## Context

[ADR 004](004-permission-levels.md) shipped in 5.2.0: an action catalog, a resolver, four levels
(supervised to unattended), `/plugin-config`, a `permission_level` option, three permission hooks,
resolver gates inside skills and scripts, and per-platform artifacts (Gemini policy, OpenCode reader,
Codex rules). In daily use the maintainer got permission prompts constantly, even at level `unattended`
with Claude Code in `bypassPermissions`: Claude Code honours a hook `ask` in every mode, bypass
included, so every gated action still stopped for a human. For a solo maintainer the feature cost more
in interruptions and upkeep than it protected; the host's own permission mode already says how much
the agent may do unattended.

## Decision

Remove the feature in **6.0.0**: the catalog (`core/permissions/`), the resolver and its library,
`/plugin-config` on every platform, the `permission_level` option, the permission hooks, the skill and
script gates, and the platform artifacts. Keep the protections that existed before #348:

- `guard-sensitive-files.sh` + `hooks/lib/write-targets.py` — still deny writes to lockfiles and
  generated files (`PM_ALLOW_PROTECTED=1` to override) and to host settings and the installed plugin cache;
  the asks it gained in 5.2.0 (a source checkout's own guard files, git replays onto protected paths) are gone;
- `enforce-worktree-edits.sh`, `protect-other-branches.sh`, `skill-creator-guard.sh`;
- `docker-guard.py` — denies durable docker state, `PM_ALLOW_DOCKER=1` approves one command, and under
  Claude Code `bypassPermissions` it lets everything through except a prune (deny);
- the host permission rules in `platforms/claude/settings.d/`.

No plugin hook emits a permission `ask` any more: a hook either denies or stays out of the way.

## Consequences

**Easier:**

- Skills return to their own chat confirmations where they had one before the gates; the host's own
  permission mode is the one control for how much runs unattended.
- Far less code to keep in sync across five platforms (no catalog, resolver, policies or per-host
  enforcement quirks), and fewer test suites.

**Harder / migration:**

- There is no per-action knob any more. Someone who wants a stricter setup uses the host's own
  permission mode and rules.
- Stale files from 5.x are no longer read and can be deleted:
  `~/.config/tamirs-superpowers/permissions.json`, any project `.tamirs-superpowers/permissions.json`,
  and the plugin's tickets and stamps under `~/.local/state/tamirs-superpowers/`.
- The research under [`research/permissions/`](../research/permissions/) is kept as history.

---

<p align="center"><a href="https://github.com/Tamircohen28">Have a Question?</a>&nbsp;·&nbsp;<a href="https://github.com/Tamircohen28/tamirs-superpowers/issues/new/choose">Open an Issue</a></p>
