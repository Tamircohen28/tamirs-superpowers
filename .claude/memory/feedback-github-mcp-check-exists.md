---
name: feedback-github-mcp-check-exists
description: Always check file existence before create_or_update_file — SHA required for updates
metadata:
  type: feedback
---

`create_or_update_file` fails with a confusing error if the file already exists and no `sha` is provided. Always check first.

**Why:** Tried to create LICENSE and SECURITY.md as new files; they already existed on the branch, causing an API error that required an extra round trip to recover.

**How to apply:** Before calling `create_or_update_file`:
```bash
SHA=$(gh api "repos/OWNER/REPO/contents/PATH?ref=BRANCH" --jq '.sha' 2>/dev/null || echo "")
# If SHA is empty → file is new (omit sha param)
# If SHA is set   → file exists (pass sha param)
```
