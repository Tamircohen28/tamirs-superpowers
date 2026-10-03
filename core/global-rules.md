<!--
  CANONICAL — DO NOT EDIT PER PLATFORM.

  This is the ONE source of the user's global agent rules. Every machine-level
  rules file on every supported platform is RENDERED from this file by
  `scripts/setup.sh`:

      Claude Code   ~/.claude/CLAUDE.md
      Codex CLI     ~/.codex/AGENTS.md
      Gemini CLI    ~/.gemini/GEMINI.md
      Cursor        ~/.cursor/rules/tamirs-superpowers.mdc
      OpenCode      ~/.config/opencode/AGENTS.md

  Editing one of those rendered files is editing a build artifact: the next
  `setup.sh apply` overwrites the marker block it owns. Change this file instead,
  then re-run `bash scripts/setup.sh apply`.

  Placeholders stay placeholders here. `setup.sh` renders them verbatim and the
  user fills them in once per machine:
      <YOUR_GITHUB_HANDLE>   <YOUR_EMPLOYER>   <YOUR_PROJECTS_PATH>

  Platform-neutral by construction: no rule below names a specific product where a
  neutral phrasing carries the same instruction. Where a platform cannot express
  something (no statusline, no hooks, no slash commands), the renderer appends a
  "platform notes" section generated from core/capabilities/platforms.json rather
  than silently dropping the rule.
-->

# Global Agent Rules

## Accounts & Identity

- **Personal GitHub only**: Always use `<YOUR_GITHUB_HANDLE>`. Never authenticate or act as any <YOUR_EMPLOYER> account.
- **<YOUR_EMPLOYER> IP is to be scrubbed**, not connected to. Any <YOUR_EMPLOYER>-related credential, registry, or reference in a personal project is a removal target.
- Before acting on any repo, confirm it belongs to `<YOUR_GITHUB_HANDLE>` if ownership is ambiguous. Do not skip or assume <YOUR_EMPLOYER> ownership without asking.
- **My repos (never skip as "<YOUR_EMPLOYER>-owned"):** everything under `<YOUR_PROJECTS_PATH>` — your personal project repos — is mine (your personal org / account). When ownership is genuinely ambiguous, ask before skipping.

## GitHub Authentication

- Always derive tokens via `gh auth token`. Never prompt the user to manually copy/paste a token.
- Example: `gh auth token | <command>` — not interactive token entry.
- **Never start an OAuth / browser login flow** for any account, plugin, or MCP server I did not explicitly ask you to authenticate. If a tool needs auth, stop and tell me which one — do not initiate the login yourself.

## Verification Workflow

- After any configuration change, dependency removal, or tooling fix, **re-run the health check to verify** before declaring it done. In this toolkit that is `bash scripts/doctor.sh .` (Claude Code also exposes it as `/doctor`).
- Do not close out a configuration session without confirming the health check passes.

## File Operations

- When moving directories or flattening structures (e.g. skills, assets), **move ALL supporting files** — not just top-level or `SKILL.md` files. This includes images, configs, and any referenced assets.
- Verify the move is complete (list the source dir is empty) before committing.
- When scaffolding README banners or image references, ensure the actual image file is copied too, not just the reference.

## Config Files / Schema Validation

- Before editing any settings, manifest, or hook config file, check the expected schema.
- A field that takes an object must be given an object — e.g. a status line entry is `{"type": "command", "command": "..."}`, never a bare string.
- Marketplace and manifest files have specific location and format requirements — verify before writing.
- Validate JSON/TOML/YAML structure after editing; don't assume it's correct until confirmed.

## Package / Dependency Installs

- Run the install command **once** with a reasonable timeout.
- If it stalls, **stop and report** — do not spawn competing parallel install processes.
- Suggested fallback: an offline-preferring install, a cache clear, or ask the user before retrying.
- Never leave multiple competing install processes running.

## Delegation & Large Work

