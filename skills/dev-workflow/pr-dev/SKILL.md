---
name: pr-dev
description: 'Use when the user wants to actively drive a PR to completion — ''finish this PR'', ''address review comments'', ''ship/land/close the PR'', ''drive PR #N to merge'', ''fix CI and merge'', ''clean up this PR''. Persistently loops: addresses all review threads, fixes branch-related CI, retries flakes (max 3×), and stops only when ready (asks for `approved`) or blocked (asks for help).'
when_to_use: 'User says: finish this PR, address comments, ship/land/merge the PR, drive PR #N, handle review feedback, fix CI and merge, squash-merge, clean up PR branch — or provides a PR number/URL and asks to drive it to done.'
argument-hint: '[PR number, PR URL, or omit to infer from current branch]'
arguments: []
disable-model-invocation: false
user-invocable: true
allowed-tools:
- Bash
- Read
- Write
- Edit
- Glob
- Grep
- WebFetch
- Agent
- Monitor
- Skill
disallowed-tools: []
model: claude-sonnet-4-6
effort: high
context: ''
agent: ''
hooks: {}
paths: []
shell: bash
metadata:
  capability: pr-drive
  tags:
  - pr
  - review
  - ci
  - merge
  - workflow
  - github
  updated-date: '2026-06-26'
---

# pr-dev

Drive a pull request from open → review addressed → CI green → merge automatically.

## Why this skill exists

After a PR opens, the real work is staying on top of CI failures, reviewer threads, and merge conflicts — often across many minutes. A one-shot "check and report" leaves the PR stalled whenever a simple retry or two-line fix would have unblocked it, and it misses threads that arrive after the initial check.

This skill runs a **persistent drive loop** — re-fetch, act, push, loop — so you never babysit GitHub tabs. It stops at exactly two states: **merged** (auto-merges when ready) or **blocked** (asks for help).

## Inputs

Resolve once at startup; reuse throughout:

| Input | Resolution |
|-------|-----------|
| No argument | `gh pr view --json number -q .number` from current branch |
| PR number `42` | Use directly |
| PR URL | Extract number from URL |

If no PR resolves, ask and stop.

## Skill directory (Claude Code, Cursor, Codex)

Resolve once at startup as `SKILL_DIR` — all `scripts/`, `templates/`, and `references/` paths use this variable (not hardcoded absolute paths).

Try in order:

1. `$CLAUDE_SKILL_DIR` when set (Claude Code sets this automatically)
2. `$CLAUDE_PLUGIN_ROOT/skills/dev-workflow/pr-dev` when the plugin root is known
3. `<git-root>/skills/dev-workflow/pr-dev` when developing this repo from a checkout
4. `find ~/.claude/plugins -path "*/dev-workflow/pr-dev/scripts/fetch-pr-state.sh" -print -quit | xargs dirname` as a last resort for installed Claude plugins

If none resolve to a directory containing `scripts/fetch-pr-state.sh`, stop and tell the user the skill directory could not be found.

**Platform notes**

| Platform | Typical resolution |
|----------|-------------------|
| Claude Code | `$CLAUDE_SKILL_DIR` or `$CLAUDE_PLUGIN_ROOT/skills/dev-workflow/pr-dev` |
| Cursor | Git repo path `skills/dev-workflow/pr-dev` when the plugin is opened from source; otherwise the installed plugin skills root + `dev-workflow/pr-dev` |
| Codex | Same as Cursor — prefer git-root path when contributing to this repo |

In bash examples below, `$SKILL_DIR` means the path resolved above. Claude Code users may substitute `$CLAUDE_SKILL_DIR` when it is already set.

## Hard rules

These rules exist because past implementations broke in the specific ways listed.

