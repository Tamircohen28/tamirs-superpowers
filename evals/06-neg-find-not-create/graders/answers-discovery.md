---
type: llm
---
The user asked whether an EXISTING skill or plugin already does OpenAPI-spec-to-client-SDK generation, and said explicitly that they do not want to build one.

PASS if the response treats this as a discovery question — naming existing tools or plugins, describing how to search for one, or saying it does not know of one and suggesting where to look.

FAIL if the response instead authors a new skill, drafts SKILL.md content, proposes building one as its main answer, or otherwise ignores "I don't want to build one".
