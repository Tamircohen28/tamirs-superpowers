---
name: feedback-fetch-before-audit
description: git fetch and audit against origin/<default> before any review that reports versions or counts — the local checkout drifts and the wrong numbers propagate into the report
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 0ecd4a1e-ed87-4ea9-a55d-5727b73b1a29
  modified: 2026-09-01T22:00:52.306Z
---

A `/repo-standards` review on 2026-09-01 ran every inventory and gap-scoring script against the
**local working directory** without fetching first. Local `master` was one commit behind
`origin/master`, so the report stated the canonical version as **3.4.0** when it was **3.5.0**.

**Why it mattered more than one stale number:** the version fed a finding. S10-05 was reported as
"manifest 3.4.0 has no matching release tag", when the truth was that **two** versions (3.4.0 and
3.5.0) were unreleased and the newest 3.5.0 had no CHANGELOG section at all. The finding's
severity and its remediation were both wrong, and the report had to be corrected twice — once for
the version, once for the consequence.

Audit output is read later, out of session, as a record. A wrong number in it outlives the
session that produced it.

**How to apply:** before any audit, review or report that states versions, counts, or "what is on
the default branch":

```bash
git fetch origin --quiet
git rev-list --count HEAD..origin/master   # 0, or the checkout is behind
```

If non-zero, either audit a worktree pinned at `origin/master` or say plainly in the report which
commit was audited. The user's global CLAUDE.md already requires this shape for *resumed* work
("Resume protocol" — `git log origin/main -5` before writing code); the same reasoning applies to
any audit, which is equally a claim about remote state.

Note the plugin's own `repo-standards` skill does not fetch, so this is on the caller until that
changes.

Related: [[feedback-verify-mechanism-claims]] — a state claim taken from stale local data, and
[[project-github-description-outside-git]] for the audit surface no local checkout contains at all.
