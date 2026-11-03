# ADR 004 — adversarial security review

Objective `permissions-design`, task-008 (role: security-reviewer). Target: [`004-permission-levels.md`](../../decisions/004-permission-levels.md) (status Proposed), read at branch `worker/permissions-design/008`. Date 2026-11-03. Bare numbers are ADR line numbers; other files are named.

**Threat model.** An attacker controls text the agent reads: PR and issue bodies, review threads, files in a cloned repo, MCP output, web pages. The user is careless but honest. On every host the agent runs as the user's UID and has a shell.

**Tags.** **measured** = run in this review; **source-cited** / **doc-cited** = taken from the cited research file; **inferred**; **unverified**.

**Measured in this review** (scratch directory only; no repo script was run). In agent Bash, `: </dev/tty` fails with `device not configured`. A `python3 -I -c` program called `pty.fork()`, ran `bash -c 'read -r a </dev/tty; echo got-py:$a'` in the child, wrote `y\n` to the master, and printed `got-py:y`. The same call made `guard-sensitive-files.sh` emit its UNSURE advisory ("NOT checked against the protected-path rules") and allow the command.

## Summary

| id | class | severity | platforms affected | stopped by ADR? | required ADR change (one line) |
|---|---|---|---|---|---|
| S-01 | 3, 1 | critical | all five | no | A TTY proves nothing alone: require a knowledge factor (PIN), make pty and terminal drivers R4, and on Claude let only the host dialog satisfy R4 |
| S-02 | 4, 3 | critical | gemini (concrete); opencode, codex, cursor (likely); claude (contingent) | no | Accept no raise in a non-interactive session; catalog every nested agent-host spawn as R3 m, never automatic |
| S-03 | 1 | high | all five | partial | Add host settings files and option stores to D10.1; GSF checks the `realpath`, denies UNSURE writes that name a protected path, and ignores `PM_ALLOW_PROTECTED` for them |
| S-04 | 5, 1 | high | claude, gemini, cursor (codex and opencode unverified) | no | Take the user and state dirs from the passwd entry, never from the session's `XDG_*` or `HOME`; env switches may only tighten |
| S-05 | 3, 8 | high | all five | no | A level ticket never satisfies R4; R4 needs a single-use action ticket that names the id, the exact target and the effect shown |
| S-06 | 9, 8 | high | all five | partial | Define a precondition of `none` as never automatic, and list the R3 ids that may run automatically under `unattended` |
| S-07 | 7 | high | all five | partial | Add an equivalents table (REST, GraphQL, refspecs, wrappers, aliases, hooksPath, target env) and an opaque-command rule (UNCLASSIFIED ⇒ R4) |
| S-08 | 5 | high | claude, codex, cursor (gemini if wired) | no | A hook-run `deps.install` that runs lifecycle scripts is `code.exec.foreign_repo` (R3 m) and never runs in a hook |
| S-09 | 3 | medium | all five | partial | Prompt hooks record lowering tickets, and PG enforces them |
| S-10 | 3 | medium | codex, cursor | partial | Chat-confirm stays off until U5/S3 are measured; the phrase restates scope and the challenge goes through a channel the user sees |
| S-11 | 4 | medium | claude (inferred), codex, cursor, opencode | partial | Bind tickets to the main thread (`agent_id`); a worker gets one only when the orchestrator re-issues it |
| S-12 | 6 | medium | codex (a); all (b); claude desktop, codex, cursor desktop (c) | partial | Deadline on PG's network calls; resolver failure ⇒ deny; a per-call stamp instead of the per-platform heartbeat |
| S-13 | 8, 5 | medium | all five | partial | Require a pinned-source check or an approving review and no workflow or policy edits in the PR; catalog status writes |
| S-14 | 8 | medium | all five | no | Add row-0 ids for invariants 4 and 6; deny `--admin` while a required check is failing |
| S-15 | 5, 2 | medium | all five | partial | Trust widens only for actions whose target is the entry's `remote`, and only `actions["pr.merge.auto"]` |
| S-16 | 6, 5 | medium (unverified) | opencode | partial | Measure the evaluate-hook order with a second plugin and with a project-local plugin before calling the deny "final" |
| S-17 | 2, 3 | low | all five | partial | Consume tickets atomically, hash the bytes you parse, specify the nonce, read `--perms=` from the first line only |
| S-18 | 9 | low | all five (mostly codex, cursor, opencode) | partial | Document a CI provisioning route that runs before the agent starts |
| S-19 | 10 | low | claude | yes, with a note | Scoped `allowed-tools` for `plugin-config`; keep any PIN route out of the Claude dist |
| S-20 | 7 | low | all five | no (out of scope) | State that browser and computer-use MCP servers, other GitHub servers and `copilot.assign` are not covered |

