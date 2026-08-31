# Hook classification

Every hook in `hooks/` classified into exactly one category, with the platforms
it applies to, what happens on a platform that has no hooks, and whether it
should ship to ordinary plugin users at all.

This exists because "hooks" is not one thing. A hook that prevents an agent from
destroying another agent's work and a hook that prints a changelog on startup
are unrelated products that happen to share a delivery mechanism, and treating
them as one bundle is why the current set is shipped wholesale to every user
regardless of what they installed the plugin for.

## Categories

| Category | Definition | Removable? |
|---|---|---|
| **core-safety-invariant** | Prevents data loss, work destruction, or a policy violation that cannot be undone. The behavior must exist on every platform, in a hook or otherwise. | No — must be replaced, never dropped |
| **worktree-lifecycle** | Creates, locates, records, or retires an agent workspace. | No, but degrades to explicit skill-driven setup |
| **claude-convenience** | Improves the experience of one Claude Code session. Nothing breaks without it. | Yes |
| **contributor-only** | Useful when working **on this plugin** (or on agent config generally), noise for someone merely using it. | Yes — should not be on by default for users |
| **optional-notification** | Tells a human something. No effect on the work. | Yes |
| **platform-specific** | Bound to one runtime's event or binary; has no meaning elsewhere. | Yes |

A hook can have secondary characteristics (most `worktree-lifecycle` hooks are
also bound to Claude Code events); the table assigns the **primary** category —
the one that answers "what breaks if this is gone".

## The classification

| Hook | Event | Category | Platforms | Without hooks | Ship to users? |
|---|---|---|---|---|---|
| `protect-other-branches.sh` | PreToolUse `Bash\|Shell` | **core-safety-invariant** | Claude Code, Cursor | **Unprotected.** Concurrent agents overwrite each other's branches and PRs. | **Yes** |
| `release-agent-claims.sh` | SessionEnd | **core-safety-invariant** | Claude Code, Cursor | Claims expire on their own staleness window instead of immediately | **Yes** |
| `enforce-worktree-edits.sh` | PreToolUse `Edit\|Write\|…` | **core-safety-invariant** | Claude Code, Cursor | Main-checkout edits become an advisory rule in `AGENTS.md` | **Yes** |
| `guard-sensitive-files.sh` | PreToolUse `Edit\|Write\|…` **and `Bash`** | **core-safety-invariant** | Claude Code, Cursor | Lockfiles, build output and workflows are hand-editable | **Yes** |
| `goal-condition-lint.sh` | UserPromptSubmit | **core-safety-invariant** | Claude Code only (`/goal`) | **Unprotected.** A `/goal` condition that cannot terminate blocks every turn-end until the harness cap trips — 21 blocks on 2026-08-17, ~15 on 2026-08-31. | **Yes** |
| `capture-task-slug.sh` | UserPromptSubmit | **worktree-lifecycle** | Claude Code only | No automatic workspace; skills must create one explicitly | **Yes**, opt-out |
| `session-init.sh` | SessionStart | **worktree-lifecycle** | Claude Code only | No session dir, no session-files reload, no stale-worktree pruning | **Yes**, opt-out |
| `session-end.sh` | SessionEnd | **worktree-lifecycle** | Claude Code only | Session files are not archived; stale worktrees accumulate | **Yes**, opt-out |
| `worktree-create.sh` | WorktreeCreate | **worktree-lifecycle** | Claude Code only | Also runnable as a CLI (`--list`, `--migrate`, `--objective/--unit`) | **Yes** |
| `worktree-remove.sh` | WorktreeRemove | **worktree-lifecycle** | Claude Code only | Worktrees are removed by hand with `git worktree remove` | **Yes** |
| `check-done.sh` | Stop | **claude-convenience** | Claude Code only | No definition-of-done reminder; the rule lives in `AGENTS.md` | **Yes** |
| `directory-added.sh` | DirectoryAdded | **claude-convenience** | Claude Code 2.1.219+ | The same warning arrives later, at the first denied edit | **Yes** |
| `goal-compact-reminder.sh` | UserPromptSubmit | **claude-convenience** | Claude Code only (`/compact`, `/goal`, `/login`) | Nothing; a cache-warmth tip is lost | Optional |
| `scope-decompose-reminder.sh` | UserPromptSubmit | **claude-convenience** | Any (text heuristic) | Nothing; a decomposition nudge is lost | Optional |
| `skill-creator-guard.sh` | PreToolUse `Edit\|Write\|…` | **claude-convenience** | Claude Code, Cursor | Hand-written `SKILL.md` files are not intercepted | Optional |
| `handoff-reminder.sh` | SessionEnd | **claude-convenience** | Claude Code only | No handoff nudge; `switch-dev` is still invocable | Optional |
| `plugin-reload-reminder.sh` | PostToolUse `Edit\|Write` | **contributor-only** | Claude Code only | Nothing; the author reloads manually | **No** — plugin authors only |
| `plugin-version-watch.sh` | Stop | **contributor-only** | Claude Code only | No 24h `/platform-sync` nudge | **No** — agent-config authors only |
| `wix-ip-guard.sh` | PostToolUse `Edit\|Write` | **contributor-only** | Any | Nothing | **No** — see *Must not ship as-is* |
| `validate-report-links.sh` | PostToolUse `Write` | **contributor-only** | Claude Code only | `report.md` links are unchecked | **No** — see *Must not ship as-is* |
| `show-changelog.sh` | SessionStart | **platform-specific** | Claude Code only (shells out to `claude --version`) | Nothing | Optional |
| `notify.sh` | Notification | **optional-notification** | Claude Code + a terminal that honours OSC 99, or macOS `osascript` | No desktop notification | Optional |
| `ensure-exit.sh` | UserPromptSubmit | **optional-notification** | Any (needs `curl`) | No VPN/exit-node check | Optional (already env-gated, silent by default) |

