# Handoff protocol

The contract between a unit of work and whoever picks it up next. A task ends at commit + handoff; the handoff is a JSON file; everything that reads state after a task — the integrator, the orchestrator, a session on another platform, three hooks, the `diagnose-objective` skill — reads that file and never the task's reasoning. This page is the one place the whole protocol is written down, so that another plugin can implement it and interoperate with this one on the same `.dev-files/` workspace.

Normative schemas live in [`core/workflow/`](../../../core/workflow/README.md); this page does not change them. Where it proposes an addition, it says so and leaves the schema alone. The state machine around the files is [orchestration-state-machine.md](orchestration-state-machine.md); the worktree layout is [branch-worktree-model.md](branch-worktree-model.md).

## 1. The vocabulary

A handoff's `status` is one of five values. The enum in [`handoff-schema.json`](../../../core/workflow/handoff-schema.json) already carries all five, as does `handoff.sh emit`; the prose in `worker-dev` lists the first four because a worker never chooses `cancelled` for itself.

| Status | Meaning | Evidence owed | What the integrator does |
|---|---|---|---|
| `completed` | The task's goal holds, inside its `scope[]`, committed on the task branch. | `validation[]` non-empty — commands actually run, with their real results. A `completed` with an empty `validation[]` is a claim with no evidence; every reader below flags it. | Integrates. |
| `partial` | Some of the goal holds; the handoff says which part and why it stopped. The honest status for "ran out of turns", "hit a limit", "stopped early". | `summary` names what is and is not done. `validation[]` may be empty. | Decides: resume the task, re-plan, or integrate the done part explicitly. Never integrates around it quietly. |
| `failed` | The task tried and could not reach its goal. | `summary` names the failure. | Re-plans. A task with **no handoff at all** is also `failed` — the state machine's rule, not an inference. |
| `blocked` | The task cannot proceed without something outside its scope or authority: a dependency's wrong handoff, a missing credential, a decision only the user can make. | `summary` names the blocker; `followups[]` names what would unblock it, with `blocking: true`. | Resolves the blocker or re-plans; does not retry the task unchanged. |
| `cancelled` | The task was withdrawn before or during work, by the orchestrator or the user — not by the worker's own judgment. | `summary` says who cancelled and why. | Drops it; dependents are re-planned. The task's `status` in `task-NNN.json` also becomes `cancelled`. |

Rules every reader applies, from [orchestration-state-machine.md](orchestration-state-machine.md):

1. `running → completed` only when a handoff file exists. No handoff ⇒ `failed`.
2. `validation[]` lists only commands that were actually run. An unrun command must not appear.
3. `commits[]` are real SHAs. Never fabricated.
4. `files_changed[]` falls inside the task's `scope[]`. Work needed elsewhere is a `followup`, never an out-of-scope edit.
5. A hook or a host can label a result `partial` on the worker's behalf — Claude Code marks a subagent that hit its own `maxTurns` as `partial` — and the reader treats that exactly like a self-reported `partial`.

## 2. The handoff file

One JSON object per task, `additionalProperties: false`, validated by `handoff.sh emit`/`write` against the schema. Field by field:

| Field | Type | Required | Meaning |
|---|---|---|---|
| `schema_version` | integer, `1` | no | Schema the file was written against. Write it. |
| `task_id` | `task-NNN` | **yes** | The task this handoff closes; matches the file name. |
| `status` | enum above | **yes** | See §1. |
| `summary` | string | no (in practice always) | One paragraph: what was done, and anything the integrator must know first. For every status but `completed`, the reason. |
| `branch` | string | no | The task branch, conventionally `worker/<objective>/NNN`. |
| `commits[]` | `^[0-9a-f]{7,40}$` | no | Real commit SHAs on the task branch. |
| `files_changed[]` | `{path, change}` | no | Every path touched; `change` ∈ `added | modified | deleted | renamed`. All inside `scope[]`. |
| `validation[]` | `{command, tier?, result, skip_reason?, output_excerpt?}` | no (required in spirit for `completed`) | Commands actually run. `result` ∈ `pass | fail | skipped`; `skip_reason` required when skipped; `tier` ∈ `edit | worker | integration | delivery` per [validation-tiers.md](validation-tiers.md). |
| `decisions[]` | `{decision, rationale?, alternatives?[]}` | no | Choices the next task must build on rather than re-litigate. |
| `risks[]` | `{risk, severity?, mitigation?}` | no | `severity` ∈ `critical | high | medium | low`. |
| `followups[]` | `{item, blocking?, suggested_role?}` | no | Work deliberately left undone, including anything needed outside `scope[]`. `blocking: true` means the objective cannot deliver without it. |
| `completed` | date-time | no | When the handoff was written. |

