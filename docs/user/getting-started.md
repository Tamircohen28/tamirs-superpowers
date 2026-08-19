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

## 2. Install the plugin

Follow the guide for your platform — each one covers install, verify, update, and uninstall:

- [Claude Code](install/claude-code.md)
- [Claude Desktop](install/claude-desktop.md) — the same plugin, a different runtime surface
- [Codex CLI](install/codex.md)
- [Cursor](install/cursor.md)
- [Gemini CLI](install/gemini.md) — two commands: the extension, then the skills mirror
- [OpenCode](install/opencode.md)

That makes the skills available *inside* that platform. It does not touch your machine's
global config — that is the next step, and it is separate on purpose.

## 3. Set up your machine (optional)

Installing the plugin does not write any config. `setup` is what renders this repo's
canonical configuration — global rules, the Claude permissions policy, agent definitions,
the statusline — into the config directory each agent CLI actually reads: `~/.claude`,
`~/.codex`, `~/.cursor`, `~/.gemini`, `~/.config/opencode`.

The first-run path is four steps, and the first two write nothing:

```bash
git clone https://github.com/Tamircohen28/tamirs-superpowers.git
cd tamirs-superpowers

make setup-plan          # 1. detect targets, print every change. Writes nothing, ever.
make setup               # 2. + 3. diff each change, ask, then write the ones you accept
bash scripts/doctor.sh . # 4. confirm the result
```

**1 — plan.** Detection replaces selection: you are never asked which platforms you have.
A target counts as present if its binary is on `PATH` or its config directory exists. The
plan names every file it would touch and why, and exits 0.

**2 — review.** `apply` shows a unified diff of each change *before* asking
`Proceed? [y/N/a/q]`, and the default is **No**. `a` accepts everything remaining, `q`
stops. Read the diff for `enabledPlugins` in particular — see the warning below.

**3 — apply.** Only what you accepted is written. The original of every file touched is
copied to `<file>.pre-tamirs-superpowers` first, and `bash scripts/setup.sh remove` restores
from exactly that copy. Running `apply` a second time reports `already up to date` and
writes nothing: idempotence is a content comparison, not a state file.

**4 — verify.** `bash scripts/doctor.sh .`, then open a session on any platform and check
that the global rules are in effect.

> **The one surprise worth knowing before step 3.** The canonical set records 15 plugins as
> deliberately **disabled**. On a machine where those are currently on, `apply` turns them
> off — intended, because the previous canonical set was all-on and would have re-enabled
> plugins that were switched off on purpose. The plan says so with the exact count before
> anything is written. Details: [setup](setup.md#applying-will-switch-some-plugins-off).

Useful variants:

```bash
bash scripts/setup.sh apply --targets claude   # one platform
bash scripts/setup.sh plan --json              # machine-readable plan
bash scripts/setup.sh remove                   # undo, scoped to what setup wrote
```

Full reference: [setup](setup.md) for the engine and the Claude modules,
[platform setup](platform-setup.md) for what each of the other four gets and what is
deliberately left alone.

## 4. Verify

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

## 5. Your first objective

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

## 6. What to read next

| If you want to | Read |
|---|---|
| Understand the model | [Concepts](concepts.md) |
| Drive multi-part work, or resume after an interruption | [Orchestration](orchestration.md) |
| Know what each skill does | [Skills](skills.md) |
| Know what your platform actually supports | [Platform differences](platform-differences.md) |
| Turn features on or off | [Configuration](configuration.md) |
| Manage machine-level config across all five CLIs | [Setup](setup.md) · [Platform setup](platform-setup.md) |
| Fix something | [Troubleshooting](troubleshooting.md) |

## Common first-run surprises

- **A worker did not open a PR.** Correct. Tasks end at commit + handoff; the objective
  opens exactly one PR at the end. See [work unit ≠ delivery unit](concepts.md#2-work-unit--delivery-unit).
- **It ran sequentially.** Most platforms have no verified parallel subagents, so the
  registry says `unknown` and the orchestrator degrades honestly rather than pretending.
- **A capability is listed `unknown`.** That means *this repo has not measured it*, not that
  it is broken. It is treated as unavailable until someone records evidence.
