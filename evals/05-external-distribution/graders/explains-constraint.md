---
type: llm
---
The user asked for a skill they intend to upload to claude.ai, and asked that it not break when they do.

PASS if the response shows awareness that skills distributed outside Claude Code accept only a restricted set of frontmatter fields — name, description, license, compatibility, metadata, allowed-tools — and that Claude-Code-only fields such as context, agent, disable-model-invocation, user-invocable, model, effort or argument-hint would be rejected. Either stating this constraint, or explicitly saying the frontmatter was kept to the portable/spec fields for that reason, counts as PASS.

FAIL if the response never addresses the upload constraint at all, or claims any frontmatter field is fine to include.
