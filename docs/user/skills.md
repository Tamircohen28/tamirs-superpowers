# Skills

The toolkit ships **25 skills** in 7 domains — 22 you can invoke directly, 3 internal
companions invoked only by other skills. Counted from `skills/**/SKILL.md` on 2026-08-19 and
enforced by `scripts/check-doc-claims.sh`, which fails the build when this number and the
tree disagree.

Each skill lives at `skills/<domain>/<name>/SKILL.md`.

---

## How a skill gets invoked

| Way | Looks like | Needs |
|---|---|---|
| Slash command | `/orchestrate-dev` | the `slash_commands` capability |
| By name | *"use the retro skill"* | nothing |
| Automatically | the agent picks it from your phrasing | the `skill_auto_invocation` capability |
| By another skill | `mcp-builder` pulls in `mcp-pagination` | nothing |

Auto-invocation is `native` only on Claude Code and Claude Desktop, `partial` on Cursor, and
`unknown` elsewhere — so on most platforms, name the skill. See
[platform differences](platform-differences.md).

Two frontmatter switches control this: `user-invocable: false` hides a skill from the slash
menu, and `disable-model-invocation: true` stops it triggering automatically. Skills marked
**internal** below carry both.

**Where the files come from differs by platform.** Claude Code, Claude Desktop, Codex,
Cursor, and OpenCode all read the canonical `skills/<domain>/<name>/` tree directly. Gemini
CLI cannot — it scans exactly one level below a skills root, so the two-level tree resolves
to zero skills, silently — and instead reads a generated flat symlink mirror at
`.gemini/skills/`. Same skills, one copy in the repo, different discovery path; see the
[Gemini install guide](install/gemini.md).

---

## dev-workflow

| Skill | Role | Tier | What it does |
|---|---|:--:|---|
| `/plan-dev` | planner | 0 | Turn an informal request, spec, or review doc into phases and GitHub issues. Output is a roadmap, not code. |
| `/orchestrate-dev` | orchestrator | 2 | Own a multi-part objective: task graph, dispatch (parallel or sequential), integration, combined-diff review, **one** PR. |
| `/worker-dev` | implementer | 1 | Execute exactly one task inside its scope. Ends at commit + handoff — never a PR. |
| `/deliver-dev` | integrator | 2 | Turn an integrated objective into the delivery unit: final diff review, full gates, push, open the one PR. |
| `/pr-dev` | — | 3 | Drive an open PR to merge: review threads, CI fixes, flake retries, merge policy. |
| `/start-dev` | implementer | 2 | Compatibility front door. Routes to worker-only, orchestrate, or worker+deliver. |
| `/switch-dev` | — | — | Hand off, resume, or list work across platforms. Explicit invocation only. |
| `/decision` | — | 0 | Summarize a pending decision, issue, or PR in plain language and hand you a choice menu. |

`/start-dev` still works exactly as before for a simple standalone task — it now calls
`worker-dev` and `deliver-dev` instead of doing everything itself. See
[Orchestration](orchestration.md).

## repo

| Skill | What it does |
|---|---|
| `/repo-standards` | Audit, plan, and polish a repo to standard: README, docs tree, CI/CD, changelog, branch protection, hygiene, multi-agent setup. |
| `/repo-scaffold` | Create a new repo with production-ready infrastructure. `--type plugin` scaffolds an agent-kit distribution repo. |
| `/multi-agent-repo` | Audit, plan, or implement canonical multi-agent setup (AGENTS.md + thin adapters + drift checks). |
| `/cleanup` | Full repo housekeeping: stale branches, open PRs, idle worktrees (rescuing uncommitted work), build artifacts, local/remote sync. |

## documentation

| Skill | What it does |
|---|---|
| `/platform-sync` | Audit any repo against the latest platform docs and synthesize a numbered improvement plan. |
| `/dark-terminal-doc` | Produce a polished single-file HTML technical document. |
| `docs-review` | **internal** — documentation quality sweep, used by `/repo-standards`. |
| `changelog-review` | **internal** — changelog/pattern audit, used by `/repo-standards`. |

## toolkit

| Skill | What it does |
|---|---|
| `/skill-creator` | Create, improve, and benchmark skills. Always use this rather than hand-writing a SKILL.md. |
| `/find-skill` | Search public skill and plugin marketplaces and rank matches. |
| `/retro` | Session postmortem — find friction and propose rule/hook/memory/skill improvements. Proposes; never writes without approval. |
| `/session-report` | Token and cache usage analytics. Requires readable session transcripts — Claude Code only today. |
| `/notify-setup` | Wire opt-in phone notifications via Pushover. |

## mcp

| Skill | What it does |
|---|---|
| `/mcp-builder` | Build and scaffold an MCP server around an API, database, or service. |
| `mcp-pagination` | **internal** — pagination guardrails, pulled in by `/mcp-builder`. |

## debugging

| Skill | What it does |
|---|---|
| `/targeted-debug` | Root-cause a concrete error — a stack trace, panic, or `file:line`. Reads only the named files. |

## creative

| Skill | What it does |
|---|---|
| `/field-notebook-ui` | Interactive UI artifacts in the engineer's field-notebook visual style. |

---

## Reading a skill's contract

Every `SKILL.md` declares, in its frontmatter under `metadata.tamirs`:

- `visibility` — `public` or `internal`;
- `category` — the domain directory it lives in;
- `role` — which [role](agents.md) it plays, if any;
- `validation-tier` — which [tier](concepts.md#5-validation-tiers-03) it runs;
- `capabilities.required` / `capabilities.optional` — what it needs from the platform.

A skill whose required capability is missing on your platform says so and degrades along the
stated fallback. Portable-schema details: [engineering/architecture/skill-schema.md](../engineering/architecture/skill-schema.md).

## Writing your own

Use `/skill-creator`. It generates conforming frontmatter, keeps the description
trigger-shaped, and can benchmark whether the skill actually fires.
