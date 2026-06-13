# Skill Reference

Complete reference for all 15 skills bundled in `tamirs-superpowers`. Each becomes a slash command in Claude Code.

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

**When to use:** After opening a PR. You want Claude to handle the full review → merge cycle.

**What it does:**
1. Fetches fresh PR state and all unresolved review threads
2. Addresses each thread (agree / partial / disagree) and commits fixes
3. Monitors CI until all checks pass
4. Pauses for your explicit "approved" before merging
5. Squash-merges, closes linked issues, and removes the worktree

**Example:** `/tamirs-superpowers:pr-dev 42`

---

### `/tamirs-superpowers:docs-review`

**When to use:** When docs feel stale, links may be broken, or you want a quality pass before a release.

**What it does:** Sweeps every `*.md` under `README.md` and `docs/` across 5 axes: visual cleanliness, freshness vs git history, stray plan files, link validity, and cross-reference consistency. Fixes in-place, writes a findings report.

**Example:** `/tamirs-superpowers:docs-review` or `/docs-review docs/user/`

---

### `/tamirs-superpowers:task-audit`

**When to use:** After finishing a branch, before requesting review. Verify quality before human eyes see it.

**What it does:** Audits the branch diff across 7 dimensions: scope, commit quality, test coverage, leftover markers (TODO/FIXME/debugger), breaking changes, docs sync, and PR readiness. Writes a `task-audit.md` report.

**Example:** `/tamirs-superpowers:task-audit` (current branch) or `/task-audit feat/add-auth`

---

### `/tamirs-superpowers:targeted-debug`

**When to use:** You have a specific stack trace or error and want a focused hypothesis — not a broad codebase exploration.

**What it does:** Reads **only** files named in the stack trace. Forms a hypothesis from the trace alone before opening any file. Produces a structured report with root cause, suggested fix, and out-of-scope follow-ups. Never launches a broad investigation without asking.

**Example:** `/tamirs-superpowers:targeted-debug NullPointerException at UserService.java:142`

---

### `/tamirs-superpowers:babysit-pr`

**When to use:** After opening a PR, when you want Claude to monitor it autonomously in the background — polling CI, surfacing review comments, retrying flaky failures.

**What it does:** Continuously polls the PR until merged/closed or user help is needed. Retries likely-flaky CI failures up to 3 times, auto-fixes branch-related issues, surfaces review feedback promptly.

**Example:** `/tamirs-superpowers:babysit-pr 42`

---

## Meta

### `/tamirs-superpowers:changelog-review`

**When to use:** Any question about Claude Code features, hooks, plugins, settings, or "what changed between vX and vY".

**What it does:** Fetches live official Claude Code documentation (never relies on training knowledge). Three modes:
- **Answer** — any question about Claude Code behavior
- **Diff** — changelog between two versions
- **Review** — audit your Claude Code config against current docs

**Example:** `/tamirs-superpowers:changelog-review what hook events are available?` or `/changelog-review diff v2.0 v2.1`

---

### `/tamirs-superpowers:mcp-builder`

**When to use:** Building a new MCP server to integrate an external API or service.

**What it does:** Guides creation of high-quality MCP servers in Python (FastMCP) or TypeScript (MCP SDK) — tool design, error handling, pagination, auth patterns.

---

### `/tamirs-superpowers:mcp-pagination`

**When to use:** Working with any MCP tool that supports pagination (Jira, Slack, GitHub, etc.).

**What it does:** Enforces that pagination parameters are always included in MCP list/search calls. A guardrail skill — it fires as a reminder/constraint rather than an active workflow.

---

### `/tamirs-superpowers:find-skill`

**When to use:** "Is there a skill for X?" or "What skill should I use to do Y?"

**What it does:** Searches leading skill/plugin marketplaces in real time (Anthropic official, obra/superpowers, mattpocock/skills, Smithery, mcp.directory, and more) and returns ranked matches with quality scores.

**Example:** `/tamirs-superpowers:find-skill something that reviews PRs automatically`

---

### `/tamirs-superpowers:skill-creator`

**When to use:** You want to create a new Claude Code skill, improve an existing one, or measure skill quality.

**What it does:** Guides the full skill lifecycle — authoring new skills from scratch, iteratively improving description and trigger accuracy, running evals, and benchmarking performance with variance analysis.

**Example:** `/tamirs-superpowers:skill-creator` or `/tamirs-superpowers:skill-creator improve description for my-skill`

---

### `/tamirs-superpowers:session-report`

**When to use:** After a long session, or when you want to understand token spend, cache hit rates, and which skills were used.

**What it does:** Scans `~/.claude/projects` transcripts and generates a self-contained HTML report showing total tokens, cache savings, subagent calls, skill invocations, and most expensive prompts.

**Example:** `/tamirs-superpowers:session-report`

---

## Content

### `/tamirs-superpowers:dark-terminal-doc`

**When to use:** You need a polished, shareable HTML document — comparison table, reference sheet, changelog, release notes — with a dark terminal aesthetic.

**What it does:** Generates rich HTML documents using a consistent dark terminal-inspired design system. Outputs a self-contained file ready to share or open in a browser.

---

### `/tamirs-superpowers:algorithmic-art`

**When to use:** You want generative art created with code.

**What it does:** Creates original algorithmic art using p5.js — flow fields, particle systems, geometric patterns, and more. Uses seeded randomness for reproducibility and supports interactive parameter exploration.
