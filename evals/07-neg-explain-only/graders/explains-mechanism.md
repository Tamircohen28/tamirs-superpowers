---
type: llm
---
The user asked how Claude Code decides which skill to auto-invoke, and said they are not changing anything.

PASS if the response explains the mechanism: that Claude matches the request against each skill's `description` (optionally extended by `when_to_use`), which is why description wording determines whether a skill triggers. Mentioning related controls such as `disable-model-invocation` or `paths` also counts toward a PASS.

FAIL if the response creates or drafts a skill, starts editing anything, or gives an explanation that misidentifies the mechanism — for example claiming skills are chosen by filename, by directory order, or by an explicit registry the user must configure.
