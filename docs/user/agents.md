# Agents

An **agent** is a reusable specialist you can delegate a bounded piece of work to. A
**role** is what that work needs done. The toolkit defines roles once and ships agents that
declare which role they play — so the same contract holds whether the work runs as a
subagent, as a sequential turn in your main session, or under a different harness entirely.

Canonical roles: [`core/roles/`](../../core/roles/README.md). Agent definitions:
[`agents/`](../../agents/). `scripts/validate-roles.sh` fails the build if the two disagree.

---

## The roles

| Role | Writes? | Default tier | Purpose |
|---|:--:|:--:|---|
| planner | plan artifacts only | 0 | Decompose an objective into a task graph |
| orchestrator | state files only | 0 | Own the objective: dispatch, integrate, deliver |
| implementer | yes, inside `scope[]` | 1 | Execute one task; commit + handoff |
| test-engineer | yes (tests) | 1 | Coverage gaps, focused tests, regression tests |
| reviewer | **no** | 2 | Review the combined diff; produce structured findings |
| security-reviewer | **no** | 2 | Vulnerabilities, leaked secrets, over-broad permissions |
| performance-reviewer | **no** | 2 | Hot paths, N+1s, unnecessary work, bundle/render cost |
| debugger | no by default | 1 | Reproduce, isolate, and root-cause before proposing a fix |
| integrator | yes (integration branch) | 2 | Merge worker branches, resolve conflicts, apply review fixes |
| research-agent | **no** | 0 | Verify APIs and patterns against current documentation |

**Reviewers are read-only.** A review produces findings — severity, confidence, affected
files, evidence, recommended fix, blocking or not. The *integrator* applies them, or the
orchestrator creates a scoped fix task. That separation is why review findings stay
auditable instead of dissolving into someone's edit.

---

## The shipped agents

| Agent | Role | Use it when |
|---|---|---|
| `orchestrator` | orchestrator | A multi-task objective needs owning end to end |
| `implementer` | implementer | One scoped task needs doing |
| `integrator` | integrator | Worker branches need assembling and conflicts resolving |
| `spec-reviewer` | reviewer | The integrated diff needs checking against the stated objective |
| `architecture-reviewer` | reviewer | Adding a subsystem, before a large refactor, or code that feels over-engineered |
| `security-reviewer` | security-reviewer | Anything touching auth, input handling, secrets, IAM, or external I/O |
| `performance-reviewer` | performance-reviewer | Something is slow, or a perf-sensitive path is about to ship |
| `test-engineer` | test-engineer | After a feature or fix, or when a critical path is thinly covered |
| `debugging-specialist` | debugger | A non-trivial bug, or a failure that recurred |
| `research-agent` | research-agent | You are unsure of an API signature, config option, or version behavior |

---

## Role ≠ provider

Which harness runs a role is separate from the role itself, and is recorded only as
`task.provider` metadata — never in a branch name, worktree path, or state directory.
Default is `current`: whatever you are already running in. **No objective requires a second
AI subscription to complete.**

## Where the agents come from on each platform

| Platform | `subagents` | What that means |
|---|---|---|
| Claude Code | `native` | `agents/*.md` are read as shipped |
| Codex · Cursor | `native` | same canonical files |
| Gemini CLI | `adapter` | the canonical files are **rejected** by Gemini (`tools.0: Invalid tool name`); `.gemini/agents/*.md` is generated with Gemini's own tool names and loads clean |
| OpenCode | `adapter` | `.opencode/agent/` is generated because OpenCode's frontmatter genuinely differs |
| Claude Desktop | `unknown` | not exercised there by this repo — assume unavailable, but that is not a measured failure |

`adapter` means **you have the agents**, through a file this repo builds and drift-checks —
not that they are missing. What you must not do is hand-edit the generated copy; regenerate
it (`make gemini-extension`, `make opencode-agents`) and let the matching check target
(`make gemini-extension-check`, `make check-gemini-adapter`, `make opencode-agents-check`)
catch drift.

Where subagents are genuinely unavailable, the role still runs — inline, in your main
session, sequentially, with a narrowed scope. Same contract, same handoff, less concurrency.
See [platform differences](platform-differences.md) and
[orchestration](orchestration.md#the-sequential-path-is-a-first-class-option).

## Adapters

OpenCode's agent frontmatter genuinely differs, so `.opencode/agent/` is **generated** from
`agents/` by `scripts/build-opencode-agents.sh`. Never hand-edit the generated copies;
regenerate them. `make opencode-agents-check` fails on drift.