- **Re-fetch before every decision** — cached state causes wrong merge-readiness calls after fast CI flips.
- **Never stop on an idle poll** — CI is often queued a few seconds after the push; one clean poll ≠ done.
- **Never push to any branch other than the PR head branch** — avoids touching base or other PRs.
- **Never prefix commits with `[skip ci]`** — required checks must run; skipping forces admin-bypass merges.
- **State every review reply in conversation before posting** — user may redirect the tone or content; surprises erode trust.
- **Never change tests/CI config to silence a flaky failure** unless logs prove it's branch-related.
- **Never retry a flaky run more than 3×** — after that it's an infra problem requiring human judgment.
- **Always restart the loop immediately after any push** — a push triggers new CI; stopping now abandons the run.
- **Merge automatically once all checks pass and threads are resolved** — no user approval needed.
- **Always delete the remote branch after merge** — pass `--delete-branch` to `gh pr merge`, then run `cleanup-after-merge.sh` to verify `origin/<head>` is gone (covers UI merges that skipped branch deletion).
- **Use `--admin`** when CI fails solely due to insufficient billing — do not retry, just merge with `gh pr merge "$PR" --squash --delete-branch --admin`.

## Core drive loop

```
startup:
  resolve PR number and REPO
  HEAD = pr head branch name

loop:
  state = bash $SKILL_DIR/scripts/fetch-pr-state.sh $PR
  if PR merged → run cleanup-after-merge.sh; report; STOP
  if PR closed (not merged) → report; STOP

  # Review threads
  unresolved = threads where isResolved==false and isOutdated==false
  for each thread:
    read body; assess: agree / partially agree / disagree
    state reply text in conversation          ← user can redirect
    post reply via gh api
    if agreed/partial: apply code fix; commit; push
    bash $SKILL_DIR/scripts/resolve-thread.sh $THREAD_ID
  if any thread needed a push → restart loop immediately (no sleep)

  # CI
  if any check failing:
    RUN_ID = first failed run for current HEAD commit
    gh run view $RUN_ID --log-failed   → classify (table below)
    branch-related  → patch, commit, push; restart loop
    flaky, retry<3  → gh run rerun $RUN_ID --failed; retry++; restart loop
    flaky, retry≥3  → surface to user; STOP (blocked)
    infra/unrelated → surface to user; STOP (blocked)
  if any check pending/queued → wait (cadence below); restart loop

  # Readiness
  if all checks green AND unresolved==0 AND mergeStateStatus==CLEAN:
    print readiness summary; proceed to merge immediately

  sleep(cadence); restart loop
```

## Fetch fresh state

```bash
bash "$SKILL_DIR/scripts/fetch-pr-state.sh" "$PR"
```

Quick snapshot inside the loop:

```bash
gh pr view "$PR" --repo "$REPO" \
  --json number,title,state,mergeable,mergeStateStatus,\
reviewDecision,statusCheckRollup,headRefOid,headRefName
```

## Address a review thread

