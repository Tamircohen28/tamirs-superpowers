---
name: feedback-ci-yml-guard-hook
description: ".github/workflows/*.yml is guarded — a workflow edit needs the user's approval; never route around the hook via the GitHub MCP"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 4d09d4e0-b2ec-46c3-8c1c-8cf1d67342b8
  modified: 2026-11-03T23:34:46.742Z
---

`.github/workflows/*.yml` in tamirs-superpowers is protected by the `guard-sensitive-files.sh` PreToolUse hook. The Edit and Write tools are blocked on these paths.

**Why:** Since ADR 004 (permission levels, accepted 2026-11-03) a workflow edit is an R4 action, and the GitHub MCP `create_or_update_file` route this note used to recommend is exactly the hook bypass the ADR's security review flagged (MCP tools skip Bash-matched guards). The old advice is withdrawn.

**How to apply:** Ask the user before any workflow change, then make it the way they approve (normally a normal commit after they unlock it with the guard's override for `workflow.edit`, which stays user-unlockable). Never use the MCP to sidestep the guard. Related: [[feedback-verify-mechanism-claims]].
