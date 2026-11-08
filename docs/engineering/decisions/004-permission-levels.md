# ADR 004 — Permission levels: presets, config, overrides and enforcement per platform

**Status:** Accepted — 2026-11-03

## Context

The plugin's skills push, open PRs, arm auto-merge, delete branches, create repositories and write global config;
today the only brakes are skill prose, one resolver and a concurrency guard. The research ([synthesis][R]), three
audits ([dev-workflow and repo skills][A1], [other skills][A2], [agents, scripts, hooks, mod, MCP][A3]) and an
adversarial [security review][SR] of this ADR found:

- **No host lets a plugin widen host permissions** ([R]; [claude], [codex], [cursor], [gemini], [opencode]), so the
  most autonomous level only removes the *plugin's own* gates. The levers that *can* widen are banned in D10.4.
- **Enforcement verbs differ per host** (D8): Claude honours a hook `ask` in every mode (measured headless C4/U3,
  [S1], and interactive M1, [S3]);
  Codex fails open on it (source-cited X1); Cursor `preToolUse` drops it, `beforeShellExecution` prompts interactively but is ignored under `--yolo` (measured S1, 2026-11-04)
  (source-cited U1); a Gemini hook `ask` hangs headless (measured G1); OpenCode `--auto` approves it (measured O1).
- **The agent can fake a typed prompt on every host:** it drives `/dev/tty` through `pty.fork()` (measured, [SR]
  S-01), and a nested headless host turns its text into the prompt hooks see (Gemini `-p` measured G2; [SR] S-02).
- **The shipped guards do not cover danger.** `protect-other-branches.sh`, a concurrency guard, allows force-push,
  remote delete, `branch -D`, `gh pr merge --admin` and `gh api -X DELETE/PUT …/protection` (reproduced, [A3] D1).
  GitHub MCP tools bypass every Bash-matched hook; [`github-mcp.sh`][mcpsh] passes no restriction flag ([A3] D3). The
  machine config sets `defaultMode: bypassPermissions` with broad allows ([`settings.d/defaults.json`][sdefaults],
  [A3] A), so hooks are the only enforcement there. Nothing protects policy, guards or host settings ([A3] D7, E).
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

