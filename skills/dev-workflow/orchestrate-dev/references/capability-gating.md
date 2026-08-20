# Capability gating

Read in Step 3 of `orchestrate-dev`, and whenever a step is about to depend on
something the harness might not have.

## The rule

Never assume a capability. Check the registry, then either use the capability,
use its stated fallback, or say plainly that the feature is unsupported here.
Silently pretending is the one forbidden outcome — it produces reports that
claim work that never happened.

## Reading the registry

Definitions live in [`core/capabilities/schema.json`](../../../../core/capabilities/schema.json);
status lives in `core/capabilities/platforms.json`.

The registry is rooted at the **platform** — `claude`, `codex`, `cursor`, `gemini`,
`opencode` — with that platform's runtime **surfaces** underneath, keyed by surface id.
Capabilities hang off a surface, never off the platform, because that is the granularity
you actually run in: Claude Code and Claude Desktop are one platform and two harnesses.

The six **supported** surface ids are `claude_code`, `claude_desktop`, `codex`, `cursor`,
`gemini_cli`, `opencode`.

```bash
SURFACE=claude_code   # the harness you are actually running in
jq -r --arg p "$SURFACE" '(first(.platforms[]?.surfaces[$p]? | select(. != null)) // .platforms[$p]?)
     | .capabilities | to_entries[] | "\(.key): \(.value.status)"' core/capabilities/platforms.json
```

The `// .platforms[$p]?` tail is not decoration: it keeps the lookup working against an
older, flat schema\_version 1 registry in a repo that has not been reshaped yet.

Do not re-derive that walk in a script. `scripts/lib/registry.sh` flattens the whole
registry to one entry per **supported** surface, keyed by surface id, and every checker in
this repo reads that view:

```bash
. scripts/lib/registry.sh
FLAT="$(registry_flat_tmp core/capabilities/platforms.json)"   # caller deletes it
jq -r --arg p "$SURFACE" '.platforms[$p].capabilities
     | to_entries[] | "\(.key): \(.value.status)"' "$FLAT"
```

Status values and what they mean for you:

| Status | Do |
|---|---|
| `native` | Use it |
| `native-experimental` | Use it, but have the fallback ready and say it is experimental |
| `partial` | Read the platform's notes for the limit before relying on it |
| `emulated` | The framework builds it from shell + git; slower, still correct |
| `adapter` | Available through a translation layer, not the canonical artifact |
| `unsupported` | Use the fallback, or say the feature is unavailable |
| `unknown` | Treat as `unsupported` until someone verifies it |

If `platforms.json` is missing, unparseable, or has no entry for your surface,
assume the conservative path for every capability and say the registry was
unavailable.

**Unverified surfaces carry no capabilities block at all.** A surface marked
`support: "unverified"` — `codex_ide`, `cursor_cli`, `gemini_code_assist`,
`opencode_desktop` — was never measured, so the registry states nothing about it in
either direction and `registry_flat` omits it. If you are somehow running there, take the
conservative path for every capability and say the surface is unverified. Never read the
missing block as "unsupported", and never present an unverified surface as a target.

## Capabilities this workflow actually depends on

| Capability | Used for | Absent → |
|---|---|---|
| `subagents` | Dispatching workers | [Sequential mode](sequential-fallback.md) |
| `parallel_subagents` | Concurrent workers | Serialized dispatch, one at a time |
| `worktree_isolation` | Per-task worktrees | Commit tasks onto the objective branch in order |
| `git` | Everything | Stop. This workflow is git-based; say so |
| `github_cli` | The PR at the end | Integrate and validate, then hand the user the exact `gh`/web steps |
| `background_tasks` | Long CI waits in `pr-dev` | Poll in the foreground, or hand back with the PR url |
| `shell` | The state scripts | Maintain `.dev-files/` by hand via file writes; state model is plain JSON |
| `agent_teams` | Named multi-agent coordination | Plain subagents, or sequential |

## Degradation must be visible

Every degraded run says, once, in the report:

- which capability was missing;
- which fallback ran;
- what the user gets less of (usually: wall-clock time, or context isolation).

Example:

> `parallel_subagents: unsupported` on this platform — the three independent
> tasks ran one at a time. Same graph, same single PR, roughly 3× the
> wall-clock.

## Do not overclaim in the other direction either

A capability marked `native` still fails at runtime sometimes. If a dispatch
errors, that is a real failure of that task — mark it `failed`, retry once,
then re-plan. Do not quietly finish the work yourself and report it as the
worker's handoff; the handoff must describe what actually happened.
