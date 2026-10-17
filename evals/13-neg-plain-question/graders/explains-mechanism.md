---
type: llm
---
The user asked for an explanation of `git merge` versus `git rebase` and when to use each, and said they are not changing anything.

PASS if ALL of these hold:
- The response explains the mechanical difference: merge joins two histories (typically with a merge commit, or a fast-forward when possible) and keeps the existing commits as they are; rebase replays/rewrites the branch's commits on top of a new base, producing a linear history with new commit ids.
- It gives usable guidance on when to pick each — for example rebase for local or unshared branches to keep history linear, merge for integrating shared work, and the warning against rebasing commits others have already based work on.
- It creates and edits nothing and does not start a workflow (no branch, worktree, task, objective, issue or pull request is proposed as the next step).

Accept any substantively correct framing; extra accurate detail (interactive rebase, `--ff-only`, `rerere`, pull with rebase) is never a reason to fail.

FAIL if ANY of these hold:
- It treats the question as a task: proposes implementing something, creating a branch or worktree, opening or driving a pull request, or asks which issue to work on.
- It misstates the mechanism (for example claiming rebase preserves the original commit ids, or that merge rewrites history).
- It never explains when to use which.