Counts: 2 critical, 6 high, 8 medium, 4 low.

## Findings

### S-01 Critical: the model can drive the human-origin TTY route

**Scenario.** (1) Injected text gets the model to request a widening (`bash scripts/plugin-config.sh pr-dev unattended`), or to make an R3/R4 call that PG answers with deny + ticket. (2) The writer prints a nonce into Bash output that the model reads (D6, 216-218). GSF denies writes only (276-277), so the model can also read the pending record in the state dir. (3) The model runs `python3 -c '…pty.fork()… exec scripts/plugin-config.sh confirm <nonce>; os.write(master, b"y\n")'`. The child's `/dev/tty` is the pty, so the confirm succeeds and the sanctioned writer writes the ticket. The technique is measured above. Other ways in: `expect`, `unbuffer`, `script` (flaky here with piped EOF), Codex exec with a tty plus `write_stdin` (unverified), `tmux send-keys` or `screen -X stuff` into the user's own pane, `osascript … do script` (Terminal.app becomes the process's parent, so the ancestry no longer leads back to the agent), and computer-use MCP typing into a terminal.

**Evidence and why it is not stopped.** 194 says "reads `/dev/tty`; agent Bash has no TTY". 198 says only the prompt hooks and the TTY path write tickets. 180-181 say a ticket satisfies an R4 ask for one call. On codex, cursor, gemini and opencode, R3/R4 asks are delivered as deny + ticket (240-244), so there the ticket is the whole gate. The basis cited, [A1] D-9 (`audit/devflow-repo-skills.md:121`), describes the default state, not an adversary. The shipped allow list holds `Bash(python3 *)` ([A3] `audit/non-skill-surfaces.md:14`). The proof is "a program with a TTY ran", and any same-UID process can create one. PG reads command text only (Open risk 309), and the confirm is a sanctioned writer call.

**Required change.** Replace the 194 row: "TTY route = `plugin-config.sh confirm <nonce>` plus a PIN set on a TTY at `make setup`. The PIN is stored as a salted scrypt hash, mode 0600, beside the user file, and entered with echo off. It never appears in chat, argv or a file the model reads. With no PIN, the TTY route is disabled. A nonce alone is never a human proof." Add a D1 row: `tty.drive` (`script`, `expect`, `unbuffer`, python/node `pty`, `tmux send-keys`, `screen -X stuff`, `osascript` with `keystroke`/`do script`, `xdotool`) = R4. Add to D5: "On Claude Code only the host dialog of a hook `ask` (C4) satisfies R4; tickets never do." Add an Open risk row: "a PIN typed where the model or a computer-use tool can read it is burned." **Confidence:** high (mechanism measured; impact follows from the ADR text).

### S-02 Critical: a nested agent host turns model text into "user" prompts

**Scenario.** Gemini, concrete: the model runs `gemini -p "/tamirs-superpowers:pr-dev 42 --perms=unattended …"`. 191 accepts "headless, the invoker's `-p` text" as a raise, and G2 measured that headless `BeforeAgent.prompt` is that text verbatim (`spikes/cursor-gemini-opencode.md:136-138`). The nested session gets a ticket, and one R4 call passes (180-181). PG lets the spawn through: `gemini` has no catalog id, only `process.spawn.claude_cli` does (71, 80). The other hosts:

- OpenCode: `opencode run` with a command reaches `session.hook("prompt")` (192; doc-cited, unmeasured). Whether child-session prompts fire it is unverified.
- Codex: `codex exec "/pr-dev 42 --perms=…"`, then `codex exec resume --last "confirm <nonce>"`. `UserPromptSubmit` sees text the model wrote (193; Open risk 310).
- Cursor: `cursor-agent -p`, likely the same (unverified).
- Claude: `claude -p "/tamirs-superpowers:pr-dev 42 --perms=unattended"` qualifies only if `-p` sets `source: "user"` (unverified, `spikes/claude-codex.md:70-77`). skill-creator already spawns `claude -p` as R2 m, which runs without asking at `standard` (71; [A2] F5).
- Every host: a nested interactive host driven over a pty (S-01) emits events that really are typed.

**Why it is not stopped.** D5's premise is "an event the model cannot author" (186). A child host whose input the model writes is such an author.

**Required change.** In D5: "No raise is accepted in a non-interactive session: Claude `-p`/SDK (`source` ≠ `user`), Gemini `-p`, `opencode run`, `codex exec`, `cursor-agent -p`. Headless sessions take their level only from the user file or the option store." Delete the headless clause of 191. In D1, add `process.spawn.agent_host` (`claude`, `codex`, `gemini`, `opencode`, `cursor-agent`, `agy`, also via `npx`, `bunx`, `pnpm dlx` or `node …/cli.js`) = R3 m, never automatic. Keep row 71 only for a child given `--permission-mode` and `TS_NESTED=1`. Raise hooks refuse a session whose env carries `TS_NESTED`, `CLAUDECODE`, `GEMINI_CLI`, `CODEX_*` or `OPENCODE*` (defence in depth only, since the model can unset these). **Confidence:** high for Gemini (ADR text plus measured G2); medium for OpenCode and Codex; low for Claude `-p`.

### S-03 High: host config and option stores are outside D10's protected set, and GSF has three bypasses

**Scenario.** The Edit tool writes `~/.claude/settings.json`. Any one of three changes is enough. Setting `pluginConfigs["tamirs-superpowers@…"].options.permission_level = "unattended"` raises the level, because with no `level` in the user file the effective level is the option store's (131). Setting `"disableAllHooks": true`, or removing the plugin from `enabledPlugins`, removes every L2 from the next session on, leaving only advisory L1. Nothing guards the write: `enforce-worktree-edits.sh` exempts `~/.claude` ([A3] D7, `audit/non-skill-surfaces.md:190`), and no guard covers global config on any host ([A3] E, line 216). Equivalents on the other hosts:

- Gemini: a user-tier `~/.gemini/policies/*.toml` allow outranks the extension's rules (`platforms/gemini.md:46-59`; integrity check unverified, :379). Also `tools.allowed` and the extension `.env`.
- Codex: `~/.codex/config.toml`. Separately, any write into the installed plugin root changes its content hash, which silently disables every plugin hook, even mid-session (`platforms/codex.md:99-100, 188`).
- Cursor: `~/.cursor/{hooks,cli-config,permissions}.json`.
- OpenCode: the plugin list in `~/.config/opencode/opencode.json`.

GSF bypasses that D10.1 inherits:
- (a) An UNSURE write is an advisory allow (`hooks/guard-sensitive-files.sh:151-164`), observed live here.
- (b) Targets are `normpath`, not `realpath` (`hooks/lib/write-targets.py:837`). `ln -s ~/.config/tamirs-superpowers/permissions.json notes.txt`, then an Edit of `notes.txt`, writes the policy file.
- (c) `PM_ALLOW_PROTECTED=1` in the hook env skips GSF entirely (`:67`), and its deny text tells the agent to set it (`:93`).

**Why it is only partly stopped.** D10.1 (276-278) lists only the XDG dirs, plugin caches and guard files, and item 5 (328) implements GSF "per D10". The `config.global.write` row names GSF but no paths (87). Lines 227 and 282 deny only the host config CLIs, not direct file writes. D10.3 (281) claims the CVE-2025-53773 class, whose original is an agent editing host settings.

**Required change.** Append to D10.1:

> GSF denies, as R4 `policy.edit` with no `PM_ALLOW_PROTECTED` bypass, every Edit-class and parsed-Bash write to the paths below. It checks the `realpath` of the target and of any `ln` destination. An UNSURE write whose command text names one of these paths is a deny.
>
> - Claude: `~/.claude/settings*.json`, `<repo>/.claude/settings*.json`
> - Gemini: `~/.gemini/settings.json`, `~/.gemini/policies/**`, `<repo>/.gemini/**`, the extension's `.env`
> - Codex: `~/.codex/{config.toml,hooks*,rules/**,plugins/**}`
> - Cursor: `~/.cursor/{hooks,cli-config,permissions}.json`, `<repo>/.cursor/hooks.json`
> - OpenCode: `~/.config/opencode/**`, `<repo>/{opencode.json,.opencode/**}`
> - Shared: `~/.config/gh/**`, `~/.gitconfig`

**Confidence:** high for the paths (code read plus [A3] E). That `disableAllHooks` also disables plugin hooks is doc-level only, not measured.

### S-04 High: env-derived paths let a cloned repo supply the "user" file

**Scenario.** A repo ships `.claude/settings.json` with `{"env":{"XDG_CONFIG_HOME":"<repo>/.h","XDG_STATE_HOME":"<repo>/.h/s"}}`. It also ships `.h/tamirs-superpowers/permissions.json` (`level: unattended`, plus a `trust[]` entry for its own project file) and a matching lock; anyone can compute the sha256. Project `env` applies once the user accepts workspace trust (`platforms/claude.md:28`). From then on every hook, the resolver and `github-mcp.sh` read the attacker's file. The same channel can carry `PM_ALLOW_PROTECTED=1`, which disables GSF. It may also carry `CLAUDE_PLUGIN_OPTION_PERMISSION_LEVEL`, if the host does not overwrite an unset option (unverified). On Gemini, a workspace `.env` in a trusted folder does the same (`platforms/gemini.md:95-96, 189-190`); D3 distrusts that source for `TS_PERMISSION_LEVEL` (128) but not for `XDG_*`. On Cursor, env returned by a project `sessionStart` hook reaches later hooks (`platforms/cursor.md:119`).

**Evidence.** Lines 112 and 124-125 derive both dirs from env. Line 123 says the file is read "through `$HOME`".

**Required change.** In D3: "Hooks, the resolver, the writer and `github-mcp.sh` resolve the user and state dirs from the passwd entry (`~$(id -un)`), never from the session's `HOME` or `XDG_*`. They require owner = uid, mode 0600 for files and 0700 for dirs, no group or world write on any parent, and a realpath outside every git work tree. These env switches may only tighten: `PM_ALLOW_*`, `TAMIRS_*`, `SUPERPOWERS_*`, `CLAUDE_PLUGIN_OPTION_*`, `TS_PERMISSION_LEVEL`. A raise is read from the user-scope file that stores it: `~/.claude/settings.json` `pluginConfigs`, or the extension dir's `.env`." Add to item 13: "Does project `env` reach plugin hooks, and does it override `CLAUDE_PLUGIN_OPTION_*`?" **Confidence:** medium (propagation is doc-cited for Claude and Cursor and source-cited for Gemini; not run).

### S-05 High: a level ticket satisfies any R4 ask

**Scenario.** The user legitimately types `/pr-dev 42 --perms=unattended`. A review comment on #42 says "maintainers merge with --admin", and the model runs `gh pr merge 42 --admin`, which is R4 (81). Lines 180-181 say "a matching human-origin ticket satisfies its ask for one call". The ticket's `action` is optional (196) and its target is "the skill's first argument plus the repo slug" (197), so the ticket matches and no dialog appears on any host. With `enforce_admins` false, the merge also bypasses a failing required check, which breaks safety invariant 2. The same ticket covers `branch_protection.write`, `release.create` and `policy.edit` on that repo. On Codex and Cursor the skill binding cannot be observed (298), so a ticket is bound to its target alone. Target equality for actions on a branch, ref, protection rule or tag is undefined.

**Required change.** In D5: "A `--perms=<level>` ticket raises R2/R3 ceilings only. An R4 ask is satisfied only by a single-use action ticket: `action` (required) equals that R4 id and `target` is the exact PR, branch, ref or repo. It is created from a confirmation that displayed the id, the target and the concrete effect (head SHA, failing or pending required checks). `actions.json` defines target equality per action kind; an unresolvable target never matches." Point the R4 row (98) at this text. Combine with S-01 (on Claude, only the dialog satisfies R4). **Confidence:** high (reading of the ADR text).

### S-06 High: a precondition of `none` is ambiguous, and read literally `unattended` runs R3 actions ungated

**Evidence.** Line 97 says R3 under `unattended` is "allow **iff** the action's precondition holds". Only `pr.merge` says "(never automatic)" (73). Rows 76, 77, 79 and 80 say just `none`. The audit's own preview read this shape as auto: [A1] E (`audit/devflow-repo-skills.md:130-150`) marks `repo.settings.merge`, `git.push.default_branch` and `pr.merge (manual)` `auto`.

**Scenario.** Read literally, `unattended` runs all of these without asking:
- `pr.review.approve` on an attacker's PR, where the user's token supplies the required review;
- `file.write.remote` to the default branch;
- `repo.settings.merge`;
- `git.push.default` to an unprotected default branch;
- `code.exec.foreign_repo`, `docker.state` and `process.kill`;
- `process.spawn.claude_cli` inheriting `bypassPermissions`;
- `handoff.force` and `file.write.outside_repo`.

**Required change.** Under the D1 table: "A precondition of `none` means none exists, so the action is never automatic and asks at every level." Rewrite those cells as "none (never automatic)". List the R3 ids that may run automatically under `unattended`: `pr.merge.auto`, `branch.delete.remote`, `pr.close`/`issue.close`, `git.push.force` (own branch, with lease), and `pkg.*` with a pinned lockfile. **Confidence:** high.

### S-07 High: the ADR does not specify which equivalent commands PG must catch

**Scenario.** Under `standard`, `pr.merge` should ask, yet each of these merges unprompted: `gh api -X PUT repos/me/app/pulls/5/merge`; `gh api graphql -f query='mutation{mergePullRequest(…)}'`; `curl -X PUT -H "Authorization: token $(gh auth token)" https://api.github.com/repos/me/app/pulls/5/merge`. The same gap covers:
- other refspec forms: `git push origin :feat`, `+HEAD:main`, `--mirror`, `git push <url>`;
- env that changes the target: `GH_REPO=me/other gh pr merge 5`;
- aliases: `git -c alias.m='!gh pr merge 5 --admin' m`, `gh alias set`;
- hooks: `git config core.hooksPath x && git commit` (R1 per row 60, yet it runs arbitrary code);
- wrappers: `make deliver`, `bash s.sh`, `xargs`, `eval`, `$(…)`.

**Evidence.** Only the ruleset row names a non-`gh pr` form (84: `gh api …/protection`). [A3] D1 (`audit/non-skill-surfaces.md:177-178`) reproduced that today's tokeniser, which item 4 (324) reuses, lets `gh api -X DELETE/PUT`, `curl` and `make` through. Line 40 says "UNCLASSIFIED ⇒ R4", but a guard that matches known patterns allows what it cannot classify.

**Required change.** In D1 and item 4: "`actions.json` carries an equivalents table that PG implements and tests." It must cover:
- REST method plus path per id: `pulls/N/merge`, `git/refs`, `branches/*/protection`, `rulesets`, repo POST/DELETE, `forks`, `releases`, tag refs, `contents`, `statuses`, `check-runs`, issue or PR PATCH of `state`/`base`, reviews with `event=APPROVE`;
- GraphQL mutations: `mergePullRequest`, `enablePullRequestAutoMerge`, `deleteRef`, `updateRef`, `closePullRequest`, `createCommitOnBranch`, `updateBranchProtectionRule`, `createRepository`;
- refspec forms;
- target env: `GH_REPO`, `GH_HOST`, `GIT_DIR`, `GIT_CONFIG_*`;
- HTTP clients pointed at `api.github.com`, `uploads.github.com` or the GHE host.

Also add: "A command that parses to no id but contains a mutation marker (`gh `, `git push`, `api.github.com`, `graphql`, `gh auth token`, `GH_TOKEN`, `GITHUB_TOKEN`, a protected path) is UNCLASSIFIED ⇒ R4. A file-sourced GraphQL query (`-F query=@…`) is R4. `git config alias.*`, `core.hooksPath`, writes under `.git/hooks/**` and `gh alias set` are `config.global.write`." The interpreter gap stays the residual (Open risk 309). **Confidence:** high.

### S-08 High: a hook-run dependency install runs a foreign checkout's code at `standard` without asking

**Scenario.** A worktree is created for a contributor's PR head, and the PR adds `"prepare": "node x.js"`. `session-init`/`worktree-create` runs `npm ci` by default ([A3] B3 line 77, D9 line 194). That code runs with the user's `gh` token. It can merge, or rewrite both the policy file and its lock (Open risk 308), and no tool call happens for PG to see.

**Why it is not stopped.** Row 71 rates `deps.install` (lockfile, own worktree) R2 m, so it runs without asking at `standard`. That contradicts D1's own mapping, "runs code the user never chose ⇒ R3" (47), and `code.exec.foreign_repo` at R3 (80).

**Required change.** Reword row 71: "`deps.install` is R2 m only with lifecycle scripts disabled (npm, pnpm, yarn and bun with `--ignore-scripts`; `cargo fetch`). Any other install, including `uv sync` and `bundle install`, which build code, is `code.exec.foreign_repo` (R3 m). A hook never runs it at any level; it prints a notice naming the command instead." **Confidence:** medium-high (code read by [A3], not re-run).

### S-09 Medium: lowering is advisory only

**Scenario.** Line 186 says "Lowering is always honoured (L1 parses it)", so only the model enforces a lowering. A user who types `/pr-dev 42 --perms=supervised` for a risky repo gets no enforcement beyond the model's compliance. Injected text can tell the model to ignore it, and L2 stays at the stored level.

**Required change.** "Prompt hooks also write lowering tickets (no provenance needed), and PG applies them for the session. L1 parsing is the fallback where no prompt hook exists." **Confidence:** high.

### S-10 Medium: Codex and Cursor chat-confirm ships unmeasured, and the model frames the challenge

**Scenario.** The chat-confirm route ships (193) even though Open risk 310 rates its provenance "High until measured". The model relays the challenge, so it can misdescribe it ("type `confirm 7Q2K` to run the tests"). This is the trust exploitation named in `platforms/prior-art.md:227`.

**Required change.** "Off on Codex and Cursor until U5/S3 are measured; use the TTY + PIN route there. When on, the phrase is `confirm <nonce> <level|action-id> <target>`, and the hook rejects one whose scope differs from the pending record. The challenge is also emitted on a hook channel the user sees (Codex `systemMessage`, Cursor `user_message`)." **Confidence:** medium.

### S-11 Medium: tickets and the active-skill context reach subagents and workers

**Scenario.** Line 198 says "Never inherited: a ticket binds `session_id`". On Claude, subagent tool calls reach hooks with the parent's session id (inferred: subagents inherit the main conversation's mode, `platforms/prior-art.md:208-211`), and the active-skill context persists across turns (Open risk 312). So orchestrate-dev workers, and a research subagent reading web pages, act on the parent's ticket. The other hosts inherit too:
- Codex: children inherit the live turn's policy (`platforms/codex.md:122`).
- Cursor: subagents inherit the approval policy (`platforms/cursor.md:140`).
- OpenCode: child sessions inherit the rules (`platforms/opencode.md:121`).