**Rubric gap — local non-config effects** ([A2] A): a *mapping* with a `machine` tag (`m`), not a sixth class (one
more column everywhere, meaning only "R2/R3, but local"). Plugin-owned, session-scoped (loopback viewer, browser) ⇒
R1. Outside the worktree but owned and undoable by the plugin (its daemon by verified PID, a script-free lockfile
install) ⇒ R2. Not owned, or code the user never chose (a foreign PID, a model-named package, `docker run/pull`, a
foreign repo's script, lifecycle scripts) ⇒ R3. Persists into host config or trust, or forges a human signal (D5) ⇒ R4.

The catalog is one plugin-owned registry (`core/permissions/actions.json`, not user-editable); audit aliases fold
into the canonical id. L2 points: **PG** = new `hooks/permission-guard.sh` on Bash/Shell (and its Gemini/OpenCode
ports), **MCP** = GitHub MCP tool matcher + server flags (D8), **GSF** = [`guard-sensitive-files.sh`][gsf] path rules.

| id (aliases) | R | where (audit evidence) | L2 point · unattended precondition |
|---|---|---|---|
| `repo.read` (`mcp.read`, gh view/api GET), `net.get` (`net.get.docs`), `secrets.read.config`, `env.read.names` | R0 | all skills ([A1] C, [A2] C) | none |
| `file.write.repo` (`fs.state.write`, `scaffold.local.write`, `file.overwrite.nocheck`, `objective.set_delivery`) | R1 | most skills | `enforce-worktree-edits.sh` |
| `git.commit` (`git.commit.local`), `git.branch.create`, `git.index.untrack`, `git.merge.local`, `git.rebase.own`, `git.sync.ff`, `git.worktree.add` (`.move`), `worktree.remove` (clean and pushed), `worktree.cleanup` (auto) | R1 | worker, orchestrate, cleanup, capture-config, resolve-worktree, session-init ([A3] B3) | none |
| `branch.delete.local` (`git.branch.delete.local`); R3 if unmerged with no remote copy | R1 | cleanup-after-merge ([A1] D-1) | PG |
| `fs.build_dirs.delete` (gitignored, regenerable only) | R1 | cleanup | `cleanup.sh` guard |
| `work.discard` (`git clean`, `checkout --`, `restore`, `stash drop`/`clear`, `reset --hard` other than `git.reset_to_remote`) | R1; R4 if it drops unpushed commits; deny over uncommitted changes | none intended ([SR] S-14) | PG · [safety] invariant 4 |
| `agent.spawn` (`subagent.spawn`, the host's own subagent tool): the child runs at the caller's ceiling, never higher | R1 | orchestrate, skill-creator | none |
| `server.local.start`, `browser.open`, `code.exec.repo_script` (this worktree) | R1 m | skill-creator, docs-review ([A2] C) | none |
| `git.push.branch` (own, non-default) | R2 | deliver, start, pr-dev, switch ([A1] C) | PG |
| `pr.create`, `pr.comment`, `pr.review_request`, `ci.rerun`, `pr.update_branch`, `pr.thread.resolve` (threads the agent answered) | R2 | pr-dev, deliver ([A1] C) | PG, MCP |
| `issue.create`, `issue.comment`, `issue.edit` (`issue.edit.resume`), `label.create`/`.edit`, `label.apply` (`github-labels.sh apply`: create + update the canonical set), `copilot.assign` | R2 | plan-dev, switch-dev, github-labels ([A1] C, [A3] B5) | PG, MCP |
| `file.write.remote` on a non-default branch (`create_or_update_file`, `push_files`, `delete_file`) | R2 | MCP ([A3] B5) | MCP |
| `notify.send`, `net.post.external`, `secrets.collect.chat` | R2 | notify-setup ([A2] F7) | L1 only |
| `daemon.start`/`.stop` (plugin-owned, PID verified), `deps.install` (lockfile, own worktree) with lifecycle scripts off (npm, pnpm, yarn, bun `--ignore-scripts`; `cargo fetch`) | R2 m | usage-capture, session-init ([A2] F1, [A3] D9) | L1; a hook never installs, it prints the command ([SR] S-08) |
| `pr.merge.auto` (`pr.auto_merge.enable`) | R3 | pr-dev ([A1] D-5) | PG · ≥ 1 required check with a pinned source (ruleset `integration_id`, classic `app_id`) or ≥ 1 required approving review, and the PR touches nothing under `.github/workflows/**`, `CODEOWNERS` or `.tamirs-superpowers/**` (GitHub behaviour inferred, [SR] S-13) |
| `pr.merge` (direct; MCP `merge_pull_request`) | R3 | pr-dev, MCP ([A3] D3) | PG, MCP · none (never automatic) |
| `branch.delete.remote`; R4 with unmerged commits | R3 | pr-dev, cleanup ([A1] D-1, D-6) | PG · PR `MERGED`, not base/default, not cross-repo |
| `pr.close`, `issue.close` | R3 | pr-dev ([A1] D-10) | PG, MCP · own PR or `Closes #N` of a merged PR |
| `git.push.default` (`git.push.default_branch`) | R3 | none intended ([A1] D-11) | PG · none (never automatic); denied when protected ([safety] invariant 5) |
| `git.push.force` (`git.force_push`; own, non-default branch) | R3 | none executes it ([A1] D-11; enforced on 2 of 5 hosts, [A3] D2) | PG · `--force-with-lease` and own claim ([git] "no force-push to base") |
| `pr.review.approve`, `pr.thread.resolve` (others' threads), `file.write.remote` on the default branch, `repo.settings.merge`, `file.write.outside_repo`, `handoff.force`, `commit.status.write`, `check_run.write`, `label.delete` (`github-labels.sh apply --prune`; strips the label from every issue that carried it) | R3 | MCP, pr-dev, repo-scaffold/-standards, retro, github-labels ([A1] D-4, D-7, D-13; [A2] F3; [SR] S-13) | PG, MCP · none (never automatic) |
| `process.kill` (`process.kill.port`, unverified PID), `pkg.install.network`, `pkg.exec.network`, `docker.state` (run/build/pull/up/prune), `code.exec.foreign_repo` (incl. every install with lifecycle scripts on, `uv sync`, `bundle install`) | R3 m | skill-creator, mcp-builder, docker-guard, session-init ([A2] F5/F6/F8, [A3] B3) | PG · pinned lockfile only for `pkg.*`; otherwise none (never automatic); never run by a hook |
| `git.verify.skip` (`--no-verify`, `-n`, `-c core.hooksPath=/dev/null`, `HUSKY=0`, `SKIP=`) | R4 | none intended ([SR] S-14) | PG · [safety] invariant 6: only the D5 host prompt grants the one-off |
| `pr.merge.admin` | R4 | pr-dev ([A1] D-2) | PG; denied while a required check fails or is pending ([safety] invariant 2) |
| `git.push.force.default` (`git.force_push.default`), `release.create`, `tag.push` (`git.tag.create`) | R4 | none today ([A3] D1, C) | PG |
| `process.spawn.agent_host` (`process.spawn.claude_cli`): `claude`, `codex`, `gemini`, `opencode`, `cursor-agent`, `agy`, headless or not, also via `npx`, `bunx`, `pnpm dlx`, `node …/cli.js`; `tty.drive`: `script`, `expect`, `unbuffer`, python/node `pty`, `tmux send-keys`/`paste-buffer` (after any global option such as `-L`/`-S`/`-f`), `cmux send`/`send-key`, `wezterm cli send-text`, `kitty @ send-text`, `zellij action write`, `screen -X stuff`, `osascript` (`keystroke`, `do script`, `write text`), `xdotool` (list: [S3] Impact 4) | R4 m | skill-creator nested `claude -p` ([A2] F5); `tty.drive`: none intended | PG; both can forge a typed prompt or answer a TTY or host prompt (D5; [SR] S-01, S-02) |
| `repo.create` (incl. `fork_repository`), `repo.delete` | R4 | repo-scaffold, MCP ([A1] D-3, [A3] B5) | PG, MCP, server exclusion |
| `ruleset.apply`, `ruleset.apply.org`, `branch_protection.write` (apply, remove, legacy shim) | R4 | github-policy, repo-* ([A1] D-8/D-9) | PG (script names, `gh api …/protection`) |
| `workflow.edit` (remote), `file.write.remote` to workflows, hooks or policy | R4 | A local workflow edit is ordinary source since 5.6.7 (the user's decision of 2026-11-06); the remote write is still R4 | MCP |
| `config.global.write` (incl. `git config alias.*`/`core.hooksPath`, `.git/hooks/**`, `gh alias set`), `config.policy.stage`, `secrets.capture.bodies` | R4 | setup/install, usage-capture, mcp-builder, retro, capture-config ([A2] F1–F4, [A3] D11) | PG (script names), GSF |
| `policy.edit` (`plugin.permission_policy.edit`): permission files, lock, tickets, guard scripts, installed caches, host settings and option stores (D10), `claude plugin configure`, `gemini extensions config` | R4 | any write ([A3] D7, E) | GSF + PG deny; only the D6 writer, through D5 |
| `worktree.remove.force`, `worktree.drop`, `git.reset_to_remote` that discard uncommitted or unpushed work | R4 | pr-dev script, cleanup ([A1] D-1, D-6) | PG; [safety] invariant 4 |
| `fs.delete.tree`: a recursive `rm` of `/`, a top-level directory, the home directory or one of its direct children, or a git repository's root | R4 | none intended | PG |

**Host bypass (2026-11-06).** When Claude Code itself runs with `bypassPermissions`, the user has chosen not to be
asked. `permission-guard.sh` then lets every ask through except the catalog's `host_bypass.still_ask` list:
`repo.delete`, `fs.delete.tree`, `git.push.force.default`, `git.reset_to_remote`, `worktree.drop`,
`worktree.remove.force` — the operations that cannot be undone. Plugin-config confirms and every other host
are unchanged. The user's decision, recorded with the change (5.6.5). Since 5.6.7 a level's deny steps aside as
well, except a `still_ask` id, `policy.edit`/`config.global.write` and a command too long to read, and three more
guards honour the mode: `docker-guard.py` (a prune still asks), `guard-sensitive-files.sh` (its generated-file
rules; the protected paths hold) and `protect-other-branches.sh` (work claims).

**`none` means never automatic** ([SR] S-06): such an action asks at every level. Under `unattended` only
`pr.merge.auto`, `branch.delete.remote`, `pr.close`, `issue.close`, `git.push.force` (own branch, with lease) and
`pkg.*` with a pinned lockfile run without asking.

**Equivalents** ([SR] S-07): `actions.json` lists, and PG implements and tests, every form that reaches an id — the
REST paths, GraphQL mutations, refspecs, target env (`GH_REPO`, `GH_HOST`, `GIT_DIR`, `GIT_CONFIG_*`) and GitHub API
HTTP clients [SR] S-07 enumerates. A command mapping to no id but carrying a mutation marker (`gh `, `git push`,
`api.github.com`, `graphql`, `gh auth token`, `GH_TOKEN`, `GITHUB_TOKEN`, a protected path) or a file-sourced GraphQL
query (`-F query=@…`) is UNCLASSIFIED ⇒ R4. A non-GET call to a GitHub API host is classified only when its method,
path and body are all established — read through one table-driven argv model per HTTP client and a GraphQL parser
(issue #349) — and anything unestablished (an unknown option or target, a route override, a body from a file, stdin or a
template, a client config file, a dot segment or escape in the path, an undecodable body the id depends on) is
UNCLASSIFIED. Wrappers (`make`, `eval`, `$(…)`) and interpreters stay the residual.

### D2 — Level presets are ceilings (b)

| rubric | `supervised` (default) | `standard` | `unattended` |
|---|---|---|---|
| R0, R1 | allow | allow | allow |
| R2 | ask | allow | allow |
| R3 | ask | ask | allow **iff** the id is on the D1 automatic list and its precondition holds, else ask |
| R4 | ask on a host prompt (D5), per call, naming the target | same | same — never automatic |
| explicit `deny`, [safety] invariants | deny | deny | deny |
| `pr.merge.auto` | ask | ask (= off) unless `actions["pr.merge.auto"]: "allow"` in the user file or a trusted project file | allow iff its D1 precondition holds |

- **Auto-merge means `gh pr merge --auto` only**, so GitHub protection decides ([P] Steal table); the plugin never
  performs a direct `pr.merge` automatically.
- **No human present ⇒ ask becomes deny** plus the setting that would allow it: the once-only route (`--perms=`,
  where D5 lists a host prompt) and the durable one (D6); for R4, that no setting allows it automatically. Claude hook
  `ask` and Gemini static `ask_user` deny headless themselves; elsewhere the plugin delivers the ask as a deny (D8).
- A level governs the plugin, never the host: `unattended` does not stop host prompts ([R] "The one fact").

### D3 — Config: one user file, one project file, option stores hold only the preset (c)

**User file (canonical):** `<home>/.config/tamirs-superpowers/permissions.json` (0600) beside `permissions.lock`
(`{sha256, by, at}`, D6 writer only); short-lived state (tickets, pending records, call stamps) in
`<home>/.local/state/tamirs-superpowers/`, because Codex skills never see `PLUGIN_DATA` ([codex] C). **`<home>` comes
from the passwd entry (`~$(id -un)`), never the session's `HOME` or `XDG_*`**, which a repo's `.claude/settings.json`
`env`, a trusted Gemini workspace `.env` or a Cursor `sessionStart` hook can set ([SR] S-04). Every reader requires
owner = uid, 0600 files, 0700 dirs, no group or world write on a parent and a realpath outside every git work tree.
**Env switches only tighten:** `PM_ALLOW_*`, `TAMIRS_*`, `SUPERPOWERS_*`, `CLAUDE_PLUGIN_OPTION_*`, `TS_PERMISSION_LEVEL`.

Rejected ([R] "Design conclusions" 1): `${CLAUDE_PLUGIN_DATA}` (Claude only, deleted on last uninstall, [claude] C,
X2); Cursor/Gemini plugin dirs (replaced on update, [cursor] C, [gemini] C); OpenCode `ctx.storage` (SQLite, O3);
`~/.claude/…` (host config, [A3] D7); option stores (flat strings; X4, U3).

**Option stores hold only the preset:** Claude `userConfig.permission_level`, Gemini `TS_PERMISSION_LEVEL`. A raise
from either is read from the user-scope file that stores it (`<home>/.claude/settings.json` `pluginConfigs`, the
extension dir's `.env`), never from env (a workspace `.env` can hold it too, [gemini] C). Codex, Cursor and OpenCode
have none; OpenCode `ctx.options` is ignored because a project `opencode.json` could set it ([opencode] C).
**Effective level = the lower of the option store and the user file `level`; neither ⇒ `supervised`.** A source
that is absent (no option store on that host, or a user file with no `level` key) is *skipped*, not read as
`supervised` — so a Claude install-picker choice of `unattended` with no user file yields `unattended`, while store
`unattended` + file `standard` yields `standard`. A Claude project-scope install carries no preset (`pluginConfigs`
is user/managed scope, doc-cited [claude] C). A user-file `skills`/`groups` level replaces the file's `level` for that
skill, and then the option store and every env switch **lower again** (lowering always wins:
`TS_PERMISSION_LEVEL=supervised` tightens a skill with its own entry; second pass F10). The store read is that of the
host the resolver runs under: `--host` is a claim, and when the nearest agent host in the resolver's own process
ancestry differs, the stricter of the two answers stands, both D9 floors apply and no raise ticket applies (F7), so a
claim never skips a store.

**Project file:** `<repo>/.tamirs-superpowers/permissions.json` (committable; `.dev-files/` is gitignored). It may
always tighten. **It may widen only `actions["pr.merge.auto"]`**, only once `/plugin-config trust` records its sha256
under the repo's realpath (shared by its worktrees) in the user file, and only for actions whose target repo equals
both the entry's `remote` and the checkout's origin ([SR] S-15). A changed hash or a new clone ⇒ widening ignored
with a notice. An invalid file ⇒ `supervised`, overrides ignored, warning (fail closed).

```json
{ "version": 1, "level": "standard", "skills": { "pr-dev": "unattended" }, "actions": { "pkg.install.network": "deny" },
  "trust": [ { "repo": "/Users/you/src/app", "remote": "github.com/you/app", "file": ".tamirs-superpowers/permissions.json", "sha256": "<64 hex>", "widens": ["pr.merge.auto"], "at": "2026-11-03T10:00:00Z" } ] }
```

| field (JSON Schema `core/schemas/permissions.schema.json`) | type · constraint | user | project |
|---|---|---|---|
| `version` | integer, const 1 | required | required |
| `level` | enum `supervised` · `standard` · `unattended` | optional | optional, tighten only |
| `groups.<g>` | `{level, skills[]}`; `g` ∈ skill categories (`dev-workflow`, `repo`, `toolkit`, …); `skills` is a snapshot — a skill added to the group later gets a group *raise* only after re-confirmation ([P] §5.6) | optional | optional, tighten only |
| `skills.<id>` | level enum; `id` ∈ shipped skills | optional | optional, tighten only |
| `actions.<id>`, `skill_actions.<skill>.<id>` | enum `allow` · `ask` · `deny`; `id` ∈ catalog; R4 ids accept only `ask` · `deny` | optional | optional; `allow` only for `pr.merge.auto` |
| `trust[]` | `{repo, remote, file, sha256 (^[0-9a-f]{64}$), widens[], at}`; `widens` ⊆ `["pr.merge.auto"]` | optional | forbidden |
| everywhere | `additionalProperties: false`, ASCII only | | |

### D4 — One precedence chain, one resolver (d)

`scripts/resolve-permission.sh <action-id> [--skill s] [--target t] [--objective id] [--call n]` prints `{decision,
r, level, level_source, decided_by, allow_with, warnings}` and is the only implementation: hooks (L2),
[`resolve-merge-policy.sh`][rmp] (for `pr.merge.auto`; it keeps computing capability, protection and merge method),
pr-dev and deliver-dev (L1, quoting `decided_by`) and `/plugin-config show` all call it. [`deliver-dev`][deliver]
Step 6 drops its own list and reports the resolver's source.

| # (highest first) | input | may widen? | migration of the legacy input |
|---|---|---|---|
| 0 | [safety] invariants, R4-never-automatic, repo capability (auto-merge disallowed, protection) | never | resolver rule 4 kept as is |
| 1 | `--perms=` ticket (D5) | lower always; raise only through a D5 host prompt | new |
| 2 | `TAMIRS_AUTO_MERGE` | `never` tightens; `always` is ignored with a warning naming `/plugin-config pr.merge.auto allow` (an agent can type an env prefix, [A3] D5) | rule 1 demoted |
| 3 | objective `delivery.auto_merge` | `false` tightens; `true` records the resolved decision, never grants (state is agent-written) | rule 2 demoted |
| 4 | project file | tighten always; widen `pr.merge.auto` only if trusted (D3) | `.dev-files/policy.json` `delivery.auto_merge` is read **tighten-only** (`false` ⇒ `actions["pr.merge.auto"]: "deny"`; `true` is ignored with a warning naming the trusted-file route) for one minor release, then removed — it is gitignored and agent-written, so it can never carry a trust entry |
| 5 | user file: `skill_actions` > `actions` > `skills` > `groups` | yes (user-authored, hash-locked) | — |
| 6 | level = lower of option store and user file `level` | — | — |
| 7 | default `supervised` | — | rule 5 ("enable when the repository allows") deleted |

Combination: start from the ceiling (6–7), apply 5 (the most specific key present decides between allow and ask),
then 4 → 0, where tighten-only inputs move only toward deny. **Any `deny` from any layer is final. R4 never becomes
allow:** only the host prompt on that very call (D5) passes it; no ticket, file or env does. **Resolver failure is a
deny** ([SR] S-12): if it is missing, exits non-zero, prints invalid JSON or lacks `jq`/`gh`, PG denies R2 and above
and L1 stops; a precondition it cannot establish (`unknown`) never holds.

### D5 — Human channels and the `--perms=<level>` ticket (e)

No host parses `--perms=`; it is prompt text ([R] conclusion 5). **A channel is human only if the host attests the
human origin and nothing reachable from the agent's own tools produces it.** Not human: `/dev/tty` (driven through
`pty.fork()`, `expect`, `script`; measured, [SR] S-01), keys sent to a terminal, any file, and any prompt a prompt
hook sees, since a nested agent host, headless or on a pty, delivers model text as a typed prompt ([SR] S-02; G2's
interactive run was itself pty-driven). A prompt hook only **requests**: on a user-typed prompt it writes a pending
record `{nonce, skill, level, target, session_id, agent}`; a ticket exists only once `scripts/plugin-config.sh
confirm <nonce>` passes a host prompt naming skill, level, target and expiry.

| platform | host-attested channel (raise, D6 widening, R4) | prompt hook that writes the pending record | evidence |
|---|---|---|---|
| Claude Code | the permission dialog of a PG hook `ask`, on `confirm` or on the R4 call itself | `UserPromptExpansion.command_args` of a prompt whose `UserPromptSubmit.source == "user"` (paired on their shared `prompt_id`); missing `source` ⇒ not user; a model `Skill` call never qualifies. **2.1.318 sends no `source` at all, so no raise request is ever written: the Claude `--perms=` raise is disabled until the host emits it** (the refusal says so and names `/plugin-config`); a lowering still applies | dialog: measured headless C4/U3 (honoured in every mode, headless ⇒ deny) and interactive M1 ([S3]: `default`, `auto`, `bypassPermissions`; the reason shown verbatim, multi-line too, with its origin label; `1. Yes` pre-selected, `2. No`; Esc rejects and the call never runs). Prompt hooks: M2 (`command_name`, `command_args`, `command_source: "plugin"`; the submit fires first, same `prompt_id`); `source` declared in the schema but absent in the interactive CLI, `-p` and stream-json (M3) ⇒ never attested |
| Gemini CLI | a static extension `ask_user` rule matching `confirm` and the R4 patterns | interactive `BeforeAgent.prompt` right after `BeforeTool(activate_skill)` | `ask_user` holds under `--yolo` and denies headless (measured G3); its TTY prompt source-cited. Hook input cannot tell `gemini -p` (G1, G2) |
| Cursor CLI | **none**: S1 (measured 2026-11-04, CLI 2026.10.22) showed `beforeShellExecution` `ask` prompts interactively but is ignored under `--yolo`, and print mode is inconclusive (a no-hook control is rejected the same way), so it is not a host-attested channel | none: `beforeSubmitPrompt` also sees `cursor-agent -p` text | U1, S1–S3 ([S2]) |
| Codex CLI, Cursor desktop, OpenCode | **none: the raise path is disabled.** Codex hook `ask` fails open (X1) and plugins cannot ship execpolicy rules ([codex] A6); Cursor desktop carries a shell ask from 3.28.7 (S2) but not the confirm a raise needs (D8: its Allowlist card shows no reason); OpenCode `--auto` approves every pending ask client-side (O1) | none: `codex exec`, `cursor-agent -p` and `opencode run` author the prompt | X1, O1, [SR] S-02/S-10 |

**Where no channel exists**, `--perms=` only lowers; levels change only outside any agent session (the writer in the
user's own terminal — PG denies its widening subcommands and `confirm` from agent Bash —, `make setup`, CI
`provision`), and an R4 call is denied with the command for the user to run. The Codex/Cursor chat-confirm is
removed: their hooks cannot tell typed text from `codex exec resume` or `cursor-agent -p` ([SR] S-10).

**"Outside any agent session" is checked, not inferred from an empty ancestry** (second pass F1): the writer widens at
once only when no agent host or marker is visible, its ancestry reads to pid 1, it is not reparented (its session
leader is an ancestor and nothing up to it is a child of pid 1: `( cmd & )`, `nohup`, `setsid` after a double fork
fail), it has a controlling terminal, `HOME`/`PATH`/`TERM` are set (`env -i` fails) and no pty driver or interpreter
runs above it; then it shows the rows on `/dev/tty` and writes only after `y`. Any other run is `unverified`, a
no-channel session. A TTY and that `y` are still no human proof (S-01): the rules keep agent routes out, the prompt
makes a stray run show what it widens. `provision` keeps CI's shape (no TTY, a CI marker, the session-leader rule
relaxed for a CI service) and never replaces a file it did not write.

**On Claude Code the proof is the host running the approved call, not the dialog being shown** (F1): PG's confirm
stamp `asked/<nonce>.json` is written when PG *returns* `ask` and names the call's `tool_use_id`. `confirm`, running
inside that call, consumes the stamp and only **stages** its result (`staged/<nonce>.json`, bound to the stamp's
`tool_use_id`, session and agent); the resolver never reads a staged record and honours a raise ticket only with
`state: "active"`. `hooks/permission-approved.sh`, a Claude PostToolUse hook on `Bash`, promotes it — writes the
user file and lock, or the raise ticket as active — only when its payload's `tool_use_id`, `session_id` and agent
equal the staged record's and the command is exactly the plain `plugin-config.sh confirm <nonce>`. Claude Code runs
PostToolUse only for a call that ran: a declined dialog never runs the call, so nothing is promoted; a confirm re-run
later through a form PG misses has another `tool_use_id` and is not the plain form, so it is never promoted; a staged
record lapses with the stamp (15 minutes). Gemini's `confirm` stays one-phase (its static `ask_user` rule is the
prompt, and no post-call binding is wired): Open risks.

| ticket rule | text |
|---|---|
| shape | `{id, skill, target, level, session_id, agent, created, expires}`: one skill, one target (first argument + repo slug; `actions.json` defines equality per action kind, and an unresolvable target never matches), 15 minutes; written only by the D6 writer, GSF denies every other write |
| R2/R3 only ([SR] S-05) | no ticket satisfies R4: it passes only on the host prompt of that very call, which shows the id, the target and the effect (head SHA, failing or pending required checks) |
| main thread ([SR] S-11) | binds `(session_id, agent)`; honoured on main-thread calls unless the orchestrator has the writer re-issue it to a named task. Claude Code's hook input carries `agent_id` (and `agent_type`) on every subagent call and on no main-thread call (measured M5, [S3]), so a main-thread ticket never reaches a subagent |
| never from content | file, PR, issue or tool output never reaches a prompt hook; L1 ignores `--perms=` there; hooks parse it only as a standalone token on the first line of `command_args` |
| lowering ([SR] S-09) | needs no provenance: prompt hooks write lowering tickets and PG applies them for the session; L1 parsing is the fallback where no prompt hook exists. A later confirmed raise does not retire it (D4 row 1 lowers always); `show` and `--level` list the active ones, and the writers prune expired tickets |
| mechanics ([SR] S-17) | nonce ≥ 64 bits from `/dev/urandom`, bound to its pending record's hash and expiring with it; single-use records consumed by atomic `rename`; readers hash and parse the same bytes, read once |
| two-phase (F1) | on Claude Code `confirm` stages, bound to the dialog's `tool_use_id`, and only that approved call's PostToolUse promotes; a raise ticket counts only with `state: "active"` |

Tickets replace the agent-typeable approval token of [`docker-guard.py`][docker] ([A3] D5).

### D6 — `/plugin-config` (f)

```text
/plugin-config show | <level> | <skill|group> <level> | <action-id> [<skill>] allow|ask|deny
/plugin-config reset [<skill|group|action-id>|all] | trust (this repo's project file) | confirm <nonce>
```

- **Explicit-only where the host supports it:** Claude and Cursor `disable-model-invocation: true` (on Claude it
  also blocks subagent invocation, wanted here); Codex `policy.allow_implicit_invocation: false` ([codex] D);
  OpenCode a code command via `ctx.command.transform`, no model in the loop ([opencode] implication 6). Gemini has
  no such flag ([gemini] D): the `ask_user` rule on `confirm` is the gate there.
- **Deterministic writer:** every write goes through `scripts/plugin-config.sh` — schema validation, `jq -S` with
  fixed indent, atomic tmp + `mv`, 0600, `.bak`, lock rewrite. `show` prints each value's source and hash status.
- **Anti-escalation:** the writer diffs every action's effective decision before and after. A change that widens
  nothing is written at once. One that widens anything (including `reset` of a deny and `trust`) is recorded pending
  with its rows and a nonce, and written only by `confirm <nonce>` passing a D5 host prompt that shows them — on
  Claude Code in two phases, staged by the approved call and promoted by its PostToolUse (D5) — or, where D5 lists
  none, by the writer run outside any agent session as D5 defines it, after `y` on `/dev/tty`. It never writes R4
  `allow` or host option stores; a Claude/Gemini level raise prints the host route (`/config`, `/plugin configure`;
  `gemini extensions config`).
- **CI** ([SR] S-18): `plugin-config.sh provision` writes the file and lock in a workflow step before the agent
  starts; PG denies it from agent Bash, it requires a CI marker and an unbroken session (D5), it never replaces a file
  whose lock is not `by: provision`, and `show` marks such a lock `by: provision`.

### D7 — Install and later change (g)

| platform | at install | later | no config |
|---|---|---|---|
| Claude Code | `userConfig.permission_level`: `type: string`, `options: ["supervised","standard","unattended"]`, `default: "supervised"` (plain strings, default ∈ options; reported "not yet set" until stored — measured C1/C2) | `/config` picker (CLI only, [claude] E), `/plugin configure`, `claude plugin configure --values-stdin` in the user's terminal (PG denies it from agent Bash); Desktop: none — "Add to this computer" installs with no `userConfig` dialog and offers no Configure entry, and with nothing stored the hook env carries no `CLAUDE_PLUGIN_OPTION_*` (measured U4, [S3]), so Desktop runs at the no-config level; whether its embedded Claude Code reads a value the CLI stored is untested | `supervised` |
| Gemini CLI | `settings[]` `TS_PERMISSION_LEVEL` (string only, prompted unless `--skip-settings`, [gemini] C) | `gemini extensions config tamirs-superpowers TS_PERMISSION_LEVEL`; not in the enum ⇒ `supervised` + warning | `supervised` |
| Codex, Cursor, OpenCode | none ([codex] C; [cursor] C; [opencode] C) | `/plugin-config` tightens in session; a widening runs `scripts/plugin-config.sh` in the user's own terminal, `make setup` (asks once on a TTY) or CI `provision` | `supervised`; one SessionStart notice |

### D8 — Enforcement matrix (h)

Layers: **L1** skill gate (resolver call before the step), **L2** hook deny, **L3** host-native ask. **E** = ENFORCED,
**A** = ADVISORY. L1 is advisory everywhere (OWASP LLM06, [P] §5.7). The neutraliser column is design, not today.

| platform | L2 shell (R2–R4) | L2 GitHub MCP | L3 host ask | ask is delivered as | fail-open neutralised by | per-skill levels at L2 |
|---|---|---|---|---|---|---|
| Claude Code | E: PG on `Bash`, `onFailure: "block"` | E: the `mcp__plugin_tamirs-superpowers_github__.*` matcher fires for the bundled server's tools and a sibling matcher does not (measured M4, [S3]) + server flags | E: hook `ask` in default/auto/bypass, reason shown verbatim, Esc rejects (measured M1, [S3]); headless ⇒ deny (C4/U3) | hook `ask` (the D5 dialog; the only R4 route) | `onFailure: "block"` (2.1.295+) | E: a skill the host records as active for that agent takes its level from the user's verified, locked file — a `UserPromptExpansion` paired with its `UserPromptSubmit` on one `prompt_id` (M2), or a `PreToolUse` on the `Skill` tool (measured M6, [S3]: the matcher fires for a model `Skill` call, `tool_input.skill` names it); no `source` needed (M3). Bound per agent (M5): a subagent runs at most at the main thread's level (D1 `agent.spawn`); project-file levels only tighten |
| Claude Desktop | hooks run (a project `PreToolUse` and a plugin `SessionStart` fired, measured U4, [S3]); `deny` not exercised | server flags | E: a `PreToolUse` hook `ask` raises Desktop's "Allow Claude to run this command?" card, reason verbatim, Deny / Allow once, under Bypass permissions too; Deny stops the call (measured U4, 2026-11-04, Desktop 4.16336.0 with embedded Claude Code 2.1.317, a project-settings hook; a plugin-shipped `PreToolUse` `ask` not run separately) | as CLI: hook `ask`; the call stamp (below) stays as defence in depth | call stamp; else L1 runs `supervised` | A |
| Codex CLI | E, deny only: exit 2 + stderr, or `deny` with reason (source-cited X1; live U5) | MCP-tool hook actions (0.148, [codex] E) matcher unverified ⇒ server flags | none: hook `ask` fails open (X1) | deny naming the D5 out-of-session route; R4 always deny | guard traps every error to a deny, never exits non-0/2; SessionStart canary self-test; `setup.sh` offers user-owned execpolicy `prompt` rules for R4 as a belt while plugin hooks are untrusted ([codex] implication 10) | A |
| Cursor CLI | E: `preToolUse` + `beforeShellExecution` deny, `failClosed` (source-cited U1) | E: `preToolUse` deny on the MCP path (source-cited U1.4) | `beforeShellExecution` ask prompts interactively, ignored under `--yolo` (measured S1) — not relied on | deny (S1 confirms: an ask cannot be trusted to survive `--yolo`); PG tells the CLI by its dated `cursor_version` (`2026.…`) | `failClosed: true` | A |
| Cursor desktop | E: `preToolUse` + `beforeShellExecution` deny, `failClosed`; the shell tool runs `preToolUse` and then, unless it denied, `beforeShellExecution` in one wrapper (source-cited, `cursor-agent-exec` in 3.28.7) | as CLI (`preToolUse` deny on `MCP:<tool>`), unverified | E from 3.28.7: a `beforeShellExecution` `ask` is an approval card in Auto-Review, Allowlist and Run Everything, which runs only on Run; a `preToolUse` `ask` is ignored (S2, measured 2026-11-04, Cursor 3.28.7, [S3]) | ≥ 3.28.7: every shell ask, R4 included, is a `beforeShellExecution` ask, and PG's `preToolUse` Shell answer for it is no decision so that hook is reached; a `plugin-config.sh confirm` stays a deny (the Allowlist card shows no reason text, so the D5 record cannot be shown, S2); below 3.28.7, unreadable, or MCP: deny | `failClosed: true` | A |
| Gemini CLI | E: BeforeTool deny, never `ask` (hangs headless and hook input cannot tell headless, G1); paired static extension `deny` | static extension rules on `mcpName = "github"` (unmeasured) + hook | E: static mode-less `ask_user` for R4 patterns and `confirm` (headless deny under `--yolo` measured G3; TTY prompt source-cited) | deny; R4 and `confirm` via static `ask_user`, other R4 deny | static policy pairs every must-hold rule (hooks fail open, [A3] D8) | E: `BeforeTool(activate_skill)` |
| OpenCode | E (sole plugin): `permission.hook("evaluate")` deny, final under `--auto` (O1b); order across plugins unmeasured ([SR] S-16) | MCP calls are `<server>_<tool>` actions (doc-cited, [opencode] A), unmeasured | A: hook `ask` auto-approved under `--auto` (O1c) | R2: hook `ask` (A under `--auto`); R3/R4: deny | `guard.ts` catches every error as deny | E: `skill` action |

Antigravity is not a target; its hooks accept `allow`/`auto_approve` ([gemini] E), so if wired it is deny-only.
**Call stamp** (replaces a per-platform heartbeat, [SR] S-12): L1 calls the resolver with `--call <random>`; PG,
deciding that Bash call, stamps `<state>/seen/<random>`; the resolver consumes it and, finding none, answers as
`supervised`. PG gives every network lookup a deadline well under the host timeout and denies when it expires.

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
The resolver applies it with `--host`: the version is the host CLI's `--version` on PATH, as `doctor.sh` reads it
under the same 3 s deadline, probed only when an answer would be looser than `supervised`'s and cached per session
for 10 minutes; the clamp is named in each answer it changes and in `--level`. The guard's fast path never probes.

| platform | minimum | the feature that forces it |
|---|---|---|
| Claude Code | 2.1.317 | hook `ask` honoured under bypass and headless deny measured here (C4/U3), the interactive dialog on 2.1.318 (M1); `UserPromptSubmit.source` declared but not emitted on 2.1.318 (M3). Below it: `options` load floor 2.1.271 (C2), `onFailure: "block"` 2.1.295 ([claude] F) |
| Codex CLI | 0.166.0 | deny-only contract and fail-open paths source-cited at this tag (X1); unknown keys ignored (X4) |
| Cursor CLI / desktop | 2026.10.22 / 3.27.22 | shell deny/ask consumer source-cited (U1); desktop deny-only below 3.28.7, the build where a `beforeShellExecution` ask was measured to hold in every run mode (S2, measured 2026-11-04, Cursor 3.28.7) |
| Gemini CLI | 0.66.0 | G1–G3 measured |
| OpenCode | 2.2.5 | O1–O3 measured |

### D10 — Self-protection (j)

1. **Policy, guards and host config are R4 `policy.edit`** ([SR] S-03). GSF denies, with no `PM_ALLOW_PROTECTED`
   bypass, Edit-class and parsed-Bash writes to the D3 dirs, host plugin caches, guard files in the running plugin
   root (R4 ask in a source checkout, where contributors edit them) and host settings: Claude
   `{~,<repo>}/.claude/settings*.json`; Gemini `~/.gemini/{settings.json,policies/**}`,
   `<repo>/.gemini/{settings.json,policies/**,extensions/**}`, the
   extension `.env`; Codex `~/.codex/{config.toml,hooks*,rules/**,plugins/**}` (a write into the plugin root changes
   its content hash and stops its hooks until re-trusted, [codex] B2); Cursor
   `~/.cursor/{hooks,cli-config,permissions}.json`, `<repo>/.cursor/hooks.json`; OpenCode `~/.config/opencode/**`,
   `<repo>/{opencode.json,opencode.jsonc}`, `<repo>/.opencode/{opencode.json,opencode.jsonc,plugin/**,plugins/**,agent/**,agents/**}`
   (config, plugin code and agents' permission rules); shared `~/.config/gh/**`, `~/.gitconfig`. A repository's
   generated command, skill and agent-adapter dirs for other hosts (`.gemini/skills/`, `.gemini/agents/`,
   `.opencode/commands/`) are not policy and are not protected. It resolves the `realpath` of the target and of any
   `ln` destination; an UNSURE write whose text names one of these paths is a deny — the text that could steer the
   write, not the words of a read-only command or data written to a file (issue #402, `_needle_text` in
   `hooks/lib/write-targets.py`). The commands a `$(…)`, a backtick or a `<(…)`/`>(…)` runs are parsed like
   top-level commands; a command name built by expansion, a runner the parser does not unwrap (`strace`, `ssh`,
   `docker run`, …), an environment variable naming a command, and a file the same command writes and then runs
   (`make`, `bash`, `source`, `pytest`, `npm`, a git hook, `./path`) are UNSURE; `sort -o`, `git diff --output`,
   `git archive -o`, `git bundle create`, `git format-patch -o` and `git config --file` are targets (issue #405).
   A git replay (checkout, switch,
   restore, reset, merge, pull, rebase, cherry-pick, revert, am, stash) that would rewrite one of these paths is an
   R4 ask — `hook_ask`, the host prompt, on Claude Code and a deny on every other host — never a silent allow: an
   integrator merging a branch legitimately brings such a file in, and the user decides.
2. **Hash and re-confirm (CVE-2025-54136 class, [P] §5.2):** a user file whose sha256 ≠ the lock, or a project file
   whose hash ≠ its trust entry, keeps its tightening entries (measured against the no-file defaults) and drops its
   widening ones until a human confirms through D5/D6.
3. **The agent never edits its own policy (CVE-2025-53773 class, [P] §5.1):** only the D6 writer writes, every
   widening needs a D5 host prompt or a step outside the session, and PG and GSF deny the host config CLIs and files.
4. **No mod `tool.check`, ever** — it can approve over a user deny ([claude] B, doc-cited; directory hold
   `MOD_ANSWERS_PERMISSION`, [mods]). **No `ctx.session.update` widening** (beats a config deny, measured O2, [S2]),
   **no Codex `PermissionRequest` allow**, **no Antigravity `auto_approve`** ([codex] B2, [gemini] E). A manifest
   test holds all four.
5. **Deny texts stop pointing at bypasses:** the workflow remedy "use the GitHub MCP `create_or_update_file`"
   ([`guard-sensitive-files.sh`][gsf], [A3] D3) becomes the R4 ask, and no deny text names `PM_ALLOW_PROTECTED`.

## Consequences (k)

**Easier:** one registry and one resolver replace three precedence lists; the default matches `safety.md`; every
level states what it does on every host, with no claim beyond the evidence; the GitHub MCP and Bash paths meet the
same ceiling; ADR 003's option pattern (`CLAUDE_PLUGIN_OPTION_*`, manifest default) is reused for lowering.

**Harder:** `supervised` costs about six prompts per typical objective run, `standard` two ([A1] E); a `--perms=`
raise costs one host prompt where a host attests the prompt's origin — today none does (Claude Code sends no
`UserPromptSubmit.source`, M3; Gemini's pairing is unwired), so a durable per-skill level is the in-session route, and
on Codex, Cursor and OpenCode nothing raises inside a session. `/plugin-config` is
the first explicit-only skill (CLAUDE.md's "No skill is Explicit-only today" changes). Per-skill raises do nothing at
L2 on Codex and Cursor. Hooks stop installing dependencies; skill-creator's nested `claude -p` asks per spawn; an
agent can no longer edit host settings files, and workflow edits via MCP (memory `feedback-ci-yml-guard-hook`) give
way to a human-approved local edit. Option names (`permission_level`, `TS_PERMISSION_LEVEL`) become an interface.

## Open risks

| risk | severity |
|---|---|
| A same-UID process that bypasses the Bash parser (`python3 -c`, `make`, [A3] D13) and rewrites both the policy and its lock, or runs the writer, is undetected. The writer's session rules (D5) and the two-phase confirm close the agent routes the second pass found, but such a process can still escape the ancestry and the terminal rules (a compiled pty driver with an innocuous name, keys typed into the user's own terminal through tmux or the terminal app), forge the confirm stamp and a PostToolUse payload, or `provision` a machine with no user file after `setsid` and a forged CI marker | High |
| Text-level L2 cannot see inside interpreters or scripts (reproduced, [A3] D1): an interpreter can drive a pty (measured, [SR] S-01), start a nested host on a pty that answers its own prompts (inferred), or inject keys into the user's terminal to answer a host prompt; allows such as `Bash(python3 *)` widen that gap | High |
| A careless user approves a host prompt that injected text requested; pending records come only from typed prompts, and the Claude dialog shows the reason verbatim but pre-selects `1. Yes`, so an Enter reflex approves (M1, [S3]) | Medium |
| Codex, Cursor and OpenCode have no in-session raise; the out-of-session step pushes users toward a global `unattended` ([SR] S-18) | Medium |
| A Gemini user "Always allow" (4.95) outranks the extension rules, including the `ask_user` on `confirm` (source-cited inference, [gemini] B) | Medium |
| The active-skill context persists across turns until that agent's next slash command or `Skill` call or the session's end, and a model's own `Skill` call selects that skill's user-file level: the user chose the level, not the moment (a main-thread ticket no longer reaches subagents: M5) | Medium |
| The D9 probe reads the host CLI on PATH, not the running host process: an auto-updated binary, or a repository `env` that changes PATH, can report another version than the one running; it only decides whether the clamp applies | Low |
| Channels outside the plugin — browser and computer-use MCP servers acting on github.com, another GitHub MCP server or `gh` from another tool, `copilot.assign` handing work to an agent with its own write access — are governed by no level ([SR] S-20) | Medium |
| MCP flags are fixed for the server's lifetime; a mid-session level change applies at L1/L2 only | Low |
| A Gemini `confirm` is one-phase: the static `ask_user` rule is its only gate, so a confirm reaching the writer through a form the rule's command regex misses writes at once (the F1 class, unbound there until a guard stamp and an AfterTool binding are wired) | High |
| The second adversarial pass (below) ran against the implementation of PR #348; its fixes — the writer's session rules, the two-phase confirm, the host check — have had no third pass | Medium |
| Codex plugin hooks run only after `/hooks` trust, re-required on every update ([codex] B2); until then only L1 (at `supervised`: no call stamp) and server flags apply | Medium |

## Second adversarial pass (implementation)

An adversarial review of the implementation (PR #348, 2026-11-04) found ten numbered findings, low-severity ones and
two Codex review threads. The hardening wave of the implementation objective fixed them; the commits below are the
merged ones, and `tests/test-security-regressions.sh` replays every reproduced input against the real
hooks: 131 rows, each naming its finding, all held now and all failing against origin/master's hooks (80 of them
because the hook or script did not exist there yet).

| finding | severity | what | fix (merged commits) | disposition |
|---|---|---|---|---|
| F1 | critical | the writer read an empty ancestry (`( cmd & )`, `env -i`) as "outside any session" and widened at once; the Claude confirm stamp was written when PG *asked*, so a declined dialog left it usable, and PG missed the `plugin-config.sh` script in some forms | writer session rules and `y` on `/dev/tty`, two-phase confirm with `hooks/permission-approved.sh` (D5, D6): c8a9c7e; PG `script_hit`: a7cb121; suites: 9413ab7 | fixed; same-UID forging stays a High open risk |
| F2 | high | PG fast path | a7cb121 | fixed |
| F3 | high | PG tokeniser | a7cb121 | fixed (anomalies fail closed) |
| F4 | high | GSF protected paths: case, fd, copy, extract, git and hardlink forms | b1c7b3f; repo-relative narrowing and git replays as an R4 ask (D10.1): 1b658b8 | fixed; a hard link made before the call stays unseen (low) |
| F5 | high | PG payload size and deadline | a7cb121 | fixed (> 8 KB denied) |
| F6 | medium | GSF override | b1c7b3f; OpenCode: d2944c5 | fixed |
| F7 | medium | a `--host` claim from env could skip an option store | PG host: a7cb121; resolver host check (D3): c8a9c7e | fixed |
| F8 | medium | PG literal matching | a7cb121 | fixed |
| F9 | medium | PG remotes | a7cb121; suites: 9413ab7 | fixed |
| F10 | medium | a per-skill or per-group level replaced the env- and store-lowered level | lowering after the skill level (D3): c8a9c7e | fixed |
| L1 | low | `github-mcp.sh` took `github-mcp-server` from the inherited PATH, with the token | fixed trusted locations, owner and mode checks, the token withheld from helpers: 7cbb417 | fixed |
| L4 | low | OpenCode parity of the protected paths | b43a1c9; guard.ts through `write-targets.py --protected`: d2944c5 | fixed where python3 is present; the rules.ts port is the fallback |
| Codex P1 | — | `curl -d` with an attached body read as a GET | a7cb121 | fixed |
| Codex P2 | — | a parent-directory `rm`/`mv` bypassed repo-relative protection | b1c7b3f | fixed |

ADR and user docs for the wave: db05ef1; the plugin-config skill's exit rows: d00578c.

Open risks above carry what stays: the same-UID row and the text-level row are High, and Gemini's one-phase confirm
is a new, explicit High: unbound until a guard stamp and an AfterTool binding are wired.

## Implementation objective must…

1. Add `core/permissions/actions.json` (D1, with the equivalents) and `core/schemas/permissions.schema.json` (D3); a
   test fails when a skill or script `gh`/`git`/MCP call maps to no id.
2. Add `scripts/resolve-permission.sh` (D4) with a table test per precedence row and per failure mode.
3. Change [`resolve-merge-policy.sh`][rmp]: delete step 5, demote `TAMIRS_AUTO_MERGE=always` and objective `true`,
   alias `.dev-files/policy.json`; make the [`pr-dev`][prdev] precedence block and [`deliver-dev`][deliver] Step 6
   cite the resolver. Update [`safety.md`][safety]'s auto-merge row to link this ADR and the R4 rule.
4. Add `hooks/permission-guard.sh`, a tokeniser lib shared with `hooks/lib/agent-claim.sh`, and `hook_ask` in
   `hooks/lib/hook-output.sh` (`ask` only on Claude); wire it in `hooks/hooks.json` (`onFailure: "block"`, MCP
   matcher), `platforms/{codex,cursor}/hooks.json` (`failClosed`), `platforms/gemini/policies.source.json` +
   `scripts/build-gemini-hooks.sh`, `platforms/opencode/plugin/{guard,rules}.ts`.
5. Extend `hooks/guard-sensitive-files.sh` `classify()` and `hooks/lib/write-targets.py` (`realpath`) per D10, with
   no `PM_ALLOW_PROTECTED` for protected paths; replace the MCP remedy there, in the Gemini policy and in `rules.ts`.
6. Add the D5 pending-record hooks per platform, `plugin-config.sh confirm` and `provision` with their host-prompt
   wiring (Claude PG `ask`, Gemini static `ask_user`) and the call stamp; make `scripts/github-mcp.sh` apply the D8
   flags and resolve its dirs per D3.
7. Add `permission_level` to `.claude-plugin/plugin.json` `userConfig` (string replace, never a JSON round-trip) and
   `TS_PERMISSION_LEVEL` to `gemini-extension.json`.
8. Create the `plugin-config` skill with `skill-creator` (explicit-only, D6, scoped `allowed-tools`), its writer
   `scripts/plugin-config.sh`, the Codex `agents/openai.yaml` policy and the OpenCode code command; update CLAUDE.md's
   invocation tiers; keep `make check-claude-dist` green with state outside `${CLAUDE_PLUGIN_DATA}` ([SR] S-19).
9. Add the TTY level prompt and the optional Codex execpolicy rules to `scripts/lib/setup-*.sh`.
10. Add L1 gates and fix the audit findings: `cleanup-after-merge.sh` (D-1), pr-dev `--admin` and `issue.close`,
    repo-scaffold `repo.create`, `enable-repo-merge-settings.sh` `--apply`, usage-capture, mcp-builder Phase 6,
    retro, capture-config `--adopt all`, skill-creator nested `claude -p` (now R4) and port kill, hook-run installs,
    the `docker-guard.py` inline token and `github-policy.sh` `GITHUB_POLICY_ALLOW_LIVE` (both → tickets).
11. Record D9 in `platform-targets.json` (then the pins) and the four widening levers in
    `core/capabilities/platforms.json`; document levels in `docs/user/configuration.md`.
12. Extend `tests/test-manifest-invariants.sh` (fail-closed wiring; no `tool.check`, `session.update` allow or
    `PermissionRequest` hook); add `tests/test-permission-guard.sh` with crafted stdin per host dialect: the Codex
    fail-open cases, the equivalents, the `tty.drive` and `process.spawn.agent_host` forms.
13. Measure. **Gate:** U3 steps 3–4 run before any task builds on D5's Claude R4 route, which rests on them (only
    headless is measured). Claude: U1, U2, U3 steps 3–4 (dialog rendering), U4 ([S1]); `UserPromptSubmit.source` under `claude
    -p`/SDK; an agent id in subagent hook input; project `env` reaching hooks or overriding `CLAUDE_PLUGIN_OPTION_*`;
    `disableAllHooks` vs plugin hooks; `pluginConfigs` in project settings; the Claude and Codex MCP matchers. Codex:
    U5, `codex exec` with a tty plus `write_stdin`. Cursor: S1–S4 ([S2]), `beforeShellExecution` `ask` interactive
    and under `-p`, `sessionStart` env reach. Gemini: the `ask_user` TTY prompt, `BeforeAgent` on subagent prompts,
    user-tier policy integrity, workspace `.env` reach. OpenCode: MCP action names, `session.hook("prompt")` under
    `opencode run` and child sessions, evaluate-hook order with a second and a project-local plugin ([SR] S-16).
    **Measured on Claude Code 2.1.318 ([S3]):** the gate passed (U3 steps 3–4 = M1, plugin hook M1b), U2 (M2),
    `source` under `-p` and stream-json (M3: absent), the Claude MCP matcher (M4) and the agent id (M5). **Measured
    since ([S3] "Live checks" and "GUI checks", 2026-11-04):** U1, U5, U6, S1, and U4, S2, S3; S4 blocked (no Cursor
    Teams admin on the account). Still open: the other Claude rows above.

## Alternatives rejected

- **Level names `strict/auto/bypass`** — collide with host modes and promise a host effect the plugin cannot have
  ([claude] implication 2, [P] §5.5).
- **Host widening levers** (mod `tool.check`, [A3] D4; OpenCode `session.update`, [opencode] implication 7; Codex
  `PermissionRequest`, [codex] implication 4) — see D10.4. **Hook `ask` everywhere** — fails open on Codex, hangs
  Gemini headless, auto-approved by OpenCode `--auto` (X1, G1, O1).
- **A TTY `confirm`, with or without a PIN, as the human proof** ([SR] S-01) — the model drives a pty; a PIN is not
  host attestation, its hash sits in a same-UID file the model can read and guess offline, and a credential-shaped
  file clashes with the directory rules ([SR] S-19). **Chat-confirm on Codex and Cursor** — see D5 ([SR] S-10).
- **Claude-style allow/ask/deny lists of skill and command names** — the user asked whether skills and commands
  should sit on those lists. They do not: a skill bundles steps at different R-levels (pr-dev reads at R0 and merges
  at R3, [A1]), so a skill-name verdict is either too broad or too narrow. Skills and groups carry a *level*
  (`skills.<id>`, `groups.<id>`); only *actions* carry `allow / ask / deny` (`actions.<id>`), and a deny on an action
  holds whichever skill reaches it (D3).
- **Per-skill levels in `userConfig` or `.dev-files/policy.json`** — `userConfig` is flat and per-user ([claude]
  C); `.dev-files/` is gitignored and agent-written. **A project file that widens silently** — the clone attack
  ([P] Steal: repo scope may only narrow). **A sixth rubric class** — see D1.
- **Extend `protect-other-branches.sh`** — a concurrency guard by design ([`protect-other-branches.sh`][pob]);
  danger rules get their own fail-closed unit and tests, sharing its tokeniser.

## Security review disposition

| finding | severity | disposition | ADR section changed | rationale |
|---|---|---|---|---|
| S-01 | critical | applied-partially | Context, D1 (`tty.drive`), D5, D8, Open risks, Alternatives | A TTY is no human proof anywhere, `tty.drive` is R4 (its terminal-driver forms widened after [S3] Impact 4: a background job could answer the R4 dialog by keys), and on Claude only the dialog passes R4; the PIN is declined (not host-attested, guessable offline from a same-UID hash) |
| S-02 | critical | applied | Context, D1 (`process.spawn.agent_host`), D5 | Prompt hooks only request; every agent-host spawn is R4 (stronger than the proposed R3 m); the env-marker check and the `--permission-mode` exception are dropped, since the spawn is R4 regardless |
| S-03 | high | applied | D1 `policy.edit`, D10.1, item 5 | Host settings and option stores protected; `realpath`; an UNSURE write naming a protected path denies; no `PM_ALLOW_PROTECTED` |
| S-04 | high | applied | D3, item 13 | Dirs come from the passwd entry with owner/mode checks; env only tightens; option raises are read from the user settings file |
| S-05 | high | applied | D1, D2, D4, D5 | No ticket satisfies R4 (stronger: no action ticket either); the per-call host prompt shows id, target and effect; target equality per action kind |
| S-06 | high | applied | D1, D2 | `none` means never automatic; the R3 ids that may run unattended are listed |
| S-07 | high | applied | D1, items 1, 12 | Equivalents and the opaque-command rule; wrappers and interpreters stay the stated residual |
| S-08 | high | applied | D1 (R2 m, R3 m rows), Consequences, item 10 | Only script-free installs are R2; a hook never installs |
| S-09 | medium | applied | D5 | Lowering tickets are enforced by PG |
| S-10 | medium | applied | D5, D8, Alternatives | Chat-confirm removed outright (stronger than "off until measured"): the hook cannot tell typed text from `codex exec resume` |
| S-11 | medium | applied | D5, D8, Open risks, item 13 | Tickets bind `(session_id, agent)` with re-issue; Claude Code's hook input carries `agent_id` on subagent calls and none on the main thread (measured M5, [S3]), so a main-thread ticket never reaches a subagent, and the active-skill context is bound per agent too |
| S-12 | medium | applied | D4, D8 | Network deadline, resolver failure ⇒ deny, `unknown` never holds; a per-call stamp replaces the heartbeat |
| S-13 | medium | applied | D1 (`pr.merge.auto`, status writes) | Pinned-source check or required review, no workflow/CODEOWNERS/policy edits; status and check-run writes never automatic (GitHub behaviour inferred) |
| S-14 | medium | applied | D1 (`git.verify.skip`, `work.discard`, `pr.merge.admin`) | Adapted: verify-skip is R4, as invariant 6's one-off needs the host prompt; discard is denied over uncommitted changes; `--admin` denied while a check fails or is pending |
| S-15 | medium | applied | D3, D4 | Widening needs target = `remote` = origin; a project file widens only `pr.merge.auto`, matching the binding decision |
| S-16 | medium | applied | D8 (OpenCode), item 13 | "E (sole plugin)" until the evaluate-hook order is measured |
| S-17 | low | applied | D5, D10.2 | Atomic consume, hash the parsed bytes, no-file defaults, first-line token, nonce spec |
| S-18 | low | applied | D6, D7, Open risks | A `provision` subcommand for CI |
| S-19 | low | applied | item 8, Alternatives | Scoped `allowed-tools` and `make check-claude-dist`; the PIN route is moot (declined under S-01) |
| S-20 | low | applied | Open risks | The channels outside the plugin are named |

[R]: ../research/permissions/README.md
[SR]: ../research/permissions/design-security-review.md
[claude]: ../research/permissions/platforms/claude.md
[codex]: ../research/permissions/platforms/codex.md
[cursor]: ../research/permissions/platforms/cursor.md
[gemini]: ../research/permissions/platforms/gemini.md
[opencode]: ../research/permissions/platforms/opencode.md
[P]: ../research/permissions/platforms/prior-art.md
[S1]: ../research/permissions/spikes/claude-codex.md
[S2]: ../research/permissions/spikes/cursor-gemini-opencode.md
[S3]: ../research/permissions/spikes/implementation-measurements.md
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

---

<p align="center"><a href="https://github.com/Tamircohen28">Have a Question?</a>&nbsp;·&nbsp;<a href="https://github.com/Tamircohen28/tamirs-superpowers/issues/new/choose">Open an Issue</a></p>
