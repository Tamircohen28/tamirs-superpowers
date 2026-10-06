---
name: project-directory-submission-holds
description: "Claude plugin-directory submission (submitted 2026-10-05, tracking tag `claude`): which portal holds are structural and stay, so they are not re-chased"
metadata:
  node_type: memory
  type: project
  originSessionId: 03613cd1-02ee-4604-ab0f-03bd4306a67a
  modified: 2026-10-06T16:00:58.313Z
---

The plugin was submitted to Anthropic's plugin directory on 2026-10-05, tracking the `claude` tag
(built by `scripts/build-claude-dist.sh`; release.yml is workflow_dispatch-only — cut it by hand).
Portal "policy holds" mean a human reviewer reads that version; they are **not refusals**. Validation
passed with 5 warnings / 20 holds on 4.11.10–4.11.11.

**Structural — stays unless a feature is removed:**
- `UNREAD_ASSET_REFERENCED` (14): exists while `listing/icon.png` ships. Measured: no token in the 13
  held scripts' text causes it. Only lever: drop the icon (user chose to keep it, per the checklist).
- `COMMAND_NAMES_MOD_FILE` (~6 places in `skills/repo/_contract/scripts/`): they must name an audited
  repo's hook manifest / plugin-root paths; indirect spelling would be obfuscation.
- `MCP_FORWARDS_CREDENTIAL_ENV` on `notify-pushover.sh`: vendor's own credential via sensitive userConfig.
- `COMMAND_SCRIPT_NOT_FOLLOWED`: hooks source shared libs and use here-docs.
- `UNKNOWN_KEY` `types`: **required** by Claude Code's validator for a mod — removing it fails
  `claude plugin validate --strict`.

**Why:** six release rounds were spent partly re-chasing these. **How to apply:** before another
directory pass, compare the new report against this list and work only on what is new. The full
round-by-round tracker is in the session files of 2026-10-03; the shipped-root README is
`platforms/claude/directory/README.md` (it replaces README.md in the build).
Related: [[feedback-fix-the-class-not-the-example]].