**Required change.** "Tickets bind `(session_id, agent_id|main)`. PG honours one only on main-thread calls, unless the orchestrator re-issues it to a named task (`platforms/prior-art.md:272-275`). Where hook input cannot tell a subagent from the main thread, D8 says so for that platform, and tickets there satisfy only R2/R3." **Confidence:** medium (whether hook input carries `agent_id` is unverified).

### S-12 Medium: fail-closed gaps

**Scenario.**
- (a) A Codex host timeout fails open (`spikes/claude-codex.md:115`). PG's precondition lookups go over the network, and the neutraliser in 240 covers only errors inside the guard.
- (b) D4 (162-166) never says what happens when `resolve-permission.sh` is missing, exits non-zero, prints invalid JSON, or lacks `jq`/`gh`. The resolver it replaces "always exits 0" and maps failures to `unknown` (`skills/dev-workflow/pr-dev/scripts/resolve-merge-policy.sh:18-19`).
- (c) The heartbeat is keyed per platform with a 12 h window (247-248), so a heartbeat written by one session vouches for another. A CLI session makes Desktop look guarded (239). After a Codex update, hooks are untrusted (Open risk 314) while that morning's heartbeat still counts. A Cursor CLI heartbeat covers desktop.

**Required change.**
- "PG gives every network lookup an internal deadline well under the host timeout, and denies when it expires."
- "If the resolver fails, PG denies R2 and above and L1 stops. An `unknown` precondition never holds."
- "PG stamps `<state>/seen/<session_id>` on every call. A resolver invoked from agent Bash checks that PG saw this very call; otherwise it runs `supervised`." This replaces the 12 h heartbeat.

