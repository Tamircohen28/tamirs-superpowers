# ADR 004 — Permission levels: presets, config, overrides and enforcement per platform

**Status:** Proposed — 2026-11-03

## Context

The plugin's skills push, open PRs, arm auto-merge, delete branches, create repositories and write global config;
today the only brakes are skill prose, one resolver and a concurrency guard. The research ([synthesis][R]) and three
audits ([dev-workflow and repo skills][A1], [other skills][A2], [agents, scripts, hooks, mod, MCP][A3]) found:

- **No host lets a plugin widen host permissions** ([R]; [claude], [codex], [cursor], [gemini], [opencode]), so the
  most autonomous level only removes the *plugin's own* gates. Levers that *can* widen, designed against: a Claude
  mod `tool.check` approves over a user deny on personal logins ([claude] B, doc-cited); an OpenCode
  `ctx.session.update` session allow beats a config deny (measured O2, [S2]); Codex `PermissionRequest` and
  Antigravity `auto_approve` hooks answer prompts ([codex] B2, [gemini] E).
- **Enforcement verbs differ per host.** Claude honours a hook `ask` in default, auto and bypassPermissions and
  denies it headless (measured C4/U3, [S1]). Codex fails open on hook `ask`, bare `allow`, crash, timeout and odd
  exit codes (source-cited X1, [S1]). Cursor `preToolUse` consumes only `deny`; `beforeShellExecution` `ask` forces
  a CLI prompt (source-cited U1, [S2]). A Gemini hook `ask` hangs headless (measured G1); an extension `ask_user`
  policy holds under `--yolo` and denies headless (measured G3). OpenCode auto-approves a hook `ask` under `--auto`;
  a hook `deny` is final (measured O1).
- **The shipped guards do not cover danger.** `protect-other-branches.sh` is a concurrency guard that allows
  force-push, remote delete, `branch -D`, `gh pr merge --admin` and `gh api -X DELETE/PUT …/protection`
  (reproduced, [A3] D1). GitHub MCP tools bypass every Bash-matched hook and [`github-mcp.sh`][mcpsh] passes no
  restriction flag ([A3] D3). The installed machine config sets `defaultMode: bypassPermissions` with broad allows
  ([`settings.d/defaults.json`][sdefaults], [A3] A), so hooks are the only enforcement there. Nothing protects a
  policy file or the guard scripts ([A3] D7).
- **The merge policy disagrees with itself.** [`safety.md`][safety]: auto-merge "Off unless configured";
  [`resolve-merge-policy.sh`][rmp] step 5: enable whenever the repo allows; [`deliver-dev`][deliver] lists 4
  precedence rules, [`pr-dev`][prdev] 5 ([A1] D-5).

Binding user decisions (2026-11-03): levels `supervised` (default) / `standard` / `unattended`; `standard` =
auto-merge off unless configured, `safety.md` canonical; a repo file may enable auto-merge only after hash-confirmed
trust; host minimums may be raised; platform drift is out of scope.

## Decision

### D1 — One action catalog over the R0–R4 rubric (a)

The rubric is [prior art][P] §4 (reversibility × blast radius × visibility). **UNCLASSIFIED ⇒ R4; R4 is never
automatic; context may raise a level, never lower it** (a remote delete with unmerged commits is R4).

