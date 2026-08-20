# First-party platform capabilities (stay on one tool longer)

Use these **before** cross-platform handoff when rate-limited on a single model tier. Authoritative machine-readable status lives in `core/capabilities/platforms.json`; this page is the human summary.

The registry is rooted at the **platform** and lists that platform's runtime **surfaces**
underneath. Five platforms, six supported surfaces — Claude Code, Claude Desktop, Codex
CLI, Cursor IDE, Gemini CLI, OpenCode CLI. Each platform below also has a sibling surface
that is **unverified**: listed so the question "does this work there?" gets an honest "not
measured" instead of silence, never as a handoff target.

## Claude

Supported surfaces: **Claude Code** (CLI) · **Claude Desktop** (desktop).

- **Subagents** (Agent tool) — parallel focused workers
- **Agent Teams** (experimental) — coordinated multi-session teams with a shared task list
- **Agent view** — multiple sessions; attach when needed
- **EnterWorktree** — isolated branch per task
- Docs: https://code.claude.com/docs/en/agents

## Cursor

Supported surface: **Cursor IDE**. The **Cursor CLI** is unverified — it shares
`.cursor-plugin/plugin.json` with the IDE, but every measurement under `cursor` was taken
against an IDE plugin install and no CLI run has been recorded here. Do not hand work to it.

- **`/multitask`** — parallel async subagents
- **Cloud agents** / **`/in-cloud`** — hand local work to a cloud VM; close the laptop
- **Agents Window** — manage many agents across repos
- Docs: https://cursor.com/docs/subagents

## Codex

Supported surface: **Codex CLI**. The **Codex IDE extension** is unverified — it consumes
the same `AGENTS.md` and `.codex-plugin/plugin.json`, but this repo has never invoked a
skill there. Do not hand work to it.

- **`/goal`** — persistent objective across hours/days; pause and resume
- **`codex resume`** / **`codex resume --last`** — reopen a prior session in the same directory
- **Side chats** — status without interrupting the main goal
- Docs: https://developers.openai.com/codex/prompting

## Gemini

Supported surface: **Gemini CLI**. **Gemini Code Assist** is unverified — a different host
that does not install CLI extensions, so this repo's `.gemini/` mirror has no established
install path there. Do not hand work to it.

- **Agent Skills** — same `SKILL.md` contract; `description` is the only trigger signal, so a skill with a weak description will not fire here
- **Checkpointing / `/restore`** — roll a session's file changes back to a known point
- **`/chat save <tag>` and `/chat resume <tag>`** — named local session snapshots; the closest thing to `codex resume`
- **Subagents:** verify against `core/capabilities/platforms.json` before relying on parallel dispatch; assume sequential role execution when the registry does not say otherwise
- Docs: https://google-gemini.github.io/gemini-cli/

## OpenCode

Supported surface: **OpenCode CLI**. The **OpenCode desktop app** is unverified — whether
it reads the same `opencode.json` `skills.paths` this repo installs into has not been
checked. Do not hand work to it.

- **Agents** — configured in `opencode.json`; primary and subagent modes
- **Agent Skills** — smaller recognised frontmatter set; unknown fields are ignored rather than rejected, so `metadata.tamirs` travels safely
- **Sessions** — `opencode` resumes the last session per directory
- **Hooks:** plugin API, *not* Claude Code hooks. Nothing in `hooks/hooks.json` applies here.
- **Statusline:** unsupported — never make a workflow depend on it
- Docs: https://opencode.ai/docs/

## Capability-driven degradation

Before a handoff, check the **target surface's** row in `core/capabilities/platforms.json`
for the capabilities the remaining work needs. Capabilities hang off a surface, not off a
platform, so look the surface id up under its platform:

```bash
SURFACE=gemini_cli   # the surface you are handing off to
jq -r --arg p "$SURFACE" '(first(.platforms[]?.surfaces[$p]? | select(. != null)) // .platforms[$p]?)
     | .capabilities | to_entries[] | "\(.key): \(.value.status)"' core/capabilities/platforms.json
```

`scripts/lib/registry.sh` does the same walk once and hands back a flat, one-entry-per-
supported-surface view — prefer it over re-deriving the path in a script.


| Capability | If `unsupported` on the target |
|---|---|
| `subagents` / `parallel_subagents` | Hand off a **sequential** wave order; do not promise parallel execution |
| `github_cli` | Skip the GitHub issue export; local `.dev-files/objectives/` state is enough |
| `worktree_isolation` | Hand off a branch name only; the target works in the main checkout |
| `hooks` / `statusline` | Nothing to do — no workflow step may depend on them |
| `ask_user_question` | `/decision` falls back to numbered options; no action needed |

An **unverified** surface has no capabilities block at all — nobody measured it, and the
registry says nothing in either direction. It is never a handoff target; the row you want
does not exist, and inventing one is the failure this model was built to stop.

State the degradation in the handoff note. Never hand off work that silently assumes a capability the target does not have.

## Coexistence with plugin worktrees

Claude Code hooks may use `~/.claude/worktrees/<repo>/<slug>/` (global). Older dev-workflow runs used repo-local `.<platform>/.worktrees/<slug>/`; the objective model prefers `.agent-worktrees/<objective>/<task>/`, which carries no platform in the path. All three are valid and `resolve-worktree.sh` understands them; `switch-dev` records whichever path is actually in use.
