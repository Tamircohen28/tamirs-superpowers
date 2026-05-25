# External skill references

The skill collections below are referenced from `README.md` but not redistributed inside this plugin. Each lives in its own repo with its own license and release cadence — install upstream so you always get the latest.

## obra/superpowers — 14 workflow skills

Source: https://github.com/obra/superpowers/tree/main/skills

| Skill | Description |
|---|---|
| `brainstorming` | Use before any creative work — explores user intent, requirements and design before implementation. |
| `dispatching-parallel-agents` | Use when facing 2+ independent tasks that can be worked without shared state. |
| `executing-plans` | Execute a written implementation plan with review checkpoints. |
| `finishing-a-development-branch` | Decide how to integrate completed work (merge, PR, cleanup). |
| `receiving-code-review` | Process review feedback with technical rigor before implementing suggestions. |
| `requesting-code-review` | Verify work meets requirements before merging. |
| `subagent-driven-development` | Execute implementation plans with independent tasks in the current session. |
| `systematic-debugging` | Systematic process for any bug, test failure, or unexpected behavior. |
| `test-driven-development` | Use before writing any implementation code. |
| `using-git-worktrees` | Isolated workspace via git worktree before plan execution. |
| `using-superpowers` | Establishes how to find and use skills at conversation start. |
| `verification-before-completion` | Run verification commands and confirm output before claiming work is done. |
| `writing-plans` | Use when you have a spec for a multi-step task, before touching code. |
| `writing-skills` | Use when creating new skills or editing existing ones. |

### Install

```bash
git clone https://github.com/obra/superpowers ~/.claude/plugins/superpowers
```

Or follow the install instructions in the repo's README.

---

## mattpocock/skills — engineering & productivity

Source: https://github.com/mattpocock/skills

Category-based layout (`skills/<category>/<skill-name>/`):

**engineering/** — `diagnose`, `grill-with-docs`, `improve-codebase-architecture`, `prototype`, `setup-matt-pocock-skills`, `tdd`, `to-issues`, `to-prd`, `triage`, `zoom-out`

**productivity/** — `caveman`, `grill-me`, `handoff`, `write-a-skill`

**misc/** — `git-guardrails-claude-code`, `migrate-to-shoehorn`, `scaffold-exercises`, `setup-pre-commit`

**personal/** — `edit-article`, `obsidian-vault`

**in-progress/** — `review`, `writing-beats`, `writing-fragments`, `writing-shape`

### Install

```bash
git clone https://github.com/mattpocock/skills ~/.claude/plugins/mattpocock-skills
```

Then run the `setup-matt-pocock-skills` skill from inside Claude to wire it up.

---

## Other referenced repos

| Repo | Why | Install |
|---|---|---|
| `anthropics/claude-plugins-official` | Source for `session-report` plugin and the upstream `skill-creator` plugin. | `git clone https://github.com/anthropics/claude-plugins-official` |
| `anthropics/skills` | Source for `skill-creator` and `mcp-builder` (already bundled here). | `git clone https://github.com/anthropics/skills` |
| `openai/codex` | Source for `babysit-pr` (already bundled here). The skill lives under `.codex/skills/babysit-pr/`. | `git clone https://github.com/openai/codex` |

## Why these aren't bundled

1. **License / attribution** — bundling third-party skills changes who's distributing them. Linking upstream preserves their attribution and license terms.
2. **Updates** — these repos change frequently; bundling a snapshot means you miss fixes.
3. **Plugin size** — superpowers and mattpocock/skills together would more than double the plugin size, with skills not all of which Tamir uses.

If you want one of these skills as an opinionated frozen snapshot inside `tamir-library`, copy its `SKILL.md` (and any `references/` it depends on) into `skills/<name>/` and re-zip.

## Can these become plugin dependencies too?

Maybe — if the upstream marketplace exposes them as named plugins. Per the [plugin dependencies docs](https://code.claude.com/docs/en/plugin-dependencies):

> Cross-marketplace dependencies are blocked unless the target marketplace is allowlisted in the root marketplace's `marketplace.json`.

To depend on a plugin from `obra/superpowers` or `mattpocock/skills`:

1. Add the marketplace once: `/plugin marketplace add obra/superpowers` (or `mattpocock/skills`).
2. Inspect what plugins it publishes via `/plugin` → Discover tab.
3. If `tamir-library` is itself hosted in a marketplace, allowlist the upstream marketplace in `marketplace.json` and add a `dependencies` entry with `{name, marketplace}`. If `tamir-library` is installed as a standalone `.plugin` file (no marketplace of its own), declare the dep with the explicit `marketplace` field and ensure the user has added that marketplace before installing.
4. Without that step, just install the plugins manually after adding the marketplace — they behave identically once installed; only the auto-install on `tamir-library` install is lost.