**Confidence:** medium-high.

### S-13 Medium: the PR or the agent can satisfy `pr.merge.auto`'s precondition

**Scenario.** The precondition is "protection reports ≥ 1 required check" (72, 100). Two ways around it:
- A same-repo PR that edits the workflow behind the required check is tested by its own edited workflow.
- A token with `statuses:write` can POST `success` for a required context that no app is pinned to (`gh api -X POST …/statuses/<sha>`), and that call has no catalog id.

Under `unattended`, pr-dev then arms auto-merge on such a PR.

**Required change.** The precondition becomes: at least one required check with a pinned source (ruleset `integration_id`, classic `app_id`) or at least one required approving review, and a PR diff that touches nothing under `.github/workflows/**`, `CODEOWNERS` or `.tamirs-superpowers/**`. Add `commit.status.write` and `check_run.write` as R3, never automatic. **Confidence:** medium (GitHub behaviour, not measured here).

### S-14 Medium: safety invariants 2, 4 and 6 have no catalog ids

**Scenario.** Line 99 and row 0 (170) promise that the safety invariants deny at every level. But no id covers invariant 6 (`--no-verify` and `-n`, `-c core.hooksPath=/dev/null`, `HUSKY=0`, `SKIP=`) or invariant 4 (`git clean`, `git checkout --`, `git restore`, `git stash drop` and `clear`, and `git reset --hard` other than reset-to-remote; row 89 covers only reset-to-remote and worktree removal). These commands fall under `git.commit` (60), which has no PG point, or are not parsed at all. For invariant 2, `pr.merge.admin`, an R4 ask, can bypass a failing check (S-05).

