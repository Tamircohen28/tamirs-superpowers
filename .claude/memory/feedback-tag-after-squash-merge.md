---
name: feedback-tag-after-squash-merge
description: "Tag a release AFTER the squash merge lands on master, never on the pre-merge branch commit"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 2cf8ac00-e3a4-499b-bfcd-278317a64ff9
  modified: 2026-09-21T17:24:09.383Z
---

This repo's merge method is **squash**, so the branch commit you validated is *not* the commit
that ends up on master — squashing creates a new SHA and the branch is deleted.

Tagging `v3.9.0` on the release branch's commit (`03e3185`) before merging left the tag on an
orphaned commit: identical content, but unreachable from master, so `git describe` missed it and
a release tarball would have come from a dangling commit.

**Why:** a release tag must be reachable from the default branch. Squash-merge guarantees the
pre-merge SHA never is.

**How to apply:** merge first, then `git tag -a vX.Y.Z <squash-sha>`. Verify before pushing the
release with `git merge-base --is-ancestor vX.Y.Z^{commit} origin/master` and
`git describe --tags origin/master`. If a tag was already pushed to the wrong commit, delete it
remotely (`git push origin :refs/tags/vX.Y.Z`), recreate on the merge SHA, and re-push — safe only
while nothing depends on it yet.

Related: [[reference-release-tag-alignment]] (cut the release, or installed users stay on the
cached copy), [[feedback-background-task-exit-codes]] (read the log's `EXIT=` line, and note which
SHA it judged — a green result ages out fast when several agents are pushing).
