# Install — Cursor

Registry id: `cursor`. Validated against Cursor desktop **3.22.7** (feature changelog
**3.11**, covered through date-only **2026-09-23**); that floor is the version this repo
actually tested, not a guess. Desktop **3.27.12** (hook `tool_use_id` / `parent_tool_call_id`
correlation, auto-review risky-delete approval) was reviewed from the IDE release notes;
no live run has validated it yet.

---

## Install

Cursor imports a plugin marketplace straight from a repo:

1. Open the Cursor **Dashboard** → **Plugins**.
2. **Team Marketplaces** → **Add Marketplace** → **Import from Repo**.
3. Point it at `Tamircohen28/tamirs-superpowers` (or `Tamircohen28/tamirs-marketplace`).
4. Install **tamirs-superpowers** from the imported listing.

Cursor reads [`.cursor-plugin/plugin.json`](../../../.cursor-plugin/plugin.json), the
canonical `skills/` tree, [`.cursor/rules/`](../../../.cursor/rules) — declared explicitly,
see below — `agents/`, and the github MCP server from
[`platforms/cursor/mcp.json`](../../../platforms/cursor/mcp.json), a Cursor-specific file
generated with the manifest from one source
([manifests](../../engineering/build-and-release/manifests.md)). Enable **Auto Refresh**
on the marketplace and pushes propagate without a version bump.

## Set the `GITHUB_TOKEN` plugin variable

The bundled github MCP server needs a GitHub personal access token, and in a Cursor plugin
a token is a **plugin variable**: the MCP file says `${GITHUB_TOKEN}`, the manifest
declares `GITHUB_TOKEN` under `variables`, and the value is set by you — never in the repo.

1. Dashboard → **Plugins** → **tamirs-superpowers** → **Configure**.
2. Set **GitHub token for the bundled github MCP server** to a token with `repo` scope.

Cursor hands it to the server as `GITHUB_PERSONAL_ACCESS_TOKEN`; nothing else in the
plugin reads it. Leave it unset to keep the server off — it refuses to start without one,
and no skill depends on it.

Why a separate MCP file: Cursor treats every `${VAR}` in a plugin's MCP config as a
plugin variable that must be declared under `variables`, and the Claude file's
`${user_config.github_token}` is not a declarable name. The generator refuses to write a
Cursor MCP file that uses a variable the manifest does not declare, and
`tests/test-manifests.sh` plants one to prove it.

## The Claude-format hooks file does not come with the install

Worth knowing before you go looking for `hooks/hooks.json` in Cursor's hook list: **a Cursor
install never loads that file.** The hooks that do run come from a separate, Cursor-format
bundle — the next section.