**Rubric gap — local non-config effects** ([A2] A). Resolved as a *mapping* with a `machine` tag (`m`), not a
sixth class: blast radius gains the rung "this machine, outside the worktree". Plugin-owned and session-scoped
(loopback viewer, browser open) ⇒ R1. Outside the worktree but owned and undoable by the plugin (its own daemon by
verified PID, a lockfile install into its own worktree, a nested CLI pinned to the caller's level) ⇒ R2. Touches
what the plugin does not own or runs code the user never chose (kill a foreign PID, install a model-named package,
`docker run/pull`, a foreign repo's script, a nested `claude -p` inheriting the host mode) ⇒ R3. Persists into host
config or trust ⇒ R4 (`config.global.write`). Why: levels are ceilings on one axis; a sixth class would need a
column in every preset and override and would only mean "R2/R3, but local".

The catalog is one plugin-owned registry (`core/permissions/actions.json`, not user-editable); audit aliases fold
into the canonical id. L2 points: **PG** = new `hooks/permission-guard.sh` on Bash/Shell (and its Gemini/OpenCode
ports), **MCP** = GitHub MCP tool matcher + server flags (D8), **GSF** = [`guard-sensitive-files.sh`][gsf] path rules.

| id (aliases) | R | where (audit evidence) | L2 point · unattended precondition |
|---|---|---|---|
| `repo.read` (`mcp.read`, gh view/api GET), `net.get` (`net.get.docs`), `secrets.read.config`, `env.read.names` | R0 | all skills ([A1] C, [A2] C) | none |
| `file.write.repo` (`fs.state.write`, `scaffold.local.write`, `file.overwrite.nocheck`, `objective.set_delivery`) | R1 | most skills | `enforce-worktree-edits.sh` |
| `git.commit` (`git.commit.local`), `git.branch.create`, `git.index.untrack`, `git.merge.local`, `git.rebase.own`, `git.sync.ff` | R1 | worker, orchestrate, cleanup, capture-config | none |
| `git.worktree.add` (`.move`), `worktree.remove` (clean and pushed), `worktree.cleanup` (auto) | R1 | resolve-worktree, session-init ([A3] B3) | none |
| `branch.delete.local` (`git.branch.delete.local`); R3 if unmerged with no remote copy | R1 | cleanup-after-merge ([A1] D-1) | PG |
| `fs.build_dirs.delete` (gitignored, regenerable only) | R1 | cleanup | `cleanup.sh` guard |
| `agent.spawn` (`subagent.spawn`): the child runs at the caller's ceiling, never higher | R1 | orchestrate, skill-creator | none |
| `server.local.start`, `browser.open`, `code.exec.repo_script` (this worktree) | R1 m | skill-creator, docs-review ([A2] C) | none |
| `git.push.branch` (own, non-default) | R2 | deliver, start, pr-dev, switch ([A1] C) | PG |
| `pr.create`, `pr.comment`, `pr.review_request`, `ci.rerun`, `pr.update_branch`, `pr.thread.resolve` (threads the agent answered) | R2 | pr-dev, deliver ([A1] C) | PG, MCP |
| `issue.create`, `issue.comment`, `issue.edit` (`issue.edit.resume`), `label.create`/`.edit`, `copilot.assign` | R2 | plan-dev, switch-dev ([A1] C, [A3] B5) | PG, MCP |
| `file.write.remote` on a non-default branch (`create_or_update_file`, `push_files`, `delete_file`) | R2 | MCP ([A3] B5) | MCP |
| `notify.send`, `net.post.external`, `secrets.collect.chat` | R2 | notify-setup ([A2] F7) | L1 only |
| `daemon.start`/`.stop` (plugin-owned, PID verified), `deps.install` (lockfile, own worktree), `process.spawn.claude_cli` (child given `--permission-mode` no wider than the caller) | R2 m | usage-capture, session-init, skill-creator ([A2] F1/F5, [A3] D9) | L1; hook-run installs are skipped with a notice under supervised |
| `pr.merge.auto` (`pr.auto_merge.enable`) | R3 | pr-dev ([A1] D-5) | PG · protection reports ≥ 1 required check |
| `pr.merge` (direct; MCP `merge_pull_request`) | R3 | pr-dev, MCP ([A3] D3) | PG, MCP · none (never automatic) |
| `branch.delete.remote`; R4 with unmerged commits | R3 | pr-dev, cleanup ([A1] D-1, D-6) | PG · PR `MERGED`, not base/default, not cross-repo |
| `pr.close`, `issue.close` | R3 | pr-dev ([A1] D-10) | PG, MCP · own PR or `Closes #N` of a merged PR |
| `pr.review.approve`, `pr.thread.resolve` (others' threads) | R3 | MCP, pr-dev ([A1] D-7) | PG, MCP · none |
| `git.push.default` (`git.push.default_branch`) | R3 | none intended ([A1] D-11) | PG · none; denied when protected ([safety] invariant 5) |
| `git.push.force` (`git.force_push`; own, non-default branch) | R3 | none executes it ([A1] D-11; enforced on 2 of 5 hosts, [A3] D2) | PG · `--force-with-lease` and own claim ([git] "no force-push to base") |
| `file.write.remote` on the default branch, `repo.settings.merge`, `file.write.outside_repo`, `handoff.force` | R3 | MCP, repo-scaffold/-standards, retro ([A1] D-4, D-13; [A2] F3) | PG, MCP · none |
| `process.kill` (`process.kill.port`, unverified PID), `pkg.install.network`, `pkg.exec.network`, `docker.state` (run/build/pull/up/prune), `code.exec.foreign_repo`, `process.spawn.claude_cli` (inherits host mode) | R3 m | skill-creator, mcp-builder, docker-guard ([A2] F5/F6/F8, [A3] B3) | PG · pinned lockfile only for `pkg.*`; otherwise none |
| `pr.merge.admin` | R4 | pr-dev ([A1] D-2) | PG |
| `git.push.force.default` (`git.force_push.default`) | R4 | none ([A3] D1) | PG |
| `repo.create` (incl. `fork_repository`), `repo.delete` | R4 | repo-scaffold, MCP ([A1] D-3, [A3] B5) | PG, MCP, server exclusion |
| `ruleset.apply`, `ruleset.apply.org`, `branch_protection.write` (apply, remove, legacy shim) | R4 | github-policy, repo-* ([A1] D-8/D-9) | PG (script names, `gh api …/protection`) |
| `release.create`, `tag.push` (`git.tag.create`) | R4 | none today ([A3] C) | PG |
| `workflow.edit` (local or remote), `file.write.remote` to workflows, hooks or policy | R4 | GSF today denies locally and points at the MCP path ([A3] D3) | GSF, MCP |
| `config.global.write`, `config.policy.stage`, `secrets.capture.bodies` | R4 | setup/install, usage-capture, mcp-builder, retro, capture-config ([A2] F1–F4, [A3] D11) | PG (script names), GSF |
| `policy.edit` (`plugin.permission_policy.edit`): permission files, lock, tickets, guard scripts, installed caches, `claude plugin configure`, `gemini extensions config` | R4 | any write ([A3] D7) | GSF + PG deny; only the D6 writer, with a human proof |
| `worktree.remove.force`, `worktree.drop`, `git.reset_to_remote` that discard uncommitted or unpushed work | R4 | pr-dev script, cleanup ([A1] D-1, D-6) | PG; [safety] invariant 4 |

### D2 — Level presets are ceilings (b)

| rubric | `supervised` (default) | `standard` | `unattended` |
|---|---|---|---|
| R0, R1 | allow | allow | allow |
| R2 | ask | allow | allow |
| R3 | ask | ask | allow **iff** the action's precondition (D1) holds, else ask |
| R4 | ask, per call, naming the target | ask | ask — never automatic |
| explicit `deny`, [safety] invariants | deny | deny | deny |
| `pr.merge.auto` | ask | ask (= off) unless `actions["pr.merge.auto"]: "allow"` in the user file or a trusted project file | allow iff protection reports ≥ 1 required check |

- **Auto-merge means `gh pr merge --auto` only**, so GitHub protection decides ([P] Steal table). The plugin never
  performs a direct `pr.merge` automatically at any level.
- **No human present ⇒ ask becomes deny plus the setting that would allow it.** Every denial names the once-only
  route (`--perms=`, D5) and the durable one (`/plugin-config …`, D6); for R4 it says no setting allows it
  automatically. Where the host denies its own ask headless (Claude hook `ask`, Gemini static `ask_user`) the host
  does this; elsewhere the plugin delivers R3/R4 asks as deny + ticket (D8), the same deny headless.
- A level governs the plugin, never the host: `unattended` does not stop host prompts ([R] "The one fact").

### D3 — Config: one user file, one project file, option stores hold only the preset (c)

**User file (canonical):** `${XDG_CONFIG_HOME:-$HOME/.config}/tamirs-superpowers/permissions.json`, mode 0600,
beside `permissions.lock` (`{sha256, by, at}`, written by the D6 writer only).

| rejected location | why ([R] "Design conclusions" 1) |
|---|---|
| `${CLAUDE_PLUGIN_DATA}` | Claude only, deleted on the last uninstall ([claude] C); Codex `PLUGIN_DATA` reaches hooks only (X2, [S1]) |
| Cursor / Gemini plugin dirs | none survives an update: SHA-keyed cache ([cursor] C), extension dir recopied ([gemini] C) |
| OpenCode `ctx.storage` | machine-local SQLite row, not human-editable (measured O3, [S2]); cache at most |
| `~/.claude/…` | host config dir, exempt from the worktree rule ([A3] D7) |
| platform option stores | flat strings; Codex ignores unknown `[plugins."x@y"]` keys (measured X4); Cursor `variables` reach MCP only (U3) |

The XDG path is outside every plugin root and host config dir, readable by every hook through `$HOME` ([cursor]
implication 3) and by every skill through a shell read. Short-lived state (tickets, guard heartbeat) lives at
`${XDG_STATE_HOME:-$HOME/.local/state}/tamirs-superpowers/`, because Codex skills never see `PLUGIN_DATA` ([codex] C).

**Option stores hold only the preset:** Claude `userConfig.permission_level`; Gemini setting `TS_PERMISSION_LEVEL`,
raising only from the user-scope `.env` in the extension dir (a workspace `.env` can hold it too, [gemini] C, so that
source may only lower). Codex, Cursor and OpenCode have none; OpenCode `ctx.options` is not read because a project
`opencode.json` could set it ([opencode] C). **Effective level = the lower of the option store and the user file
`level`; neither ⇒ `supervised`.** A Claude project-scope install carries no preset (`pluginConfigs` is user/managed
scope, doc-cited [claude] C), so the project file is the only repo-level channel.

**Project file:** `<repo>/.tamirs-superpowers/permissions.json` (committable; `.dev-files/` is gitignored by
default). It may always **tighten**. It may **widen** — the only way to turn on repo-level auto-merge — only after
`/plugin-config trust` records its sha256 under the repo's realpath (shared by its worktrees) in the user file. A
changed hash or a new clone ⇒ widening entries ignored with a notice, tightening entries still applied. An invalid
file ⇒ `supervised`, overrides ignored, warning (fail closed).

```json
{ "version": 1, "level": "standard",
  "groups": { "repo": { "level": "supervised", "skills": ["cleanup", "github-policy", "multi-agent-repo", "repo-scaffold", "repo-standards"] } },
  "skills": { "pr-dev": "unattended" },
  "actions": { "pr.merge.auto": "allow", "pkg.install.network": "deny" },
  "skill_actions": { "pr-dev": { "issue.close": "deny" } },
  "trust": [ { "repo": "/Users/me/src/app", "remote": "github.com/me/app", "file": ".tamirs-superpowers/permissions.json",
               "sha256": "<64 hex>", "widens": ["pr.merge.auto"], "at": "2026-11-03T10:00:00Z" } ] }
```

| field (JSON Schema `core/schemas/permissions.schema.json`) | type · constraint | user | project |
|---|---|---|---|
| `version` | integer, const 1 | required | required |
| `level` | enum `supervised` · `standard` · `unattended` | optional | optional |
| `groups.<g>` | `{level, skills[]}`; `g` ∈ skill categories (`dev-workflow`, `repo`, `toolkit`, …); `skills` is a snapshot — a skill added to the group later gets a group *raise* only after re-confirmation ([P] §5.6) | optional | optional |
| `skills.<id>` | level enum; `id` ∈ shipped skills | optional | optional |
| `actions.<id>`, `skill_actions.<skill>.<id>` | enum `allow` · `ask` · `deny`; `id` ∈ catalog; R4 ids accept only `ask` · `deny` | optional | optional |
| `trust[]` | `{repo, remote, file, sha256 (^[0-9a-f]{64}$), widens[], at}` | optional | forbidden |
| everywhere | `additionalProperties: false`, ASCII only | | |

### D4 — One precedence chain, one resolver (d)

`scripts/resolve-permission.sh <action-id> [--skill s] [--target t] [--objective id]` prints `{decision, r, level,
level_source, decided_by, allow_with, warnings}` and is the only implementation: hooks (L2),
[`resolve-merge-policy.sh`][rmp] (for `pr.merge.auto`; it keeps computing capability, protection and merge method),
pr-dev and deliver-dev (L1, quoting `decided_by`) and `/plugin-config show` all call it. [`deliver-dev`][deliver]
Step 6 drops its own list and reports the resolver's source.

| # (highest first) | input | may widen? | migration of the legacy input |
|---|---|---|---|
| 0 | [safety] invariants, R4-never-automatic, repo capability (auto-merge disallowed, protection) | never | resolver rule 4 kept as is |
| 1 | `--perms=` ticket (D5) | lower always; raise only with human-origin proof | new |
| 2 | `TAMIRS_AUTO_MERGE` | `never` tightens; `always` is ignored with a warning naming `/plugin-config pr.merge.auto allow` (an agent can type an env prefix, [A3] D5) | rule 1 demoted |
| 3 | objective `delivery.auto_merge` | `false` tightens; `true` records the resolved decision, never grants (state is agent-written) | rule 2 demoted |
| 4 | project file | tighten always; widen only if trusted (D3) | `.dev-files/policy.json` `delivery.auto_merge` is read as `actions["pr.merge.auto"]` under the same trust rule for one minor release, then removed |
| 5 | user file: `skill_actions` > `actions` > `skills` > `groups` | yes (user-authored, hash-locked) | — |
| 6 | level = lower of option store and user file `level` | — | — |
| 7 | default `supervised` | — | rule 5 ("enable when the repository allows") deleted |

Combination: start from the ceiling (6–7), apply 5 (the most specific key present decides between allow and ask),
then 4 → 0, where tighten-only inputs move only toward deny. **Any `deny` from any layer is final. R4 never becomes
allow:** a matching human-origin ticket satisfies its ask for one call.

### D5 — `--perms=<level>` is a one-shot ticket (e)

No host parses `--perms=`; it is prompt text everywhere ([R] conclusion 5). **Lowering is always honoured** (L1
parses it). **Raising** creates a ticket only from an event the model cannot author:

| platform | raise accepted from | evidence |
|---|---|---|
| Claude Code | `UserPromptExpansion.command_args` of a prompt whose `UserPromptSubmit.source == "user"`; missing `source` ⇒ not user; a model-invoked `Skill` call never qualifies | source-cited C3; live capture and the correlation of the two events unmeasured (U2, [S1]) |
| Gemini CLI | interactive `BeforeAgent.prompt` right after `BeforeTool(activate_skill)`; headless, the invoker's `-p` text | measured G2; order correlation unverified under concurrency ([S2]) |
| OpenCode | command `$ARGUMENTS` seen by `session.hook("prompt")` | doc-cited [opencode] B, D; unmeasured |
| Codex, Cursor | not directly: the raise starts an in-chat confirmation; the user's next message `confirm <nonce>`, captured by Codex `UserPromptSubmit` / Cursor `beforeSubmitPrompt` | events doc-cited ([codex] B2, [cursor] B); prompt payload unverified (U5, S3) |
| every platform | `scripts/plugin-config.sh confirm <nonce>` in the user's own terminal (reads `/dev/tty`; agent Bash has no TTY) | [A1] D-9, [A3] B2 |

A ticket is `{id, nonce, skill, action?, target, level, origin, session_id, created, expires}`: one skill, one target
(the skill's first argument plus the repo slug), 15 minutes, single use for R4. Only the prompt-origin hooks and the
TTY path write tickets; GSF denies every other write. **Never inherited:** a ticket binds `session_id` and target,
and L1 forbids `--perms=` in worker or subagent prompts. **Never from content:** file, PR, issue or tool-output text
never reaches a prompt-origin hook, and L1 ignores `--perms=` found there. This replaces the agent-typeable approval
token of [`docker-guard.py`][docker] ([A3] D5).

### D6 — `/plugin-config` (f)

```text
/plugin-config show | <level> | <skill|group> <level> | <action-id> [<skill>] allow|ask|deny
/plugin-config reset [<skill|group|action-id>|all] | trust (this repo's project file) | confirm <nonce>
```

- **Explicit-only where the host supports it:** Claude and Cursor `disable-model-invocation: true` (on Claude it
  also blocks subagent invocation, wanted here); Codex `policy.allow_implicit_invocation: false` ([codex] D);
  OpenCode a code command via `ctx.command.transform`, no model in the loop ([opencode] implication 6). Gemini has
  no such flag ([gemini] D): the writer's check is the gate there.
- **Deterministic writer:** every write goes through `scripts/plugin-config.sh` — schema validation, `jq -S` with
  fixed indent, atomic tmp + `mv`, 0600, `.bak`, lock rewrite. `show` prints each value's source and hash status.
- **Anti-escalation:** the writer diffs every catalog action's effective decision before and after. A change that
  widens nothing is written at once. One that widens anything — including `reset` of a deny and `trust` — prints
  the widened rows and a nonce, and is written only after a matching human-origin confirmation (D5); no session
  confirms its own change. It never writes R4 `allow` or host option stores; a Claude/Gemini level raise prints the
  host route (`/config` or `/plugin configure`; `gemini extensions config`), since the lower-of rule (D3) means the
  file alone cannot raise there.

### D7 — Install and later change (g)

| platform | at install | later | no config |
|---|---|---|---|
| Claude Code | `userConfig.permission_level`: `type: string`, `options: ["supervised","standard","unattended"]`, `default: "supervised"` (plain strings, default ∈ options; reported "not yet set" until stored — measured C1/C2) | `/config` picker (CLI only, [claude] E), `/plugin configure`, `claude plugin configure --values-stdin` in the user's terminal (PG denies it from agent Bash); Desktop route unverified (U4) | `supervised` |
| Gemini CLI | `settings[]` `TS_PERMISSION_LEVEL` (string only, prompted unless `--skip-settings`, [gemini] C) | `gemini extensions config tamirs-superpowers TS_PERMISSION_LEVEL`; not in the enum ⇒ `supervised` + warning | `supervised` |
| Codex, Cursor, OpenCode | none ([codex] C; [cursor] C; [opencode] C) | `/plugin-config`; `make setup` asks once on a TTY | `supervised`; one SessionStart notice |

### D8 — Enforcement matrix (h)

Layers: **L1** skill gate (resolver call before the step), **L2** hook deny, **L3** host-native ask. **E** = ENFORCED,
**A** = ADVISORY. L1 is advisory everywhere (OWASP LLM06, [P] §5.7). The neutraliser column is design, not today.

| platform | L2 shell (R2–R4) | L2 GitHub MCP | L3 host ask | ask is delivered as | fail-open neutralised by | per-skill levels at L2 |
|---|---|---|---|---|---|---|
| Claude Code | E: PG on `Bash`, `onFailure: "block"` | E if a `mcp__plugin_tamirs-superpowers_github__.*` matcher fires (unverified, [A3] A) + server flags | E: hook `ask` in default/auto/bypass, headless ⇒ deny (measured C4/U3; interactive rendering unobserved) | hook `ask` | `onFailure: "block"` (2.1.295+) | E via `UserPromptExpansion`; a model `Skill` call as a context signal is unverified |
| Claude Desktop | unverified (C5/U4) | server flags | unverified | as CLI if the heartbeat (below) is fresh | heartbeat; else L1 runs `supervised` | A |
| Codex CLI | E, deny only: exit 2 + stderr, or `deny` with reason (source-cited X1; live U5) | MCP-tool hook actions (0.148, [codex] E) matcher unverified ⇒ server flags | none: hook `ask` fails open (X1) | deny + ticket | guard traps every error to a deny, never exits non-0/2; SessionStart canary self-test; `setup.sh` offers user-owned execpolicy `prompt` rules for R4 ([codex] implication 10) | A |
| Cursor CLI | E: `preToolUse` + `beforeShellExecution` deny, `failClosed` (source-cited U1) | E: `preToolUse` deny on the MCP path (source-cited U1.4) | `beforeShellExecution` ask forces a prompt (source-cited U1) — unused until S1 | deny + ticket | `failClosed: true` | A |
| Cursor desktop | deny assumed as CLI, 3.28 unverified (S2) | as CLI, unverified | unverified (forum: ignored under Auto-review, [cursor] B) | deny + ticket | `failClosed: true` | A |
| Gemini CLI | E: BeforeTool deny, never `ask` (hangs headless and hook input cannot tell headless, G1); paired static extension `deny` | static extension rules on `mcpName = "github"` (unmeasured) + hook | E: static mode-less `ask_user` for R4 patterns (headless deny under `--yolo` measured G3; TTY prompt source-cited) | deny + ticket; R4 also static `ask_user` | static policy pairs every must-hold rule (hooks fail open, [A3] D8) | E: `BeforeTool(activate_skill)` |
| OpenCode | E: `permission.hook("evaluate")` deny, final under `--auto` (O1b) | MCP calls are `<server>_<tool>` actions (doc-cited, [opencode] A), unmeasured | A: hook `ask` auto-approved under `--auto` (O1c) | R2: hook `ask` (A under `--auto`); R3/R4: deny + ticket | `guard.ts` catches every error as deny | E: `skill` action |

Antigravity is not a target of this ADR; its hooks accept `allow`/`auto_approve` ([gemini] E), so if it is ever
wired it is deny-only. **Heartbeat:** SessionStart writes `<state>/heartbeat/<platform>`; L1 treats a heartbeat that is
missing or older than 12 h as "no guard" and runs `supervised`.

**GitHub MCP server flags by level** (`github-mcp.sh` at server start; the installed v2.1.0 supports `--read-only`
and `--exclude-tools`, [A3] D3). Tickets never widen the tool set.

| level | flags |
|---|---|
| `supervised` | `--read-only` |
| `standard`, `unattended` | `--exclude-tools merge_pull_request,delete_repository,create_repository,fork_repository`; plus, until that platform's MCP matcher is verified (only Cursor's is, source-cited), every tool whose arguments can reach R3/R4: `create_or_update_file,push_files,delete_file,issue_write,update_pull_request,pull_request_review_write` |

`merge_pull_request` is excluded at every level because the only automatic merge is `gh pr merge --auto`; R4 tools
are excluded because their human gate lives on the `gh` path.

### D9 — Minimum host versions (i)

Recorded per target in [`platform-targets.json`][targets] (new `permissions_min` beside `supported_min`). A readable
host version below it ⇒ levels above `supervised` run as `supervised`, said once; an unreadable one ⇒ warning only.

| platform | minimum | the feature that forces it |
|---|---|---|
| Claude Code | 2.1.317 | hook `ask` honoured under bypass and headless deny measured only here (C4/U3); `UserPromptSubmit.source` still rolling out (C3). Below it: `options` load floor 2.1.271 (C2), `onFailure: "block"` 2.1.295 ([claude] F) |
| Codex CLI | 0.166.0 | deny-only contract and fail-open paths source-cited at this tag (X1); unknown keys ignored (X4) |
| Cursor CLI / desktop | 2026.10.22 / 3.27.22 | shell deny/ask consumer source-cited (U1); desktop deny-only, pending S2 |
| Gemini CLI | 0.66.0 | G1–G3 measured |
| OpenCode | 2.2.5 | O1–O3 measured |

### D10 — Self-protection (j)

1. **Policy and guards are R4 `policy.edit`.** GSF denies Edit-class and parsed-Bash writes to the XDG config and
   state dirs, host plugin caches and guard files inside the running plugin root; in a source checkout guard files
   are R4 ask, not deny (contributors edit them).
2. **Hash and re-confirm (CVE-2025-54136 class, [P] §5.2):** a user file whose sha256 ≠ the lock, or a project file
   whose hash ≠ its trust entry, keeps its tightening entries and drops its widening ones until a human confirms.
3. **The agent never edits its own policy (CVE-2025-53773 class, [P] §5.1):** only the D6 writer writes, every
   widening needs a human-origin confirmation, and PG denies the host config CLIs.
4. **No mod `tool.check`, ever** — it can approve over a user deny ([claude] B) and the directory holds
   `MOD_ANSWERS_PERMISSION` ([mods]). **No `ctx.session.update` widening** (O2), **no Codex `PermissionRequest`
   allow**, **no Antigravity `auto_approve`**. A manifest test holds all four.
5. **Deny texts stop pointing at bypasses:** the workflow remedy "use the GitHub MCP `create_or_update_file`"
   ([`guard-sensitive-files.sh`][gsf], [A3] D3) becomes the R4 ask.

## Consequences (k)

**Easier:** one registry and one resolver replace three precedence lists; the default matches `safety.md`; every
level states what it does on every host, with no claim beyond the evidence; the GitHub MCP and Bash paths meet the
same ceiling; ADR 003's option pattern (`CLAUDE_PLUGIN_OPTION_*`, manifest default when unset) is reused unchanged.

**Harder:** `supervised` costs about six prompts per typical objective run, `standard` two ([A1] E).
`/plugin-config` is the first explicit-only skill (CLAUDE.md's "No skill is Explicit-only today" changes). Codex
and Cursor raises take two steps (flag, then `confirm <nonce>`): neither host gives the plugin a trustworthy ask.
Per-skill raises do nothing at L2 on Codex and Cursor (no observable skill activation); users there set action
overrides. Hook-run dependency installs stop being silent under `supervised` (`deps.install` is R2 m). Workflow
edits via MCP `create_or_update_file` (project memory `feedback-ci-yml-guard-hook`) give way to a human-approved
local edit, so that note goes stale. Option names (`permission_level`, `TS_PERMISSION_LEVEL`) become an interface,
as in ADR 003.

## Open risks

| risk | severity |
|---|---|
| A same-UID process that bypasses the Bash parser (`python3 -c`, `make`, [A3] D13) and rewrites both the policy and its lock is undetected | Medium |
| Text-level L2 cannot see inside interpreters or scripts (reproduced, [A3] D1); allows such as `Bash(python3 *)` widen that gap | High |
| Codex/Cursor prompt-hook provenance (non-user sources) unverified (U5, S3) | High until measured |
| A Gemini user "Always allow" (4.95) outranks the extension rules (source-cited inference, [gemini] B) | Medium |
| The active-skill context persists across turns until the next session or compaction | Low |
| MCP flags are fixed for the server's lifetime; a mid-session level change applies at L1/L2 only | Low |
| Codex plugin hooks run only after `/hooks` trust, re-required on every update ([codex] B2); until then only L1 + server flags apply | Medium |

## Implementation objective must…

1. Add `core/permissions/actions.json` (D1) and `core/schemas/permissions.schema.json` (D3); a test fails when a
   skill or script `gh`/`git`/MCP call maps to no id.
2. Add `scripts/resolve-permission.sh` (D4) with a table test per precedence row.
3. Change [`resolve-merge-policy.sh`][rmp]: delete step 5, demote `TAMIRS_AUTO_MERGE=always` and objective `true`,
   alias `.dev-files/policy.json`; make the [`pr-dev`][prdev] precedence block and [`deliver-dev`][deliver] Step 6
   cite the resolver. Update [`safety.md`][safety]'s auto-merge row to link this ADR and the R4 rule.
4. Add `hooks/permission-guard.sh`, a shell tokeniser lib shared with `hooks/lib/agent-claim.sh`, and `hook_ask` in
   `hooks/lib/hook-output.sh` (emits `ask` only on Claude); wire it in `hooks/hooks.json` (`onFailure: "block"`,
   MCP matcher), `platforms/codex/hooks.json`, `platforms/cursor/hooks.json` (`failClosed`),
   `platforms/gemini/policies.source.json` + `scripts/build-gemini-hooks.sh`, `platforms/opencode/plugin/{guard,rules}.ts`.
5. Extend `hooks/guard-sensitive-files.sh` `classify()` per D10; replace the MCP remedy there, in the Gemini policy
   text and in `platforms/opencode/plugin/rules.ts`.
6. Add the prompt-origin ticket hooks (D5) per platform and the `confirm` TTY path; make `scripts/github-mcp.sh`
   apply the D8 flags.
7. Add `permission_level` to `.claude-plugin/plugin.json` `userConfig` (string replace, never a JSON round-trip) and
   `TS_PERMISSION_LEVEL` to `gemini-extension.json`.
8. Create the `plugin-config` skill with `skill-creator` (explicit-only, D6), its writer `scripts/plugin-config.sh`,
   the Codex `agents/openai.yaml` policy and the OpenCode code command in `platforms/opencode/plugin/index.ts`;
   update CLAUDE.md's invocation tiers.
9. Add the TTY level prompt and the optional Codex execpolicy rules to `scripts/lib/setup-*.sh`.
10. Add L1 gates and fix the audit findings: `cleanup-after-merge.sh` (D-1), pr-dev `--admin` and `issue.close`,
    repo-scaffold `repo.create`, `enable-repo-merge-settings.sh` `--apply`, usage-capture, mcp-builder Phase 6,
    retro, capture-config `--adopt all`, skill-creator nested `claude -p` and port kill, the `docker-guard.py`
    inline token and `github-policy.sh` `GITHUB_POLICY_ALLOW_LIVE` (both → tickets).
11. Record D9 in `platform-targets.json` (then the pins) and the four widening levers in
    `core/capabilities/platforms.json`; document levels in `docs/user/configuration.md`; add this ADR to
    `docs/engineering/decisions/README.md`.
12. Extend `tests/test-manifest-invariants.sh` (fail-closed wiring; no `tool.check`, no `session.update` allow, no
    `PermissionRequest` hook) and add `tests/test-permission-guard.sh` with crafted stdin per host dialect,
    including the Codex fail-open cases.
13. Verify what is still unmeasured: Claude U1 (defaulted picker in the dialog), U2 (live `command_args`), U4
    (Desktop userConfig + hooks) ([S1]); Codex U5 (live fail-open, and whether `UserPromptSubmit` carries the
    prompt); Cursor S1–S4 ([S2]); `pluginConfigs` ignored in project settings; the Claude and Codex MCP matchers;
    the Gemini workspace `.env` reaching the hook env; OpenCode MCP action names.

## Alternatives rejected

- **Level names `strict/auto/bypass`** — collide with host modes and promise a host effect the plugin cannot have
  ([claude] implication 2, [P] §5.5).
- **Enforce through the mod's `tool.check`** — widens over user denies; directory hold ([A3] D4).
- **Hook `ask` as the universal verb** — fails open on Codex, hangs Gemini headless, auto-approved by OpenCode
  `--auto` (X1, G1, O1).
- **Per-skill levels in `userConfig` or `.dev-files/policy.json`** — `userConfig` is flat and per-user ([claude]
  C); `.dev-files/` is gitignored and agent-written. **A project file that widens silently** — the clone attack
  ([P] Steal: repo scope may only narrow).
- **OpenCode `session.update` for `--perms=`** ([opencode] implication 7) — overrides a config deny (O2). **Codex
  `PermissionRequest` auto-approve** — a widening ([codex] implication 4). **A sixth rubric class** — see D1.
- **Extend `protect-other-branches.sh`** — a concurrency guard by design ([`protect-other-branches.sh`][pob]);
  danger rules get their own fail-closed unit and tests, sharing its tokeniser.

[R]: ../research/permissions/README.md
[claude]: ../research/permissions/platforms/claude.md
[codex]: ../research/permissions/platforms/codex.md
[cursor]: ../research/permissions/platforms/cursor.md
[gemini]: ../research/permissions/platforms/gemini.md
[opencode]: ../research/permissions/platforms/opencode.md
[P]: ../research/permissions/platforms/prior-art.md
[S1]: ../research/permissions/spikes/claude-codex.md
[S2]: ../research/permissions/spikes/cursor-gemini-opencode.md
[A1]: ../research/permissions/audit/devflow-repo-skills.md
[A2]: ../research/permissions/audit/other-skills.md
[A3]: ../research/permissions/audit/non-skill-surfaces.md
[safety]: ../../../core/policies/safety.md
[git]: ../../../core/policies/git.md
[rmp]: ../../../skills/dev-workflow/pr-dev/scripts/resolve-merge-policy.sh
[prdev]: ../../../skills/dev-workflow/pr-dev/SKILL.md
[deliver]: ../../../skills/dev-workflow/deliver-dev/SKILL.md
[gsf]: ../../../hooks/guard-sensitive-files.sh
[pob]: ../../../hooks/protect-other-branches.sh
[docker]: ../../../hooks/docker-guard.py
[mcpsh]: ../../../scripts/github-mcp.sh
[sdefaults]: ../../../platforms/claude/settings.d/defaults.json
[mods]: ../architecture/mods.md
[targets]: ../build-and-release/platform-targets.json
