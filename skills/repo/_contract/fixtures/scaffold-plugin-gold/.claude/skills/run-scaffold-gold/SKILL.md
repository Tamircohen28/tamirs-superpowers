---
name: run-scaffold-gold
description: Run scaffold-gold fixture commands for contract validation.
when_to_use: Internal fixture skill for contract gold tree only.
argument-hint: '[command]'
arguments: []
disable-model-invocation: true
user-invocable: true
allowed-tools:
- Bash
disallowed-tools: []
model: claude-sonnet-4-6
effort: low
context: ''
agent: ''
hooks: {}
paths: []
shell: bash
metadata:
  updated-date: '2026-06-23'
---

# run-scaffold-gold

Run `make test` and `make lint` for this fixture.
