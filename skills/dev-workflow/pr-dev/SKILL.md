---
name: pr-dev
description: 'Use when an open PR must be driven to completion — ''finish this PR'', ''address review comments'', ''land the PR'', ''ship/land/close the PR'', ''drive PR #N to merge'', ''fix CI and merge'', ''clean up this PR'', ''the checks are red, get it green and merged'', ''pr-dev 42''.'
when_to_use: 'drive PR #N to done, handle review feedback, squash-merge and clean up the PR branch, get red checks green and merge, ship a PR number or URL.'
argument-hint: '[PR number, PR URL, or omit to infer from current branch]'
arguments: []
disable-model-invocation: false
user-invocable: true
allowed-tools:
- Read
- Glob
- Grep
- Agent
- Skill(tamirs-superpowers:cleanup)
- Skill(tamirs-superpowers:decision)
- Skill(tamirs-superpowers:deliver-dev)
- Skill(tamirs-superpowers:switch-dev)
disallowed-tools: []
model: sonnet
effort: high
context: ''
agent: ''
hooks: {}
paths: []
shell: bash
metadata:
  tamirs:
    visibility: public
    category: dev-workflow
    role: integrator
    updated-date: '2026-11-04'
    validation-tier: 3
    capabilities:
      required:
        - shell
        - git
        - github_cli
      optional:
        - background_tasks
    tags:
      - pr
      - delivery
      - merge-policy
      - ci
      - review
  capability: pr-drive
  tags:
  - pr
  - review
  - ci
  - merge
  - workflow
  - github
  updated-date: '2026-07-09'
---

# pr-dev

The **final delivery lifecycle driver**. One objective's PR, from open → review addressed → CI green → merged, under the repository's actual merge policy.

## Why this skill exists

After a PR opens, the real work is staying on top of CI failures, reviewer threads, and merge conflicts — often across many minutes. A one-shot "check and report" leaves the PR stalled whenever a simple retry or two-line fix would have unblocked it, and it misses threads that arrive after the initial check. This skill runs a **persistent drive loop** — re-fetch, act, push, loop — so nobody babysits GitHub tabs.

Two things changed from the earlier version, and they matter:

1. **It is not called once per worker.** A worker task ends at commit + handoff. `pr-dev` runs **once per objective**, on the PR that `deliver-dev` opened from the integration branch. Driving five PRs for one objective was the defect, not the workflow.
2. **Auto-merge is a permission, off unless configured.** It is the action `pr.merge.auto`, decided by the permission resolver, resolved once at startup and reported.

## Validation tier

**Tier 3 — delivery/CI.** CI is the independent authority here. This skill does not re-run the full local suite on every loop; it runs the repo's pre-PR gates before each push it makes (Tier 2) and lets CI be Tier 3.

## Inputs

Resolve once at startup; reuse throughout:

| Input | Resolution |
|-------|-----------|
| No argument | `gh pr view --json number -q .number` from current branch |
| PR number `42` | Use directly |
| PR URL | Extract number from URL |

If no PR resolves, ask and stop.

## Skill directory (all platforms)

Resolve once at startup as `SKILL_DIR` — every `scripts/`, `templates/`, and `references/` path below uses it. Never hardcode an absolute path.

Try in order:

1. `$CLAUDE_SKILL_DIR` when set (Claude Code sets this automatically)
2. `$CLAUDE_PLUGIN_ROOT/skills/dev-workflow/pr-dev` when the plugin root is known
3. `<git-root>/skills/dev-workflow/pr-dev` when developing this repo from a checkout
4. `find ~/.claude/plugins -path "*/dev-workflow/pr-dev/scripts/fetch-pr-state.sh" -print -quit | xargs dirname` as a last resort

If none resolve to a directory containing `scripts/fetch-pr-state.sh`, stop and say so.

| Platform | Typical resolution |
|----------|-------------------|
| Claude Code / Desktop | `$CLAUDE_SKILL_DIR` or `$CLAUDE_PLUGIN_ROOT/skills/dev-workflow/pr-dev` |
| Cursor / Codex / Gemini CLI / OpenCode | Git-root path when working from a checkout; otherwise the installed skills root + `dev-workflow/pr-dev` |