**Required change.** Add `git.verify.skip` and `work.discard` at row 0, denied unless an action ticket names them; invariant 6 allows only a "deliberate, user-authorized one-off". `work.discard` is denied while the tree holds changes this task did not commit. `pr.merge.admin` is denied while any required check is failing or pending; an action ticket may bypass only a missing review. **Confidence:** high.

### S-15 Medium: project-file trust is not bound to the target and widens more than auto-merge

**Scenario.** Trust is keyed by the repo's realpath (135-137). The entry records `remote` (146), but nothing requires the action's target to equal it. So in a trusted checkout, `gh pr merge --auto 7 --repo me/other` is judged by the trusted file. Separately, the binding decision (33) lets a repo file enable auto-merge only, yet D3 admits every widening entry once trusted (`level`, `skills`, `actions`). That raises what a consent-phishing request ("run `/plugin-config trust` to fix the build") can get.

**Required change.** "Widening applies only when the action's resolved target repo equals both the entry's `remote` and the checkout's current origin. A project file may widen only `actions["pr.merge.auto"]`; every other entry in it can only tighten." **Confidence:** high.

### S-16 Medium (unverified): another OpenCode plugin may overwrite guard.ts's deny

**Scenario.** Plugin hooks rewrite a shared `effect` (`spikes/cursor-gemini-opencode.md:191-197`), and their order across several plugins was not measured. A project-local `.opencode/plugin/` from a cloned repo may also load (inferred). O2 showed that a session rule beats a config deny. Line 244 calls the plugin's deny final, but that was measured with one plugin.

