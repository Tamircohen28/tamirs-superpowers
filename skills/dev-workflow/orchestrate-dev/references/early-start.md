# Early start: dependent phase while the predecessor is in CI/review

A phase that depends on a predecessor need not wait for the predecessor's PR to merge. It may **start from the predecessor's head SHA** while that PR is in CI or review.

## Rules

1. Branch from the predecessor head: `git worktree add -b <dep-branch> <path> <predecessor-head-sha>`. Record the SHA in the task (`depends_on` plus a note).
2. **Do not open the dependent PR until the predecessor merges.** A PR stacked on an unmerged head shows the predecessor's diff and may merge out of order.
3. When the predecessor merges, replay only the dependent's own commits:
   ```bash
   git fetch origin
   git rebase --onto origin/<default> <predecessor-head-sha> <dep-branch>
   ```
   If the predecessor was squash-merged its SHA is gone from `<default>`, which is exactly why `--onto` with the old head SHA is required: it drops the predecessor's commits and keeps yours. If review changed the predecessor head, rebase onto the **new** head first, then use `--onto`.
4. Re-run Tier 1 after the rebase, then open the PR.

## Collision rules (all three, or do not early-start)

- **Disjoint paths**: the dependent's `scope[]` shares no file with the predecessor's open review fixes.
- **Separate migration ranges**: assign each phase its own migration number range up front.
- **Additive registration points**: shared registries (routers, indexes, plugin lists) are appended to, one line per phase, so a rebase conflict is a trivial union.

If any rule cannot hold, wait for the merge.
