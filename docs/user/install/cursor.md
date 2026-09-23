# Install — Cursor

Registry id: `cursor`. Validated against Cursor desktop **3.21.13** (feature changelog
**3.11**, covered through date-only **2026-09-10**); that floor is the version this repo
actually tested, not a guess.

---

## Install

Cursor imports a plugin marketplace straight from a repo:

1. Open the Cursor **Dashboard** → **Plugins**.
2. **Team Marketplaces** → **Add Marketplace** → **Import from Repo**.
3. Point it at `Tamircohen28/tamirs-superpowers` (or `Tamircohen28/tamirs-marketplace`).
4. Install **tamirs-superpowers** from the imported listing.

Cursor reads [`.cursor-plugin/plugin.json`](../../../.cursor-plugin/plugin.json), the
canonical `skills/` tree, [`.cursor/rules/`](../../../.cursor/rules) — declared explicitly,
see below — `agents/`, and the MCP stubs. Enable **Auto Refresh** on the marketplace and pushes propagate without a version
bump.

## Hooks do not come with the install

Worth knowing before you assume the safety guards are active: **a Cursor install of this
plugin wires none of its hooks.**

Cursor *can* import Claude Code hooks, and the setting is on by default
(Settings → Agents → Third-Party Imports → "Include Third-Party Plugins, Skills, and Other
Configs"). But it reads them from exactly three paths:

- `.claude/settings.local.json`
- `.claude/settings.json`
- `~/.claude/settings.json`

This plugin ships its hooks in `hooks/hooks.json`, wired through the plugin manifest — which
is not one of those three. The files are all present on disk after an install (see the
section below), but nothing loads them.

**One exception, and it is not part of the install.** This repo ships
[`.cursor/hooks.json`](../../../.cursor/hooks.json) with a single advisory
`beforeShellExecution` hook for people working *on this repo* in Cursor. Cursor reads
`.cursor/hooks.json` from the **project root**, so that file applies when this repo is your
open project — it is not delivered to your project by installing the plugin, and
`.cursor-plugin/plugin.json` declares no `hooks` field. It is a useful proof that the
Cursor-native format works here, not a counterexample to the paragraph above.

Of the 10 events this repo wires, Cursor's published mapping covers 6 — `PreToolUse`,
`PostToolUse`, `UserPromptSubmit`, `Stop`, `SessionStart`, `SessionEnd`. The other four —
`Notification`, `DirectoryAdded`, `WorktreeCreate`, `WorktreeRemove` — have no Cursor
equivalent, so even a hand-copied translation would be lossy.

A Cursor-native bundle, in Cursor's own richer 21-event format, is tracked as
[#179 E1](https://github.com/Tamircohen28/tamirs-superpowers/issues/179).

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
## The safety hooks now run on Cursor

`.cursor-plugin/plugin.json` declares `hooks` at `./platforms/cursor/hooks.json`, a
Cursor-format bundle wiring the two safety invariants to `preToolUse` and
`beforeShellExecution`.

**It points somewhere non-default deliberately.** Cursor's component discovery falls back to
`hooks/hooks.json`, which in this repo is the **Claude-format** file — PascalCase events Cursor
cannot read. An undeclared component does not disable itself; it binds to that default and
yields nothing.

**It runs the same scripts as Claude and Codex, not forked copies.** No translation layer was
needed, because three pieces were already platform-aware:

- `hooks/lib/hook-output.sh` detects Cursor from the payload (`conversation_id`,
  `cursor_version`, `workspace_roots`) and emits `{permission, user_message, agent_message}`
  instead of `hookSpecificOutput`
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
carry the name is the `Task` call that starts it (`tool_input.subagent_type`), so the guard
reconstructs the association from event **order**: push on `Task`, check against active frames, pop
on `postToolUse`. With two subagents running it applies the **intersection** of their allowlists —
stricter than either alone, which is the safe direction, since a refused call is visible and a
permitted one is not.

**It is advisory, not a sandbox.** It infers "inside a subagent" from event sequence, raising the
cost of an unlisted call without making one impossible, and a missed `postToolUse` fails safe
(over-restrictive rather than unguarded). Treat these agents as **role prompts with a raised
floor** — meaningfully better than prose alone, and still not an isolation boundary.

Tracked as [#179](https://github.com/Tamircohen28/tamirs-superpowers/issues/179); guard shipped in
[#223](https://github.com/Tamircohen28/tamirs-superpowers/pull/223).

## Which of Cursor's 21 hook events this plugin wires

Cursor exposes 21 hook events; **7 of them can deny an action**, the rest are observational.
This plugin wires 3 events, and the other 18 are accounted for rather than merely absent —
an event is wired because a guard needs it, not to fill in the table.

| Event | Can deny | Wired | Why / why not |
|---|:---:|:---:|---|
| `preToolUse` | ✅ | ✅ | 5 guards: worktree edits, sensitive files, branch concurrency, skill-creator, agent `tools:` allowlist |
| `beforeShellExecution` | ✅ | ✅ | `guard-sensitive-files.sh` — a shell command is a write path too |
| `postToolUse` | — | ✅ | pops the agent-allowlist frame |
| `subagentStart` | ✅ | ▲ | **Best available improvement.** Carries `subagent_type` *and* `subagent_id`, so the allowlist frame could be keyed on a real identifier instead of inferred from event order. Not yet wired: the push would need to de-duplicate against the existing `preToolUse Task` push (`subagentStart.tool_call_id` matches `preToolUse.tool_use_id`), and wiring it half-way risks a double push that never pops. |
| `subagentStop` | — | ▲ | Fires on complete **, error, or abort** — a more reliable pop than `postToolUse Task`, and would fix the documented stuck-frame case. Blocked on the same de-duplication design: its payload carries `subagent_type` but no id, so popping must match by agent name. |
| `beforeMCPExecution` | ✅ | ❌ | `preToolUse` already fires for MCP tool calls, so wiring this too would double-judge the same call |
| `beforeReadFile` · `beforeTabFileRead` | ✅ | ❌ | This plugin makes no guarantee about *reads*. Every read-only agent is supposed to read |
| `beforeSubmitPrompt` | ✅ | ❌ | Claude's `UserPromptSubmit` peers (`skill-suggest.sh`, goal/scope reminders) inject context into a model turn; the port is real work, not a wiring change |
| `sessionStart` · `sessionEnd` | — | ❌ | Claude peers exist (`session-init.sh`, `session-end.sh`, `handoff-reminder.sh`) and are a genuine gap — a Cursor user gets no session lifecycle today |
| `stop` · `preCompact` | — | ❌ | Claude peers exist (`check-done.sh`, `precompact-snapshot.sh`); same gap, same reason |
| `afterShellExecution` · `afterMCPExecution` · `afterFileEdit` · `afterTabFileEdit` · `postToolUseFailure` · `afterAgentResponse` · `afterAgentThought` · `workspaceOpen` | — | ❌ | Observational. No guard here needs them; wiring one would add cost and no guarantee |

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
exact path is Claude's **PascalCase** format, so discovery finds it and yields no usable
events. That is a cheaper route for a Cursor hook bundle than the `settings.json` import
path — a Cursor-format file declared in the manifest, with no `settings.json` involvement —
and is tracked as [#179 E1](https://github.com/Tamircohen28/tamirs-superpowers/issues/179).

## Verify

```bash
jq empty .cursor-plugin/plugin.json
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
| skills | native | since desktop 3.21.13 pin; pin as **Custom Mode** (2026-08-19) via ⌥⏎ / Alt+Enter from `/` |
| subagents | native | declared capability; cloud subagents can use **isolated VMs** (2026-08-19) |
| slash commands | partial | 26 generated into `.cursor/commands/`, one per user-invocable skill; declared in the manifest. `partial` because no live Cursor run has confirmed they appear under `/` |
| MCP | native | `.mcp.json` |
| git · shell · GitHub CLI | native | `gh` is an optional host dependency everywhere |
| auto-invocation | partial | CLI sticky skills + Custom Modes; description-based selection across all surfaces is unverified — **name the skill** or pin a mode |
| hooks | partial | **Cursor-format plugin hooks DO run**, from `platforms/cursor/hooks.json`, declared in the manifest. Claude-shaped hooks (`hooks/hooks.json`) still do not — Cursor never reads a plugin's own `hooks.json`, which is why the bundle sits at a declared non-default path. `partial` because 3 of Cursor's 21 events are wired (`preToolUse`, `beforeShellExecution`, `postToolUse`) |
| worktree isolation | emulated | The skill runs `git worktree` itself; no hook automation |
| parallel subagents | partial | Cloud swarm on isolated VMs (2026-08-19); local concurrency unmeasured |
| background tasks · structured questions · session transcripts | unknown | Not measured — treated as unavailable, with stated fallbacks |
| statusline · artifacts · extension install | unsupported | Cosmetic, absent, and not a Cursor mechanism, respectively |

### Working tips (3.11 → 2026-09-10; desktop CLI 3.21.13; CLI 2026-08-26)
- **Projects (2026-09-10)** — Cursor **Projects** (left nav) suit multi-week / multi-agent work. A **coordinator** plans and delegates (does not write code); **shared context** files sync across cloud and local agents; **subscriptions** can watch Slack, schedules, or all PRs. Use a Project when validating this plugin across a long refactor or multi-PR initiative; keep ordinary `/diagnose-refusal` / one-shot skill runs in a normal Agent chat. Projects compose with (do not replace) Cloud Agents, Custom Modes, and Self-Hosted Machines ([changelog](https://cursor.com/changelog)).
- **CLI persistent sessions (2026-08-26)** — keep a long `agent` validation / `make validate` session alive across disconnects with `agent persist`, `/detach`, and `agent persist attach` ([CLI changelog](https://cursor.com/docs/cli/changelog)). Useful for cloud-headless and overnight plugin checks; prefer over killing the client mid-run.
- **Self-Hosted Machines (2026-09-02)** — Cursor can run Cloud Agent tool execution on **My Machines**, **Team Pools** (dynamic scale + hibernation), or partner sandboxes (AWS Lambda, Coder, Cloudflare, Daytona, Modal, Namespace, Vercel, E2B), with **computer use** on Linux/Mac ([docs](https://cursor.com/docs/cloud-agent/self-hosted)). Inventory workers with `list-self-hosted-workers`. **Not** the same as GitHub Actions `runs-on: [self-hosted]` — this public plugin repo stays on `ubuntu-latest` forever. Prefer managed Cloud Agents for validation; self-hosted only when private network / custom hardware requires it.

- **Start from scratch / no SCM (2026-08-27)** — Cloud Agents can begin without a connected GitHub repo: pick **Start from scratch**, prompt immediately, then **Create repo** to save into Origin (private/internal). Use **browser port-forward preview** (design mode) while the agent runs; optional **Vercel publish** for a live URL. GitHub remains canonical for marketplace installs and CI.

- **Custom Modes (2026-08-19)** — from `/`, pick a skill and press ⌥⏎ (Mac) or Alt+Enter (Windows) → **Use as Mode**. The skill stays pinned for the chat. Prefer this for `repo-standards`, `targeted-debug`, `platform-sync`, or any long playbook instead of re-invoking each turn.
- **`/goal` + steering (2026-08-19)** — give a long-lived objective with `/goal` (pair with a Custom Mode). Follow-ups now wait for the next tool call instead of cutting mid-action; type a follow-up and Send, or press ⏎ twice. Cloud Agents also expose native **CreateGoal** / **UpdateGoal** tools for the same long-lived objective pattern. CLI Aug 11 steer/`/goal` notes still apply for `agent` runs.
- **Subscriptions (Cloud Agents, 2026-08-19)** — agents can wake on PR events, Slack threads, or schedules; agents auto-subscribe to PRs they create and drive CI/review comments. Useful for unattended plugin validation Automations.
- **Subagents on their own machines (2026-08-19)** — cloud subagents get isolated project copies. Prefer for collision-free `make validate` / swarm checks.
- **Origin (2026-08-17)** / **Builds (default 2026-08-17)** — GitHub remains canonical for marketplace installs and CI; Origin is optional mirror. Confirm Cloud environments have a recent successful Build.

**The one to internalize:** hook guards are advisory in Cursor. The same rules are enforced
in CI, which is where they actually bind.

Source of truth: [`core/capabilities/platforms.json`](../../../core/capabilities/platforms.json).
Comparison: [platform differences](../platform-differences.md).