**Required change.** Add to item 13: two evaluate hooks (ours first, then ours last) and a project-local plugin. Until measured, write the D8 cell as "E (sole plugin)". **Confidence:** low.

### S-17 Low: ticket and hash mechanics

Add one sentence each to D5/D6:
- (a) Consume a single-use R4 ticket by atomic `rename`, because parallel tool calls and workers race.
- (b) Read the file once, then hash and parse those same bytes.
- (c) For a user file that does not match its lock, "widening" is measured against the no-file defaults (279-280).
- (d) Parse `--perms=` only as a standalone token on the first line of `command_args`, so pasted text cannot carry one.
- (e) The nonce is at least 64 bits from `/dev/urandom`, bound to the hash of the pending diff, and expires with it.

**Confidence:** high.

### S-18 Low: no CI route, and usability pushes users toward a global `unattended`

**Scenario.** Headless `supervised` denies R2 (push, open a PR). That is safe, but CI breaks. The writer needs a human for any widening (216-218). Codex, Cursor and OpenCode have no option store (129-130), so a CI operator must hand-write the file and lock, which looks exactly like the tampering the lock is meant to catch. About six prompts per run (295), on a machine shipped at `bypassPermissions` ([A3] line 14), pushes users to set `unattended` globally, and S-06 makes that level broader than intended.

