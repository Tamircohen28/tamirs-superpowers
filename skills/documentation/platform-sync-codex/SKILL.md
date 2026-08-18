---
name: platform-sync-codex
description: >-
  DEPRECATED compatibility shim. OpenAI Codex CLI analysis now runs inside the single
  `platform-sync` engine; this skill only delegates to it and adds no behaviour of its own.
  Kept so anything invoking it by name keeps working for one release. Not user-invocable.
  New callers should invoke `tamirs-superpowers:platform-sync` directly.
when_to_use: |
  Do not reach for this skill in new work — invoke `tamirs-superpowers:platform-sync`.
  It exists only so an existing caller that names `platform-sync-codex` still resolves.
  Scheduled for removal one release after the platform-sync restructure.
argument-hint: "[none]"
arguments: []
disable-model-invocation: true
user-invocable: false
allowed-tools:
  - Read
  - Skill
disallowed-tools: []
model: claude-sonnet-4-6
effort: low
context: ''
agent: ''
hooks: {}
paths: []
shell: bash
metadata:
  tamirs:
    visibility: internal
    category: documentation
    role: research-agent
    validation-tier: 0
    updated-date: '2026-08-19'
    capabilities:
      required:
        - skills
      optional: []
    tags:
      - documentation
      - platform
      - deprecated
      - compatibility-shim
      - codex
  capability: documentation
  provider: developer-workflow
  updated-date: '2026-08-19'
---

# platform-sync-codex (deprecated shim)

This skill no longer contains any OpenAI Codex CLI analysis logic.

The four per-platform sync skills were near-identical orchestration loops that differed
only in their source URLs, local config paths, and feature-scan areas. Those differences
are now **data**, in
`skills/documentation/platform-sync/references/platforms/codex.md`, and the single loop
that consumes them is
`skills/documentation/platform-sync/references/analysis-protocol.md`. Adding a target no
longer adds a skill — that is how Gemini CLI was added without a fifth sub-skill.

## What to do when invoked

1. Invoke `tamirs-superpowers:platform-sync` via the Skill tool, scoped to `codex`.
2. Return its `OpenAI Codex CLI` section unchanged.

Do not re-implement the analysis here, and do not fetch anything yourself. If
`platform-sync` is unavailable, say so and stop — do not fall back to training knowledge
about OpenAI Codex CLI.

## Migration

| Was | Now |
|---|---|
| `platform-sync-codex` SKILL.md | `platform-sync/references/platforms/codex.md` (data) |
| its `references/urls.md` | the "Sources — P0/P1/P2" tables in that file |
| its Step 1–4 body | `platform-sync/references/analysis-protocol.md` (shared) |

Callers should move to `tamirs-superpowers:platform-sync` before this shim is removed.
