# Getting started

Install, verify, and run your first objective. Budget five minutes.

---

## 1. Prerequisites

| Tool | Required? | Why |
|---|---|---|
| A supported agent platform | yes | Claude Code, Claude Desktop, Codex CLI, Cursor, Gemini CLI, or OpenCode |
| `git` 2.30+ | yes | branch and worktree workflows |
| `jq` | yes | every hook and check script parses JSON with it |
| `bash` 3.2+ | yes | all scripts are POSIX-friendly bash; macOS system bash works |
| `gh` (GitHub CLI), authenticated | optional | PR and issue workflows (`/pr-dev`, `/plan-dev`, delivery). Without it, delivery stops at a pushed branch and says so |
| `python3` + `pyyaml` | contributors only | frontmatter validation in `make validate` |

There is no build step, no `package.json`, and no runtime to install. The toolkit is
Markdown, JSON, and bash.

## 2. Install

Follow the guide for your platform — each one covers install, verify, update, and uninstall:

- [Claude Code](install/claude-code.md)
- [Claude Desktop](install/claude-desktop.md) — the same plugin, a different runtime surface
- [Codex CLI](install/codex.md)
- [Cursor](install/cursor.md)
- [Gemini CLI](install/gemini.md) — two commands: the extension, then the skills mirror
- [OpenCode](install/opencode.md)

> **Not the same thing as contributing.** `make install` bootstraps a Claude *machine*
> profile for this repo's maintainer workflow. It is not how you install the plugin, and you
> should not run it to become a user. Contributor setup lives in
> [docs/CONTRIBUTING.md](../CONTRIBUTING.md).

## 3. Verify

From a clone (or the installed plugin directory):

```bash
bash scripts/doctor.sh .
```

`doctor` reports the detected platform, the canonical version and any drift, which required
and optional tools are present, which optional features are therefore usable, and a one-line
remedy for anything missing. It exits non-zero only when the install is genuinely broken —
missing optional tools are reported, not failed.

Inside your agent session, the quickest check is that the skills resolve:

```text
/orchestrate-dev
```

If your platform does not expose slash commands (see
[platform differences](platform-differences.md)), ask for the skill by name instead:
*"use the orchestrate-dev skill"*.

## 4. Your first objective

Start small — one coherent change:

```text
/start-dev add a --json flag to scripts/doctor.sh
```

`/start-dev` routes: a simple standalone task runs as one worker plus one delivery, and you
get one PR. Now try something with parts:

```text
/orchestrate-dev implement rate limiting: middleware, config plumbing, and tests
```

You should see, before any code is written:

1. a one-line decision about whether to orchestrate at all;
2. the objective id and the task graph, each task with its write scope;
3. the execution mode — concurrent, serialized, or **sequential** — and the capability
   finding that chose it.

Then workers run, each ending at commit + handoff; the branches merge onto
`objective/<slug>`; the combined diff is reviewed; and **one** PR opens.

## 5. What to read next

| If you want to | Read |
|---|---|
| Understand the model | [Concepts](concepts.md) |
| Drive multi-part work, or resume after an interruption | [Orchestration](orchestration.md) |
| Know what each skill does | [Skills](skills.md) |
| Know what your platform actually supports | [Platform differences](platform-differences.md) |
| Turn features on or off | [Configuration](configuration.md) |
| Fix something | [Troubleshooting](troubleshooting.md) |

## Common first-run surprises

- **A worker did not open a PR.** Correct. Tasks end at commit + handoff; the objective
  opens exactly one PR at the end. See [work unit ≠ delivery unit](concepts.md#2-work-unit--delivery-unit).
- **It ran sequentially.** Most platforms have no verified parallel subagents, so the
  registry says `unknown` and the orchestrator degrades honestly rather than pretending.
- **A capability is listed `unknown`.** That means *this repo has not measured it*, not that
  it is broken. It is treated as unavailable until someone records evidence.