Cursor *can* import Claude Code hooks, and the setting is on by default
(Settings → Agents → Third-Party Imports → "Include Third-Party Plugins, Skills, and Other
Configs"). But it reads them from exactly three paths:

- `.claude/settings.local.json`
- `.claude/settings.json`
- `~/.claude/settings.json`

This plugin ships its Claude hooks in `hooks/hooks.json`, wired through the Claude plugin
manifest — which is not one of those three. The file is present on disk after an install
(see the section below), but nothing on Cursor loads it; the Cursor manifest points at
`platforms/cursor/hooks.json` instead.

**One exception, and it is not part of the install.** This repo ships
[`.cursor/hooks.json`](../../../.cursor/hooks.json) with a single advisory
`beforeShellExecution` hook for people working *on this repo* in Cursor. Cursor reads
`.cursor/hooks.json` from the **project root**, so that file applies when this repo is your
open project — it is not delivered to your project by installing the plugin, and
`.cursor-plugin/plugin.json` declares no `hooks` field. It is a useful proof that the
Cursor-native format works here, not a counterexample to the paragraph above.

Of the events `hooks/hooks.json` wires, Cursor's published import mapping covers
`PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `Stop`, `SubagentStop`, `SessionStart`,
`SessionEnd` and `PreCompact`. `StopFailure`, `Notification`, `DirectoryAdded`,
`WorktreeCreate`, `WorktreeRemove` and the agent-teams pair `TaskCompleted` and
`TeammateIdle` have no Cursor equivalent, so even a hand-copied
translation would be lossy — which is why the plugin ships a Cursor-native bundle instead
of relying on the import.

## What an install actually materializes

Worth knowing, because it is the difference between 29 working skills and 29 that silently
no-op: **a Cursor install is a full git clone of the repo, not a Markdown-only sync.** Cursor
materializes it twice, under `~/.cursor/plugins/cache/` and `~/.cursor/plugins/marketplaces/`,
and both copies carry every tracked file.

Measured against a real install on macOS (Cursor 3.21.16, install copy at plugin 2.0.1):

| | |
|---|---|
| Tracked paths vs. the source commit | **identical** — zero files dropped |
| Non-Markdown files | 263 of 452 |
| Shell scripts | 103 `.sh`, **87 executable** |
| Executable-bit mismatches vs. source | **0**, across all 451 files |
| `hooks/hooks.json` + hook scripts | present, all 25 |
| Python helpers / JSON config | 14 `.py`, 53 `.json` |

`git status` inside the installed copy reports no modified or deleted tracked files — only an
untracked `.cache-complete` marker that Cursor writes itself.

This matters because the repo's contract tests run against a local checkout and never an
installed copy, so nothing in CI would catch an install path that dropped shell assets. It
does not drop them; the mechanism is a clone, so there is no file-type filter to get wrong.

**Still unverified:** skill *invocation* inside Cursor — palette listing and invoking a skill
by name. Asset delivery being sound does not establish that, and the capability registry
reflects the narrower claim.
## The safety hooks, the session lifecycle and the prompt hooks run on Cursor

`.cursor-plugin/plugin.json` declares `hooks` at `./platforms/cursor/hooks.json`, a
Cursor-format bundle wiring ten of Cursor's 21 events: the two safety invariants on
`preToolUse` and `beforeShellExecution`, the agent `tools:` guard on `preToolUse`/`postToolUse`,
the session lifecycle on `sessionStart`/`sessionEnd`, the `/goal` lint and the two prompt
reminders on `beforeSubmitPrompt`, the definition-of-done reminder on `stop`, the
pre-compaction snapshot on `preCompact`, and a `workspaceOpen` hook that can auto-load a
checkout of the plugin. The engineering note behind every entry is
[`platforms/cursor/README.md`](../../../platforms/cursor/README.md).

**The safety tier fails closed.** `enforce-worktree-edits.sh`, `guard-sensitive-files.sh`
(both events), `protect-other-branches.sh` and the agent-tools guard carry `failClosed: true`
— Cursor's `onFailure: "block"` — so a guard that crashes or times out **denies** rather than
allows, and `loop_limit: null` so Cursor's default cap of five firings per loop never turns a
guard off. Every advisory entry stays fail-open: a broken reminder costs a reminder, not a
tool call.

**It points somewhere non-default deliberately.** Cursor's component discovery falls back to
`hooks/hooks.json`, which in this repo is the **Claude-format** file — PascalCase events Cursor
cannot read. An undeclared component does not disable itself; it binds to that default and
yields nothing.

**It runs the same scripts as Claude and Codex, not forked copies.** The dialect lives in
three shared pieces:

- `hooks/lib/hook-output.sh` detects Cursor from the payload (`conversation_id`,
  `cursor_version`, `workspace_roots`) and emits `{permission, user_message, agent_message}`
  instead of `hookSpecificOutput` on the tool events
- `hooks/lib/cursor-output.sh` speaks the other shapes: `{continue, user_message}` on
  `beforeSubmitPrompt`, `{additional_context}` on `sessionStart`, `{pluginPaths}` on
  `workspaceOpen`, nothing on `sessionEnd` — and never `followup_message`, which Cursor would
  auto-submit as your next message
- `hooks/lib/write-targets.py` already treats Cursor's `Shell` like `Bash`
- Cursor's `preToolUse` carries `tool_name` `Read`/`Write`/`Shell` with `tool_input.file_path`
  and `tool_input.command` — the same names and fields Claude uses for `Read`/`Write`

Verified end to end on `cursor-agent` 2026.07.17-3e2a980:

```
> Overwrite .github/workflows/ci.yml so it contains only the text BROKEN.

  The write was blocked: local edits to GitHub Actions workflow files are not
  allowed in this environment.

  ci.yml content: name: ci        ← unchanged
```

and the control, so the guard is selective rather than blanket:

```
> Create ordinary.txt with the word fine.
  ordinary.txt → written
```

**These hooks constrain *writes by path*.** They do not, by themselves, make an agent's declared
`tools:` list enforceable — that is a separate guarantee, supplied by a separate guard described
in the next section.

## Cursor does not enforce an agent's `tools:` list — this plugin adds a guard that does

Worth knowing before you rely on a reviewer agent being read-only: **Cursor does not enforce
the `tools:` allowlist in agent frontmatter.**

Measured on `cursor-agent` 2026.07.17-3e2a980. A probe agent declaring:

```yaml
tools: Read, Grep, Glob        # no Write
```

was asked to create a file, and created it.

So the seven agents here that are read-only by declaration — `architecture-reviewer`,
`security-reviewer`, `spec-reviewer`, `performance-reviewer`, `research-agent`,
`debugging-specialist`, `orchestrator` — were constrained on Cursor only by the prose in their
own system prompt, which is a model instruction rather than a guarantee.

A first probe looked reassuring and proved nothing: `architecture-reviewer` refused, explaining
it was review-only. That refusal came from its own instructions. Only an agent whose prose
actively *demanded* writing separated "the model declined" from "the platform prevented."

**What this plugin does about it.** On Claude Code the `tools:` list is enforced by the host; on
OpenCode `scripts/build-opencode-agents.sh` translates it into explicit `permission:` entries.
Cursor has neither, so `hooks/cursor-agent-tools-guard.sh` supplies it, wired to `preToolUse` and
`postToolUse` from `platforms/cursor/hooks.json`.

It cannot simply ask which agent is running. A subagent's tool calls carry no agent field, and its
`conversation_id`, `generation_id` and `session_id` are **identical to the parent's**. What does
carry the name is the `Task` call that starts it (`tool_input.subagent_type`).

**Desktop ≥ 3.22 / 3.24 (adopted):** Cursor now sends `tool_use_id` on the Task `preToolUse` and
`parent_tool_call_id` on the subagent's own tool calls (the Task id). The guard keys frames on
that id, so two concurrent subagents are attributed correctly — a Write allowed for `implementer`
is no longer denied just because a read-only sibling is also running. Shell/MCP hooks also receive
the same `tool_use_id` (3.24), and every hook gets `transcript_path` / `CURSOR_TRANSCRIPT_PATH`.

**Fallback (older payloads):** when those ids are absent, the guard still reconstructs from event
**order** — push on `Task`, check against active frames, pop on `postToolUse` — and under
concurrency applies the **intersection** of allowlists (safer than guessing).

**It is advisory, not a sandbox.** A missed `postToolUse` fails safe (over-restrictive rather than
unguarded). Treat these agents as **role prompts with a raised floor** — meaningfully better than
prose alone, and still not an isolation boundary.

Tracked as [#179](https://github.com/Tamircohen28/tamirs-superpowers/issues/179); guard shipped in
[#223](https://github.com/Tamircohen28/tamirs-superpowers/pull/223).

## Which of Cursor's 21 hook events this plugin wires

Cursor exposes 21 hook events; **7 of them can deny an action**, the rest are observational.
This plugin wires 10, and the other 11 are accounted for rather than merely absent — an event
is wired because a script needs it, not to fill in the table. The **Cloud** column says whether
the event fires at all inside a [cloud agent](#what-runs-where-cloud-agents).

| Event | Can deny | Cloud | Wired | What / why not |
|---|:---:|:---:|:---:|---|
| `preToolUse` | ✅ | ✅ | ✅ **fail-closed** | `enforce-worktree-edits.sh`, `guard-sensitive-files.sh`, `protect-other-branches.sh`, `cursor-agent-tools-guard.sh` (all `failClosed: true`); `skill-creator-guard.sh` (contributor tier, fail-open) |
| `beforeShellExecution` | ✅ | ✅ | ✅ **fail-closed** | `guard-sensitive-files.sh` — a shell command is a write path too |
| `postToolUse` | — | ✅ | ✅ | pops the agent-allowlist frame; fail-open on purpose (a missed pop is over-restrictive, never unguarded) |
| `beforeSubmitPrompt` | ✅ | ✅ | ✅ | `goal-condition-lint.sh` refuses an unsatisfiable `/goal` with `continue:false` and the rewrite menu as `user_message`; `scope-decompose-reminder.sh` and `skill-suggest.sh` pass with `continue:true` and a note. This event has no model-visible channel, so the notes are addressed to **you** |
| `sessionStart` | — | ❌ | ✅ | `session-init.sh` → `additional_context` (session dirs, prior session files on resume, stale-worktree prune); session state keyed by `session_id`/`conversation_id` the way the guards key it |
| `sessionEnd` | — | ❌ | ✅ | `session-end.sh` (archive, prune), `release-agent-claims.sh`, `handoff-reminder.sh` (reminder on stderr from a `~/.cursor/worktrees/…` checkout). Cursor documents no output for this event; none is printed |
| `stop` | — | ✅ | ✅ | `check-done.sh`, the definition-of-done reminder — on stderr (stdout is the no-op `{}`), never as `followup_message` |
| `preCompact` | — | ✅ | ✅ | `precompact-snapshot.sh` writes `.dev-files/compaction/latest.md` before context is lost |
| `workspaceOpen` | — | ❌ | ✅ | `cursor-workspace-open.sh` → `{"pluginPaths": […]}` from `SUPERPOWERS_CURSOR_PLUGIN_PATH` (colon-separated absolute plugin checkouts); `[]` otherwise. The route to auto-load a checkout of this plugin without a marketplace install |
| `subagentStop` | — | ✅ | ❌ | Its peer `subagent-handoff-check.sh` still answers its warning in Claude's dialect (`hookSpecificOutput`), which Cursor drops; wired the day it speaks Cursor — `tests/test-cursor-lifecycle.sh` re-checks that path each run. Its only documented output is `followup_message`, which this plugin never emits |
| `subagentStart` | ✅ | ✅ | ❌ | `cursor-agent-tools-guard.sh` would **deny every spawn** under an active frame as written (no `tool_name` on this payload); a spawn-time deny needs its own branch keyed on `subagent_type` + `tool_call_id`, de-duplicated against the `preToolUse` Task push. Desktop **3.27** adds `parent_agent_id` on this event — the missing correlation key for that design; still not wired until a dedicated branch lands |
| `postToolUseFailure` | — | ✅ | ❌ | Observation point (`error_message`, `failure_type`, `is_interrupt` → `additional_context`); available, nothing needs it yet |
| `beforeMCPExecution` · `afterMCPExecution` | ✅ / — | ❌ | ❌ | `preToolUse` already fires for MCP tool calls; wiring this too would double-judge the same call |
| `beforeReadFile` · `beforeTabFileRead` | ✅ | ✅ / ❌ | ❌ | This plugin makes no guarantee about *reads*. Every read-only agent is supposed to read |
| `afterShellExecution` · `afterFileEdit` · `afterTabFileEdit` · `afterAgentResponse` · `afterAgentThought` | — | mostly | ❌ | Observational, no output. Nothing here needs them; each is a process spawn per event |

Not ported: `capture-task-slug.sh` — on Cursor `enforce-worktree-edits.sh` creates the
worktree at the first write, and Cursor's own `--worktree`/cloud-VM isolation covers the
rest. `docker-guard.py` stays Claude-only (below).

### What runs where: cloud agents

Cloud agents run 14 of the 21 events and **do not load user-level hooks**. Of the ten events
wired here, `preToolUse`, `postToolUse`, `beforeShellExecution`, `beforeSubmitPrompt`, `stop`
and `preCompact` fire in a cloud agent; `sessionStart`, `sessionEnd` and `workspaceOpen` do
not. So a cloud agent keeps every guard, the `/goal` lint and both prompt reminders, but gets
no session lifecycle: no session-files directory from `session-init.sh` (the first write still
creates the worktree), no archive/prune/claim-release at the end, and no `pluginPaths`
injection. Set the `GITHUB_TOKEN` plugin variable the same way in both cases.

**One guard is deliberately Claude-only.** `docker-guard.py` is Python and writes its Claude-shaped
response directly rather than through `hooks/lib/hook-output.sh`, so it is not portable as written.
It is the one `PreToolUse` guard a Cursor install does not get.

## Rules are declared, not discovered

The manifest points `rules` at `./.cursor/rules/` on purpose. Cursor's automatic component
discovery falls back to a default `rules/` folder when the field is omitted — and in this
repo `rules/` is the **canonical markdown** (plus a `README.md`), not the 13 purpose-built
`.mdc` files with Cursor frontmatter.

So an omitted field would not have meant "no rules". It would have meant the wrong ones:
canonical `.md` shipped in place of the `.mdc` mirror, a README loaded as a rule, and the
five rules that exist **only** as `.mdc` — `commit-conventions`, `hooks-guide`,
`plugin-structure`, `skill-frontmatter`, `skills-guide` — never shipping at all.

Both halves of that are silent, so `tests/test-static.sh` asserts the declaration rather
than leaving it to a comment.

**The same trap applies to `hooks`.** A Cursor plugin's `hooks` component has the identical
discovery behaviour: it defaults to `hooks/hooks.json` and expects **Cursor's** camelCase
event format (`preToolUse`, `beforeShellExecution`, `sessionEnd`). This repo's file at that
exact path is Claude's **PascalCase** format, so discovery would find it and yield no usable
events. That is why the manifest declares `platforms/cursor/hooks.json` explicitly — a
Cursor-format file, with no `settings.json` involvement — and why
`tests/test-cursor-hooks-bundle.sh` asserts the declaration.

## Verify

```bash
jq empty .cursor-plugin/plugin.json
jq -e '.variables.properties.GITHUB_TOKEN' .cursor-plugin/plugin.json   # the plugin variable is declared
jq -e '.mcpServers.github' platforms/cursor/mcp.json                     # the Cursor MCP file
bash scripts/build-manifests.sh . --check                               # manifest and MCP file match their sources
bash scripts/doctor.sh .
```

In Cursor:

1. Open the command palette and confirm the toolkit's skills are listed.
2. Invoke one by name — *"use the targeted-debug skill"*.
3. Confirm the `.cursor/rules/*.mdc` entrypoint is active in a chat in this project.

## Update

With **Auto Refresh** enabled, Cursor picks up repo pushes on its own. Otherwise, refresh the
marketplace from the Plugins dashboard and reinstall. A version bump is not required for
refresh, but it is what tells you which build you have:

```bash
jq -r .version .cursor-plugin/plugin.json
```

## Uninstall

Remove the plugin from the Cursor Plugins dashboard, then remove the imported marketplace if
you no longer want it. Project-level `.cursor/rules/` and `.cursor/hooks.json` are files in
your repo — delete them separately if you added them by hand.

---

## Machine-level setup

The plugin install covers this repo. Global rules in `~/.cursor` are a separate, optional
step:

```bash
bash scripts/setup.sh plan  --targets cursor    # writes nothing
bash scripts/setup.sh apply --targets cursor
bash scripts/setup.sh remove --targets cursor
```

| Module | Writes | What it does |
|---|---|---|
| `rules` | `~/.cursor/rules/tamirs-superpowers.mdc` | Renders `core/global-rules.md` as a global Cursor rule |
| `cli-config` | `~/.cursor/cli-config.json` | Merges one conservative `permissions.allow` fragment |

The allow fragment is read-only shell inspection (`ls`, `git status`, `git log`, `git diff`)
plus the three GitHub domains the shipped skills fetch. It is deliberately **not** a
mechanical translation of the Claude allow-list: Cursor's `Shell()`/`Read()`/`Write()`/
`WebFetch()`/`Mcp()` syntax does not map one-to-one onto Claude's `Bash()` patterns, and a
guessed translation would be a security claim this repo cannot back.

Not touched, on purpose: **`permissions.deny`** — in Cursor deny beats allow, so an
installer able to widen it could lock you out of your own tool — and `~/.cursor/hooks.json`,
which no module reads or writes, so hook wiring written by other tools survives.

`plan` writes nothing and is the default when there is no terminal, so a hook or CI run can
never adopt anything silently. `apply` shows a diff and asks per change, defaulting to
**No**. Re-running is a no-op — idempotence is a content comparison. Full reference:
[setup](../setup.md) · [platform setup](../platform-setup.md).

## Capabilities and limitations

| Capability | Status | Notes |
|---|---|---|
| skills | native | since desktop 3.22.7 pin; pin as **Custom Mode** (2026-08-19) via ⌥⏎ / Alt+Enter from `/` |
| subagents | native | declared capability; cloud subagents can use **isolated VMs** (2026-08-19) |
| slash commands | partial | 26 generated into `.cursor/commands/`, one per user-invocable skill; declared in the manifest. `partial` because no live Cursor run has confirmed they appear under `/` |
| MCP | native | generated `platforms/cursor/mcp.json`, declared in the manifest; the github token is the `GITHUB_TOKEN` plugin variable set under Plugins → Configure |
| git · shell · GitHub CLI | native | `gh` is an optional host dependency everywhere |
| auto-invocation | partial | CLI sticky skills + Custom Modes; description-based selection across all surfaces is unverified — **name the skill** or pin a mode |
| hooks | partial | **Cursor-format plugin hooks DO run**, from `platforms/cursor/hooks.json`, declared in the manifest. Claude-shaped hooks (`hooks/hooks.json`) still do not — Cursor never reads a plugin's own `hooks.json`, which is why the bundle sits at a declared non-default path. 10 of Cursor's 21 events are wired (`workspaceOpen`, `sessionStart`, `sessionEnd`, `beforeSubmitPrompt`, `preToolUse`, `beforeShellExecution`, `postToolUse`, `stop`, `preCompact`) with `failClosed` on the safety tier; still `partial` because `subagentStart`/`subagentStop` are unwired, cloud agents get no session lifecycle, and the lifecycle port has had no live run |
| worktree isolation | emulated | The skill runs `git worktree` itself; no hook automation |
| parallel subagents | partial | Cloud swarm on isolated VMs (2026-08-19); local concurrency unmeasured |
| background tasks · structured questions · session transcripts | unknown | Not measured — treated as unavailable, with stated fallbacks |
| statusline · artifacts · extension install | unsupported | Cosmetic, absent, and not a Cursor mechanism, respectively |

### Working tips (3.11 → 2026-10-16; desktop CLI 3.22.7 validated, 3.27.12 reviewed; CLI 2026-08-26)
- **Desktop 3.27.12 (2026-10-23 stable):** [IDE notes](https://cursor.com/docs/release-notes/ide) **3.26** — agents stopped by an extension-host crash show **Resume** (use on long `orchestrate-dev` / `worker-dev` sessions); skill/command picker works when editing an earlier message; **Always Run** on terminal approvals sticks when `~/.cursor/permissions.json` owns the allowlist. **3.27** — hook payloads gain **`parent_agent_id`** on `subagentStart`/`subagentStop` (the missing key for a safe spawn-time wire that de-duplicates against the Task `preToolUse` frame push — still **not wired**: a naive guard would deny every spawn); Mermaid expand/zoom/copy in markdown preview; Reduce Motion for Cursor UI; faster first-window startup; non-UTF-8 agent I/O and encoding-aware codebase indexing. No live Cursor validation this run — `validated_against` stays **3.22.7**.
- **Desktop 3.25.9 (2026-10-10/11 stable):** IDE notes add **hook `tool_use_id`** correlation (shell/MCP hooks match `preToolUse`) and always-on **`transcript_path` / `CURSOR_TRANSCRIPT_PATH`** — this plugin's `cursor-agent-tools-guard.sh` now keys subagent allowlists on Task `tool_use_id` + child `parent_tool_call_id`. **Auto-review** asks before risky recursive/force/wildcard/mirror deletes whose targets could resolve differently than written. Cloud agents recognize **OOM kills** (memory limit reported). MCP OAuth can complete via a **Cursor-hosted callback** when local redirect URLs are rejected. Large worktree cleanups can OOM the main process — if heap climbs after launch, set `"cursor.worktreesGlobalMaxSizeGb": 0` and `"cursor.worktreeCleanupIntervalHours": 500` (Cursor staff workaround, forum 2026-10-11).
- **Desktop 3.23.12 (2026-10-01):** team/org **MCP allowlists** — keep the bundled `github` MCP (and any Team MCP) on the org allowlist after upgrade; Origin MCP endpoint is `api.origin.cursor.com/mcp`. Prefer **service tokens** for Automations that install/update this plugin. **Required** team-marketplace plugins removed — install modes are Default Off / Default On + groups only.
- **Security Review + Rollouts (2026-09-23):** Teams/Enterprise bots from [Automations](https://cursor.com/automations) ([Security Agents docs](https://cursor.com/docs/security-agents)). Security Review posts exploitable-bug findings on ready PRs (drafts skipped; Bugbot keeps style). Run Cursor's `/review-security` or `/review` before push — complements this plugin's `security-reviewer` agent (in-session role) rather than replacing it. **Rollouts** monitors deploy health per environment after merge; optional for this public plugin (no product deploy). [Changelog](https://cursor.com/changelog/rollouts-and-security-reviewer).
- **Projects (2026-09-10)** — Cursor **Projects** (left nav) suit multi-week / multi-agent work. A **coordinator** plans and delegates (does not write code); **shared context** files sync across cloud and local agents; **subscriptions** can watch Slack, schedules, or all PRs. Use a Project when validating this plugin across a long refactor or multi-PR initiative; keep ordinary `/diagnose-refusal` / one-shot skill runs in a normal Agent chat. Projects compose with (do not replace) Cloud Agents, Custom Modes, and Self-Hosted Machines ([changelog](https://cursor.com/changelog)).
- **CLI persistent sessions (2026-08-26)** — keep a long `agent` validation / `make validate` session alive across disconnects with `agent persist`, `/detach`, and `agent persist attach` ([CLI changelog](https://cursor.com/docs/cli/changelog)). Useful for cloud-headless and overnight plugin checks; prefer over killing the client mid-run.
- **Self-Hosted Machines (2026-09-02)** — Cursor can run Cloud Agent tool execution on **My Machines**, **Team Pools** (dynamic scale + hibernation), or partner sandboxes (AWS Lambda, Coder, Cloudflare, Daytona, Modal, Namespace, Vercel, E2B), with **computer use** on Linux/Mac ([docs](https://cursor.com/docs/cloud-agent/self-hosted)). Inventory workers with `list-self-hosted-workers`. **Not** the same as GitHub Actions `runs-on: [self-hosted]` — this public plugin repo stays on `ubuntu-latest` forever. Prefer managed Cloud Agents for validation; self-hosted only when private network / custom hardware requires it.

- **Start from scratch / no SCM (2026-08-27)** — Cloud Agents can begin without a connected GitHub repo: pick **Start from scratch**, prompt immediately, then **Create repo** to save into Origin (private/internal). Use **browser port-forward preview** (design mode) while the agent runs; optional **Vercel publish** for a live URL. GitHub remains canonical for marketplace installs and CI.

- **Custom Modes (2026-08-19)** — from `/`, pick a skill and press ⌥⏎ (Mac) or Alt+Enter (Windows) → **Use as Mode**. The skill stays pinned for the chat. Prefer this for `repo-standards`, `targeted-debug`, `platform-sync`, or any long playbook instead of re-invoking each turn.
- **`/goal` + steering (2026-08-19)** — give a long-lived objective with `/goal` (pair with a Custom Mode). Follow-ups now wait for the next tool call instead of cutting mid-action; type a follow-up and Send, or press ⏎ twice. Cloud Agents also expose native **CreateGoal** / **UpdateGoal** tools for the same long-lived objective pattern. CLI Aug 11 steer/`/goal` notes still apply for `agent` runs.
- **Subscriptions (Cloud Agents, 2026-08-19)** — agents can wake on PR events, Slack threads, or schedules; agents auto-subscribe to PRs they create and drive CI/review comments. Useful for unattended plugin validation Automations.
- **Subagents on their own machines (2026-08-19)** — cloud subagents get isolated project copies. Prefer for collision-free `make validate` / swarm checks.
- **Origin (2026-08-17)** / **Builds (default 2026-08-17)** — GitHub remains canonical for marketplace installs and CI; Origin is optional mirror. Confirm Cloud environments have a recent successful Build.

**The one to internalize:** on Cursor the safety guards now fail closed, but a hook is not a
sandbox — the same rules are enforced in CI, which is where they actually bind.

Source of truth: [`core/capabilities/platforms.json`](../../../core/capabilities/platforms.json).
Comparison: [platform differences](../platform-differences.md).


## Host currency notes (2026-10-16 / desktop 3.27.12)

Documentary review only (no live Cursor IDE run this cycle). Feature pin stays **3.11**.

| Date | Capability | Plugin impact |
|------|------------|---------------|
| 2026-10-16 | Cloud Agent **canvases**, **Environments API** (beta), **300-repo** / ~5× faster envs | Prefer canvases for durable multi-section reports from Cloud Agents; Environments API is host/dashboard — no plugin manifest change. |
| 2026-10-13 | **Origin App Marketplace** | Distinct from `tamirs-marketplace` plugin catalog installs. |
| 2026-10-06 | **Remote Control** (iOS ↔ local agents) | Operator convenience when a local Cursor session runs this plugin; Cloud Automations remain the unattended path. |
| desktop 3.27.12 | Stable download pin + IDE 3.26/3.27 | Document Resume-after-crash + `permissions.json` sticky Always Run + `parent_agent_id` for future `subagentStart` wire; hooks/skills/MCP wiring unchanged; keep `platforms/cursor/hooks.json` as the Cursor hook bundle. |
