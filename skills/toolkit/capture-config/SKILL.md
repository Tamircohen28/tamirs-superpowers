---
name: capture-config
description: 'Use when a hand-edit to a machine-level agent config should become permanent and available everywhere — the user edited ~/.claude/settings.json, ~/.claude/CLAUDE.md, ~/.codex/AGENTS.md, ~/.cursor/, ~/.gemini/ or ~/.config/opencode/ by hand and says ''make this permanent'', ''save this to the repo'', ''keep this setting'', ''add this rule everywhere'', ''sync my machine back to the repo'', ''capture my config'', ''I tweaked a permission, don''t lose it'', ''put this on all my platforms'' — or when setup/doctor reports the machine has drifted from the repo and the machine is the side that is right. Offer it proactively right after helping the user hand-edit one of those files. It classifies each difference (portable / machine-local / secret / third-party / unknown), refuses credentials, blocks employer references, and produces a reviewed PR. It never merges.'
when_to_use: 'User hand-edited a global agent config and wants it kept: ''make this permanent'', ''save this setting to the repo'', ''add this rule to every platform'', ''capture my machine config'', ''my repo and my machine have drifted, the machine is right'', ''don''t lose this permission'' — or you just helped them edit ~/.claude/settings.json, ~/.claude/CLAUDE.md or another machine-level config file and the change is worth keeping. Not for repo-scoped .claude/settings.json, and not for pushing the repo onto the machine (that is setup.sh / make setup).'
argument-hint: '[optional: detect | review | deliver | --targets claude,codex]'
arguments: []
disable-model-invocation: false
user-invocable: true
allowed-tools:
- Bash
- Read
- Edit
- Grep
- AskUserQuestion
disallowed-tools: []
model: claude-sonnet-4-6
effort: medium
context: ''
agent: ''
hooks: {}
paths: []
shell: bash
compatibility:
  claude-code: supported
  claude-desktop: unsupported
  codex: unknown
  cursor: unknown
  gemini: unknown
  opencode: unknown
metadata:
  updated-date: '2026-08-19'
  tamirs:
    visibility: public
    category: toolkit
    role: integrator
    validation-tier: 2
    updated-date: '2026-08-19'
    capabilities:
      required:
        - shell
        - git
      optional:
        - github_cli
        - ask_user_question
    tags:
      - toolkit
      - config
      - capture
      - multi-platform
      - canonical-source
      - pull-request
---

# capture-config

Propose a machine's hand-edits back into this repo, as a reviewed pull request.

`scripts/setup.sh` renders repo → machine. This is the inverse: machine → repo.
Your job is to run it, read the classified change set with the user, and hand the
result to `pr-dev`. **You do not decide what is portable — the script classifies,
and the user answers.**

## Why this is not automatic

Rendering only ever writes files this repo authored. Capture reads files a
*person* edited, so a run can pick up a credential, a path that exists only on
one laptop, or another tool's wiring. That is why nothing is adopted without an
explicit answer, why secrets are refused rather than skipped, and why the result
is a PR and never a commit. Do not try to shortcut any of that.

## When to offer it

Offer it — do not wait to be asked — when:

- you have just helped the user hand-edit `~/.claude/settings.json`,
  `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.cursor/`, `~/.gemini/` or
  `~/.config/opencode/`, and the change reads like policy rather than a one-off
- `scripts/doctor.sh` or `setup.sh plan` reports repo/machine drift **and the
  machine is the side that is right**
- the user says a setting "keeps getting lost" between machines

Do **not** offer it for a repo-scoped `.claude/settings.json`, and do not offer
it when the repo is right and the machine is stale — that is `make setup`.

## The three steps

### 1. Look first, always

```bash
bash scripts/capture-config.sh detect
```

Never writes. Prints one line per difference with its classification. Read the
table with the user before doing anything else. If everything is
`machine-local`, `secret` or `third-party`, say so and stop — there is nothing
to capture, and that is a good outcome, not a failure.

Add `--targets claude` (or a comma list) when the user names a platform, and
`--json` when you need to reason about the change set programmatically.

### 2. Review and adopt

```bash
bash scripts/capture-config.sh review
```

This prompts per hunk on `/dev/tty` with `[y/N/a/q/s]`, default **skip**.

**If you are running in a session with no terminal**, the command prints the
change set and adopts nothing — that is correct, not an error. Do not work
around it. Either surface the change set to the user and ask which ids they
want, then pass them explicitly:

```bash
bash scripts/capture-config.sh review --adopt 3,7
```

…or tell the user to run `make capture` themselves in their terminal. Naming ids
is a decision the user made; there is no `--yes` and you must not invent one.

Adopted hunks are staged into the **canonical source** — `core/global-rules.md`
or `platforms/<target>/settings.d/` — never into a platform's rendered file. The
command then re-runs the renderers and prints the downstream diff, so the user
sees what the change does on all five platforms before agreeing to a PR. Walk
them through that section; it is the reason this tool exists.

### 3. Deliver

```bash
bash scripts/capture-config.sh deliver
```

Runs `make validate`, creates `capture/<date>-<slug>`, one commit per platform
touched, and writes a PR body naming what was captured, from which machine file,
where it now renders, and what was skipped and why.

It does **not** push and does **not** open the PR. Show the user the printed
`gh pr create` command, then hand off to `/pr-dev` if they want it driven.
**Never merge.** Opening and merging are separate decisions.

## Reading the classifications

| Class | What you should say about it |
|---|---|
| `portable` | offered — this is what the user is here for |
| `machine-local` | skipped; name the reason (absolute path, machine state) so it does not look like an oversight |
| `secret` | **refused.** Never print, echo, or work around the value. If the user wants the setting, capture the env var *name* (`${GITHUB_TOKEN}`) instead |
| `third-party` | skipped, owner named. Do not adopt another tool's wiring on the user's behalf |
| `unknown` | asked. If you have a view, give it — but the user answers |

A hunk marked `blocked: IP scan hit` is blocked on purpose and only that hunk is
affected. Do not disable the scan. If the pattern is a false positive, say so and
let the user decide; if their employer's name needs adding, point them at
`~/.config/tamirs-superpowers/scan-patterns.txt`.

## Hard rules

- **Never adopt on the user's behalf.** No terminal means no adoption.
- **Never print a refused value**, in any form, including "just to confirm".
- **Never commit or merge.** `deliver` stops at a local branch by design.
- **Never edit a platform's rendered file** to make a capture "work" — if a
  value has no canonical home, that is a gap to report, not to route around.
- **Never disable a gate** (`--adopt` is for selecting hunks, not for bypassing a
  block; a blocked hunk stays blocked).

## Verify before reporting done

```bash
bash scripts/capture-config.sh detect --json | jq '.summary'
bash tests/test-capture.sh
```

Report the summary counts and what landed where. If nothing was adopted, say
that plainly — a capture run that finds nothing worth keeping is a normal
result.

## Reference

- Full user guide: `docs/user/capture.md`
- Classification data per platform: `platforms/<target>/capture.conf`
- Test cases for this skill: `evals/evals.json`, `evals/trigger-evals.json`