**Required change.** "CI writes the user file and lock with `plugin-config.sh provision` in a workflow step that runs before the agent starts. PG denies that subcommand from agent Bash, and `show` marks the lock `by: provision`." **Confidence:** medium.

### S-19 Low: directory conformance notes

- The explicit-only `plugin-config` skill needs scoped `allowed-tools`, because the dist check refuses a bare `Bash` (`docs/engineering/build-and-release/directory-distribution.md:89`). Check its root-variable shapes against :116.
- The S-01 PIN check reads a credential-shaped file, which clashes with :86-87. Keep that route out of the Claude dist and rely on the hook dialog there.
- Whether storing prompt-derived tickets outside `${CLAUDE_PLUGIN_DATA}` triggers a scanner hold is unverified.
- No conflict: `permission_level` is not a credential, and D10.4 avoids `MOD_ANSWERS_PERMISSION`.

**Required change.** Add to item 8: "scoped `allowed-tools`; `make check-claude-dist`". **Confidence:** medium.

### S-20 Low: name the channels outside the plugin

**Scenario.** Three channels reach R3/R4 actions without passing PG or the D8 server flags:
- browser and computer-use MCP servers, acting through github.com in the user's logged-in browser;
- a second GitHub MCP server, or `gh` run from another tool;
- `copilot.assign` (R2, row 68), which hands work to an agent with its own write access to the repo.

