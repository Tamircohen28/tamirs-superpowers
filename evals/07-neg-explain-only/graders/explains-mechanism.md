---
type: llm
---
The user asked how Claude Code decides which skill to auto-invoke, and said they are not changing anything.

PASS if BOTH hold:
1. The response conveys that the decision is driven by each skill's `description` (optionally extended by `when_to_use`) — that the description text is what the request is weighed against, and therefore that description wording is what determines whether a skill fires.
2. The response creates and edits nothing.

Accept ANY substantively correct framing of (1). In particular, an answer that says there is no matcher, router, classifier or embedding search, and that skill selection is the model's own decision over the injected skill descriptions, SATISFIES (1) — that is a more precise account of the same mechanism, not a contradiction of it. Extra accurate detail is never a reason to fail: mentioning that only name + description are loaded while the SKILL.md body stays on disk until invocation, or naming related controls such as `disable-model-invocation`, `user-invocable` or `paths`, all count toward a PASS.

A preamble noting what the model could not inspect in this environment is irrelevant to the verdict. Judge only the explanation of the mechanism.

FAIL if ANY of these hold:
- The response creates or drafts a skill, or edits anything.
- It misidentifies the mechanism — for example claiming skills are chosen by filename, by directory order, by file modification time, or by a registry the user must configure by hand.
- It never explains what drives the decision at all.
