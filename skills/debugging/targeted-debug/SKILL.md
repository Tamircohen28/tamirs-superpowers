---
name: targeted-debug
description: 'Use when the user pastes a stack trace, traceback, panic, crash log, or error message WITH a file:line reference and wants to know the root cause. Triggers on: ''debug this error'', ''look at this stack trace'', ''why does X crash'', ''what causes this exception'', ''why is this panicking'', ''look at this file:line'', error types (NullPointerException, AttributeError, TypeError, nil pointer dereference, unwrap on None, index out of bounds, segfault, unbound variable, cannot read properties of undefined). Does NOT trigger on vague ''something is broken'' or ''why is it slow'' without a concrete error signal. Prefer this over ad-hoc debugging: it forks the investigation into a bounded Explore agent that reads only the frames in the trace, so the root cause comes back without spending main-thread context on a codebase sweep.'
when_to_use: 'User provides a concrete error: stack trace, panic output, crash log, or names a specific file:line and asks what''s wrong. Error is already in hand — no broad codebase exploration needed. Do not use when the user has no stack trace or no concrete error message.'
argument-hint: <error-message-or-stack-trace> [file:line ...]
arguments: []
disable-model-invocation: false
user-invocable: true
allowed-tools:
- Read
- Grep
- Glob
- Bash
disallowed-tools: []
model: claude-sonnet-4-6
effort: medium
context: fork
background: false
agent: Explore
hooks: {}
paths: []
shell: bash
metadata:
  tamirs:
    visibility: public
    category: debugging
    role: debugger
    validation-tier: 1
    updated-date: '2026-08-19'
    capabilities:
      required:
        - skills
        - shell
      optional:
        - subagents
        - git
    tags:
      - debugging
      - focused
      - targeted
      - stack-trace
      - error
      - crash
      - traceback
      - panic
  capability: focused-debugging
  provider: developer-workflow
  agents:
  - targeted-debug
  updated-date: '2026-08-19'
---

## Live context
!`git rev-parse --show-toplevel 2>/dev/null && echo "repo: $(basename $(git rev-parse --show-toplevel))" || echo "not a git repo"`
!`git branch --show-current 2>/dev/null | sed 's/^/branch: /' || true`

> The `!`-prefixed lines above are Claude Code dynamic frontmatter. Harnesses that do not
> expand them render them as literal text and lose nothing else — every step below either
> re-derives the repo root with `git rev-parse --show-toplevel` or works from paths as
> given. If `git` is unavailable, treat every path as relative to the working directory and
> say so in the report rather than guessing a root.

# Targeted Debug

Scope-bounded debugging. Reads **only** files explicitly named in the stack trace or by the user. Forms a hypothesis from observable evidence. Does NOT explore the codebase broadly. Does NOT launch a full investigation pipeline.

## Why this skill exists