Line 108 already says a level governs the plugin only.

**Required change.** Add an Open risk row naming these channels, so that no one reads `supervised` as covering them. **Confidence:** high.

## Not a finding (already handled; do not re-litigate)

- **Mod `tool.check` widening:** banned, with a manifest test (283-285).
- **OpenCode `session.update`, Codex `PermissionRequest` allow, Antigravity `auto_approve`:** banned (284-285, 363). S-16 covers only *other* plugins.
- **Hook `ask` where it fails open, hangs or is auto-approved** (Codex, Gemini, OpenCode `--auto`): not used there (240, 243, 244, 358).
- **Claude headless `ask`:** becomes deny (C4; 104-107, 238), so the headless default is safe.
- **Cloned-repo widening through the project file alone:** needs a hash-confirmed trust entry, and a project file may not carry one (134-138, 157). S-04 and S-15 are the residuals.
- **Agent-written `.dev-files`:** objective `delivery.auto_merge: true` never grants (173); `policy.json` is read under the trust rule (174).
- **`TAMIRS_AUTO_MERGE=always` env prefix:** ignored with a warning (172).
- **docker-guard inline token:** replaced by tickets (200-201, item 10).
- **Automatic direct `pr.merge` and MCP `merge_pull_request`:** never automatic (102-103), and the tool is excluded at every level (256-259).
- **MCP bypass of the Bash guards:** `--read-only` under `supervised`, and argument-dependent tools are excluded until a matcher is verified (250-259). The workflow remedy text is fixed (286-287).
- **R4 `allow` in a file:** the schema rejects it (156).
- **Invalid file:** treated as `supervised` (137-138).
- **Includes or extends in the hash scope:** there is no include mechanism (`additionalProperties: false`, 158), so the hash of the one file covers its whole effect.
- **`--perms=` in content inside the session:** excluded (199-200). S-02 covers the nested-host case.
- **Host config CLIs:** denied from agent Bash (88, 227, 282). S-03 covers direct file writes.
- **Level names colliding with host modes:** avoided (355-356).
- **Same-UID interpreter rewriting the policy and its lock:** irreducible without OS-level separation and correctly listed (308). S-01 shows the TTY proof falls to the same class.

## Unverified, to add to item 13

- What `UserPromptSubmit.source` is under `claude -p` and the SDK.
- Whether Claude hook input carries `agent_id` for subagent calls.
- Whether project `env` reaches plugin hooks, and whether it overrides `CLAUDE_PLUGIN_OPTION_*`.
- Whether `disableAllHooks` also disables plugin hooks.
- Whether the model can use Codex exec with a tty plus `write_stdin`.
- Whether `opencode run` commands and child sessions fire `session.hook("prompt")`.
- Whether Gemini subagent prompts fire `BeforeAgent`.
- The order of OpenCode evaluate hooks across several plugins.
- Whether Gemini user-tier policy files get an integrity check.
- Whether env from a Cursor `sessionStart` hook reaches this plugin's hooks.
