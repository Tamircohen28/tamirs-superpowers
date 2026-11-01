---
name: feedback-gh-before-research-agent
description: "For \"what changed in version X\", try gh/npm first — that IS the primary source, and beats a summarizing fetcher"
metadata: 
  node_type: memory
  type: feedback
  originSessionId: a35855d6-d668-42fb-af0b-d574c2b896ae
  modified: 2026-09-23T11:28:33.926Z
---

Before dispatching a research subagent to find what changed in a release, try the direct
route: `gh release view <tag> --repo <owner>/<repo>`, `gh api repos/<o>/<r>/compare/<a>...<b>`,
`npm view <pkg> version repository.url`. For any repo `gh` reaches, that **is** the primary
source.

**Why:** two research agents were dispatched for codex 0.156.1 and opencode 2.0.15, and both
questions were then answered by hand in one shell call each — one agent had to be stopped
mid-run. Worse, the codex agent's own report ended by *recommending* `gh release view`,
because its fetch tooling could only reach AI-summarized pages and one summarizer returned a
self-contradictory answer on retry. A summarizing fetcher is strictly worse than the raw API
when the raw API is available and free.

**How to apply:** delegate research when the answer is genuinely spread across many sources or
needs the open web. For a version delta on a known repo, run the command. Note that a missing
release page does not mean no evidence — opencode's 2.x line publishes no GitHub releases at
all (they top out at v1.18.32), so the review was done off the tag range instead: 42 commits,
250 files, narrowed to the one file that could break this repo. Related:
[[feedback-verify-mechanism-claims]], [[feedback-multi-agent-file-ownership]].
