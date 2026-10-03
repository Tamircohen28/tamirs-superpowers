# Policy: safety

The line this document draws is the point: **some rules are invariants and some
rules are configuration, and the repository has historically treated them as
one undifferentiated list.** Mixing them makes the real invariants
negotiable-looking and makes the preferences feel unbreakable. They are
separated below.

## Hard invariants — never violated, on any platform, under any configuration

These are not defaults. No user setting, task policy, or provider capability
turns them off.

1. **Never commit secrets.** No tokens, keys, passwords, or credentials in
   tracked files. Config uses `${ENV_VAR}` placeholders. If a secret is
   discovered, report it — do not quietly rewrite history to hide it.
2. **Never silently bypass a required security check.** Disabling, skipping, or
   stubbing a security gate to get a green result is prohibited. Failing loudly
   is the correct outcome.
3. **Never modify unrelated user work.** Files outside the task's declared
   `scope[]` are read-only, including another concurrent task's files and
   anything the user is editing.
4. **Never destroy uncommitted work.** No `git checkout --`, `git stash drop`,
   `git reset --hard`, `git clean`, or worktree removal over changes that were
   not made by this task and committed by it. Rescue first, then act.
5. **Never push directly to a protected default branch** unless the repository
   is explicitly configured to allow it and the user asked for it.
6. **Never use `--no-verify` as routine automation.** A pre-commit or pre-push
   hook that fails is information. Bypassing it may only ever be a deliberate,
   stated, user-authorized one-off.
7. **Never fake validation success.** Only commands that actually ran may be
   reported, with their real results. No inferred passes, no "this would
   pass", no output invented to fill a handoff field.
8. **Never claim a platform feature works without evidence.** "Supports X"
   means a test or validation command demonstrates X. A manifest file existing
   is not evidence (spec §2.6).

Every one of these is enforceable by inspection: a violation is visible in the
diff, the handoff, or the command log.

## Configurable policy — defaults, not rules

The following are **explicitly demoted out of the hard-rules list.** They are
reasonable defaults for this repository, and each of them is legitimately
overridable per project, per objective, or per user preference. Treating them
as invariants is what produced over-validation, PR sprawl, and Claude-only
skill frontmatter.

| Policy | Default | Overridable because |
|--------|---------|---------------------|
| Every task gets a PR | **No** — one objective, one PR (`delivery.md`) | Independent deliverables, security isolation, or deploy sequencing can justify more; a scratch objective may justify none |
| Every worker runs the full test suite | **No** — Tier 1 is targeted (`validation.md`) | A task touching a shared core may warrant the full suite; most do not |
| Every PR auto-merges | Off unless configured | Branch protection, review requirements, and user preference decide this — never force it |
| Every branch is fully updated before merge | Loose by default | Strict-update policy is a repository setting; forcing it wastes CI on every unrelated push |
| Every skill carries Claude-specific frontmatter fields | **No** | Portable core frontmatter is canonical; Claude fields live in the platform extension namespace (spec §3.4) |

When a project wants one of these on, it says so in its own rules or in the
objective's configuration. Absent that statement, the default above applies —
and a skill or script must not assume otherwise.

## Related

- [`git.md`](git.md) — branch, worktree, and migration model
- [`validation.md`](validation.md) — the four validation tiers
- [`delivery.md`](delivery.md) — objective-to-PR mapping
