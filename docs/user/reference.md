# Skill Reference

Complete reference for all 17 skills bundled in `tamirs-superpowers`. Each user-facing skill becomes a slash command in Claude Code.

Four skills are **internal** — invoked automatically by parent skills (`repo-polish`, `mcp-builder`) and hidden from the `/` menu.

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

### `/tamirs-superpowers:plugin-compat`

**When to use:** You want your repo to work as a plugin or tool for Claude Code, Cursor, and/or OpenAI Codex.

**What it does:** Fetches the latest platform docs and generates all required config files — `CLAUDE.md`, `.cursor/rules/`, `AGENTS.md` — so the repo is compatible with all three AI coding assistants.

**Example:** `/tamirs-superpowers:plugin-compat` (targets all three platforms by default)

---

### `/tamirs-superpowers:targeted-debug`

**When to use:** You have a specific stack trace or error and want a focused hypothesis — not a broad codebase exploration.

**What it does:** Reads **only** files named in the stack trace. Forms a hypothesis from the trace alone before opening any file. Produces a structured report with root cause, suggested fix, and out-of-scope follow-ups.

**Example:** `/tamirs-superpowers:targeted-debug NullPointerException at UserService.java:142`

---

## Repo

### `/tamirs-superpowers:repo-polish`

**When to use:** Preparing a personal project for public GitHub — scan employer IP, scaffold docs/CI, publish.

**What it does:**
1. Scans for employer IP and waits for your acknowledgment
2. Scaffolds README, docs tree, CI, PR templates, CLAUDE.md
3. Automatically invokes internal audits: `repo-review` → `docs-review` → `changelog-review` (plugins only)
4. Creates GitHub repo and pushes after explicit approval

**Example:** `/tamirs-superpowers:repo-polish ~/projects/my-app`

---

### `/tamirs-superpowers:repo-scaffold`

**When to use:** Starting a brand-new project — you want a fully wired GitHub repo in one command.

**What it does:** Creates a private GitHub repo from an idea or description with production-ready infrastructure: README with badges, docs tree, CI/CD, CLAUDE.md, `.claude/` config, branch protection, and project skills.

**Example:** `/tamirs-superpowers:repo-scaffold my-new-tool -- "A CLI that does X"`

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
| `docs-review` | `repo-polish` Step 6b | Audit and fix README + `docs/**` |
| `repo-review` | `repo-polish` Step 6a | Read-only repo health report |
| `changelog-review` | `repo-polish` Step 6c | Claude Code plugin pattern audit |
| `mcp-pagination` | `mcp-builder` | Pagination guardrails for list/search MCP tools |
