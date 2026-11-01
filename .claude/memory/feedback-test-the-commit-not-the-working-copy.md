---
name: feedback-test-the-commit-not-the-working-copy
description: Before claiming a review finding is already fixed, run the check against the pushed commit (git show / fresh worktree), not a shared worktree that may hold someone else's uncommitted edits
metadata:
  type: feedback
---

On #314 I told a reviewer thread "already handled by the current revision" after running the waiver function from `~/.claude/worktrees/.../self-hosted-waiver`. That working copy held five uncommitted edits made minutes earlier by someone else (the fix, plus its tests). The pushed commit did not have them, the PR merged with the bug, and I had to post a correction and ship 5.1.2.

**Why:** a worktree is shared mutable state. `git status --short` on it was never run before I trusted its contents, and the clue (tests I had not written appearing in `sed` output) was visible a step earlier.

**How to apply:** (1) run `git status --short` on any worktree I did not create this turn before reading its files as evidence; (2) to verify "this is fixed", test `git show <pushed-sha>:<path>` or a fresh `git worktree add --detach` of that SHA; (3) before merging, `git diff origin/<branch>` the worktree - if it is non-empty, someone is still editing and the merge is premature. A new test is only evidence if it fails without the fix; run it against the old script once. Related: [[feedback-verify-mechanism-claims]], [[feedback-fetch-before-audit]].