When a stack trace or error message is already in hand, broad codebase exploration adds noise without improving signal. A full investigation session is for "I don't know what's happening" — this skill is for "here's the crash, tell me why." The strict scope constraint (read only what's named) is what makes it fast, token-efficient, and precise.

## Path extraction (use the bundled script)

A deterministic path extractor is available at `scripts/extract-error-paths.sh`. Run it on the raw stack trace to get the exact file list — no manual parsing needed:

```bash
# From the repo root — pipe a stack trace through the extractor
cat stacktrace.txt | bash "$(dirname "$0")/scripts/extract-error-paths.sh"

# Or pass it inline
bash scripts/extract-error-paths.sh "at Foo.bar(Foo.java:42) caused by NullPointerException"
```

Output is one path per line, sorted, deduplicated. Use this list as your in-scope file set.

Recognized trace shapes:
| Language | Example frame | Extracted path |
|----------|--------------|----------------|
| Java/Scala | `at Foo.bar(Foo.scala:42)` | `Foo.scala` |
| JavaScript | `at Object.<anon> (/repo/lib/foo.js:12:7)` | `/repo/lib/foo.js` |
| Python | `File "/repo/src/parser.py", line 87, in parse` | `/repo/src/parser.py` |
| Bash | `script.sh: line 42:` | `script.sh` |
| Rust | `at src/handlers/payment.rs:91:42` | `src/handlers/payment.rs` |
| Go | `\t/app/services/order.go:114 +0x1c2` | `/app/services/order.go` |
| Generic (Vim) | `path/to/file.py:42` | `path/to/file.py` |

**Vendor/stdlib exclusion:** The extractor automatically suppresses paths from `~/.cargo/`, `~/go/pkg/mod/`, `/usr/local/go/src/`, and `node_modules/`. If a trace mixes project files with runtime internals, only project-source paths remain in the output.

For language-specific panic patterns and scope rules (Rust unwrap, Go nil pointer, Bash set -u), see `references/language-patterns.md`.

## Workflow

### 1. Parse input and build the in-scope file set

Accept one or more of: pasted stack trace, error signature, explicit file paths, issue description with a concrete error.

Run the extractor (or extract manually if the trace is trivial):

```bash
# resolve relative paths against repo root
git rev-parse --show-toplevel
```

**In-scope files** = files the user named + files the extractor found in the trace. That's the complete list — nothing else.

### 2. Hypothesize from the trace ALONE (before reading any file)

State in chat: the thrown exception, the frame that threw it, the call chain leading to it. This step forces reasoning from the evidence already provided before adding new evidence.

Example hypothesis statement:
> "The `NullPointerException` is thrown at `UserService.java:142`. The chain shows it was called from `OrderController.java:88`. My hypothesis: a null `User` object is being dereferenced — either `findUser()` returned null and the caller didn't check."

### 3. Read only the in-scope files (targeted sections)

For each file, read the **section relevant to the stack frame** — the failing function and its immediate local callers within the same file. Do not read entire 1000-line files.

```bash
# Confirm the file exists before reading
ls -la path/to/File.java

# Check git blame on the failing lines to see when they changed
git log -n 5 --oneline -- path/to/File.java
git blame -L 138,148 path/to/File.java
```

### 4. Refine the hypothesis

Combine trace evidence with code evidence. Three outcomes:

| Outcome | Meaning | Next step |
|---------|---------|-----------|
| **Confirmed** | Code clearly produces the observed error | Report root cause + fix |
| **Refined** | Trace was misleading; real cause is upstream | Report new hypothesis, name ONE additional file (ask user before reading) |
| **Insufficient** | In-scope files don't reveal a single root cause | Say so explicitly — name what additional evidence is needed |

### 5. Produce the structured diagnosis

The diagnosis is a **structured finding**, in the same shape every reviewer role in this
framework emits (`core/roles/reviewer.md`). That is deliberate: an orchestrator merging a
debugger's output with a reviewer's, a security reviewer's and a test engineer's must not
need a special case for this skill.

```
## Hypothesis (from stack trace, before reading code)
<one paragraph from step 2>

## Finding
| Field | Value |
|-------|-------|
| severity | critical \| high \| medium \| low |
| confidence | high \| medium \| low |
| files | <path:line>, <path:line> — in-scope files only |
| evidence | <the specific lines / signatures that confirm or refute the hypothesis> |
| recommended_fix | <the smallest concrete change, with file:line> |
| blocking | true \| false |

## Root cause
<the proximate cause — one sentence. If undetermined, write "undetermined" and set
confidence to low. Never invent one to fill the field.>

## Out-of-scope follow-ups
- <file NOT read but potentially relevant> — <one-line justification>
- Whether a broader investigation session is now warranted
```

Field discipline:

- **severity** describes the defect's impact on the system, not how hard it was to find.
- **confidence** is about this diagnosis being correct. An "Insufficient" outcome in step 4
  means `confidence: low` and `root cause: undetermined` — it does not mean guessing
  harder. Low confidence stated plainly is a useful result; a confident wrong answer is not.
- **blocking** is `true` when the diagnosis names a defect that must be fixed before
  delivery, `false` when it is a follow-up. A `confidence: low` finding is never `blocking`.
- **files** may only contain in-scope paths. Anything else goes under out-of-scope follow-ups.

The "Out-of-scope follow-ups" section is the escape hatch — list what you would read next if
the user wants to go deeper. Do not silently cross the boundary.

### Emitting machine-readable findings

When an orchestrator asks for machine-readable output, emit the same fields as JSON and
nothing else:

```json
{
  "role": "debugger",
  "severity": "high",
  "confidence": "medium",
  "files": ["src/handlers/payment.rs:91"],
  "evidence": "unwrap() on a None returned by lookup_account() at line 88",
  "recommended_fix": "replace unwrap() with a match that propagates the missing-account error",
  "blocking": true,
  "root_cause": "lookup_account returns None for closed accounts; the caller assumes Some",
  "out_of_scope": ["src/db/accounts.rs — owns the None case, not read"]
}
```

The scope rules apply unchanged in this mode.

## Running under an orchestrator

This skill is a **worker**, and it composes with orchestration without loosening a single
scope rule.

**Competing diagnoses are supported and encouraged.** An orchestrator may dispatch several
independent instances of this skill against the same trace — different in-scope seeds,
different hypotheses — and compare the structured findings. Each instance must:

- reason only from its own assigned scope, and never read another instance's output;
- report its own `confidence` honestly, including when it reaches `undetermined`;
- never widen scope to "win" against a competing diagnosis.

Convergent independent findings are the signal an orchestrator is buying. Findings
contaminated by cross-reading are worth nothing, so the isolation is the whole point.

**Where subagents are unavailable** (`subagents` capability absent), run sequentially in the
same session: complete and record one diagnosis, then start the next from the original trace
without reference to the first. State in the report that the diagnoses were sequential, so
the orchestrator knows they are less independent than parallel ones — do not present them as
if they had been isolated.

**Never** does this skill open a PR, commit, or apply a fix. It ends at a structured
finding and hands off; delivery belongs to the integrator (spec §2.4).

## Hard rules

1. **Read only what's named.** In-scope = files the user named + files in the stack trace. Nothing else without asking.
2. **No `Glob` for unrelated paths.** `Glob` is allowed only to resolve the exact paths from rule 1 (e.g., when the path is partial or relative).
3. **No `Grep` outside in-scope files.** Do not grep the whole repo for the exception class or method name.
4. **No external tool calls.** No observability, chat, issue-tracker, or GitHub MCP queries. This skill is offline. If the user wants those, they should ask explicitly.
5. **No pipeline launch.** This skill does NOT invoke any broader investigation orchestrator. It stops at the evidence boundary and surfaces what it found. Being *dispatched by* an orchestrator is fine; dispatching one is not.
6. **Stop and ask if scope must expand.** If analysis genuinely cannot proceed without reading a new file, ask — don't quietly read 10 more files. Under an orchestrator with no interactive user, do not expand: report `confidence: low` with the file you would have needed listed under out-of-scope follow-ups.
7. **No delivery.** Never commit, push, or open a PR. The output is a finding.

## What NOT to do

```
# WRONG — reading tests to "understand normal behavior"
Read /repo/tests/test_user_service.py

# WRONG — grepping the repo for the exception class
Grep "NullPointerException" /repo/src/

# WRONG — reading all files under the failing package
Glob "/repo/src/services/*.java"

# WRONG — reading node_modules, dist/, or generated code
Read /repo/dist/bundle.js
```

**Never** add speculative root causes to the report that aren't supported by in-scope evidence. If you don't know, say so.

## When to escalate

If the user's question is genuinely "something's broken, I don't know where" with no concrete stack trace or file reference, that's a full investigation session — not this skill. Tell them:

> "I need a concrete error message or stack trace to run targeted-debug. If you don't have one, a broader investigation session would be the right tool."

**Signal phrases that belong in a full investigation:** "something's broken," "it's not working," "check everything," "find the bug" (without a trace), "why is the app slow" (without a specific span/trace).