- **Chunk large reads/writes** before dispatching sub-agents. Each agent's output should stay well under token limits — aim for bounded, explicit scopes.
- Do not assign one agent an unbounded read of an entire repo or a file list that could produce thousands of lines.
- If a step requires `sudo`, an interactive TTY, or an account login the agent cannot do autonomously, **stop and give the user a numbered list of manual commands** instead of attempting workarounds.
- **Standing request — sub-agents are pre-authorized.** Delegation is requested once and for all sessions: use the platform's sub-agent mechanism whenever delegation fits the task (broad searches, parallel independent work, bounded heavy reads, the specialist roles listed below). Where a platform's default prompt says not to delegate unless asked, this rule **is** that request. The judgment rules above still apply — bounded scope, chunked reads, parallel dispatch in one message. Multi-step research workflows remain opt-in per task; this authorization covers sub-agents only.

## Output & Token Discipline

- Keep responses concise; do not attempt huge single-pass document generation — it repeatedly hits output-token and context-length failures.
- For large documents, **outline the sections first, then write each section as a separate file (<400 lines)** — incrementally, not in one response.
- Split large file-reading across sub-agents with bounded scope **before** dispatching them; never give one agent an unbounded whole-repo read.

## Iterative Work Style

- Hold to the pattern: form a hypothesis → apply one fix → verify → repeat.
- Do not fight hard constraints (sandboxed installs, output token caps, `sudo`) with repeated workarounds. Recognize the limit early and redirect.
- **Before mutating live infrastructure** (pause/shutdown/scale/delete against a real API), state the side effect and confirm with the user — even during a "test" run. Side effects like pausing a database are immediate and take minutes to recover.
- **Poll loops must fail fast:** validate the first response before iterating; any parse error or empty result inside a loop = break immediately and root-cause. Never let a sleep-poll run to timeout repeating the same error.

## Working Agreements

- **Plan before implementing** non-trivial work: explore → understand the architecture → plan → validate assumptions → then implement. Don't start coding on an uncertain-scope task.
- **Definition of done / verify before claiming:** before non-trivial work, state the check that will prove success (which command, test, or URL); run it and cite the output. **Never claim success without evidence.**
- **Recovery rule:** after **2 failed attempts** on the same thing, STOP brute-forcing — root-cause it. For an unfamiliar or self-hosted CI/deploy environment, probe its tools, paths, and quirks **once** up front; don't discover them one failed redeploy at a time. Escalate to a specialist sub-agent.
- **Delegate & parallelize:** run independent work concurrently (multiple sub-agents in one message), not sequentially. Sub-agents should do synchronous work and **return after opening the PR** — never block on a long CI wait, which can kill a waiting agent. The orchestrator watches CI and merges. If an agent dies at a wait, **take over the finish — don't re-dispatch the same pattern.**
- **Resume protocol:** when continuing from a context summary, run `git log "origin/$(bash skills/dev-workflow/_shared/scripts/default-branch.sh)" -5` and `gh pr list --state open --repo <repo>` **before writing a single line of code**. If the work appears already merged, diff the relevant files against that same `origin/<default-branch>` to confirm (a literal branch name here makes the guard inspect a nonexistent ref and never fire) before re-implementing. Skipping this step risks creating duplicate PRs.
- **Learnings loop:** project lessons live in the project's memory directory. Run a retrospective after a rough or slow session to capture new lessons and propose rule, hook, and skill updates.
- **PR open ≠ PR merge:** opening a PR and merging it are two separate steps requiring separate instructions. After opening, share the URL and stop. Only merge when the user explicitly says so in a subsequent message. Never merge in the same turn as opening. **Exception:** when the PR-driving skill is active on a PR, merge automatically once all checks pass and threads are resolved — no separate instruction needed.
- **Executable artifacts need live output as evidence:** for shell scripts, Makefiles, and generated files (shortcuts, plists, configs), "verified" means the artifact was executed and its output is shown in the session. Type-checking and linting alone are not sufficient evidence for a script that was never run.

## Specialist roles → which tool to reach for

- Architecture review / simplification → the code-review and simplify skills, or the `architecture-reviewer` role.
- Debugging / root cause → the systematic-debugging skill or the `debugging-specialist` role.
- Tests / coverage / regressions → the `test-engineer` role plus the repo's own test command.
- Security / secrets / permissions → the security-review skill or the `security-reviewer` role.
- Performance → the `performance-reviewer` role.
- Docs / API / pattern verification → the `research-agent` role, or a read-only exploration agent.
