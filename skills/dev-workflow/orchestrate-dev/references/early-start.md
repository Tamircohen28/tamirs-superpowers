# Early start: dependent work while the predecessor is in CI/review

**Early start is the default.** A dependent objective or phase does not wait for its predecessor's PR to merge. It **starts from the predecessor's integration head** while that PR is in CI or review, and is rebased onto the default branch after the merge. Waiting is the exception, taken only when a collision rule below cannot hold, and the rule that forced it is recorded.

## Why this is the default

A run of three dependent objectives (`permissions-core`, then `permissions-gates`, then `drift-fixes`; 2026-11-03/04, PRs #347, #348, #350, #353) took about 14 hours. Each objective waited for the previous PR to reach the default branch, and each PR cost about 18 minutes of local `make validate` plus 18–40 minutes of CI. Early start was adopted only mid-run, after repeated complaints about the time. Once adopted, the rebased tree matched the default branch exactly and needed no re-validation. The waiting bought nothing.

## Recipe

1. **Branch from the predecessor's head.** Record the SHA you branched from — you need it for the rebase.
   - A dependent **objective**: record the base with `objective-state.sh init <id> --base-branch objective/<predecessor>`, then cut the integration worktree from it with `resolve-worktree.sh --objective <id> --integration --base objective/<predecessor>`. The resolver does not read `base_branch` from `objective.json`; without `--base` it cuts from the default branch, which silently undoes the early start. Note the predecessor's head SHA on the objective's first task (`task-set --notes 'early-start from <sha>'`).
   - A dependent **phase inside one objective**: `git worktree add -b <dep-branch> <path> <predecessor-head-sha>`, and record the SHA on the task alongside its `depends_on`.
2. **Do the work.** Workers run Tier 1 against the predecessor's tree as if it had merged; a worker needs no knowledge that it is early-started.
3. **Do not open the dependent PR until the predecessor merges.** A PR stacked on an unmerged head shows the predecessor's diff and may merge out of order. Meanwhile the predecessor's PR is driven to merge per `pr-dev`.
4. **When the predecessor merges, replay only the dependent's own commits:**
   ```bash
   git fetch origin
   git rebase --onto origin/<default> <predecessor-head-sha> <dep-branch>
   ```
   If the predecessor was squash-merged its SHA is gone from `<default>`, which is exactly why `--onto` with the old head SHA is required: it drops the predecessor's commits and keeps yours. If review changed the predecessor's head after you branched, rebase onto the **new** head first, then use `--onto` with that SHA.
5. **Decide whether re-validation is needed:**
   ```bash
   git diff --quiet <predecessor-head-sha> origin/<default> -- && echo identical
   ```
   If the predecessor's merged tree equals the head you branched from, the rebased tree is identical to the tree Tier 1 already passed on, so Tier 1 does not need to run again; Tier 2 runs at integration as usual. If the trees differ (the predecessor took review fixes after you branched), re-run Tier 1, then continue.
6. Open the PR through `deliver-dev` as normal.

## Collision rules (all three hold, or you wait)

- **Disjoint paths**: the dependent's `scope[]` shares no file with the predecessor's scope or its open review fixes.
- **Separate migration ranges**: each phase has its own migration number range, assigned up front.
- **Additive registration points**: shared registries (routers, indexes, plugin lists, changelog sections) are appended to, one line per phase, so a rebase conflict is a trivial union.

## The exception: waiting

Wait for the merge only when a collision rule above cannot hold. When you do:

- record which rule failed on the task (`task-set --notes 'waiting: overlapping paths with <predecessor> in <file>'`);
- say so in the report, in one line, with the rule named;
- do not wait "to be safe". A wait with no named rule is a defect in the plan, not caution: either the scopes are disjoint and the work should have started, or they overlap and the task graph should say so.
