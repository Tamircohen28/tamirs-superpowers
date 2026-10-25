---
name: feedback-contract-script-canonical
description: The repo-contract scripts under skills/repo/_contract/scripts/ are COPIES; the canonical lives in scripts/ and sync-contract-scripts.sh silently overwrites an edited copy
metadata:
  node_type: memory
  type: feedback
  originSessionId: 8c6e4433-da20-49ef-8d14-9caba4e87385
  modified: 2026-10-24T10:54:50.076Z
---

`skills/repo/_contract/scripts/*.sh`, the `.tmpl` under `templates/` and the three gold
fixtures' `scripts/` are generated copies. The canonical file for each group is named in
`skills/repo/_contract/script-sync.json` (`.groups[].canonical`), and for
`check-manifest-declares.sh` it is the repo-root `scripts/check-manifest-declares.sh`.
`bash skills/repo/_contract/scripts/sync-contract-scripts.sh .` regenerates every copy from
the canonical and prints `updated: <copy>` — which looks like a success line but means
"your edit to that copy was just discarded".

**Why:** on 2026-10-24 two directory-hold fixes were applied to the copy under
`skills/repo/_contract/scripts/`, the sync "updated" it back to the canonical, `make validate`
passed, and 5.0.3 shipped without the change — the portal named the same file again a release
later. **How to apply:** before editing any file under `skills/repo/_contract/`, run
`jq -r '.groups[].canonical' skills/repo/_contract/script-sync.json` and edit the canonical;
after the sync, `git diff --stat` must show the copies moving, not the file you edited
moving back. Related: [[project-directory-submission-holds]].
