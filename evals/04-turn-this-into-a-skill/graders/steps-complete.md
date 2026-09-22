---
type: llm
focus: { source: file, path: "skills/onboard-service/SKILL.md" }
---
This file is a generated Claude Code SKILL.md for onboarding a microservice onto an observability stack.

PASS if ALL of these hold:
- All four procedures appear as actionable steps: create the dashboard from the template, register the SLO with its error budget, wire alert routes to the owning team's rotation, and add the service to the on-call runbook with dependencies and escalation path.
- The steps are in a sensible order and each says what to do, not merely that it exists.
- The `description` (or `when_to_use`) contains a concrete phrase a user would type, such as onboarding a new service, adding a service to observability, or shipping a new microservice.

FAIL if ANY of these hold:
- One or more of the four procedures is missing or reduced to a bare noun with no instruction.
- The description is generic with no trigger wording, such as "Service onboarding helper".
