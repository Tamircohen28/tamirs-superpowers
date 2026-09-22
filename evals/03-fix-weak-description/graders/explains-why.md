---
type: llm
---
The user asked why their skill never auto-triggers. The original description was "A utility for database stuff."

PASS if the response explains that the `description` field is what Claude matches against to decide whether to auto-invoke a skill, and that this one failed because it was too vague / carried no concrete trigger wording or phrases a user would type.

FAIL if the response only hands back a rewritten file without explaining the cause, or attributes the failure to something else (a settings flag, a missing field other than description/when_to_use, an installation problem) as the primary reason.
