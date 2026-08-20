# Install on OpenCode CLI

**Platform:** OpenCode. **Surface:** OpenCode CLI, the terminal client — registry id
`opencode`. Every measurement below was taken there. OpenCode also ships a desktop client;
that surface, the **OpenCode desktop app**, is **unverified** — whether it reads the same
`opencode.json` `skills.paths` this guide configures has not been checked, so it has no
install guide and the skills row below is not carried over to it. See
[platform differences](../platform-differences.md#unverified-surfaces).

| | |
|---|---|
| **Validated against** | OpenCode **1.18.11** |
| **Minimum supported** | **1.16.2** — oldest version on which recursive skill discovery was verified |
| **Manifest** | none — OpenCode has no plugin-manifest bundle |
| **Config** | `opencode.json` (`skills.paths`), `.opencode/agent/` |
| **Official docs** | [Skills](https://opencode.ai/docs/skills/) · [Config](https://opencode.ai/docs/config/) · [Agents](https://opencode.ai/docs/agents/) · [Plugins](https://opencode.ai/docs/plugins/) · [JSON Schema](https://opencode.ai/config.json) |

Check your version:

```bash
opencode --version
```

## How OpenCode differs

OpenCode has no plugin marketplace and no plugin manifest. Its "plugins" are
JavaScript/TypeScript modules registered under `"plugin"` in `opencode.json` — a
different thing entirely from a skill bundle. So this repo installs on OpenCode **by
path**: you point OpenCode at the skills and it reads them natively, in place. Nothing
is copied and nothing is converted.

**This repo ships no OpenCode plugin module, and does not use the plugin API.**
Everything it needs from OpenCode — skills and subagents — is declarative. Adding a
JS/TS plugin would introduce a Node runtime dependency to buy nothing, so it stays
out. The one thing the plugin API *could* buy is lifecycle hooks, which is why hooks
are listed as unsupported below rather than quietly reimplemented.

### `skills.paths` is load-bearing

`skills.paths` is a real config key — `"Additional paths to skill folders"` in the
[published schema](https://opencode.ai/config.json) (`Config.properties.skills`). It is
not optional decoration here:

- OpenCode's automatic scan only covers `.opencode/skills/`, `.claude/skills/` and
  `.agents/skills/` (and their `~/.config/opencode`, `~/.claude`, `~/.agents`
  equivalents). This repo's skills live in `skills/` at the repo root, which is **not**
  one of those locations.
- Verified on 1.18.11: with `skills.paths` removed, a `skills/` tree at the repo root is
  discovered **zero** times. With it, the whole tree loads.

`skills.paths` accepts absolute paths, relative paths (resolved against the config
file's directory), and *zero-level* paths — a path that **is** the skill directory
(containing `SKILL.md` directly) rather than a parent of skill directories.

**Discovery recurses.** OpenCode's published docs suggest discovery does not descend
into subdirectories. That is inaccurate as of 1.16.2 and still inaccurate at 1.18.11:
a path entry pointing at a parent directory finds `SKILL.md` files nested arbitrarily
deep beneath it, which is what makes this repo's `skills/<domain>/<name>/SKILL.md`
layout work unchanged.

> **Symlinks are NOT followed.** Verified on 1.18.11: a symlink is ignored for skill
> discovery whether it is the `skills` directory itself, a domain directory inside it,
> or an individual skill directory — all three discover **0** skills. Earlier revisions
> of this guide recommended a symlink-based global install; that method does not work.
> Use `skills.paths` with an absolute path instead, as below.

## Method A — global install (all projects)

Clone once, then point your **global** OpenCode config at the clone. Verified on
1.18.11 to load every skill in this repo with no project config present.

```bash
git clone https://github.com/Tamircohen28/tamirs-superpowers.git ~/src/tamirs-superpowers
mkdir -p ~/.config/opencode
```

Add to `~/.config/opencode/opencode.json` (use your real home path — `~` is not
expanded inside JSON):

```json
{
  "$schema": "https://opencode.ai/config.json",
  "skills": {
    "paths": [
      "/Users/you/src/tamirs-superpowers/skills/creative",
      "/Users/you/src/tamirs-superpowers/skills/debugging",
      "/Users/you/src/tamirs-superpowers/skills/dev-workflow",
      "/Users/you/src/tamirs-superpowers/skills/documentation",
      "/Users/you/src/tamirs-superpowers/skills/mcp",
      "/Users/you/src/tamirs-superpowers/skills/toolkit",
      "/Users/you/src/tamirs-superpowers/skills/repo/cleanup",
      "/Users/you/src/tamirs-superpowers/skills/repo/multi-agent-repo",
      "/Users/you/src/tamirs-superpowers/skills/repo/repo-scaffold",
      "/Users/you/src/tamirs-superpowers/skills/repo/repo-standards"
    ]
  }
}
```

Update with `git pull` — the paths keep resolving, so there is nothing to re-link.

**Why the `repo` domain is listed skill-by-skill:** `skills/repo/_contract/fixtures/`
holds complete gold-fixture skill trees used by the repo's own contract tests.
Because discovery recurses, a single entry for `skills/repo` would expose those
fixtures (`demo`, `example-skill`) as real user-facing skills. Listing the four real
repo skills individually keeps them out.

If you already keep a shared skills tree, these global locations are scanned
automatically and need no config — but they need the skills to physically live there
(a copy, not a symlink):

| Path | Notes |
|------|-------|
| `~/.config/opencode/skill/` or `skills/` | OpenCode's own |
| `~/.claude/skills/` | Shared with Claude Code — install once, both read it |
| `~/.agents/skills/` | Shared agent convention |

## Method B — per-project via `skills.paths`

Add to the project's `opencode.json`, with paths relative to that file:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "skills": {
    "paths": ["../tamirs-superpowers/skills/toolkit"]
  }
}
```

This repo's own `opencode.json` is exactly this form, listing the six domains plus the
four `repo` skills for the fixture reason above.

## Agents

Canonical agent files in `agents/` do **not** load on OpenCode as-is, for three
reasons confirmed against the [published schema](https://opencode.ai/config.json)
(`$defs.AgentConfig`):

- canonical `tools: Read, Grep, Glob` is a comma string; OpenCode has no such field shape;
- canonical `model: sonnet` is an alias; OpenCode needs a provider-prefixed id;
- canonical `name:` is not an `AgentConfig` property at all — OpenCode derives the
  agent id from the **filename**.

So this repo ships pre-translated adapters in `.opencode/agent/`, generated from
`agents/*.md` and committed, so installing from a clone needs no build step:

```bash
mkdir -p ~/.config/opencode/agent
cp ~/src/tamirs-superpowers/.opencode/agent/*.md ~/.config/opencode/agent/
```

(Copy, don't symlink — see the symlink note above. Both `agent/` and `agents/` are
accepted directory names; this repo uses the singular.)

To regenerate after editing `agents/`:

```bash
make opencode-agents          # write .opencode/agent/
make opencode-agents-check    # fail if it has drifted
```

**Never hand-edit `.opencode/agent/*.md`.** Every file carries a generated-file header
naming its source, and `make opencode-agents-check` (also run by
`tests/test-opencode-adapter.sh` and CI) fails on any drift.

### Permissions are translated, not copied

The canonical `tools:` field is an **allowlist** — an agent declaring `Read, Grep, Glob`
is read-only. Translating that to OpenCode's `tools` object naively (listing only the
granted tools) does **not** preserve it: everything unlisted stays enabled. Verified on
1.18.11, that shape resolves to `bash: true, edit: true, write: true, task: true`, so a
read-only reviewer silently gains write access.

The generator therefore emits the non-deprecated `permission:` field with an explicit
`allow`/`deny` for every gateable tool. OpenCode's own schema marks the `tools` object
`@deprecated Use 'permission' field instead`, so this is both the safer and the current
shape.

## MCP servers (optional)

OpenCode does not read `.mcp.json`. Port the entries you want into the `mcp` block of
`opencode.json` — see the [MCP docs](https://opencode.ai/docs/mcp-servers/). Use
environment variables for tokens; never commit them.

## Verify

```bash
opencode debug skill                      # lists every discovered skill
opencode debug agent security-reviewer    # resolved agent config, incl. permissions
opencode debug config                     # resolved config, including skills.paths
```

`opencode debug skill` should list every skill in this repo and **no** fixture skills
(`demo`, `example-skill`). If those two appear, a `skills.paths` entry points at
`skills/repo` rather than the four individual skill directories.

From a clone of this repo, the full adapter contract runs as:

```bash
bash tests/test-opencode-adapter.sh
```

It checks the config parses, every `skills.paths` entry resolves to real skills, no
fixtures leak, `.opencode/agent/` is in sync with `agents/`, no adapter was
hand-edited, and — when the `opencode` CLI is present — that every generated adapter
actually loads.

## Update

```bash
cd ~/src/tamirs-superpowers && git pull
cp .opencode/agent/*.md ~/.config/opencode/agent/    # only if you copied agents
```

Config is read once at startup and is **not** hot-reloaded. After changing
`opencode.json`, an agent file, or a skill, quit and restart OpenCode.

## Uninstall

```bash
# 1. remove the skills.paths entries you added
$EDITOR ~/.config/opencode/opencode.json     # or the project's opencode.json

# 2. remove copied agent adapters
rm -f ~/.config/opencode/agent/{architecture-reviewer,debugging-specialist,implementer,\
integrator,orchestrator,performance-reviewer,research-agent,security-reviewer,\
spec-reviewer,test-engineer}.md

# 3. remove the clone
rm -rf ~/src/tamirs-superpowers
```

Then restart OpenCode and confirm with `opencode debug skill`.

## Machine-level setup

`skills.paths` makes the skills discoverable. Global rules in `~/.config/opencode` are a
separate, optional step:

```bash
bash scripts/setup.sh plan  --targets opencode  # writes nothing
bash scripts/setup.sh apply --targets opencode
bash scripts/setup.sh remove --targets opencode
```

| Module | Writes | What it does |
|---|---|---|
| `agents-md` | `~/.config/opencode/AGENTS.md` | Renders `core/global-rules.md` inside `>>> tamirs-superpowers >>>` markers |
| `config` | `~/.config/opencode/opencode.json` | Asserts `$schema` and nothing else |

OpenCode loads `~/.config/opencode/AGENTS.md` with no config key, so `$schema` — which only
makes your editor validate the file — is all the fragment needs to assert. `plugin`, `mcp`
and `permission` are untouched. Config is read once at startup, so restart OpenCode after
an `apply`.

`plan` writes nothing and is the default when there is no terminal, so a hook or CI run can
never adopt anything silently. `apply` shows a diff and asks per change, defaulting to
**No**. Re-running is a no-op — idempotence is a content comparison. Full reference:
[setup](../setup.md) · [platform setup](../platform-setup.md).

## Capability support

Status vocabulary matches [`core/capabilities/platforms.json`](../../../core/capabilities/platforms.json),
which is the authoritative registry; `platforms/opencode/adapter.yaml` is the thin pointer.

| Capability | Status | Detail |
|---|---|---|
| Skills | ✅ native | Canonical `skills/` read in place via `skills.paths`. Nothing copied or converted. |
| Skill auto-invocation | ❓ unknown | Discovery is verified; automatic description-based selection is not. Name the skill explicitly. |
| Subagents | ⚙️ adapter | Generated `.opencode/agent/`; drift enforced by `make opencode-agents-check`. |
| Parallel subagents | ❓ unknown | Not measured. Assume sequential fan-out. |
| MCP | ✅ native | Via the `mcp` block of `opencode.json`, not `.mcp.json`. |
| Hooks | ❌ unsupported | OpenCode has no `hooks.json`. Its only lifecycle mechanism is the JS/TS plugin API, and **this repo ships no plugin module** — that would add a Node runtime dependency for no other gain. The worktree guards in `hooks/` do not run at all; they are enforced in CI instead. |
| Statusline | ❌ unsupported | No plugin-declared statusline extension point. Cosmetic only; nothing depends on it. |
| Marketplace install | ❌ unsupported | No plugin marketplace. Install is by path. |
| `.mcp.json` auto-wiring | ❌ unsupported | Port entries into `opencode.json` by hand. |
| Symlinked skill trees | ❌ unsupported | Not followed at any level (verified 1.18.11). Use `skills.paths`. |
| Worktree isolation | ⚙️ emulated | The skill drives `git worktree` through the shell; no hook automation. |
| Session transcripts | ❓ unknown | `session-report` targets the Claude JSONL format only and should refuse rather than guess. |

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| No skills listed | Run `opencode debug config` and confirm `skills.paths` resolved. Relative paths resolve against the config file's directory, not the cwd. |
| Skills still missing after adding paths | Config is not hot-reloaded — restart OpenCode. |
| Symlinked skills not found | Expected: symlinks are not followed. Replace the symlink with a `skills.paths` entry pointing at the real absolute path. |
| `Configuration is invalid at .opencode/agent/<x>.md` | A hand-edited or unconverted agent file. Run `make opencode-agents`. |
| Fixture skills `demo` / `example-skill` appear | A `skills.paths` entry points at `skills/repo`; list the four real repo skills individually. |
| An agent can edit files it should not | The adapter lost its denies. Run `make opencode-agents`, then `opencode debug agent <name>` and check the resolved `tools` map. |
