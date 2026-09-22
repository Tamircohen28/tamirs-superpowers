---
name: turn-this-into-a-skill
runs: 3
max_turns: 35
timeout_seconds: 720
allowed_tools: [Read, Glob, Grep, Skill, Write]
tags: [fire, create]
---

I just walked a teammate through how we onboard a new microservice onto our observability stack. Create the Grafana dashboard from our service template, register the SLO with its error budget in the SLO config, wire the alert routes so pages go to the owning team's rotation, and add the service to the on-call runbook with its dependencies and escalation path.

Turn that into a skill so I stop re-explaining it every time someone ships a new service.

Put it in `skills/onboard-service/`.