## Startup — resolve context and policy (before the first loop pass)

### 1. Objective context

A PR that came from an objective carries metadata worth knowing: which tasks it contains, which branch is the integration branch, and what delivery strategy was chosen.

```bash
PR_JSON="$(gh pr view "$PR" --json number,headRefName,baseRefName,body)"
HEAD="$(jq -r .headRefName <<<"$PR_JSON")"
BASE="$(jq -r .baseRefName <<<"$PR_JSON")"

# objective/<slug> as the head branch, or an "Objective: <id>" line in the body
OBJECTIVE_ID="$(sed -n 's|^objective/||p' <<<"$HEAD")"
[ -n "$OBJECTIVE_ID" ] || OBJECTIVE_ID="$(jq -r .body <<<"$PR_JSON" | sed -n 's/^[Oo]bjective:[[:space:]]*`\{0,1\}\([a-z0-9-]*\).*/\1/p' | head -1)"
```

When an objective resolves, read `.dev-files/objectives/$OBJECTIVE_ID/objective.json` and note:

- `integration_branch` — this is the PR head. **Never** push to a `worker/*` branch from here; worker branches are already merged into it.
- `delivery.strategy` — `single-pr` means this PR is the whole objective. If you find yourself about to open a second PR for the same objective, stop: that is the defect this design removes.
- `delivery.auto_merge` — `false` turns auto-merge off; `true` grants nothing (the resolver warns).
- `tasks` — useful context when writing review replies ("that path belongs to task-003").

No objective is a perfectly normal case (a one-off PR). Continue without one.

### 2. Merge policy

```bash
# HOST: claude | codex | cursor | gemini | opencode — the host you are running on
POLICY="$(bash "$SKILL_DIR/scripts/resolve-merge-policy.sh" ${REPO:+--repo "$REPO"} ${HOST:+--host "$HOST"} "$PR" "${OBJECTIVE_ID:-}")"
echo "$POLICY" | jq .
AUTO_MERGE="$(jq -r .auto_merge <<<"$POLICY")"            # enable | skip
AUTO_SRC="$(jq -r .auto_merge_source <<<"$POLICY")"       # the rule that decided — quote it
MERGE_METHOD="$(jq -r .merge_method <<<"$POLICY")"        # squash | merge | rebase
MERGE_QUEUE="$(jq -r .merge_queue <<<"$POLICY")"          # true | false | null
STRICT="$(jq -r .strict_branch_update <<<"$POLICY")"      # true | false | null
PROT_SRC="$(jq -r .protection_source <<<"$POLICY")"       # classic | rulesets | classic+rulesets | none
```

**The single source of truth is `scripts/resolve-permission.sh`** (the D4 precedence chain in [ADR 004](../../../docs/engineering/decisions/004-permission-levels.md)); do not restate or re-derive it. `auto_merge` is `enable` only when the resolver allows `pr.merge.auto` **and** the repository allows auto-merge. **The default is off**: with nothing configured the resolver asks, and pr-dev asks you before merging. It turns on through `/plugin-config pr.merge.auto allow` (or a trusted project file, or the unattended level when its precondition holds). `TAMIRS_AUTO_MERGE=always` and an objective's `delivery.auto_merge: true` grant nothing; `=never`, `false` and legacy `.dev-files/policy.json` `false` turn it off. A resolver that is missing or fails means skip. Report `auto_merge_source`, and any `warnings`, verbatim.

State the resolution in one line before looping:

```
Merge policy: auto-merge SKIPPED (resolve-permission pr.merge.auto: ask (level supervised ceiling for R3) — auto-merge is off unless configured; to turn it on: /plugin-config pr.merge.auto allow).
I will drive to green and ask you before merging.
Base master: strict branch updates required, 9 required checks, review required. Merge queue: none.
```

or

```
Merge policy: auto-merge ENABLED (resolve-permission pr.merge.auto: allow (user file actions["pr.merge.auto"])), squash + delete branch.
```

Then enable it, if and only if policy says so:

```bash
if [ "$AUTO_MERGE" = "enable" ]; then
  gh pr merge "$PR" --auto "--$MERGE_METHOD" --delete-branch
fi
```

## Core drive loop

```
startup:
  resolve PR, HEAD, BASE, OBJECTIVE_ID
  resolve merge policy; report it; enable auto-merge only if policy says enable

loop:
  state = bash $SKILL_DIR/scripts/fetch-pr-state.sh $PR
  if PR merged → cleanup-after-merge.sh; report; STOP
  if PR closed (not merged) → report; STOP

  # Review threads
  address every unresolved thread (see below)
  if any thread needed a push →
    re-apply merge policy (idempotent); restart loop immediately (no sleep)

  # CI
  classify every non-green check (see the table below)
  if branch-related fix pushed →
    re-apply merge policy; restart loop immediately

  # Branch freshness — only when policy says strict
  if STRICT == true and PR is BEHIND → update the branch once (see below)
  if STRICT != true → leave a behind-but-mergeable branch alone

  # Readiness — automated review is capped at two rounds (references/drive-discipline.md §5)
  if all checks green AND unresolved == 0:
    if AUTO_MERGE == enable → ensure auto-merge/queue entry; poll until merged
    else                    → print the readiness summary and ASK before merging

  sleep(cadence); restart loop
```

## Fetch fresh state

```bash
bash "$SKILL_DIR/scripts/fetch-pr-state.sh" ${REPO:+--repo "$REPO"} "$PR"
```

**Pass `--repo <owner>/<name>` whenever the working directory is not the PR's
repository.** Every script here resolves the repo from the cwd by default, so
the same PR number in a sibling checkout is a real, plausible-looking,
*completely unrelated* pull request — a wrong **answer**, not an error, which is
why it goes unnoticed. All four scripts accept `--repo` (and `--repo=<slug>`);
it pins `GH_REPO` for every `gh` call they make. This matters most for an agent
whose shell resets to a different directory between commands.

Quick snapshot inside the loop:

```bash
gh pr view "$PR" --json number,title,state,mergeable,mergeStateStatus,\
reviewDecision,statusCheckRollup,headRefOid,headRefName,autoMergeRequest
```

## Address a review thread

Highest-value part of the loop. Triage **all** open threads per round (batching: `references/drive-discipline.md`):

1. **Read** the full thread body — understand what the reviewer is asking.
2. **Assess** and state in conversation: `agree`, `partially agree`, or `disagree`.
3. **State the reply** before posting it — the user can redirect tone or content. Use the shapes in `$SKILL_DIR/templates/review-reply.md.tmpl`.
4. **Post**:
   ```bash
   gh api "repos/$REPO/pulls/$PR/comments" \
     -X POST -f body="$REPLY" -f in_reply_to="$COMMENT_ID"
   ```
5. **Fix code** if you agreed or partially agreed.
6. **Resolve**:
   ```bash
   bash "$SKILL_DIR/scripts/resolve-thread.sh" ${REPO:+--repo "$REPO"} "$THREAD_ID"
   ```
7. One push per round, then restart the loop.

When the PR spans an objective, say which task a comment lands in.

## Diagnose a CI failure

```bash
RUN_ID=$(gh run list --repo "$REPO" \
  --commit "$(gh pr view $PR --repo $REPO --json headRefOid -q .headRefOid)" \
  --json databaseId,conclusion \
  --jq '.[] | select(.conclusion=="failure") | .databaseId' | head -1)
gh run view "$RUN_ID" --repo "$REPO" --log-failed
```

## Classify CI results

| Signal | Classification | Action |
|---|---|---|
| Test/lint/compile error in a PR-touched file | Branch-related | Patch, commit, push; restart loop |
| Conclusion `cancelled` on a **superseded** commit (a newer push exists) | Supersession | **Not a failure.** Ignore it; grade only the checks on the current `headRefOid`. Never retry it and never count it against the flake budget. |
| Conclusion `cancelled` on the **current** head with no newer push | Real cancellation | Re-run once; if it cancels again, surface it — something is cancelling your runs |
| `runner provisioning failed`, network timeout, registry error | Flaky/infra | `gh run rerun $RUN_ID --repo $REPO --failed` (**max 3× per PR**) |
| Failure in a check that is not in `required_checks` | Non-blocking | Report it; it does not block merge; do not burn the flake budget on it |
| Dependency outage, GH Actions infra error | Unrelated | Surface to user; STOP |
| Ambiguous | Ambiguous | One manual diagnosis, then decide |

**Always grade the current head.** Checks from an older commit are history, not status. This is the single most common way a drive loop concludes "failing" about a run that no longer exists.

## Branch freshness — loose vs strict

`strict_branch_update` comes from branch protection's "Require branches to be up to date before merging":

| `strict_branch_update` | Behaviour |
|---|---|
| `true` (strict) | A `BEHIND` PR cannot merge. Update it **once**: `gh pr update-branch "$PR"` (or `--rebase` where the repo prefers a linear history), then let CI re-run. |
| `false` (loose) | A behind-but-mergeable PR merges fine. **Do not** merge the base in — every needless update restarts CI and cancels in-flight runs for nothing. |
| `null` (unknown) | Treat as loose. Only update when GitHub actually reports the merge as blocked by staleness. |

**Protection lives in two independent systems.** GitHub has classic branch protection
(`/branches/{b}/protection`) *and* rulesets (effective result:
`/rules/branches/{b}`). A repository may use either, both, or neither, and they do not
shadow each other — the effective protection is the **union**. `resolve-merge-policy.sh`
reads both and reports which answered in `protection_source`.

This matters because the classic endpoint returns **404 "Branch not protected"** on a
ruleset-governed branch. Reading only it reports `required_checks: []` and
`requires_review: false` for a branch that in fact requires nine checks and a pull
request — and the readiness gate then has nothing to wait for. If you ever see
`protection_source: "none"` on a repository you believe is governed, that is the finding,
not a green light.

Never update the branch in a loop. If a single update does not clear `BEHIND`, something else is wrong — diagnose instead of repeating.

## Merge queue

When `merge_queue` is `true` on the base branch:

- `gh pr merge "$PR" --auto "--$MERGE_METHOD"` **enqueues** the PR rather than merging it directly. That is the correct call; do not try to bypass the queue.
- Once queued, the queue owns branch freshness and the merge order. Stop updating the branch and stop re-running checks — you are fighting the queue.
- A PR ejected from the queue (queue CI failed) comes back as a normal failing PR: diagnose, fix, push, re-enqueue.
- Report queue position when GitHub exposes it, and keep polling until merged.

## Merging

```bash
if [ "$AUTO_MERGE" = "enable" ]; then
  gh pr merge "$PR" --auto "--$MERGE_METHOD" --delete-branch
fi
```

Run this at startup, after every push, and at the readiness gate — it is idempotent.

When `autoMergeRequest` is set, GitHub merges as soon as required checks and branch protection (including any required review) are satisfied. **`REVIEW_REQUIRED` alone is not blocked** — report "auto-merge enabled; waiting for review" and keep polling.

When policy is `skip`, do not merge silently. A direct merge is `pr.merge` (R3, never automatic). First ask the resolver with the same call shape as the `--admin` gate below, using `--action pr.merge`. On `deny` (or a failed resolver), stop and report `reason` and the setting that would allow it. On `ask`, print the readiness summary and ask:

```
PR #N is green and has no unresolved threads, but merge policy here is "ask first"
(<source of the policy>). Merge now with squash + delete branch? (yes / no)
```

**`--admin`** — `gh pr merge "$PR" "--$MERGE_METHOD" --delete-branch --admin` — is for two cases and no others:
- required checks cannot pass for reasons outside the code (e.g. Actions billing), or
- the repository is a solo-maintainer repo with branch protection whose required review can never be
  satisfied — the maintainer authors every PR, so there is nobody who *can* approve.

**Resolve that second case; never assume it.** It holds only where the repository is solo **and** the
caller holds a ruleset bypass actor. **Read `admin_bypass_available` from
`resolve-merge-policy.sh`'s own JSON output (Startup step 2) rather than re-deriving it by hand** —
the naive derivation is a trap in two different ways, both confirmed in production:

```bash
# WRONG (under-reports) — repos/$REPO/rulesets is the LIST endpoint, and the list does not
# expand bypass_actors; only a per-ruleset fetch does. This returns 0 even when a real
# always-on bypass actor exists, reading as "no bypass" and wrongly refusing a merge the
# caller is entitled to make.
bypass=$(gh api "repos/$REPO/rulesets" --jq '[.[].bypass_actors // []] | flatten | length')

# ALSO WRONG (over-reports) — repo permission is not proof of a ruleset bypass. A caller can
# hold ADMIN/MAINTAIN on the repo while no bypass_actor for the rulesets that actually apply
# to the base branch covers that role at all. resolve-merge-policy.sh derives
# admin_bypass_available from viewerPermission ALONE was exactly this bug, until it was fixed
# to resolve the ruleset(s) that apply to the branch (`/rules/branches/{b}`), fetch each one's
# bypass_actors, and check whether the caller's actual permission matches a RepositoryRole
# bypass actor with bypass_mode "always" — not from permission level in isolation.
```

```bash
# RIGHT — collaborator count is still a cheap direct check; the bypass question is already
# answered correctly in the policy object you resolved at startup.
collaborators=$(gh api "repos/$REPO/collaborators" --jq 'length' 2>/dev/null || echo 1)
# --admin is the normal path only when collaborators == 1 AND $ADMIN_BYPASS_AVAILABLE == true
# (from `resolve-merge-policy.sh`'s admin_bypass_available field, not re-derived here)
```

**Gate `--admin` on `pr.merge.admin` before every use.** It is R4: never automatic at any level, and no file, env or ticket makes it so ([`safety.md`](../../../core/policies/safety.md)). Ask the resolver, telling it whether a required check is failing or pending (it denies while one is, and while that is unknown):

```bash
PERM="$SKILL_DIR/../../../scripts/resolve-permission.sh"
ADMIN_GATE="$(bash "$PERM" --action pr.merge.admin --skill pr-dev --target "$REPO#$PR" ${HOST:+--host "$HOST"} \
  --cond required_check_failing_or_pending=<true|false, from the state you just fetched> --json)" || ADMIN_GATE='{"verdict":"deny"}'
jq -r '.verdict, .decided_by' <<<"$ADMIN_GATE"
```

- `deny` (or the resolver failed) → do not run `--admin`. Stop and report `decided_by` and `reason`.
- `ask` — the only answer R4 ever gets → stop. Show the user the exact command, the PR and `decided_by`, and run it only when the user approves that very call. A general "merge it" earlier in the session is not that approval.

It bypasses protection; it does not bypass policy.

## Readiness gate

Confirm ALL before merging or waiting on auto-merge:

- [ ] Pre-PR gates green for anything you pushed (`bash skills/dev-workflow/_shared/scripts/run-pre-pr-gates.sh` when the Makefile defines agent targets)
- [ ] Every **required** check green on the current head (no pending, no failing)
- [ ] 0 unresolved review threads (re-run `fetch-pr-state.sh` — do not trust cached state), and no automated reviewer still mid-review: a 👀 reaction from a `[bot]` login means it has not posted yet, so wait (bounded) and re-read threads; after a fix push, ask it again (e.g. comment `@codex review` — it does not re-review on push) and wait for a completed review of the new head — see `references/ci-monitor-loop.md` → After ALL-DONE
- [ ] Branch freshness satisfied per the loose/strict rule
- [ ] Merge policy resolved and stated
- [ ] **No required checks?** Merge only when every workflow run that exists for the FINAL head is fully green (and at least one exists) and 0 threads are unresolved (nothing else stops a red merge); authorization is unchanged: user say-so or the pr-dev exception
- [ ] Orchestrator pre-merge conditions are **review threads** on the PR (ruleset blocks until resolved), not chat messages

Print:

```
PR #N ready — objective auth-system (5 tasks, one PR).
  ✓ 9/9 required checks green on abc1234
  ✓ 0 unresolved review threads
  ✓ Branch up to date (strict base)
  → auto-merge enabled (squash + delete branch); waiting for GitHub
```

## Push a fix

```bash
REPO_ROOT="$(git rev-parse --show-toplevel)"
SHARED_DIR="$REPO_ROOT/skills/dev-workflow/_shared/scripts"
if [ -f "$SHARED_DIR/run-pre-pr-gates.sh" ]; then
  bash "$SHARED_DIR/run-pre-pr-gates.sh" "$REPO_ROOT"
fi

git add -p                    # stage only the relevant change
git commit -m "fix: <what and why>

Co-Authored-By: Claude <noreply@anthropic.com>"
git push origin HEAD
```

Push only to the PR's head branch. When that head is an objective integration branch, the fix belongs there — not on a worker branch that is already merged into it.

Then **restart the loop immediately**; a push is never terminal.

## Wait for CI

Short cycles: `gh pr checks "$PR" --watch`.
Long cycles (5+ min) or when other work can proceed: the Monitor `until`-loop (`$SKILL_DIR/references/ci-monitor-loop.md`); no background tasks: poll on the cadence below.
Pushed CI and review events instead of polling, on Claude Code started with `--channels`: `$SKILL_DIR/references/ci-channels.md` — the event restarts the loop early, the bounded poll below stays as the backstop, and the Monitor loop is the fallback wherever channels are unavailable.

**Poll your own PR; never idle waiting for a notification.** Poll CI and review threads with a bounded loop (a deadline on every wait); if a wait exceeds its stated bound, report to the orchestrator. See `$SKILL_DIR/references/drive-discipline.md`.

## Polling cadence

| State | Interval |
|-------|----------|
| CI pending/queued/running | 60 s |
| Fix just pushed | Immediate restart — no sleep |
| CI green, threads still open | 45 s |
| All green, auto-merge enabled | Poll until merged |
| In a merge queue | 60 s; report position changes only |

## After merge

```bash
bash "$SKILL_DIR/scripts/cleanup-after-merge.sh" ${REPO:+--repo "$REPO"} "$PR"
```

Then:

- **Exit 3 means something was kept.** The script deletes nothing unless the PR is `MERGED`, its head is neither the base nor the default branch, and it is not cross-repository. It deletes the remote branch only when GitHub does not report it protected. Each deletion goes through the resolver (`branch.delete.remote` is R3). It never force-removes a worktree with uncommitted changes. Each kept item is listed under `skipped:` with its reason and, when the resolver blocked it, the setting that would allow it (`allow with: …`). Relay that list verbatim. A kept remote branch is deleted only with the user's approval of that very branch. On Claude Code, run `git push origin --delete <branch>` as its own Bash call (never chained with other commands): the permission guard raises the host dialog naming the branch, and that dialog is the approval — a rejection means keep it. On hosts with no such dialog the guard denies the call, so give the user the command to run themselves.
- Linked issues that a `Closes #N` in the PR body did not already close: closing one is `issue.close` (R3). Ask the resolver for each issue first: `bash "$PERM" --action issue.close --skill pr-dev --target "$REPO#<N>" ${HOST:+--host "$HOST"} --json`. Run `gh issue close <N> --comment "Shipped in PR #$PR."` only on `allow`, or on `ask` after the user's yes in chat. On `deny`, leave the issue open and report the setting. **Closing a PR** (`gh pr close`, `pr.close`, R3) takes the same gate. pr-dev closes no PR it did not open.
- When an objective drove this PR, mark it done: set `objective.json` `status` to `completed` and record `delivery.pr_url` (via `objective-state.sh set` when available).
- Confirm `origin/<head>` is gone (`cleanup-after-merge.sh` deletes it when a UI merge left it behind).

If the PR was already merged when the loop starts, skip everything and run only the cleanup.

## Blocked state

```
Blocked on PR #N — need your input:

Issue: <specific description of what can't be resolved>
Options:
  A) <option>
  B) <option>

Which do you prefer?
```

Never silently stop, guess, or take a destructive action without confirmation. When the block will last a while, suggest `/switch-dev handoff` so the context survives the wait.

## Hard rules

- **Re-fetch before every decision** — cached state causes wrong merge-readiness calls after fast CI flips.
- **Pass `--repo` when the cwd is not the PR's repository.** Repo resolution is cwd-based by default, so a wrong directory yields a plausible answer about a different repository rather than an error.
- **Grade only the current head commit.** Superseded runs are history.
- **Never stop on one idle poll** — CI is often queued seconds after a push.
- **Never push to any branch other than the PR head.**
- **Never prefix commits with `[skip ci]`** — required checks must run.
- **State every review reply in conversation before posting it.**
- **Never change tests or CI config to silence a flaky failure** unless the logs prove it is branch-related.
- **Never retry a flaky run more than 3× per PR** — beyond that it is an infra problem needing human judgment.
- **Always run pre-PR gates before every push** when the repo defines them.
- **Always re-apply the merge policy after a push**, and **never force auto-merge against the resolved policy.**
- **Never open a second PR for the same objective.** One objective = one PR unless `delivery.strategy` names an exception from `core/policies/delivery.md`.
- **Never update the branch on a loose base**, and never update it in a loop.
- **Never fight a merge queue** — enqueue and wait.
- **Always delete the remote branch after merge,** through `cleanup-after-merge.sh` and its gate. When the gate keeps it, report that. Never work around the gate.

## Anti-patterns

| Wrong | Right |
|-------|-------|
| Drive one PR per worker task | One PR per objective; workers end at commit + handoff |
| `gh pr merge --auto` unconditionally | Resolve policy first; enable only when it says enable |
| Treat a `cancelled` superseded run as a failure | Grade the current head only |
| Merge base into the branch every loop | Update once, and only when the base is strict |
| Bypass the merge queue with a direct merge | Enqueue and wait |
| Idle until a notification arrives | Poll CI and threads with a deadline; report overruns |
| Post a reply without stating it first | State it, then post |
| Patch CI config to silence a flaky test | Retry; escalate if it persists |
| `--admin` to skip a review you just did not want | `--admin` only for billing/solo-maintainer protection cases, after the `pr.merge.admin` gate and the user's approval of that call |

## Supporting files

| File | Purpose |
|---|---|
| `scripts/resolve-merge-policy.sh` | Resolves auto-merge, merge method, queue, branch-protection and strictness into one JSON object |
| `scripts/fetch-pr-state.sh` | Fresh PR state + checks + review threads |
| `scripts/resolve-thread.sh` | Resolve one review thread |
| `scripts/cleanup-after-merge.sh` | Post-merge cleanup: checks merged/base/default/fork/protection, gates each deletion, exits 3 with a `skipped:` list |
| `references/ci-monitor-loop.md` | Long-cycle CI waiting with Monitor |
| `references/drive-discipline.md` | Polling bounds, no-required-checks merge gate, blocking pre-merge threads, batched review rounds, the two-round review cap |
| `templates/review-reply.md.tmpl` | Review reply shapes |

## Output format

- **Progress updates**: brief, state-change only (not every poll tick)
- **At startup**: objective context (when any) + the resolved merge policy, in two lines
- **On fix push**: `Pushed fix: <what> (SHA abc1234). Resuming.`
- **On flake retry**: `Retried flaky run (attempt N/3). Watching.`
- **On thread resolved**: `Thread "<snippet>": agreed/partial/disagree — replied and resolved.`
- **At readiness gate**: the full readiness summary above
- **After merge**: one-line summary — SHA, checks, fixes pushed, retries, issues closed, objective marked completed, remote branch deleted
