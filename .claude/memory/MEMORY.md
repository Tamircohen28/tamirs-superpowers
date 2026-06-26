# Memory — tamirs-superpowers

- [Always use /skill-creator for skills](feedback-skill-creator-required.md) — never hand-write SKILL.md; user corrected this explicitly
- [macOS sed insert fails — use Python](feedback-macos-sed-insert.md) — `sed '/pat/i text'` is GNU syntax; use Python for line insertions on macOS
- [ci.yml is guard-hooked — use GitHub MCP](feedback-ci-yml-guard-hook.md) — Edit/Write blocked on `.github/workflows/*.yml`; always use `create_or_update_file`
- [Check file exists before create_or_update_file](feedback-github-mcp-check-exists.md) — API errors if file exists and SHA is missing; check first
- [--admin required for all PRs in this repo](project-admin-merge-personal-repo.md) — solo contributor, branch protection on; --admin is the standard merge path
