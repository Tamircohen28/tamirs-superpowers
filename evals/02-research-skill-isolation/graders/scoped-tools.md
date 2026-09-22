---
type: llm
focus: { source: file, path: "skills/env-var-trace/SKILL.md" }
---
This file is a generated Claude Code SKILL.md for a read-only codebase-search skill.

PASS if ALL of these hold:
- The `description` (or `when_to_use`) names a concrete trigger, such as finding where an environment variable is used or read.
- The skill is configured for read-only investigation: if `allowed-tools` is present it contains only read/search tools such as Read, Glob, Grep, and does NOT grant Write or Edit.
- The body instructs the skill to report findings with file references.

FAIL if ANY of these hold:
- `allowed-tools` grants Write, Edit, or an unrestricted Bash.
- The description is generic with no trigger wording, such as "Searches code" or "A search utility".
- The body never asks for file references in the output.
