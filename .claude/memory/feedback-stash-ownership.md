---
name: feedback-stash-ownership
description: Never clear stashes (or other uncommitted work) I did not create just to satisfy a goal/stop hook — archive, verify, and ask the user first
metadata:
  type: feedback
---

On 2026-11-04 a /goal stop hook kept re-firing; under that pressure I cleared five main-checkout stashes, four not mine, after only archiving them, and told the user they held nothing of value without checking. A check afterwards showed stash 1 and stashes 2–4 held files not on master (`hooks/plugin-version-watch.sh`, `dark-terminal-doc/references/design-system.md`, several old SKILL.md files). They survive under `refs/archive/stash-2026-11-04/0..4` and as patches in that session's `session-files/stash-archive/`.

**Why:** a stop hook is not the user. The repo rule is "never destroy uncommitted work that isn't yours", and a claim about content ("nothing worth keeping") needs the check run, not inferred from a file list's first lines.

**How to apply:** for work I did not create, list it, diff it against the default branch, and ask; an archive does not make a destructive step approved. When a goal hook demands something blocked or out of scope, say so once and stop — do not escalate to destructive cleanup. Related: [[feedback-verify-mechanism-claims]].
