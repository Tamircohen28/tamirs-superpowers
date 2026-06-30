# First-party platform capabilities (stay on one tool longer)

Use these **before** cross-platform handoff when rate-limited on a single model tier.

## Codex

- **`/goal`** — persistent objective across hours/days; pause and resume
- **`codex resume`** / **`codex resume --last`** — reopen prior session in same directory
- **Side chats** — status without interrupting main goal
- Docs: https://developers.openai.com/codex/prompting

## Cursor

- **`/multitask`** — parallel async subagents
- **Cloud agents** / **`/in-cloud`** — hand local work to cloud VM; close laptop
- **Agents Window** — manage many agents across repos
- Docs: https://cursor.com/docs/subagents

## Claude Code

- **Subagents** (Task tool) — parallel focused workers
- **Agent Teams** (experimental) — coordinated multi-session teams with shared task list
- **Agent view** — multiple sessions; attach when needed
- **EnterWorktree** — isolated branch per task
- Docs: https://code.claude.com/docs/en/agents

## Coexistence with plugin worktrees

Claude Code hooks may use `~/.claude/worktrees/<repo>/<slug>/` (global). Dev-workflow skills use repo-local `.<platform>/.worktrees/<slug>/`. Both are valid; `switch-dev` tracks the repo-local path in the Resume block.
