# First-party platform capabilities (stay on one tool longer)

Use these **before** cross-platform handoff when rate-limited on a single model tier. Authoritative machine-readable status lives in `core/capabilities/platforms.json`; this page is the human summary.

## Claude Code / Claude Desktop

- **Subagents** (Agent tool) — parallel focused workers
- **Agent Teams** (experimental) — coordinated multi-session teams with a shared task list
- **Agent view** — multiple sessions; attach when needed
- **EnterWorktree** — isolated branch per task
- Docs: https://code.claude.com/docs/en/agents

## Cursor

- **`/multitask`** — parallel async subagents
- **Cloud agents** / **`/in-cloud`** — hand local work to a cloud VM; close the laptop
- **Agents Window** — manage many agents across repos
- Docs: https://cursor.com/docs/subagents

## Codex

- **`/goal`** — persistent objective across hours/days; pause and resume
- **`codex resume`** / **`codex resume --last`** — reopen a prior session in the same directory
- **Side chats** — status without interrupting the main goal
- Docs: https://developers.openai.com/codex/prompting

## Gemini CLI

- **Agent Skills** — same `SKILL.md` contract; `description` is the only trigger signal, so a skill with a weak description will not fire here
- **Checkpointing / `/restore`** — roll a session's file changes back to a known point
- **`/chat save <tag>` and `/chat resume <tag>`** — named local session snapshots; the closest thing to `codex resume`
- **Subagents:** verify against `core/capabilities/platforms.json` before relying on parallel dispatch; assume sequential role execution when the registry does not say otherwise
- Docs: https://google-gemini.github.io/gemini-cli/

## OpenCode

- **Agents** — configured in `opencode.json`; primary and subagent modes
- **Agent Skills** — smaller recognised frontmatter set; unknown fields are ignored rather than rejected, so `metadata.tamirs` travels safely
- **Sessions** — `opencode` resumes the last session per directory
- **Hooks:** plugin API, *not* Claude Code hooks. Nothing in `hooks/hooks.json` applies here.
- **Statusline:** unsupported — never make a workflow depend on it
- Docs: https://opencode.ai/docs/

## Capability-driven degradation

Before a handoff, check the target's row in `core/capabilities/platforms.json` for the capabilities the remaining work needs:

| Capability | If `unsupported` on the target |
|---|---|
| `subagents` / `parallel_subagents` | Hand off a **sequential** wave order; do not promise parallel execution |
| `github_cli` | Skip the GitHub issue export; local `.dev-files/objectives/` state is enough |
| `worktree_isolation` | Hand off a branch name only; the target works in the main checkout |
| `hooks` / `statusline` | Nothing to do — no workflow step may depend on them |
| `ask_user_question` | `/decision` falls back to numbered options; no action needed |

State the degradation in the handoff note. Never hand off work that silently assumes a capability the target does not have.

## Coexistence with plugin worktrees

Claude Code hooks may use `~/.claude/worktrees/<repo>/<slug>/` (global). Older dev-workflow runs used repo-local `.<platform>/.worktrees/<slug>/`; the objective model prefers `.agent-worktrees/<objective>/<task>/`, which carries no platform in the path. All three are valid and `resolve-worktree.sh` understands them; `switch-dev` records whichever path is actually in use.
