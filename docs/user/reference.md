# Skill Reference

Complete reference for all 16 skills bundled in `tamirs-superpowers`. Each user-facing skill becomes a slash command in Claude Code.

Three skills are **internal** — invoked automatically by parent skills (`repo-standards`, `mcp-builder`) and hidden from the `/` menu.

---

## Dev Workflow

### `/tamirs-superpowers:plan-dev`

**When to use:** Before writing any code. You have a task, spec, list of fixes, or GitHub issue URL and want to break it into reviewable phases before Claude starts implementing.

**What it does:**
1. Analyzes input and classifies work by type and area
2. Structures work into logical phases (each becomes a GitHub issue)
3. Presents the plan and waits for your approval
4. Creates GitHub issues after explicit approval

**Example:** `/tamirs-superpowers:plan-dev add OAuth2 login to this app`

---

### `/tamirs-superpowers:start-dev`

**When to use:** After approving a plan, or when you have a GitHub issue/task and want Claude to implement it end-to-end.

**What it does:**
1. Fetches issue details (if given a number)
2. Creates an isolated git worktree on a new branch
3. Implements the changes with conventional commits
4. Runs available tests/lint
5. Pushes and opens a PR

**Example:** `/tamirs-superpowers:start-dev #42`

---

### `/tamirs-superpowers:pr-dev`

**When to use:** After a PR is open — drive it through review and merge end-to-end.

**What it does:** Runs a persistent drive loop until the PR is merge-ready:
1. Fetches current PR state (re-fetches before every decision)
2. Addresses all unresolved review threads (states reply in conversation first)
3. Diagnoses CI failures, patches branch-related ones, retries flakes (max 3×)
4. Surfaces blockers if CI is infra-related or a thread can't be resolved
5. Prints readiness summary and **stops** — waits for you to type `approved` before merging

**Example:** `/tamirs-superpowers:pr-dev 42`

---

## Debugging

### `/tamirs-superpowers:targeted-debug`

**When to use:** You have a specific stack trace or error and want a focused hypothesis — not a broad codebase exploration.

**What it does:** Reads **only** files named in the stack trace. Forms a hypothesis from the trace alone before opening any file. Produces a structured report with root cause, suggested fix, and out-of-scope follow-ups.

**Example:** `/tamirs-superpowers:targeted-debug NullPointerException at UserService.java:142`

---

## Repo

### `/tamirs-superpowers:repo-standards`

**When to use:** Auditing or polishing an existing repo to Tamir Cohen standards — README, docs tree, CI/CD, branch protection, employer IP, hygiene, and multi-agent support.

**What it does:**
1. **review** (default) — standards inventory, IP scan, multi-agent-repo review appendix; writes `docs/engineering/repo-standards-review-<date>.md`
2. **plan** — phased remediation (phases 0–7)
3. **polish** — implements on `feat/repo-standards-setup`, delegates to `multi-agent-repo`, `docs-review`, `changelog-review`; `assert-contract.sh app-gold` must pass; opens PR (does not merge or create new remote repo)

**Example:** `/tamirs-superpowers:repo-standards review ~/projects/my-app`

---

### `/tamirs-superpowers:repo-scaffold`

**When to use:** Starting a brand-new project — you want a fully wired GitHub repo in one command.

**What it does:** Creates a private GitHub repo from an idea or description with production-ready infrastructure: README with badges, docs tree, CI/CD, AGENTS.md + multi-agent adapters, branch protection, and project skills. Output must pass the shared `app-gold` contract (`make test-repo-contract`).

**Example:** `/tamirs-superpowers:repo-scaffold my-new-tool -- "A CLI that does X"`

---

### `/tamirs-superpowers:multi-agent-repo`

**When to use:** Audit, plan, or implement canonical multi-agent development setup for Claude Code, Cursor, and Codex — or make an existing repo compatible with all three assistants.

**What it does:**
1. **review** (default) — inventories agent config, auto-scores gaps, walks full rubric, writes `docs/agent-guidelines/multi-agent-review-<date>.md`
2. **plan** — turns review gaps into phased remediation (AGENTS.md → adapters → skills → drift CI)
3. **dev** — implements the plan on `feat/multi-agent-setup`, fetches live platform docs, opens a PR (does not merge)

**Example:** `/tamirs-superpowers:multi-agent-repo review ../my-app`

---

## Meta

### `/tamirs-superpowers:find-skill`

**When to use:** "Is there a skill for X?" or "What skill should I use to do Y?"

**What it does:** Searches leading skill/plugin marketplaces in real time and returns ranked matches with quality scores.

**Example:** `/tamirs-superpowers:find-skill something that reviews PRs automatically`

---

### `/tamirs-superpowers:skill-creator`

**When to use:** Create a new Claude Code skill, improve an existing one, or measure skill quality.

**What it does:** Guides the full skill lifecycle — authoring, description optimization, evals, and benchmarking.

**Example:** `/tamirs-superpowers:skill-creator improve description for my-skill`

---

### `/tamirs-superpowers:session-report`

**When to use:** After a long session, or when you want token spend, cache hit rates, and skill usage.

**What it does:** Scans `~/.claude/projects` transcripts and generates a self-contained HTML report.

**Example:** `/tamirs-superpowers:session-report`

---

## MCP

### `/tamirs-superpowers:mcp-builder`

**When to use:** Building a new MCP server to integrate an external API or service.

**What it does:** Guides creation of MCP servers in Python (FastMCP) or TypeScript — tool design, error handling, auth patterns. Automatically invokes `mcp-pagination` for list/search tools.

---

## Creative

### `/tamirs-superpowers:dark-terminal-doc`

**When to use:** You need a polished, shareable HTML document — comparison table, reference sheet, changelog — with a dark terminal aesthetic.

**What it does:** Generates rich HTML using a consistent dark terminal-inspired design system.

---

### `/tamirs-superpowers:algorithmic-art`

**When to use:** You want generative art created with code.

**What it does:** Creates original algorithmic art using p5.js — flow fields, particle systems, geometric patterns. Seeded randomness and interactive parameters.

---

## Internal skills (not user-invocable)

These run via `Skill("…")` from parent skills — you cannot type `/skill-name` directly.

| Skill | Invoked by | Purpose |
|-------|-----------|---------|
| `docs-review` | `repo-standards` polish phase 6 | Audit and fix README + `docs/**` |
| `changelog-review` | `repo-standards` polish phase 6 (plugins) | Claude Code plugin pattern audit |
| `mcp-pagination` | `mcp-builder` | Pagination guardrails for list/search MCP tools |
