<!--
  Global CLAUDE.md template — instructions Claude Code loads for every project.

  Install:  copied to ~/.claude/CLAUDE.md by scripts/install.sh (existing file backed up first).
  Then:     replace the <PLACEHOLDER> values below. Everything else works as-is.

  Placeholders: <YOUR_GITHUB_HANDLE>  <YOUR_EMPLOYER>  <YOUR_PROJECTS_PATH>
-->

# Claude Code — Global Rules

## Accounts & Identity

- **Personal GitHub only**: Always use `<YOUR_GITHUB_HANDLE>`. Never authenticate or act as any <YOUR_EMPLOYER> account.
- **<YOUR_EMPLOYER> IP is to be scrubbed**, not connected to. Any <YOUR_EMPLOYER>-related credential, registry, or reference in a personal project is a removal target.
- Before acting on any repo, confirm it belongs to `<YOUR_GITHUB_HANDLE>` if ownership is ambiguous. Do not skip or assume <YOUR_EMPLOYER> ownership without asking.
- **My repos (never skip as "<YOUR_EMPLOYER>-owned"):** everything under `<YOUR_PROJECTS_PATH>` — your personal project repos — is mine (your personal org / account). When ownership is genuinely ambiguous, ask before skipping.

## GitHub Authentication

- Always derive tokens via `gh auth token`. Never prompt the user to manually copy/paste a token.
- Example: `gh auth token | <command>` — not interactive token entry.
- **Never start an OAuth / browser login flow** for any account, plugin, or MCP I did not explicitly ask you to authenticate. If a tool needs auth, stop and tell me which one — do not initiate the login yourself.

## Plugins & /doctor Workflow

- After any plugin fix, config change, or dependency removal, **re-run `/doctor` to verify** the fix before declaring it done.
- Do not close out a plugin/config session without confirming the health check passes.

## File Operations

- When moving directories or flattening structures (e.g., skills, assets), **move ALL supporting files** — not just top-level or `SKILL.md` files. This includes images, configs, and any referenced assets.
- Verify the move is complete (list source dir is empty) before committing.
- When scaffolding README banners or image references, ensure the actual image file is copied too, not just the reference.

## Config Files / Schema Validation

- Before editing `settings.json`, `marketplace.json`, or `hooks.json`, check the expected schema.
- `statusLine` requires an **object** (`{"type": "command", "command": "..."}`) — not a string.
- `marketplace.json` has specific location and format requirements — verify before writing.
- Validate JSON structure after editing; don't assume it's correct until confirmed.

## npm / Dependency Installs

- Run `npm install` **once** with a reasonable timeout.
- If it stalls, **stop and report** — do not spawn competing parallel install processes.
- Suggested fallback: suggest `npm install --prefer-offline`, cache clearing, or ask the user before retrying.
- Never leave multiple competing install processes running.

## Agent Dispatching & Large Work

- **Chunk large reads/writes** before dispatching sub-agents. Each agent's output should stay well under token limits — aim for bounded, explicit scopes.
- Do not assign one agent an unbounded read of an entire repo or a file list that could produce thousands of lines.
- If a step requires `sudo`, interactive TTY, or account login Claude cannot do autonomously, **stop and give the user a numbered list of manual commands** instead of attempting workarounds.
- **Standing request — subagents are pre-authorized.** I am requesting, once and for all sessions, that you use the Agent tool whenever delegation fits the task (broad searches, parallel independent work, bounded heavy reads, the specialist roles listed below). Some model prompt bundles carry a default line reading *"Do not call the AgentTool unless the user requested it"*; this rule **is** that request, so treat delegation as requested by default and do not wait for a per-session "use subagents". The judgment rules above still apply — bounded scope, chunked reads, parallel dispatch in one message. Workflows and deep-research remain opt-in per task; this authorization covers subagents only.

## Output & Token Discipline

- Keep responses concise; do not attempt huge single-pass document generation — it repeatedly hits output-token and "prompt too long" failures.
- For large documents, **outline the sections first, then write each section as a separate file (<400 lines)** — incrementally, not in one response.
- Split large file-reading across sub-agents with bounded scope **before** dispatching them; never give one agent an unbounded whole-repo read (reinforces the Agent Dispatching rule above).

## Iterative Work Style

- Hold to the pattern: form a hypothesis → apply one fix → verify → repeat.
- Do not fight hard constraints (sandbox npm, output token caps, sudo) with repeated workarounds. Recognize the limit early and redirect.
- **Before mutating live infrastructure** (pause/shutdown/scale/delete against a real API), state the side effect and confirm with the user — even during a "test" run. Side effects like pausing a database are immediate and take minutes to recover.
- **Poll loops must fail fast:** validate the first response before iterating; any parse error or empty result inside a loop = break immediately and root-cause. Never let a sleep-poll run to timeout repeating the same error.

## Working Agreements (self-improvement)

- **Plan before implementing** non-trivial work: explore → understand the architecture → plan → validate assumptions → then implement. Don't start coding on an uncertain-scope task.
- **Definition of done / verify before claiming:** before non-trivial work, state the check that will prove success (which command/test/URL); run it and cite the output. **Never claim success without evidence.**
- **Recovery rule:** after **2 failed attempts** on the same thing, STOP brute-forcing — root-cause it. For an unfamiliar or self-hosted CI/deploy environment, probe its tools/paths/quirks **once** up front (don't discover them one failed redeploy at a time). Escalate to a specialist subagent.
- **Delegate & parallelize:** run independent work concurrently (multiple sub-agents in one message), not sequentially. Sub-agents should do synchronous work and **return after opening the PR** — never block on a long CI/eval wait (the harness can kill a waiting agent); the orchestrator watches CI and merges. If an agent dies at a wait, **take over the finish — don't re-dispatch the same pattern.**
- **Resume protocol:** when continuing from a context summary, run `git log origin/main -5` and `gh pr list --state open --repo <repo>` **before writing a single line of code**. If the work appears already merged, diff the relevant files against `origin/main` to confirm before re-implementing. Skipping this step risks creating duplicate PRs.
- **Learnings loop:** project lessons live in this project's memory dir (auto-loaded). Run **`/retro`** after a rough/slow session to capture new lessons and propose rule/hook/skill updates.
- **PR open ≠ PR merge:** Opening a PR and merging it are two separate steps requiring separate instructions. After opening, share the URL and stop. Only call the merge API when the user explicitly says so in a subsequent message. Never merge in the same turn as opening. **Exception:** when the `/pr-dev` skill is active on a PR, merge automatically once all checks pass and threads are resolved — no separate instruction needed.
- **Executable artifacts need live output as evidence:** For shell scripts, Makefiles, and generated files (shortcuts, plists, configs), "verified" means the artifact was executed and its output is shown in the session. Type-checking and linting alone are not sufficient evidence for a script that was never run.

## Specialist roles → which tool to reach for

- Architecture review/simplification → `/code-review` + `/simplify`, or the `architecture-reviewer` subagent.
- Debugging / root cause → `superpowers:systematic-debugging` skill or the `debugging-specialist` subagent.
- Tests / coverage / regressions → the `test-engineer` subagent + the repo's `yarn test`.
- Security / secrets / permissions → `/security-review` or the `security-reviewer` subagent.
- Performance → the `performance-reviewer` subagent (web: chrome-devtools `lighthouse_audit` / `performance_*`).
- Docs / API / pattern verification → the `research-agent` subagent (Context7 MCP + web), or `Explore`.