A minimal valid handoff is `{"task_id":"task-001","status":"failed","summary":"…"}`. A credible `completed` one carries `commits`, `files_changed` and at least one `validation` entry.

## 3. Where the files live

```text
<repo>/.dev-files/
├── objectives/<objective-id>/
│   ├── objective.json              # objective-schema.json
│   ├── tasks/task-NNN.json         # task-schema.json — status: pending|ready|running|blocked|completed|failed|cancelled
│   └── handoffs/task-NNN.json      # handoff-schema.json — one per task, written once when the task ends
├── objectives/adhoc-<branch-slug>/ # a switch-dev handoff with no objective: same shape, task-001
│   └── handoffs/task-001.json
└── handoffs/rate-limit-<ts>.json   # §5 — the record the StopFailure hook drops; not a task handoff
```

`.dev-files/` is gitignored by default (`rules/dev/dev-files-workspace.md`); a consuming repository that wants objective state reviewable in PRs un-ignores `objectives/` itself. The GitHub-issue **Resume** block ([cross-platform-workflow.md](../../user/cross-platform-workflow.md#resume-block)) is the optional remote mirror of the same facts, for a switch to another machine or for work other people need to see; neither requires the other.

A task's handoff is read with `handoff.sh show <objective> <task>` and listed with `handoff.sh list <objective>`; the file path is the contract and the helper is a convenience, so a platform without the scripts writes the JSON directly.

## 4. Who writes, who reads

| Actor | Writes | Reads | Rule |
|---|---|---|---|
| **worker** (`worker-dev`, role `implementer` etc.) | its own `handoffs/task-NNN.json`, once, at the end | the handoffs of every task in its `depends_on` | "The handoff is your entire output." Honest status; `partial` over an inflated `completed`. |
| **integrator** | nothing in `handoffs/` | every handoff in the objective | Reads handoffs, never the worker's reasoning or closing summary. Refuses an unevidenced `completed`. |
| **orchestrator** (`orchestrate-dev`) | `tasks/*.json` status transitions; `objective.json` | all handoffs, to dispatch dependents and to resume after a crash | Never re-runs a task whose handoff exists — reads it. |
| **switch-dev** | a handoff for the task being handed off (or `adhoc-<slug>/task-001`); optionally the issue Resume block | the handoff, on `resume` | The cross-platform path, §6. |
| **`subagent-handoff-check.sh`** (SubagentStop, Claude Code) | nothing | all handoffs of the active objective | Advisory: no handoff, or `completed` with empty `validation[]`. `additionalContext` to the orchestrator. |
| **`task-handoff-check.sh`** (TaskCompleted, Claude Code agent teams) | nothing | the handoff for the completing task | Advisory, §7: missing handoff, status outside the vocabulary, unevidenced `completed`. |
| **`teammate-idle-check.sh`** (TeammateIdle, Claude Code agent teams) | nothing | `tasks/*.json` + `handoffs/` | Advisory, §7: a `running` task with no handoff when a teammate goes idle. |
| **`rate-limit-handoff.sh`** (StopFailure `rate_limit`, Claude Code) | `.dev-files/handoffs/rate-limit-<ts>.json` | nothing | §5. Message to the user; record to disk. |
| **`handoff-reminder.sh`** (SessionEnd) | nothing | nothing | Reminds the user to run `/switch-dev handoff` from an active worktree. |
| **`diagnose-objective`** (skill, V5) | nothing | every handoff, `tasks/*.json`, the rate-limit records, and session transcripts | Explains a failed objective from the files; the protocol is what makes that possible without the sessions that produced them. |
| **the mod** (`mod/register.tsx`, Claude Code ≥ 2.1.287) | nothing | objective and task state for the `/objective` pane | Display only. |

Nothing but the worker (or `switch-dev` standing in for one) ever writes a task handoff, and nothing ever rewrites one. A correction is a new status transition on the task plus a new handoff from the task that redid the work.

## 5. The rate-limit handoff record

**The problem.** The moment a session most needs `/switch-dev handoff` is the moment it cannot be asked for: the turn has died on a rate limit, there is no model turn left, and the user is looking at an error. `rate-limit-handoff.sh` fires on `StopFailure` with matcher `rate_limit` and tells the user what is at risk (`systemMessage`, the only channel left on a failed turn). That message reaches the user and nobody else. The next session, a sibling session, an orchestrator, or `diagnose-objective` needs the same facts as data.

**The record.** When the repository keeps a `.dev-files/` workspace, the hook also writes — after composing the message, without touching stdout or the exit status — `.dev-files/handoffs/rate-limit-<ts>.json`:

```json
{
  "kind": "rate-limit-handoff",
  "schema_version": 1,
  "written_at": "2026-10-17T14:03:22Z",
  "session_id": "abc123",
  "cwd": "/Users/you/Projects/app",
  "branch": "objective/auth-system",
  "objective": "auth-system",
  "uncommitted": 3,
  "resume": "/switch-dev handoff objective=auth-system",
  "message": "Rate limit ended this turn — 3 uncommitted file(s), open objective 'auth-system' on objective/auth-system. …",
  "messaging": {
    "socket": "/tmp/cc-socks-501/abc123.sock",
    "posted": false,
    "reason": "messaging socket exported, but the message line format is undocumented; nothing was posted"
  }
}
```

| Field | Meaning |
|---|---|
| `kind` | Discriminator; always `rate-limit-handoff`. Distinguishes this from a task handoff, which has `task_id` and `status` instead. |
| `objective` | The open objective, or `null` when only uncommitted work was found. |
| `uncommitted` | `git status --porcelain` line count at the moment of failure. |
| `resume` | The command that resumes the work: `/switch-dev handoff objective=<id>` with an objective, `/switch-dev handoff` without one (a plain branch handoff, §6). |
| `message` | The exact `systemMessage` text the user saw. |
| `messaging.socket` | The session's inbox socket path when Claude Code exported one, else `null`. Not a secret; the token is **never** written. |
| `messaging.posted` | Whether a structured message was also delivered over the socket. Today always `false`; see below. |

The hook writes nothing when `.dev-files/` does not exist: creating a workspace in a repository that never opted in, at the moment a session dies, is a side effect nobody asked for. Two records in the same second get a `_<pid>` suffix; readers order by `written_at`, not by name.

**The messaging socket, and why nothing is posted yet.** Claude Code (≥ 2.1.224; token ≥ 2.1.228) exports `CLAUDE_CODE_MESSAGING_SOCKET` and `CLAUDE_CODE_MESSAGING_TOKEN` to hooks and Bash commands so "a script or hook can post into a session". What the docs specify: a Unix domain socket (named pipe on native Windows); an optional first line `{"type":"auth","token":"<token>"}`, required on Windows; a complete line within 30 seconds of connecting; and own-child verification — by process evidence on Linux, by the token where that evidence is missing (macOS after the child exited, containers where Claude Code is PID 1, Windows) — which lets such a message bypass the inbound hold a bypass-permissions session would otherwise apply. What the docs do **not** specify, as of 2026-10-17: the JSON shape of the message line itself. A guessed line is either dropped or delivered as noise, so the hook posts nothing and says so in `messaging.reason`. When the line format is published, the post belongs in the hook after the record is on disk, carrying the record's `kind`, `objective`, `uncommitted` and `resume` fields, and `posted` flips to `true`.

**What a reader does with it.**

- *The next session on the same checkout*: `switch-dev resume`, `orchestrate-dev`'s resume step and `diagnose-objective` list `.dev-files/handoffs/rate-limit-*.json`, read the newest by `written_at`, and run or propose its `resume` command. A record whose `objective` has since reached `completed` or `abandoned` is stale and is ignored.
- *A sibling session or an orchestrator with `SendMessage`*: `ListAgents` finds the session named in `session_id` only while it is still alive; after a rate-limit failure it usually is, idle. A `SendMessage` to it with the `resume` command is a wake-up; the record stays the durable copy. Since Claude Code 2.1.271 a `SendMessage` result does not imply the message was read, and a held message produces a delivery notice rather than silence — treat "sent" as "sent", and the file as the truth.
- *Another platform*: the record is a file; `switch-dev handoff` turns it into a task handoff plus, optionally, the issue Resume block, which is what crosses machines.

## 6. The cross-platform resume flow

```text
Claude Code session dies on a rate limit
  │  StopFailure(rate_limit) → systemMessage to the user
  │                          → .dev-files/handoffs/rate-limit-<ts>.json
  ▼
/switch-dev handoff objective=<id> [task-NNN] [target]      (any platform, any time)
  │  writes handoffs/task-NNN.json (status partial unless the goal actually holds)
  │  sets tasks/task-NNN.json status; pushes commits
  │  optionally mirrors to the GitHub issue Resume block + agent:<target> label
  ▼
/switch-dev resume objective=<id>   or   /switch-dev resume #N          (the receiving platform)
  │  reads objective.json, tasks/, the newest handoff; resolves the worktree for this platform
  ▼
worker-dev task-NNN   (continues from the handoff's summary/decisions/followups, never from memory)
```

`switch-dev` degrades per platform ([platform-capabilities.md](../../../skills/dev-workflow/switch-dev/references/platform-capabilities.md)): the files are the protocol on every platform; what differs is which conveniences exist around them.

| Platform | Rate-limit record | Agent-teams hooks | Subagent hook | Resume |
|---|---|---|---|---|
| Claude Code | written by `rate-limit-handoff.sh` | `task-handoff-check.sh`, `teammate-idle-check.sh` (only with `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`) | `subagent-handoff-check.sh` | `switch-dev resume`; the mod's `/objective` pane shows state |
| Claude Desktop | same hooks file; `StopFailure` measured on Claude Code only | not exercised | not exercised | `switch-dev resume` |
| Codex CLI | `hooks/hooks.json` is loaded, but `StopFailure`, `TaskCompleted` and `TeammateIdle` are not Codex events — no record is written | none | `SubagentStop` is a Codex event; the hook prints `{}` when silent as Codex requires | `switch-dev resume` |
| Cursor | Cursor-format bundle does not wire these events | none | none | `switch-dev resume` |
| Gemini CLI, OpenCode | no hooks | none | none | `switch-dev resume` (Gemini headless receiver documented in cross-platform-workflow.md) |

A session on a platform without the hooks must not assume a record exists: `switch-dev handoff` is still the explicit act, and the SessionEnd reminder only fires on Claude Code.

## 7. Agent-teams hooks

With `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`, a subagent that Claude names launches as a teammate: a separate Claude Code instance with its own context, a shared task list, and file-locked task claiming. `SubagentStop` is then no longer the moment a task ends; `TaskCompleted` (the teammate marks its task complete, or finishes its turn with in-progress tasks) and `TeammateIdle` (the teammate is about to stop) are. The two hooks apply §1 at those moments.

| Event | Fires | Hook | Checks | Silent when |
|---|---|---|---|---|
| `TaskCompleted` | any agent marks a task complete via `TaskUpdate`, or a teammate ends its turn with in-progress tasks | `task-handoff-check.sh` | `handoffs/<task>.json` exists; `status` in the vocabulary; `completed` ⇒ `validation[]` non-empty | agent teams off; no objective; all checks pass |
| `TeammateIdle` | a teammate is about to go idle | `teammate-idle-check.sh` | any `tasks/*.json` with `status: running` and no handoff | agent teams off; no objective; none found |

Payloads (hooks reference): both carry the common fields plus `teammate_name`, `team_name` (deprecated) and, since 2.1.290, `agent_id`; `TaskCompleted` adds `task_id`, `task_subject`, `task_description`. Neither event supports a matcher. The host's `task_id` maps onto this repo's handoff name directly when it is already `task-NNN`, and by zero-padding when it is a bare integer; anything else is reported as unmappable rather than guessed.

**Advisory, by design.** Both events document two controls: exit 2 (completion refused / teammate kept working, with stderr fed back to the teammate) and `{"continue": false, "stopReason"}` (teammate stopped). Both hooks always exit 0 and emit the finding on two channels — `systemMessage`, documented on every event, and `hookSpecificOutput.additionalContext` in the same shape `subagent-handoff-check.sh` uses, so the lead reads it wherever the host honours it. The reason is the one `worker-dev` gives: flagging an honest `partial` trains workers to overclaim, and a hook that refuses a `partial` completion would do exactly that. A strict mode that exits 2 on a missing handoff is a reasonable opt-in for a team that wants the DoD enforced; it is not shipped.

**Why objective-wide on idle.** [`task-schema.json`](../../../core/workflow/task-schema.json) has no assignee field, so a task cannot be tied to a teammate; the host's own task list under `~/.claude/tasks/<team>/` is undocumented and is not read. The idle nudge therefore names every running task without a handoff and the idle teammate, and the lead — who knows who owns what — decides.

## 8. Conformance checklist

A plugin implements this protocol when it can share a `.dev-files/` workspace with this one. MUST/SHOULD as in RFC 2119.

**Files**
- [ ] MUST write a task's handoff to `.dev-files/objectives/<objective-id>/handoffs/<task-id>.json`, one file per task, valid against `handoff-schema.json`, with `additionalProperties: false` respected.
- [ ] MUST use the five-value vocabulary for `status` and nothing else.
- [ ] MUST NOT rewrite an existing handoff; a redo is a new task state transition and a new handoff.
- [ ] MUST treat a task with no handoff as `failed`, and a `completed` with empty `validation[]` as unevidenced.
- [ ] MUST list in `validation[]` only commands actually run, and in `commits[]` only real SHAs.
- [ ] SHOULD keep `files_changed[]` inside the task's `scope[]` and route anything else to `followups[]`.
- [ ] SHOULD write `schema_version: 1`.

**Readers**
- [ ] MUST decide integration from the handoff file, not from a closing summary or transcript.
- [ ] MUST treat `partial` as "decide", never as "integrate quietly" — including a `partial` a host applied on the worker's behalf.
- [ ] SHOULD read the handoffs of a task's `depends_on` before starting it.

**Rate-limit record**
- [ ] SHOULD write `.dev-files/handoffs/rate-limit-<ts>.json` with `kind: "rate-limit-handoff"`, `schema_version: 1`, `objective`, `uncommitted`, `resume`, when the host offers a failure hook and the workspace exists.
- [ ] MUST NOT create `.dev-files/` in a repository that does not have it.
- [ ] MUST NOT write any credential (the messaging token included) into the record.
- [ ] SHOULD, on resume, read the newest record by `written_at` and ignore one whose objective is closed.

**Hooks (where the host has them)**
- [ ] SHOULD check handoff existence and evidence at the host's end-of-task event (SubagentStop, TaskCompleted, or equivalent) and nudge at idle.
- [ ] MUST NOT block, fail, or hang on these checks: exit 0, one JSON object or nothing on stdout, bounded stdin read.
- [ ] MUST stay silent outside an objective.

**Cross-platform**
- [ ] MUST be able to resume from the files alone, with no hook having run.
- [ ] SHOULD mirror the handoff to the GitHub-issue Resume block when work crosses machines.

## 9. Proposed schema additions (not applied)

Recorded for the schema owner; nothing here is changed by this page.

- `task-schema.json`: an optional `assignee` (string: teammate name or `agent_id`) so the TeammateIdle hook, and a future `diagnose-objective`, can tie a task to the agent that claimed it instead of reporting objective-wide.
- `handoff-schema.json`: an optional `agent_id` (string) recording which subagent or teammate wrote the handoff, for the same reason, and an optional `labelled_by` (`self | host | orchestrator`) to record that a `partial` was applied by the host (`maxTurns`) rather than chosen by the worker.
- A schema for the rate-limit record (§5) under `core/workflow/`, so `handoff.sh` can validate it like a task handoff.

## 10. Unverified

Recorded rather than silently assumed, as of 2026-10-17.

- The JSON shape of a message line on the session inbox socket — the reason `messaging.posted` is always `false`.
- Whether `hookSpecificOutput.additionalContext` is read on `TaskCompleted` and `TeammateIdle`; the hooks reference lists the events that read it and these are not among them, which is why `systemMessage` is emitted alongside.
- The on-disk format of `~/.claude/tasks/<team>/`; not read.
- Whether the host's `task_id` on `TaskCompleted` is `task-NNN` (as the reference's example shows) or a bare integer in a given build; both are handled.
- `StopFailure`, `TaskCompleted` and `TeammateIdle` on Claude Desktop: the hooks file is shared, but these events are measured on Claude Code only.
