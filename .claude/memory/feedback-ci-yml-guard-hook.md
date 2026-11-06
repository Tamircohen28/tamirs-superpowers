---
name: feedback-ci-yml-guard-hook
description: "Agents may edit .github/workflows/ directly since 5.6.7 (user's decision 2026-11-06); only the remote API write stays R4"
metadata:
  type: feedback
---

Since 5.6.7, `guard-sensitive-files.sh` no longer blocks `.github/workflows/` in any repo or mode. Edit workflows with Edit/Write like any other file, commit, and ship them in the PR.

**Why:** On 2026-11-06 the user said: "I want agents to be able to edit workflows ... change the workflow rule in the guard script ... it would apply to every repo." A workflow is reviewable source and git undoes it. Before that (ADR 004, 2026-11-03) the guard denied every local workflow edit, and this note told agents to hand the change to the user.

**How to apply:** Edit workflows directly. Do not route a workflow write through the GitHub API or MCP `create_or_update_file`: that path is still `workflow.edit` (R4) in `permission-guard.sh`, and a local edit plus a PR is the normal path anyway. Related: [[feedback-verify-mechanism-claims]].
