# Install on OpenCode CLI

> ## ⚠️ OpenCode 2 only
>
> This adapter targets **OpenCode 2** (`@opencode/cli`, the `opencode.ai/v2/docs` line).
> **OpenCode 1.x is no longer supported** by this repo: V2 does not run V1 plugins
> ("V1 plugin implementations do not run in V2"), deprecated the 15-key `permission`
> map, changed the default agent mode to `primary`, allows access outside the project by
> default where 1.x asked, and reads `skills` paths from the working directory. Every
> file this repo ships for OpenCode is now written to the V2 shape and is not checked
> against 1.x at all.
>
> Upgrade an existing 1.x install, or install V2 fresh:
>
> ```bash
> opencode upgrade --major                 # from any 1.19.x
> npm install -g @opencode/cli             # or: bun install -g --trust @opencode/cli
> brew install anomalyco/tap/opencode-v2
> curl -fsSL https://opencode.ai/v2/install | bash
> ```
>
> `opencode-ai` on npm is still the **1.x** package, and `opencode.ai/install` still pulls 1.x.

**Platform:** OpenCode. **Surface:** OpenCode CLI, the terminal client — registry id
`opencode`. Every measurement below was taken there. OpenCode also ships a desktop/web
client on the same background service; that surface is **unverified** and has no install
guide. See [platform differences](../platform-differences.md#unverified-surfaces).

| | |
|---|---|
| **Validated against** | `@opencode/cli` **2.0.32**, live, without a provider key (see [Verify](#verify)): config loads, all 10 agent adapters resolve with their rules, the guard plugin loads, the `github` MCP server is declared and attempted |
| **Minimum supported** | **2.0.30** — the first release whose published schema accepts the V2 shapes this repo writes (`permissions`, `plugins`, `mcp.servers`); only 2.0.32 was run |
| **Manifest** | none — OpenCode has no plugin-manifest bundle; `opencode.json` is the project config |
| **Config** | `opencode.json` (`skills`, `plugins`, `mcp.servers`, `permissions`) + `.opencode/agents/` + `.opencode/commands/` + `platforms/opencode/plugin/` |
| **Official docs** | [Skills](https://opencode.ai/v2/docs/skills/) · [Config](https://opencode.ai/v2/docs/config/) · [Agents](https://opencode.ai/v2/docs/agents/) · [Permissions](https://opencode.ai/v2/docs/permissions/) · [Plugins](https://opencode.ai/v2/docs/plugins/) · [Building plugins](https://opencode.ai/v2/docs/build/plugins) · [CLI plugins](https://opencode.ai/v2/docs/build/plugins/cli) · [MCP servers](https://opencode.ai/v2/docs/mcp-servers) · [JSON Schema](https://opencode.ai/config.json) |

Check your version:

```bash
opencode --version      # opencode v2.0.32
```

## Where everything lives

| What | Where | How it reaches OpenCode |
|---|---|---|
| The 30 skills | `skills/<domain>/<name>/SKILL.md`, canonical, read in place | `opencode.json` `skills` array (11 entries: six domains plus the four `repo` skills listed one by one) |
| 10 specialist agents | `.opencode/agents/*.md`, **generated** from `agents/*.md` | OpenCode 2's own agent directory (plural; the 1.x `agent/` singular dir is gone) |
| 27 slash commands | `.opencode/commands/*.md`, **generated** from the user-invocable skills | OpenCode 2's command directory |
| The three core guards | `platforms/opencode/plugin/index.ts` → `guard.ts` (server plugin) | `opencode.json` `plugins: ["./platforms/opencode/plugin"]` |
| Status line + objective pane | `platforms/opencode/plugin/tui.ts` → `tui.tsx` (TUI plugin) | same directory; the terminal client loads `tui` from every configured plugin |
| GitHub MCP server | `scripts/github-mcp.sh` | `opencode.json` `mcp.servers.github`, token from `GITHUB_PERSONAL_ACCESS_TOKEN` |
| Static permission rules | `opencode.json` `permissions` | the invariants that can be written as patterns (lockfiles, workflows, force push, `external_directory: ask`) |
| Usage capture (optional) | `skills/toolkit/usage-capture/opencode-plugin.mjs` | **not** in this repo's config — add it to *your* `plugins` list |

## Method A — global install (all projects)

Clone once, then point your **global** OpenCode config at the clone with absolute
paths (`~` is not expanded inside JSON, but `{env:HOME}` is — see
[Config](https://opencode.ai/v2/docs/config/)):

```bash
git clone https://github.com/Tamircohen28/tamirs-superpowers.git ~/src/tamirs-superpowers
mkdir -p ~/.config/opencode
```

`~/.config/opencode/opencode.json`:

```json
{
  "$schema": "https://opencode.ai/config.json",
  "skills": [
    "/Users/you/src/tamirs-superpowers/skills/creative",
    "/Users/you/src/tamirs-superpowers/skills/debugging",
    "/Users/you/src/tamirs-superpowers/skills/dev-workflow",
    "/Users/you/src/tamirs-superpowers/skills/documentation",
    "/Users/you/src/tamirs-superpowers/skills/mcp",
    "/Users/you/src/tamirs-superpowers/skills/toolkit",
    "/Users/you/src/tamirs-superpowers/skills/repo/cleanup",
    "/Users/you/src/tamirs-superpowers/skills/repo/github-policy",
    "/Users/you/src/tamirs-superpowers/skills/repo/multi-agent-repo",
    "/Users/you/src/tamirs-superpowers/skills/repo/repo-scaffold",
    "/Users/you/src/tamirs-superpowers/skills/repo/repo-standards"
  ],
  "plugins": ["/Users/you/src/tamirs-superpowers/platforms/opencode/plugin"],
  "permissions": [
    { "action": "external_directory", "resource": "*", "effect": "ask" }
  ]
}
```

Then copy the agents (OpenCode reads the global agents directory with no config key)
and, if you want `/plan-dev` and friends everywhere, the commands:

```bash
mkdir -p ~/.config/opencode/agents ~/.config/opencode/commands
cp ~/src/tamirs-superpowers/.opencode/agents/*.md   ~/.config/opencode/agents/
cp ~/src/tamirs-superpowers/.opencode/commands/*.md ~/.config/opencode/commands/
```

Update with `git pull` — the skill and plugin paths keep resolving; re-copy the agents
and commands only when `agents/` or a skill description changed.

**Why the `repo` domain is listed skill-by-skill:** `skills/repo/_contract/fixtures/`
holds complete gold-fixture skill trees used by the repo's own contract tests. Discovery
recurses, so a single entry for `skills/repo` would expose those fixtures (`demo`,
`example-skill`) as real user-facing skills.

## Method B — this checkout, or a project next to it

This repo's own `opencode.json` is the complete V2 config: skills, plugins, the MCP
server and the static rules. Start OpenCode **at the repo root** and everything loads:

```bash
cd ~/src/tamirs-superpowers && opencode
```

**The skills entries resolve from the working directory, not the config file.** That is
documented V2 behaviour ("Relative path: from the active OpenCode working directory, not
the config file"), and it is the one place this config is fragile: start OpenCode in a
subdirectory and the eleven relative entries resolve nothing. Two ways around it:

- start at the root (what the repo's own tests and the Verify section below do), or
- use Method A's absolute paths in your global config, which resolve from anywhere.

`plugins` entries are different — they resolve "from the config file containing the
entry" — so the plugin keeps loading from a subdirectory even when the skills do not.

V2 also discovers `.agents/skills/` and `.claude/skills/` natively, "from the current
directory up to the project root", with no config entry at all. This repo may ship an
`.agents/skills/` mirror for other hosts; whether OpenCode 2 follows **symlinks** there is
unverified (1.18.11 did not follow them at any level, and that was never re-measured on
V2), so do not rely on it for OpenCode until it is.

For a project *next to* the clone, a per-project `opencode.json` with
`"skills": ["../tamirs-superpowers/skills/toolkit"]` works only when OpenCode is started
in that project's root, for the same reason.

## Skills

Skills are read in place; nothing is copied or converted. OpenCode 2 honours `name`,
`description`, `metadata.opencode/autoinvoke` and `disable-model-invocation` from the
frontmatter; `license`/`compatibility` are "accepted but not interpreted", and every
Claude-only field (`effort`, `user-invocable`, `context`, `agent`, `allowed-tools`) is
ignored. Skill auto-invocation is still **unknown** on OpenCode; the reliable ways to reach
a skill are the generated `/name` commands below, `@skill-id` in a prompt, or naming it.

`OPENCODE_DISABLE_CLAUDE_CODE` / `OPENCODE_DISABLE_CLAUDE_CODE_SKILLS` (2.0.30) switch off
`.claude/skills` discovery; they do not affect the `skills` array.

## Agents

Canonical `agents/*.md` do **not** load on OpenCode as-is: the canonical `tools:` comma
string is not a V2 field at all, `model: sonnet` is an alias, `name:` is not an agent
property (the id comes from the filename), and a V2 custom agent that omits `mode`
becomes a **primary** agent the user can select. So this repo ships pre-translated
adapters in **`.opencode/agents/`** (plural — V2's directory; the 1.x `agent/` singular is
removed by the generator because V2 reads both and would load every agent twice):

```yaml
---
description: <canonical description>
mode: subagent
model: anthropic/claude-sonnet-5
permissions:
  - action: subagent
    resource: "*"
    effect: deny
  # …one deny per OpenCode 2 action the canonical tools: allowlist does not grant
  - action: external_directory
    resource: "*"
    effect: ask
---
```

**Permissions are translated, not copied — and only as denies.** The canonical `tools:`
field is an allowlist, and OpenCode 2 starts every agent from a base policy of
`{ action: "*", resource: "*", effect: allow }`, so an adapter that named only its granted
tools would leave everything else enabled — a read-only reviewer would gain `shell`,
`edit` and `subagent`. The generator therefore emits a `deny` rule for every Core action
(`read edit glob grep shell subagent skill question webfetch websearch`) the canonical file
does not grant. It emits **no `allow` rules**: measured on 2.0.32, an agent's rules are
appended after the base policy and "the last matching rule wins", so a `read * allow`
would land after the host's own `read *.env → ask` and silently disable it, and a
`shell * allow` would override a `shell * ask` from your global config. A granted action
needs no rule — it is already allowed — so the allowlist is expressed purely as denies,
which can only narrow.

`external_directory: ask` is emitted for every agent because V2 **allows** access outside
the project by default where 1.x asked; this repo's worktree invariant needs that prompt.

`bash`, `task`, `doom_loop`, `lsp`, `list`, `todowrite` — the 1.x keys — never appear;
`scripts/check-opencode-permission-keys.sh` fails if they do, and `tests/test-opencode-v2.sh`
checks the generated files themselves.

```bash
make opencode-agents          # write .opencode/agents/ (and remove a stale .opencode/agent/)
make opencode-agents-check    # fail if it has drifted, or the stale dir exists
```

**Never hand-edit `.opencode/agents/*.md`.** Every file carries a generated-file header
naming its source. Note that 2.0.32 **ignores** an unknown frontmatter key rather than
rejecting the file (measured with a bogus key), so a hand edit that drifts is silent on
the host and caught only by the check.

### Commands — every user-invocable skill as `/name`

`.opencode/commands/` holds **26 generated commands**, one per user-invocable skill,
listed in the TUI and invoked as `/plan-dev`, `/pr-dev`, `/retro` and so on. Arguments
pass through as `$ARGUMENTS`:

```text
/plan-dev implement the auth spec in docs/specs/auth.md
```

Each command is a thin launcher that names its skill and points at the canonical
`SKILL.md`; nothing from the skill is duplicated. Two V2 facts shape the frontmatter:

- `subagent: false` is written explicitly. V2 renamed `subtask` to `subagent` and made
  the *omitted* value depend on the selected agent's mode ("use a child only when the
  selected agent has `mode: subagent`"). These launchers must load the skill in **your**
  session, not hand it to a background child, so they say so.
- V2 no longer expands `@path` in stored templates. The command bodies never used it —
  the `SKILL.md` path is an instruction to the model to read the file, not an attachment.

The three **internal** skills (`changelog-review`, `docs-review`, `mcp-pagination`,
`user-invocable: false`) deliberately get no command.

```bash
make opencode-commands          # write .opencode/commands/
make opencode-commands-check    # fail if it has drifted
```

## The plugin — guards, status line, objective pane

OpenCode executes no shell hook; its only lifecycle mechanism is the V2 plugin API. So
the parts of this toolkit that are hooks on Claude Code are one plugin directory here,
`platforms/opencode/plugin/`, registered in `opencode.json` as
`"plugins": ["./platforms/opencode/plugin"]`. OpenCode resolves two entrypoints from it:

**`index.ts` → `guard.ts` (server plugin)** mirrors `hooks/enforce-worktree-edits.sh`,
`hooks/guard-sensitive-files.sh` and `hooks/protect-other-branches.sh`:

| Hook | Enforces |
|---|---|
| `ctx.permission.hook("evaluate")` on `edit` | denies an edit to the **main checkout while an objective is active** (same detection as the shell hook: `SUPERPOWERS_OBJECTIVE_ID`, or an `objective.json` with `status: active` under `.dev-files/objectives/`; a linked worktree's `.git` file is followed back to the main checkout), pointing at the orchestrator's `.agent-worktrees/<objective>/task-NNN` or `integration` worktree. Denies a write to a **protected path**: lockfiles, `.github/workflows/`, `.yarn/releases/`, shadcn `components/ui/` (only when `components.json` exists), gitignored build output. |
| the same hook on `shell` | refuses a **force push** (`--force`, `-f`, `--force-with-lease`, `+refspec`) and a push to a **branch another agent holds** a live claim on (`~/.agent-work-claims/`, the same files `hooks/lib/agent-claim.sh` writes, so a Claude Code session and an OpenCode session see each other); takes the claim after an allowed push. Applies the protected-path rules to `>`/`>>`, `tee`, `sed -i`, `cp`/`mv` targets. |
| `ctx.shell.hook("create.before")` | the backstop: the same decisions, thrown as an error, for a shell created outside the permission flow (a `` !`cmd` `` command template, for instance). |

The no-objective half of the worktree hook is deliberately **not** mirrored: on Claude
Code it names (and recreates) the session's own worktree as the remedy, which needs a
task slug captured by a prompt hook OpenCode does not have; a deny with nowhere to send
the work is the degraded path the shell hook itself refuses to create. Overrides are the
hook scripts' own: `PM_ALLOW_PROTECTED=1` for an intended edit to a protected path,
`TAMIRS_OPENCODE_GUARD=0` to switch the guard off.

**`tui.ts` → `tui.tsx` (TUI plugin)** is OpenCode's analogue of the Claude Code mod and
statusline. It appends to `prompt.footer.status` — after OpenCode's own health
indicators — the context fill of the last model step (prompt tokens against the model's
context limit), the session's cost, and the active objective's progress
(`obj <id> 2/5 · 1 worker running`); and it contributes a `session.panel` with the
objective's task rows, opened with **`/objective`** or from the command palette. It reads
`.dev-files/objectives/<id>/` from the **local** checkout — against a remote server it
shows the local clone's objective. **Rate-limit windows are not shown**: OpenCode
documents no rate-limit payload anywhere a TUI plugin can read (not on the session, not in
any `session.*` event, checked against `@opencode/client` 2.0.32), so the `switch-dev`
handoff band the Claude mod raises from them has no OpenCode source yet; the plugin
shows what the host exposes and says so in its header rather than inventing a figure.

The plugin needs **no install step**: OpenCode resolves `@opencode/plugin` itself at
runtime. `platforms/opencode/plugin/package.json` exists for the type-check only
(`npm install && npm run check` runs `tsc --noEmit` against `@opencode/plugin` 2.0.32;
`tests/test-opencode-v2.sh` does it in a temp dir when the network allows). The decision
functions are pure (`rules.ts`) and unit-tested with plain Node, no install.

**What is verified and what is not.** On 2.0.32, `opencode plugin list` shows
`tamirs-superpowers.guard` loaded from `platforms/opencode/plugin/index.ts` — the server
imported the module, resolved `@opencode/plugin`, and ran `Plugin.define`. Whether a
`deny` set in `permission.hook("evaluate")` stops the edit with the message shown, and
whether a throw in `shell.hook("create.before")` stops the shell, is the documented
contract but has **not** been exercised in a session with a provider key. The capability
registry records `hooks` as `adapter` on that basis, with that caveat.

### Usage capture (optional, not in this repo's config)

`skills/toolkit/usage-capture/opencode-plugin.mjs` is now a V2 plugin (`{ id, setup }`,
`ctx.event.subscribe()`, observe-only, zero imports). It records `session.created`,
`session.skill.activated`, `session.step.ended` / `session.step.failed` and
`session.usage.recorded` as the same JSONL the collector writes for Claude Code. Add its
absolute path to *your* `plugins` list; it is deliberately not in this repo's
`opencode.json`. Request bodies cannot be captured on V2 (that was a 1.x transform hook).

## MCP servers

OpenCode does not read `.mcp.json`; servers live under `mcp.servers.<name>` in
`opencode.json`. This repo declares the GitHub server it ships for Claude Code:

```json
"mcp": {
  "servers": {
    "github": {
      "type": "local",
      "command": ["bash", "scripts/github-mcp.sh"],
      "environment": { "GITHUB_PERSONAL_ACCESS_TOKEN": "{env:GITHUB_PERSONAL_ACCESS_TOKEN}" }
    }
  }
}
```

`{env:NAME}` is OpenCode's documented substitution — the token is read from your
environment at load time and never written to a file. Export it before starting OpenCode:

```bash
export GITHUB_PERSONAL_ACCESS_TOKEN=github_pat_…
```

Without it the script exits with a JSON-RPC error and `opencode mcp list` shows
`✗ github failed: … github_token is not set` (measured on 2.0.32; the message names the
Claude Code configure command because the script is shared, the fix here is the export).
To switch the server off in your own config instead: `"mcp": { "servers": { "github": {
"disabled": true } } }`. The `command` path is relative; it resolves when OpenCode runs
from this checkout (Method B) — for Method A point `command` at the clone's absolute
`scripts/github-mcp.sh`.

## Static permission rules

`opencode.json` also carries the invariants that can be written as patterns, so they hold
even if the plugin is disabled: `edit` denies on lockfiles, `.github/workflows/*` and
`.yarn/releases/*`; `shell` denies on the common force-push spellings; and
`external_directory: ask`. These are configured denies, which "do not invoke the hook"
and cannot be bypassed with `PM_ALLOW_PROTECTED` — edit the config for an intended change.
`policies` (the admin-only, deny-only layer) is deliberately not set by a plugin.

## Verify

Everything below was run on `@opencode/cli` 2.0.32 (`npm install -g @opencode/cli`),
with a fresh `HOME`, **without a provider key and without logging in**, from this repo's
root. These are the commands and what they printed.

```bash
opencode --version
# opencode v2.0.32

opencode debug config      # configuration SOURCES, not a resolved config
# [ { "type": "directory", "path": "~/.config/opencode" },
#   { "type": "document",  "path": "<clone>/opencode.json", "info": { "$schema", "mcp", "permissions", "plugins", "skills" } },
#   { "type": "directory", "path": "<clone>/.opencode" } ]

opencode debug agents      # every resolved agent, JSON
# built-ins (build, plan, general, explore, …) plus the ten adapters, each with
# "mode": "subagent", the base policy, then this repo's deny rules and
# { "action": "external_directory", "resource": "*", "effect": "ask" } last

opencode plugin list
# ID                        VERSION  SOURCE
# tamirs-superpowers.guard  local    <clone>/platforms/opencode/plugin/index.ts

opencode mcp list
# ✗ github  failed: Connection closed: MCP server process exited with code 1: {"jsonrpc":"2.0","error":{"code":-32000,"message":"github_token is not set. …"}}
```

Three things the V2 CLI **cannot** show, recorded so nobody looks for them:

- **Skill discovery cannot be enumerated.** `debug skill` was removed in V2 and
  `debug agent <name>` became `debug agents`. The API has a `skill.list` operation, but
  `opencode api --standalone skill.list` returned `"data": []` on 2.0.32 even while
  `debug agents` listed every adapter (so did `agent.list`); the standalone route does not
  appear to load the location's catalog before answering. Per-skill discovery therefore
  stays **unverified** on V2, as `platform-targets.json` records.
- **`debug agents` returned `[]` on its first invocation in a fresh `HOME`** and the full
  list on the next; the background service was still starting. Run it twice.
- The TUI plugin is loaded by the terminal client, not the server, so it does not appear
  in `opencode plugin list`; `/objective` in a running TUI is the check.

From a clone of this repo, the full V2 contract runs as:

```bash
bash tests/test-opencode-v2.sh          # V2 shapes, plugin unit tests + type-check, config, usage-capture
bash tests/test-opencode-adapter.sh     # platform contract shared with tests/contract/run.sh
```

## Update

```bash
cd ~/src/tamirs-superpowers && git pull
cp .opencode/agents/*.md   ~/.config/opencode/agents/     # only if you copied agents
cp .opencode/commands/*.md ~/.config/opencode/commands/   # only if you copied commands
```

V2 reloads watched config directories automatically ("Changes under watched config
directories reload automatically"); after editing a plugin, `opencode service restart` or
restart OpenCode.

## Uninstall

```bash
# 1. remove the skills / plugins entries you added
$EDITOR ~/.config/opencode/opencode.json     # or the project's opencode.json

# 2. remove copied agent adapters and commands
rm -f ~/.config/opencode/agents/{architecture-reviewer,debugging-specialist,implementer,\
integrator,orchestrator,performance-reviewer,research-agent,security-reviewer,\
spec-reviewer,test-engineer}.md
rm -f ~/.config/opencode/commands/*.md        # if you copied them and have no others

# 3. remove the clone
rm -rf ~/src/tamirs-superpowers
```

Then restart OpenCode and confirm with `opencode debug agents` and `opencode plugin list`.

## Machine-level setup

The skills, plugin and MCP server come from `opencode.json`. Global rules in
`~/.config/opencode` are a separate, optional step:

```bash
bash scripts/setup.sh plan  --targets opencode  # writes nothing
bash scripts/setup.sh apply --targets opencode
bash scripts/setup.sh remove --targets opencode
```

| Module | Writes | What it does |
|---|---|---|
| `agents-md` | `~/.config/opencode/AGENTS.md` | Renders `core/global-rules.md` inside `>>> tamirs-superpowers >>>` markers |
| `config` | `~/.config/opencode/opencode.json` | Asserts `$schema` and nothing else |

OpenCode 2 "recognizes `AGENTS.md` only. It does not use `CLAUDE.md` as a fallback" — so
the global `AGENTS.md` is the right file, and it needs no config key. `plugins`, `mcp`
and `permissions` in your global config are untouched by setup. `plan` writes nothing and
is the default when there is no terminal; `apply` shows a diff and asks per change,
defaulting to **No**. Full reference: [setup](../setup.md) · [platform setup](../platform-setup.md).

## Capability support

Status vocabulary matches [`core/capabilities/platforms.json`](../../../core/capabilities/platforms.json),
which is the authoritative registry; `platforms/opencode/adapter.yaml` is the thin pointer.

| Capability | Status | Detail |
|---|---|---|
| Skills | ✅ native | Canonical `skills/` read in place via the `skills` array. Paths resolve from the working directory. |
| Skill auto-invocation | ❓ unknown | Discovery is configured; automatic selection is not measured. Use `/<skill-name>`, `@skill-id`, or name the skill. |
| Custom commands | ⚙️ adapter | Generated `.opencode/commands/` — 27 user-invocable skills as `/name`, `subagent: false`; drift enforced by `make opencode-commands-check`. |
| Subagents | ⚙️ adapter | Generated `.opencode/agents/` with V2 `permissions` rulesets; all ten resolve on 2.0.32 (`debug agents`); drift enforced by `make opencode-agents-check`. |
| Parallel subagents | ❓ unknown | V2's `subagent` tool takes `background: true` ("returns immediately and notifies the parent when the child finishes") and `experimental.subagent_depth` defaults to 1, so an orchestrator must be the primary agent and fan-out is one background child per worker; whether several foreground calls in one turn run concurrently is undocumented and was not run live. Assume sequential. |
| MCP | ✅ native | `mcp.servers.github` declared in `opencode.json`; token via `GITHUB_PERSONAL_ACCESS_TOKEN`. |
| Hooks | ⚙️ adapter | No shell hooks. The three core guards are the V2 server plugin in `platforms/opencode/plugin/`; it loads on 2.0.32, its denies are unverified live. |
| Statusline | ⚙️ adapter | The TUI plugin's `prompt.footer.status` line (context fill, cost, objective) and `session.panel` objective pane; no rate-limit figures, none exist on OpenCode. |
| Marketplace install | ❌ unsupported | No plugin marketplace. Install is by path. |
| `.mcp.json` auto-wiring | ❌ unsupported | Declared by hand in `opencode.json` instead. |
| Symlinked skill trees | ❓ unknown on V2 | Not followed at any level on 1.18.11; not re-measured on V2. Use real paths. |
| Worktree isolation | ⚙️ emulated | The skill drives `git worktree` through the shell; the guard plugin enforces the invariant under an objective. |
| Session transcripts | ❓ unknown | `session-report` targets the Claude JSONL format only and should refuse rather than guess. |

## Troubleshooting

| Symptom | Fix |
|---------|-----|
| No skills loaded | Relative `skills` entries resolve from the **working directory**. Start OpenCode at the repo root, or use absolute paths in `~/.config/opencode/opencode.json`. |
| `debug agents` prints `[]` | First call after a fresh start; run it again. |
| An adapter is missing from `debug agents` | Regenerate: `make opencode-agents`. A stale `.opencode/agent/` (singular) would load a second copy — the generator removes it. |
| An agent can edit files it should not | The adapter lost its denies. `make opencode-agents`, then `opencode debug agents` and check the `permissions` array ends with this repo's deny rules. |
| `opencode mcp list` shows `✗ github … github_token is not set` | `export GITHUB_PERSONAL_ACCESS_TOKEN=…` before starting OpenCode, or set `"disabled": true` on the server in your own config. |
| The guard denies an edit you meant to make | A protected path: `PM_ALLOW_PROTECTED=1`. A main-checkout edit under an objective: work in the objective's worktree the message names. A configured deny in `opencode.json`: edit the rule. |
| `/objective` says no objective is active | Nothing under `.dev-files/objectives/` in the **local** main checkout has `status: active`; `/plan-dev` writes one. |
| Fixture skills `demo` / `example-skill` appear | A `skills` entry points at `skills/repo`; list the four real repo skills individually. |
