---
name: feedback-ci-yml-guard-hook
description: .github/workflows/*.yml is guarded — always use GitHub MCP, never Edit tool
metadata:
  type: feedback
---

`.github/workflows/*.yml` in tamirs-superpowers is protected by the `guard-sensitive-files.sh` PreToolUse hook. The Edit and Write tools are blocked on these paths.

**Why:** The hook exists to prevent hand-editing generated/sensitive files. Using the Edit tool wastes a round trip and requires re-routing.

**How to apply:** For any workflow file change, go straight to the GitHub MCP:
1. Get the file's current blob SHA: `gh api "repos/OWNER/REPO/contents/.github/workflows/ci.yml?ref=BRANCH" --jq .sha`
2. Call `create_or_update_file` with that SHA