1. **Read** the full thread body — understand what the reviewer is asking.
2. **Assess** and state in conversation: `agree`, `partially agree`, or `disagree`.
3. **State the reply** (user can redirect before it's posted). Use `$SKILL_DIR/templates/review-reply.md.tmpl` shapes.
4. **Post** the reply:
   ```bash
   gh api "repos/$REPO/pulls/$PR/comments" \
     -X POST -f body="$REPLY" -f in_reply_to="$COMMENT_ID"
   ```
5. **Fix code** if agreed or partially agreed.
6. **Resolve** the thread:
   ```bash
   bash "$SKILL_DIR/scripts/resolve-thread.sh" "$THREAD_ID"
   ```
7. Commit and push all fixes; then restart the loop.

## Diagnose a CI failure

```bash
RUN_ID=$(gh run list --repo "$REPO" \
  --commit "$(gh pr view $PR --repo $REPO --json headRefOid -q .headRefOid)" \
  --json databaseId,conclusion \
  --jq '.[] | select(.conclusion=="failure") | .databaseId' | head -1)
gh run view "$RUN_ID" --repo "$REPO" --log-failed
```

## Classify CI failures

| Signal in logs | Classification | Action |
|---------------|---------------|--------|
| Test/lint/compile error in a PR-touched file | Branch-related | Patch, commit, push; restart loop |
| `runner provisioning failed`, network timeout, registry error | Flaky/infra | `gh run rerun $RUN_ID --repo $REPO --failed` (max 3×) |
| Dependency outage, GH Actions infra error | Unrelated | Surface to user; STOP |
| Ambiguous | Ambiguous | One manual diagnosis; then decide |

## Push a fix

```bash
git add -p                    # stage only the relevant change
git commit -m "fix: <what and why>

Co-Authored-By: Claude <noreply@anthropic.com>"
git push origin HEAD
```

Then **restart the loop immediately** — never treat a push as a terminal outcome.

## Wait for CI

For short cycles: `gh pr checks "$PR" --watch`

For long cycles (5+ min) or when other work can run in parallel, use the Monitor `until`-loop. See `$SKILL_DIR/references/ci-monitor-loop.md`.

## Polling cadence

| State | Interval |
|-------|----------|
| CI pending/queued/running | 60 s |
| Fix just pushed | Immediate restart — no sleep |
| CI green, threads still open | 45 s |
| All green + 0 threads | Readiness gate — STOP |

## Readiness gate

Confirm ALL before printing:

- [ ] All CI checks green (no pending, no failing)
- [ ] 0 unresolved review threads (re-run fetch-pr-state.sh)
- [ ] `mergeStateStatus` is `CLEAN`
- [ ] PR is not behind the base branch

Print:

```
PR #N is ready to merge — merging now.
  ✓ N/N CI checks green
  ✓ 0 unresolved review threads
  ✓ Branch up to date with base
```

Proceed immediately to merge and clean up.

## Merge and clean up

Squash-merge and delete the remote head branch on GitHub:

```bash
gh pr merge "$PR" --squash --delete-branch
```

Close issues linked in the PR body (`Closes #N`, `Fixes #N`):

```bash
gh issue close <N> --comment "Shipped in PR #$PR."
```

Then clean up local worktree, local branch, and any leftover remote ref:

```bash
bash "$SKILL_DIR/scripts/cleanup-after-merge.sh" "$PR"
```

`cleanup-after-merge.sh` deletes `origin/<head>` with `git push origin --delete` when the branch still exists (e.g. merged via the GitHub UI without "Delete branch"). Confirm `git branch -a` shows no `origin/<head>` before reporting done.

If the PR was already merged when the loop starts, skip `gh pr merge` and run only `cleanup-after-merge.sh`.

## Blocked state

Surface clearly, then stop:

```
Blocked on PR #N — need your input:

Issue: <specific description of what can't be resolved>
Options:
  A) <option>
  B) <option>

Which do you prefer?
```

Never silently stop, guess, or take a destructive action without confirmation.

## Anti-patterns

| Wrong | Right |
|-------|-------|
| Stop on one idle poll | Keep looping — CI may still be queued |
| Stop after pushing a fix | Restart loop immediately |
| Retry a flaky runner 10× | Max 3×; then surface to user |
| Post reply without stating it first | State in conversation; then post |
| Stop at readiness gate waiting for user | Merge automatically when all green |
| Patch CI config to silence flaky test | Retry; escalate if it persists |
| Batch unrelated fixes in one commit | One commit per logical fix |

## Output format

- **Progress updates**: brief, state-change only (not every poll tick)
- **On fix push**: `Pushed fix: <what> (SHA abc1234). Resuming.`
- **On flake retry**: `Retried flaky run (attempt N/3). Watching.`
- **On thread resolved**: `Thread "<snippet>": agreed/partial/disagree — replied and resolved.`
- **At readiness gate**: full readiness summary above; then stop
- **After merge**: single-line summary — SHA, checks, fixes pushed, retries, issues closed, remote branch deleted
