---
name: targeted-debug
context: fork
disable-model-invocation: true
description: "Focused debug of a specific production issue — read only files named in the stack trace, error message, or user input; form a hypothesis from observable evidence; do NOT explore the codebase broadly. Use when the user wants to understand a specific bug or error WITHOUT spinning up a full /investigate pipeline."
when_to_use: "User asks to debug, look at, or understand a specific error / stack trace / ticket WITHOUT requesting the full investigation pipeline. Trigger phrases include 'targeted debug', 'just look at', 'why does X fail', 'debug this error', or any debug request that explicitly mentions a single error / file / function."
argument-hint: "<TICKET-or-error-signature> [paths...]"
model: claude-sonnet-4-6
allowed-tools:
  - Read
  - Grep
  - Glob
  - Bash
metadata:
  capability: focused-debugging
  provider: developer-workflow
  agents:
    - targeted-debug
  platforms:
    - claude
  tags:
    - debugging
    - focused
    - targeted
    - workflow
  updated-date: "2026-05-09"
---

## Live context
!`git rev-parse --show-toplevel 2>/dev/null && echo "repo: $(basename $(git rev-parse --show-toplevel))" || echo "not a git repo"`
!`git branch --show-current 2>/dev/null | sed 's/^/branch: /' || true`

# targeted-debug

A scope-bounded debug skill. Reads ONLY files explicitly named in the stack
trace, error message, or user input. Forms a hypothesis from observable
evidence. Does NOT explore the codebase broadly. Does NOT launch
`/investigate`. Does NOT call MCP tools (Grafana, Slack, Jira) unless the
user explicitly asks for them in this turn.

## Why this skill exists

The `/insights` report flagged "Claude went into wide codebase exploration when
the user wanted targeted debug" as a top-3 friction category. The full
`/investigate` pipeline is the right tool for "I don't know what's happening,
investigate the whole thing." This skill is the right tool for "here's the
stack trace, tell me what's wrong" — and the explicit constraint that makes it
work is a hard scope rule.

## Hard rules

1. **Read only what's named.** Files in scope are: (a) files mentioned by the
   user in their prompt, (b) files appearing in the stack trace they pasted,
   (c) files that the error message references by path. Anything else
   requires asking the user first.
2. **No `Glob` for unrelated paths.** `Glob` is allowed only to resolve the
   exact paths from rule 1 when they're relative or partial.
3. **No `Grep` outside in-scope files.** Use `Grep` only on the files from
   rule 1.
4. **No MCP calls.** This skill is offline — no Grafana queries, no Slack
   searches, no Jira fetches, no GitHub MCP. If the user wants those, they
   should ask explicitly or use `/investigate`.
5. **No pipeline launch.** This skill does NOT invoke `/investigate`,
   `/auto-debug`, or any pipeline orchestrator. It produces a focused report
   for the user to act on (or pass to `/start-dev`).

If the analysis genuinely cannot proceed without expanding scope, **stop and
ask** — don't quietly read 10 more files.

## Workflow

### 1. Parse the input

The user gives you one or more of:
- A ticket key (e.g. `SCHED-46824`)
- A stack trace pasted inline
- An error signature (`NullPointerException at BookingsConfirmService:142`)
- One or more file paths

Extract the in-scope file set. The helper script does this deterministically:

```bash
bash "${CLAUDE_SKILL_DIR}/scripts/extract-error-paths.sh" "$INPUT"
```

It reads stdin or `$1` and emits a newline-separated list of file paths
detected in stack-trace format. Cross-check the output with what the user
pasted — only those files plus the user-named ones are in scope.

### 2. Form a hypothesis from the stack trace ALONE

Before opening any file, write down (in your own words, in chat) what the
stack trace tells you. The thrown exception, the frame that threw it, the
chain leading to it. This forces analysis of the evidence the user already
provided before adding new evidence.

### 3. Read the in-scope files

For each in-scope file, read the section relevant to the stack frame —
specifically the function, the lines near the error, and any tight callers
within the same file. Don't read whole 1000-line files when only one function
matters.

### 4. Refine the hypothesis

Combine the stack-trace hypothesis with what the code actually shows. Common
outcomes:
- **Confirmed:** the code clearly produces the error. Report root cause + fix.
- **Refined:** the stack trace was misleading; the real cause is upstream.
  Report the new hypothesis and which one additional file (if any) you
  need to read to confirm.
- **Insufficient:** evidence does not point to a single root cause from
  in-scope files alone. Surface this honestly — don't paper over it by
  expanding scope.

### 5. Output

Produce a short report with these sections (use `templates/report.md` as
the skeleton if helpful):

```
## Hypothesis (from stack trace)
…

## Evidence (from in-scope files)
…

## Root cause (best estimate)
…

## Suggested fix
…

## Out-of-scope follow-ups
- Files we did NOT read but might be relevant (with one-line justification)
- MCP queries that would confirm/refute (Grafana log query, Slack thread search)
- Whether `/investigate <ticket>` is now warranted
```

The "Out-of-scope follow-ups" section is the **escape hatch** — if the user
wants the broader investigation, they invoke `/investigate` with that
context. This skill stops at the boundary instead of crossing it silently.

## Anti-patterns

- ❌ Reading the entire test directory to "see how things are normally done."
- ❌ `Grep` for the exception class across the repo to find similar uses.
- ❌ Auto-invoking `/investigate` "just to be thorough." If the user wanted
   that, they'd have asked.
- ❌ Auto-invoking MCP tools (Grafana, Slack, Jira) to "gather context."
- ❌ Reading `node_modules`, `dist/`, generated code, or build outputs unless
   the stack trace literally points there.
- ❌ Adding speculative root causes in the report that aren't supported by
   in-scope evidence.

## When to escalate to `/investigate`

If the user's question is genuinely "I don't know what's happening with this
ticket," that's `/investigate` territory. Tell them so. This skill is for
when there's already a concrete error and the question is "why and where."

## References

- **[`scripts/extract-error-paths.sh`](scripts/extract-error-paths.sh)** — deterministic path extraction from stack-trace strings.
- **[`references/scope-decisions.md`](references/scope-decisions.md)** — examples of "in scope" vs "out of scope" decisions.
- **[`evals/evals.json`](evals/evals.json)** — pins the no-broad-exploration / no-MCP / no-investigate-launch rules.
