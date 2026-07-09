# Skill delegation prompts

Copy and fill placeholders when invoking child skills from repo-standards.

## multi-agent-repo (review mode — from repo-standards review)

```text
Target repository: $TARGET_ROOT
Run multi-agent-repo review in read-only summary mode.
Do NOT write any report files under docs/agent-guidelines/ or elsewhere in the target repo.
Return executive summary and P1/P2/P3 counts inline only for merge into repo-standards report appendix.
Do not edit any files in the target repo.
```

## multi-agent-repo (dev — polish phase 5)

```text
Target repository: $TARGET_ROOT
Run multi-agent-repo dev on branch feat/repo-standards-setup (same branch as repo-standards polish).
Implement AGENTS.md, thin adapters, drift checks per existing multi-agent plan if present.
If no multi-agent plan exists, run plan then dev inline.
Do not open a separate PR — continue on the current feature branch.
Do not merge.
```

## multi-agent-repo (dev — polish phase 5, plugin-gold / agent-kit)

```text
Target repository: $TARGET_ROOT
Contract profile: plugin-gold (agent-kit distribution repo).
Run multi-agent-repo dev on branch feat/repo-standards-setup.
Follow agent-kit layout in multi-agent-repo references/target-layouts.md:
- Contributor AGENTS.md at repo root (not consumer policy — that lives in canonical/rules/)
- Do not force .agents/skills/ — skills ship via canonical/skills/ + plugins/<name>/skills/
- Ensure npm run build regenerates dist/ after adapter changes
Read repo-standards references/plugin-review.md for manual axes.
Do not merge.
```

## docs-review (polish phase 6)

```text
Audit and fix README.md and docs/** in the current working directory ($TARGET_ROOT).
Apply all P1 doc fixes in place.
Print the standard docs-review completion summary.
```

## changelog-review (polish phase 6 — plugins only)

```text
Audit Claude Code plugin patterns in $TARGET_ROOT.
Apply P1 findings (frontmatter, hooks, skill paths).
Return structured summary for repo-standards polish gate.
```

## multi-agent-repo (dev — polish phase 5, agent make targets)

```text
After implementing multi-agent files, agent MUST run on $TARGET_ROOT:
  make agent-polish-gate
Do not ask the user to run checks manually.
```
