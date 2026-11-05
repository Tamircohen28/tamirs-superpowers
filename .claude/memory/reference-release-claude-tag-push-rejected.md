---
name: reference-release-claude-tag-push-rejected
description: "release.yml's \"Claude-only distribution\" job can fail on the forced push of the `claude` tag with a bare \"[remote rejected] claude -> claude (failed)\" even with no tag ruleset; do not re-run the job, move the tag by hand onto v<ver>-claude"
metadata:
  node_type: memory
  type: reference
  originSessionId: 24913b40-9931-473f-97b4-0cc26fdc1a9e
  modified: 2026-11-05T00:17:29.509Z
---

On 2026-11-05 the 5.4.1 release run (41939918707) published the GitHub release and pushed `v5.4.1-claude`,
then the step `git push --force origin refs/tags/claude` was rejected with no reason text. No tag ruleset
existed (`gh api repos/<repo>/rulesets` listed only the two branch rulesets), the move was a fast-forward
(the new build's parent was the old `claude` commit), and the identical step had succeeded for 5.4.0 an hour
earlier. Cause not established; it behaved like a transient server-side refusal.

**Do not `gh run rerun --failed`:** the job regenerates the build commit with `git commit-tree` (new timestamp,
new SHA) and then pushes `v<ver>-claude` non-forced, which now already exists at the first SHA, so the rerun
fails before it reaches the `claude` push.

**Remedy that worked** (completes release-checklist step 7 by hand):

```bash
git fetch origin "refs/tags/v<ver>-claude:refs/tags/v<ver>-claude" "+refs/tags/claude:refs/tags/claude"
T=$(git rev-parse "v<ver>-claude^{}")
git tag -f -a claude -m "Claude-only distribution, tracked by Anthropic's plugin directory (currently v<ver>)" "$T"
git push --force origin refs/tags/claude
git ls-remote --tags origin 'claude^{}' "v<ver>-claude^{}"   # both lines must show the same SHA
```

Related: [[reference-release-tag-alignment]], [[feedback-tag-after-squash-merge]].
