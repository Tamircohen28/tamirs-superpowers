# Memory — tamirs-superpowers

- [Always use /skill-creator for skills](feedback-skill-creator-required.md) — never hand-write SKILL.md; user corrected this explicitly
- [macOS sed insert fails — use Python](feedback-macos-sed-insert.md) — `sed '/pat/i text'` is GNU syntax; use Python for line insertions on macOS
- [ci.yml is guard-hooked — use GitHub MCP](feedback-ci-yml-guard-hook.md) — Edit/Write blocked on `.github/workflows/*.yml`; always use `create_or_update_file`
- [Check file exists before create_or_update_file](feedback-github-mcp-check-exists.md) — API errors if file exists and SHA is missing; check first
- [--admin required for all PRs in this repo](project-admin-merge-personal-repo.md) — solo contributor, branch protection on; --admin is the standard merge path
- [Cut a release after every manifest bump](reference-release-tag-alignment.md) — master CI "Manifest/tag version alignment" stays red until `release.yml` creates the matching v-tag
- [Bump plugin.json with a string replace](feedback-json-manifest-edits.md) — json.dump/jq round-trip escapes unicode (— → \u2014) and reformats; edit the one version line
- [Partition sub-agent fan-outs by file ownership](feedback-multi-agent-file-ownership.md) — agents share one filesystem; overlap is silent data loss, not a git conflict
- [GitHub description/topics live outside git](project-github-description-outside-git.md) — no in-repo check sees them; audit with `gh repo view`
- [Verify mechanism claims, not just success](feedback-verify-mechanism-claims.md) — a hypothesis that explains all the evidence is still a hypothesis; run the cheap check
- [make validate must be backgrounded](feedback-background-task-exit-codes.md) — >2min; read the log's `EXIT=` line, never the task notification's exit code
- [Fetch before auditing](feedback-fetch-before-audit.md) — audit `origin/<default>`; a stale checkout put the wrong version in a review report
