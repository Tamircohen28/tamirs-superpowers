---
name: project-github-description-outside-git
description: "The GitHub repo description and topics are not files — no in-repo check can see them, so they drift silently while make validate stays green"
metadata: 
  node_type: memory
  type: project
  originSessionId: 0ecd4a1e-ed87-4ea9-a55d-5727b73b1a29
  modified: 2026-09-01T19:34:34.343Z
---

The repo's **GitHub description and topics** live in GitHub's API, not in the git tree. Every
in-repo consistency check — `check-doc-claims.sh`, `check-readme-branding.sh`, `make validate`,
CI — is blind to them by construction.

Observed 2026-09-01: the description read *"Tamir's Personal Claude Code plugin … One /plugin
install and you're set."* while README, AGENTS.md, CLAUDE.md, all six manifests and all 18
`docs/user/*.md` correctly described six surfaces across five platforms. Topics listed only
`claude`, `claude-code`, `claude-code-plugin`. Every check passed the whole time. The
description is what renders in GitHub search results, the repo header and social cards, so it
was the single most-read wrong sentence in the project.

**Why:** an audit that only reads files cannot find drift in fields that are not files. This is
the same shape as two other blind spots found the same day — a badge asserted while the prose
beside it was not, and a `--self-test` written but never invoked. Each produced a confident green.

**How to apply:** in any `repo-standards` review, check the out-of-tree surfaces explicitly —
they are not covered by any gate:

```bash
gh repo view <owner>/<repo> --json description,repositoryTopics
```

Fix with `gh repo edit --description ... --add-topic ...`; it needs no PR. Also worth checking
for the same reason: the social preview image, homepage URL, and the marketplace listing text.

Related: [[reference-release-tag-alignment]] for the other state that lives outside the tree
(tags and releases), and [[project-admin-merge-personal-repo]] for the merge path.
