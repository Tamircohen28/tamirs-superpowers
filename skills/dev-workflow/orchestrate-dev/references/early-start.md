# Early start: dependent work while the predecessor is in CI/review

**Early start is the default.** A dependent objective or phase does not wait for its predecessor's PR to merge. It **starts from the predecessor's integration head** while that PR is in CI or review, and is rebased onto the default branch after the merge. Waiting is the exception, taken only when a collision rule below cannot hold, and the rule that forced it is recorded.

## Why this is the default

A run of three dependent objectives (`permissions-core`, then `permissions-gates`, then `drift-fixes`; 2026-11-03/04, PRs #347, #348, #350, #353) took about 14 hours. Each objective waited for the previous PR to reach the default branch, and each PR cost about 18 minutes of local `make validate` plus 18–40 minutes of CI. Early start was adopted only mid-run, after repeated complaints about the time. Once adopted, the rebased tree matched the default branch exactly and needed no re-validation. The waiting bought nothing.

## Recipe

### 1. Start from the predecessor's head, and record where you started

A dependent **objective**:

```bash
S=skills/dev-workflow/_shared/scripts/objective-state.sh
W=skills/dev-workflow/_shared/scripts/resolve-worktree.sh
PRED=objective/<predecessor>
PRED_SHA="$(git rev-parse "$PRED")"
bash $S init <id> --title '<title>'                    # base_branch = the default branch
bash $W --objective <id> --integration --base "$PRED"  # git start point = the predecessor's head
bash $S set <id> early_start.predecessor "$PRED"
bash $S set <id> early_start.base_sha "$PRED_SHA"
```

`base_branch` is the **delivery base**: `deliver-dev` reviews the combined diff against it and the PR targets it. It stays the default branch for the whole objective and is never set to the predecessor's branch, which is retained or deleted after its squash merge and would make that review wrong or fail. The predecessor is only the **git start point**, so it goes to the resolver's `--base` and to `early_start.*` on the objective. The resolver does not read `base_branch`; without `--base` it cuts the integration branch from the default branch, which silently undoes the early start.

A dependent **phase inside one objective**: `git worktree add -b <dep-branch> <path> <predecessor-head-sha>`, and record the SHA on the task (`task-set --notes 'early-start from <sha>'`) beside its `depends_on`.

### 2. Do the work

Workers run Tier 1 against the predecessor's tree as if it had merged; a worker needs no knowledge that it is early-started. Integrate worker branches onto `objective/<id>` per Step 10 as usual.

### 3. Open no PR until the predecessor merges

A PR stacked on an unmerged head shows the predecessor's diff and may merge out of order. Meanwhile the predecessor's PR is driven to merge per `pr-dev`.

### 4. When the predecessor merges, replay the integration branch and its worker branches together

Run this from the integration worktree, after every worker has handed off:

```bash
PRED_SHA="$(bash $S show <id> | jq -r .early_start.base_sha)"
for p in $(bash $S tasks <id> | jq -r '.[].worktree // empty'); do git worktree remove "$p"; done
git fetch origin
git rebase --onto origin/<default> "$PRED_SHA" objective/<id> --rebase-merges --update-refs
```

Each part of that command is load-bearing:

- `--onto origin/<default> "$PRED_SHA"`: a squash merge leaves none of the predecessor's SHAs on the default branch, so `--onto` with the recorded head is what drops the predecessor's commits and keeps the dependent's. If review moved the predecessor's head after you branched, rebase onto the **new** head first, then run this with that SHA.
- `--rebase-merges`: keeps the Step 10 merge topology, so each worker branch's commits are replayed as the side of its merge instead of being flattened into the integration branch.
- `--update-refs` (git 2.38+): moves every worker branch to its replayed commits. Without it the recorded worker branches stay on the old commits, and `deliver-dev` Step 1's `git merge-base --is-ancestor <worker-branch> HEAD` reports every one of them `NOT MERGED` although their changes are present. With it, the task files' `branch` values stay valid and that check holds unchanged.
- The worker worktrees are removed **first** because `--update-refs` skips a branch that is checked out in another worktree, silently, while the rebase still reports success. `git worktree remove` refuses a worktree with uncommitted changes, which is the right outcome: that worker has not handed off.

Then verify before going any further:

```bash
for b in $(bash $S tasks <id> | jq -r '.[].branch // empty'); do
  git merge-base --is-ancestor "$b" HEAD && echo "merged: $b" || echo "NOT MERGED: $b"
done
```

Any `NOT MERGED` means a worker branch did not follow: a worktree still held it, or git is older than 2.38. Fix the cause, `git reset --hard ORIG_HEAD` to return the integration branch to its pre-rebase head, and run the rebase again. Do not hand an objective to `deliver-dev` while this prints `NOT MERGED`.

### 5. Decide whether re-validation is needed

```bash
git diff --quiet "$PRED_SHA" origin/<default> -- && echo identical
```

If the predecessor's merged tree equals the head you branched from, the rebased tree is identical to the tree Tier 1 already passed on, so Tier 1 does not need to run again; Tier 2 runs at integration as usual. If the trees differ (the predecessor took review fixes after you branched), re-run Tier 1, then continue.

### 6. Deliver

Invoke `deliver-dev` as normal. Its Step 1 ancestry check holds because the worker branches were replayed with the integration branch, and its Step 2 combined-diff review runs against `base_branch`, the default branch, which now contains the predecessor and nothing of it appears in the diff twice.

## Collision rules (all three hold, or you wait)

- **Disjoint paths**: the dependent's `scope[]` shares no file with the predecessor's scope or its open review fixes.
- **Separate migration ranges**: each phase has its own migration number range, assigned up front.
- **Additive registration points**: shared registries (routers, indexes, plugin lists, changelog sections) are appended to, one line per phase, so a rebase conflict is a trivial union.

## The exception: waiting

Wait for the merge only when a collision rule above cannot hold. When you do:

- record which rule failed on the task (`task-set --notes 'waiting: overlapping paths with <predecessor> in <file>'`);
- say so in the report, in one line, with the rule named;
- do not wait "to be safe". A wait with no named rule is a defect in the plan, not caution: either the scopes are disjoint and the work should have started, or they overlap and the task graph should say so.

## Overlap review and integration with the last worker

Do not hold review, integration or delivery behind the slowest task:

- As soon as the first tasks hand off, merge them onto the integration branch and push it as a
  **draft PR** so CI starts measuring the combined change; start the reviewer on that committed code.
  Fold the remaining tasks in as they land.
- **Simulate every merge before CI does.** Before opening or updating a PR, and after each sibling PR
  merges, run `git merge-tree --write-tree origin/<default> HEAD` (conflicts) and the repo's cheap
  contract gate (`make test-repo-contract` here) on the merge result. It takes a minute; a CI round
  takes ten.
- **Order PRs that add rules before PRs that add fixtures.** A rule that applies to every fixture (a
  docs footer, an issue-template requirement) fails a fixture that landed beside it on another branch.

Why: on 2026-11-06 a new gold fixture merged beside two branches that added rules for every fixture;
each rule then failed it after merge, costing three rebases and two extra CI rounds.

