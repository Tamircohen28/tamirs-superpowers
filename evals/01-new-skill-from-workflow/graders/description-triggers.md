---
type: llm
focus: { source: file, path: "skills/release-preflight/SKILL.md" }
---
This file is a generated Claude Code SKILL.md for a pre-release checklist.

PASS if ALL of these hold:
- The `description` field states what the skill does AND when to use it, and contains at least one concrete phrase a user would actually type (for example "before a release", "release checklist", "pre-release checks", "cut a release"). A `when_to_use` field may carry the trigger phrases instead.
- The body gives the four checks as actionable steps: test suite, CHANGELOG entry, version/tag match, and TODO comments.

FAIL if ANY of these hold:
- The description is abstract or generic with no trigger wording, such as "A utility skill", "Helps with releases", or "Release helper".
- The description only names a topic and never says when to invoke the skill.
- Fewer than all four checks appear in the body.