### Shared libraries

| File | Role |
|---|---|
| `lib/hook-output.sh` | Claude Code / Cursor PreToolUse JSON dialect. Cursor fail-closes on empty stdout; Claude Code treats it as allow — so every guard must emit valid JSON either way. |
| `lib/agent-claim.sh` | The cross-tool work-claim store behind `protect-other-branches.sh`. Tool-neutral by design: Claude Code, Cursor and Codex read and write the same files. |
| `lib/worktree-common.sh` | Single-task worktree model (`~/.claude/worktrees/<repo>/<slug>`, `wt/*` branches) plus dependency-install and retention policy. **Protected**: any change requires shellcheck plus exercising both `capture-task-slug.sh` and `worktree-create.sh`. |
| `lib/objective-common.sh` | Objective model — `.agent-worktrees/<objective>/{integration,task-NNN}`, `objective/<slug>` and `worker/<slug>/NNN` branches, active-objective detection, and cross-layout classification. |

## What "without hooks" actually means

Only Claude Code and Cursor execute anything in `hooks/`. Cursor sees the four
PreToolUse guards (via `lib/hook-output.sh`'s dual dialect); it has no
UserPromptSubmit, SessionStart/End, WorktreeCreate/Remove, DirectoryAdded,
Notification or Stop equivalent. Codex, Gemini CLI and OpenCode execute none of
them.

That matters for exactly one category. A convenience or a notification that
never fires is a smaller product, not a broken one. A **core safety invariant**
that never fires is a promise the plugin is not keeping, and it must be
re-stated somewhere the platform does read:

| Invariant | Enforced by hook | Fallback where hooks do not run |
|---|---|---|
| One agent per branch / PR / issue | `protect-other-branches.sh` | `core/policies/git.md`, restated in `AGENTS.md`; the claim store is tool-neutral, so a platform can implement the check itself |
| Repo edits happen in a worktree, never the main checkout | `enforce-worktree-edits.sh` | `core/policies/git.md`, restated in `AGENTS.md` and each platform's rules adapter |
| Generated and protected files are not hand-edited | `guard-sensitive-files.sh` | `AGENTS.md` + CI (the real backstop — CI catches it regardless of platform) |

The honest statement of support is therefore **"enforced on Claude Code and
Cursor; documented and CI-checked everywhere else"** — never "supported".
Silently pretending the guard ran is the failure mode this table exists to
prevent.

## Objective-model changes

Four hooks changed shape for the one-objective/many-workers model. The single
task model is unchanged when no objective is active.

**`capture-task-slug.sh` — stands down under an orchestrator.** Its original
contract was "one prompt creates one task worktree", which under an objective
actively splits the work: the orchestrator has already laid out
`.agent-worktrees/<objective>/{integration,task-NNN}`, and a prompt-derived
`wt/<slug>` worktree beside it is a second home for work that already has one.
It now detects an active objective (`SUPERPOWERS_OBJECTIVE_ID`, or an
`objective.json` with `status: "active"`) and creates nothing, reporting the
objective's workspaces instead. With no objective, behavior is byte-identical.

**`enforce-worktree-edits.sh` — knows every layout.** It allows
`objective-integration`, `objective-worker`, `legacy-platform`, `legacy-global`
and `native-claude` workspaces, and denies only the main checkout. The legacy
shapes are listed deliberately: a worker whose worktree the guard did not
recognize would be denied every edit, so the work would have nowhere legal to
go. Recognizing a platform-shaped path is not endorsing it — nothing creates
one. Under an active objective the denial message points at the objective's
worktrees rather than telling the agent to make a new one.

**`protect-other-branches.sh` — an integrator carve-out, scoped to nothing
else.** Integration means combining other agents' commits, so a guard that
treats "another agent holds this branch" as a universal veto makes the job
impossible by construction. Reading was already unguarded — only `git push` and
mutating `gh` commands are detected, so `fetch`/`log`/`show`/`cherry-pick`/
`merge` never reach the claim check. The carve-out adds one thing: with
`SUPERPOWERS_ROLE=integrator` and an active objective, a push to
`worker/<that objective>/NNN` is allowed. It does **not** extend to the
integration branch (two integrators still collide), to `main`, to another
objective's workers, or to PRs and issues.

**`check-done.sh` — validation-tier aware.** It used to demand green CI from
whoever stopped. A worker cannot satisfy that and was never meant to: its
contract ends at commit + handoff, and it has no PR for CI to be green on. The
tier is resolved from `SUPERPOWERS_VALIDATION_TIER`, then the task's
`validation_tier`, then the branch (`worker/*` → 1, `objective/*` → 2), and with
no tier context at all the original message is emitted unchanged.

## Dependency installation

`run_worktree_post_setup` runs at most `SUPERPOWERS_MAX_CONCURRENT_INSTALLS`
(default 2) installers at a time, shares one package-manager cache across
worktrees, skips when the lockfile digest matches the last successful install,
and can be switched off entirely.

| Variable | Default | Effect |
|---|---|---|
| `SUPERPOWERS_WORKTREE_INSTALL_DEPS` | `auto` | `0`/`false`/`off`/`no` disables installs entirely |
| `SUPERPOWERS_MAX_CONCURRENT_INSTALLS` | `2` | Cap on simultaneous installers |
| `SUPERPOWERS_INSTALL_SLOT_WAIT` | `300` | Seconds to wait for a slot before skipping |
| `SUPERPOWERS_PKG_CACHE_DIR` | `~/.claude/cache/pkg` | Shared npm/yarn/pnpm/poetry/pip cache |

The success stamp lives in the worktree's **git directory**, not its tree: an
untracked file at the top level makes `git status --porcelain` non-empty, which
is exactly the signal `cleanup_stale_worktrees` uses to decide a worktree still
holds work — a stamp in the tree would quietly disable stale cleanup.

## Must not ship as-is

Two hooks encode one employer's internal namespace into a plugin distributed to
everyone. Both are `contributor-only` above; neither should be in a default
install.

- **`wix-ip-guard.sh`** exists to catch a specific employer's registries, APIs
  and scoped packages leaking into personal projects. That is a real need for
  its author and meaningless to every other user. It should become a
  **configurable deny-list** (patterns from config or env, empty by default) so
  the mechanism ships and the specific names do not.
- **`validate-report-links.sh`** hardcodes `wix-analytics` in its Grafana URL
  check, alongside generic GitHub/Slack/placeholder checks. The generic checks
  are fine; the employer-specific hostname violates the repo's own hard
  constraint against internal references and should be moved to configuration.

Neither was changed here — removing a guard someone relies on is a product
decision for the repo owner, not a refactor side effect. Both are recorded in
`session-files/requests/hooks-audit.md`.

## Recommended packaging

Not a change made here — the shape the table argues for.

| Tier | Contents | Default |
|---|---|---|
| **safety** | `protect-other-branches`, `release-agent-claims`, `enforce-worktree-edits`, `guard-sensitive-files`, `goal-condition-lint` | on |
| **worktree** | `capture-task-slug`, `session-init`, `session-end`, `worktree-create`, `worktree-remove` | on, opt-out |
| **convenience** | `check-done`, `directory-added`, `goal-compact-reminder`, `scope-decompose-reminder`, `skill-creator-guard`, `handoff-reminder`, `show-changelog` | on, opt-out |
| **notification** | `notify`, `ensure-exit` | off unless configured |
| **contributor** | `plugin-reload-reminder`, `plugin-version-watch`, `wix-ip-guard`, `validate-report-links` | off for users |

## Tests

| File | Covers |
|---|---|
| `tests/test-concurrency-guard.sh` | The claim guard's general contract (46 cases, pre-existing) |
| `tests/test-integrator-carveout.sh` | The integrator exception **and its boundaries** |
| `tests/test-worktree-objective.sh` | Stand-down under an objective, both layouts accepted, `--list`/`--migrate`, removal refusals, dependency-install controls |
| `tests/test-check-done-tiers.sh` | Tier resolution and per-tier wording, including the unchanged no-tier default |
| `tests/test-statusline.sh` | Piped JSON, `</dev/null`, and an open pipe with no writer — each under a hard wall-clock timeout |
| `tests/test-goal-condition-lint.sh` | Which `/goal` conditions are refused and — weighted deliberately heavier — which must **not** be, including near-misses, carve-outs, the `force:` override, and that the menu's own recommended rewrite passes the hook |

Run them with `make test-hooks`.
