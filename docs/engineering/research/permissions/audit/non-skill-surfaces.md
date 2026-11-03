# Danger-score audit: agents, scripts, hooks, mod, MCP server

Objective `permissions-design`, task-006 (role: security-reviewer, read-only). Snapshot: branch `worker/permissions-design/006`, plugin 5.1.3.
Rubric: R0 observe, R1 local reversible, R2 shared-additive, R3 shared-mutating, R4 irreversible/privileged. UNCLASSIFIED = R4.
Flags: N network, S secrets, M model-invocable, A subagent-reachable. Confidence: H read in code or reproduced, M inferred from code plus host docs, L host behaviour not measured here.

## A) Method and assumptions

- Read every file named in the task from this worktree. Every claim carries file:line (paths relative to repo root).
- Behaviour check, not just reading: ran `hooks/protect-other-branches.sh` with crafted stdin in a throwaway repo (`origin` = `https://github.com/example/demo.git`, `HOME` and `AGENT_CLAIM_DIR` in a temp dir, nothing outside it touched). Results in D1.
- Did not execute any other hook or script. `github-mcp-server stdio --help` (v2.1.0, installed) was run to read its flags; no token, no server start.
- "Max R" is the worst thing the item can do on its own authority, not what it usually does. A guard's own Max R is the class it can stop, written `guards Rn`.
- Assumed host facts (L unless noted): Claude Code PreToolUse matchers accept MCP tool names (`mcp__<plugin>__<tool>`); a hook `deny` holds in every permission mode (H for this repo's stated position: `hooks/docker-guard.py:9-11`); a mod `tool.check` could approve over a user deny (given by the task, not re-measured). The GitHub MCP tool names below are the ones this session's host lists for the plugin server (`mcp__plugin_tamirs-superpowers_github__*`).
- Machine baseline this repo installs matters more than any single item: `platforms/claude/settings.d/defaults.json:9` sets `permissions.defaultMode = bypassPermissions` and `:19` sets `skipDangerousModePermissionPrompt: true`; `permissions-allow.json:5,9,17,19` allows `Bash(gh repo create *)`, `Bash(git push *)`, `Bash(python3 *)`, `Bash(gh api *)`; `permissions-ask.json` holds 39 docker entries only; no `permissions.deny` is shipped for any platform. Under bypass, `ask` rules do not fire (`hooks/docker-guard.py:3-11`, `settings.d/permissions-ask.json` comment). Hooks are therefore the only enforcement layer on this machine.

## B) Tables per surface

### B1 Agents (`agents/*.md`, frontmatter `tools:` and `model:` read at lines 4-5)

All ten pin `model: sonnet`. None sets `disallowedTools`, `permissionMode`, `readonly`, `hooks` or `mcpServers`. `tools:` is an allowlist, so no agent can reach a GitHub MCP tool (none lists one); the only MCP names listed are two Context7 ids in research-agent, `mcp__claude_ai_Context7__*`, which do not match the `mcp__plugin_context7_context7__*` ids this host exposes (L, possible dead allowlist entry).

| Agent | tools | Can Write/Edit | Can Bash | Max R | Flags | Existing control | Cursor `readonly: true`? |
|---|---|---|---|---|---|---|---|
| architecture-reviewer | Read Grep Glob | no | no | R0 | M A | tools allowlist (Claude enforces; Cursor via `cursor-agent-tools-guard.sh`) | YES, safe |
| research-agent | Read Grep Glob WebSearch WebFetch + 2 Context7 | no | no | R0 (N) | M A N | allowlist | YES, safe (web fetch is read) |
| security-reviewer | Read Grep Glob Bash | no | yes | R4 via Bash | M A | prose "read-only"; hooks apply to its Bash | Probably; it only needs `git diff`, `grep`, no builds. Verify Cursor readonly still allows read-only shell |
| spec-reviewer | Read Grep Glob Bash | no | yes | R4 via Bash | M A | prose "read-only" (`agents/spec-reviewer.md:14`) | Probably, same as above |
| performance-reviewer | Read Grep Glob Bash | no | yes | R4 via Bash | M A | prose | NO: "measure" implies running benchmarks that write caches |
| debugging-specialist | Read Grep Glob Bash | no (read-only by default, `agents/debugging-specialist.md:11`) | yes | R4 via Bash | M A | prose | NO: reproducing bugs runs tests and creates files |
| orchestrator | Read Grep Glob Bash | no | yes | R4 via Bash | M A | prose (`agents/orchestrator.md:35` no forced auto-merge) | NO: it must run `objective-state.sh`, which writes state under `.dev-files/objectives/` |
| implementer | Read Grep Glob Bash Edit Write | yes | yes | R4 via Bash | M A | worktree/sensitive-file hooks; role contract forbids PR (`core/roles/`) | NO (writes by design) |
| integrator | Read Grep Glob Bash Edit Write | yes | yes | R4 via Bash | M A | same hooks; `core/roles/integrator.md:55` forbids force-push over worker or default branch, by prose only | NO |
| test-engineer | Read Grep Glob Bash Edit Write | yes | yes | R4 via Bash | M A | same hooks | NO |

Evidence: tool lists at `agents/<name>.md:4`; Cursor not enforcing `tools:` is measured in `hooks/cursor-agent-tools-guard.sh:5-9`.

Notes:
- Seven agents are "read-only by declaration" (`cursor-agent-tools-guard.sh:9-10`), but five of the seven hold Bash, so read-only is prose, not a capability limit. Only architecture-reviewer and research-agent are read-only by capability. (H)
- Seven with Bash can run any of the gh/git commands in C; the hook layer, not the agent definition, is the only brake. A Claude agent definition cannot carry `hooks`/`permissionMode` from a plugin (host restriction, L), so per-agent narrowing has to be a `tools:` change or a hook keyed on agent identity (only Cursor has one, `cursor-agent-tools-guard.sh`).
- Safest `readonly: true` set today: architecture-reviewer, research-agent. Candidate after a Cursor measurement: security-reviewer, spec-reviewer.

### B2 Scripts (side-effecting)

| Item | Max R | Flags | What it writes or does | Existing control | Evidence |
|---|---|---|---|---|---|
| `scripts/setup.sh` (+ `scripts/lib/setup-{claude,codex,cursor,gemini,opencode,common,rules-common}.sh`) | R4 | M? (reached via Bash, or `make setup`) | renders `~/.claude/settings.json` (incl. `defaultMode: bypassPermissions`, allow list), `~/.claude/CLAUDE.md`, agents, statusline; also `~/.codex`, `~/.cursor/cli-config.json`, `~/.gemini`, `~/.config/opencode` | verbs `plan` default without TTY; `apply` diffs and confirms per change; `--yes`/`SETUP_YES=1` skips prompts; `remove` is symmetric | `scripts/setup.sh:5-20,24-26`; `platforms/claude/settings.d/defaults.json:9` |
| `scripts/install.sh`, `update.sh`, `uninstall.sh` | R4 | M? | shims over setup.sh: `install` = `--yes --targets claude` (no confirmation); also writes `~/.claude/ensure-exit.sh` when proxy env set | `--dry-run`; uninstall restores backup `settings.json.pre-tamirs-superpowers` | `scripts/install.sh:3-12,16-17`; `uninstall.sh:3-12` |
| `scripts/github-policy.sh` | R4 | N S M (skill `github-policy` is `disable-model-invocation: false`, `skills/repo/github-policy/SKILL.md:9`) | `apply` writes repository rulesets and branch protection through `gh api`, one repo, `--all`, or `--org`, optionally an org-level ruleset (`--org-level`) | default verb `audit`; `apply` confirms each diff on /dev/tty; no TTY and no `--yes` prints the plan; no TTY needs `GITHUB_POLICY_ALLOW_LIVE=1` plus `--yes`; refuses weakening without `--allow-weakening` | `scripts/github-policy.sh:2-60,1384`; `scripts/lib/github-org.sh:629` prints (does not run) a `gh api -X DELETE .../protection` hint; the tool refuses to do that step itself |
| `scripts/capture-config.sh` | R2 (machine to repo PR) but feeds R4 | N M (skill `capture-config`, `skills/toolkit/capture-config/SKILL.md:6`) | `deliver`: branch, commits, PR body; runs `make validate`; "NEVER merges". `--adopt all` takes machine permission edits into the canonical source, which `setup.sh` then renders to every platform | classification: secrets refused, machine-local skipped; PR review | `scripts/capture-config.sh:2-50`; `platforms/claude/capture.conf:34,40,112,121` (captures `permissions.defaultMode`) |
| `scripts/usage-capture/enable.sh` | R4 | M (skill `usage-capture`) | edits `~/.claude/settings.json` env: OTEL endpoint to 127.0.0.1; `--force` overwrites an existing endpoint | opt-in; `--dry-run`, `--disable` | `scripts/usage-capture/enable.sh:25-42,125-129` |
| `scripts/usage-capture/collector.py` | R1 | S (logs may hold prompts if `--bodies`) | long-lived loopback daemon on port 17431, writes under `~/.local/share/tamirs-superpowers/usage` | binds 127.0.0.1; started only by `usage-capture-ensure.sh` when `TAMIRS_USAGE_CAPTURE` set | `collector.py:6`; `hooks/usage-capture-ensure.sh:14-30` |
| `scripts/notify-pushover.sh` | R2 | N S | POSTs to `api.pushover.net` with the user's token and key | inert without `CLAUDE_PLUGIN_OPTION_PUSHOVER_*`; `hook_tier_gate notification` | `scripts/notify-pushover.sh:40-44,103` |
| `scripts/github-mcp.sh` | R4 (launcher) | N S | `exec github-mcp-server stdio` with the user's PAT; no `--read-only`, `--toolsets`, `--tools` or `--exclude-tools` | none: token scope only | `scripts/github-mcp.sh:25-30`; flags confirmed by `github-mcp-server stdio --help` |
| `scripts/doctor.sh` | R0 | N | checks tools, `gh` auth; prints remedies only | read-only | `scripts/doctor.sh:150-171` |
| `scripts/agent-health.sh` | R0 | | reads worktrees and git state | read-only | `scripts/agent-health.sh:1-20` |
| `scripts/build-*.sh` (13) | R1 | | generate files inside the repo/dist; `$HOME` appears only in comments | none needed | grep of `$HOME` in `build-*.sh` returned no code line |
| `scripts/probe-platform-versions.sh`, `check-platform-targets.sh --sync`, `check-repo-description.sh` | R0 (N) | N | `curl`/`gh api` GETs | read-only | `probe-platform-versions.sh:92,99,110`; `check-repo-description.sh:68` |
| `scripts/statusline.sh` | R0 | | reads session JSON | read-only | CLAUDE.md note on piped stdin |

Pattern: every global writer (setup, install, github-policy, enable) gates on a TTY prompt or `--yes`. An agent running it through Bash has no TTY, so it must type `--yes` plus an env twin; that is an explicit act, but a model can type it, and the allow list has `Bash(python3 *)` and `Bash(gh api *)` so nothing prompts. The gate is a convention, not a control the harness enforces.

### B3 Hooks (`hooks/`: 32 entry scripts, 8 libs; manifests `hooks/hooks.json`, `platforms/{codex,cursor,gemini}/hooks.json`)

Classification uses `docs/engineering/architecture/hooks-classification.md` plus what the code emits. ENF = can deny/block (writes a deny, `decision: block`, or exit 2). ADV = advisory or notification (context, stderr, `{}`).

| Hook | Event / matcher | Class | Max R it causes | Flags | Existing control | Evidence |
|---|---|---|---|---|---|---|
| protect-other-branches.sh | PreToolUse `Bash|Shell` | ENF (claim-based deny) | guards R2/R3 | | `onFailure: block` (Claude), `failClosed` (Cursor); fail-open on Codex and Gemini | `hooks/hooks.json:9`; `platforms/cursor/hooks.json` preToolUse; `hooks/protect-other-branches.sh:394` |
| enforce-worktree-edits.sh | PreToolUse `Edit|Write|MultiEdit|NotebookEdit|StrReplace` | ENF | guards R1; can recreate a removed session worktree as a side effect | | same | `hooks/enforce-worktree-edits.sh:61-67,105` |
| guard-sensitive-files.sh | PreToolUse Edit-class and `Bash|Shell` | ENF (path-based, via `lib/write-targets.py`) | guards R1/R3 files | | `PM_ALLOW_PROTECTED=1` in hook env skips it | `hooks/guard-sensitive-files.sh:67,99` |
| docker-guard.py | PreToolUse `Bash|Shell` | ENF (regex deny) | guards R1 (docker state) | | inline `PM_ALLOW_DOCKER=1` in the command text approves | `hooks/docker-guard.py:54,62,170` |
| cursor-agent-tools-guard.sh | Cursor preToolUse/postToolUse | ENF (tool-name allowlist per subagent) | guards R-any by tool name | | `failClosed`; stale state drops after 3600s | `hooks/cursor-agent-tools-guard.sh:218` |
| goal-condition-lint.sh | UserPromptSubmit | ENF on the prompt (exit 2); the only non-tool gate | none | | | `hooks/goal-condition-lint.sh:231` |
| task-handoff-check.sh, teammate-idle-check.sh | TaskCompleted, TeammateIdle | ADV by design: the host offers exit 2 as a gate, these always exit 0 and emit `systemMessage` | none | | | `hooks/task-handoff-check.sh:25-30`; tail of both scripts |
| validate-report-links.sh | PostToolUse `Write` | ADV (emits `decision: block` after the write, cannot undo) | none | | contributor tier, default off | `hooks/validate-report-links.sh:81` |
| worktree-create.sh / worktree-remove.sh | WorktreeCreate / WorktreeRemove | lifecycle, ADV for permissions | R1 (`rm -rf` of a worktree path) | | | `hooks/worktree-remove.sh:57`; `worktree-create.sh:84,233` |
| session-init.sh, capture-task-slug.sh | SessionStart, UserPromptSubmit | lifecycle | R1 + code execution: create worktrees, run `npm ci`/`yarn`/`pnpm`/`bun`/`uv sync`/`cargo fetch`/`bundle install` from the repo's lockfile (lifecycle scripts of an untrusted repo run); default on | N M | `SUPERPOWERS_WORKTREE_INSTALL_DEPS=0` opt-out; install slot limiter | `hooks/lib/worktree-common.sh:266-271,417-463` |
| session-init.sh (cleanup) | SessionStart | lifecycle | R1: detached auto-delete of clean worktrees older than retention, `worktree remove --force` or `rm -rf` | | clean worktrees only; `SUPERPOWERS_WORKTREE_CLEANUP=0` | `hooks/lib/worktree-common.sh:675-680,728-731` |
| session-end.sh, release-agent-claims.sh, precompact-snapshot.sh, handoff-reminder.sh | SessionEnd, PreCompact | ADV | R1 (local files) | | | classification doc |
| usage-capture-ensure.sh | SessionStart | ADV | R1 (starts daemon) | | env opt-in | `hooks/usage-capture-ensure.sh:14-30` |
| ensure-exit.sh | UserPromptSubmit | ADV | R0 (N: `curl` through the user's proxy) | N | env-gated | `hooks/ensure-exit.sh:22` |
| notify.sh | Notification | ADV | R1 (osascript) | | | `hooks/notify.sh:45` |
| show-changelog.sh | SessionStart | ADV | R0 (runs `claude --version`) | | | `hooks/show-changelog.sh:10` |
| skill-creator-guard.sh | PreToolUse Edit-class | ADV despite name (additionalContext + allow) | none | | contributor tier off | `hooks/skill-creator-guard.sh:65-72` |
| check-done.sh, skill-suggest.sh, scope-decompose-reminder.sh, goal-compact-reminder.sh, plugin-reload-reminder.sh, directory-added.sh, rate-limit-handoff.sh, subagent-handoff-check.sh | Stop, UserPromptSubmit, PostToolUse, DirectoryAdded, StopFailure, SubagentStop | ADV | none | | `check-done.sh:2` "never blocks" | classification doc |
| cursor-workspace-open.sh | Cursor workspaceOpen | ADV | R0 | | | `platforms/cursor/hooks.json` |
| gemini-wrap.sh | wraps every Gemini hook | translator; always exits 0 | none | | translates exit 2 into `decision: deny` | `hooks/gemini-wrap.sh:25-30` |
| lib/hook-output.sh | all guards | dialect: `hook_allow`, `hook_deny` only. No `hook_ask`. Claude allow = `{}` (no decision); Cursor allow = explicit `{"permission":"allow"}` | | | | `hooks/lib/hook-output.sh:109-128` |
| lib/gemini-output.sh | Gemini | already translates Claude `permissionDecision: "ask"` | | | | `hooks/lib/gemini-output.sh:182` |

#### What each existing guard denies today, and what it would take (level-aware candidates, not a design)

| Guard | Denies today (exactly) | `gh pr merge` | `gh api -X DELETE` | `git push --force` | `git push origin --delete` | `git branch -D` | policy-file edit | GitHub MCP merge |
|---|---|---|---|---|---|---|---|---|
| protect-other-branches.sh | `git push` or mutating `gh pr|issue` verb or `gh api` mutating method on a PR/issue path, only when ANOTHER live agent holds a claim on that branch/PR/issue; denies when it cannot tell (no jq, unresolvable target, `--all`/`--mirror`, no refspec) | Parsed (`merge` in `GH_PR_VERBS`, `:177`) but only a claim check; allowed if nobody else holds it | Parsed only when the path matches `repos/o/r/(pulls|issues)/N` (`:226-247`); refs, branches, protection, repo paths ignored | Destination parsed, force flag discarded: `-*) :` at `lib/agent-claim.sh:551`; `+refspec` stripped | Recognised to find the destination (`agent-claim.sh:546`), no level | Not parsed at all | Not applicable (no write-target parse) | Not applicable (matcher `Bash|Shell`) |
| enforce-worktree-edits.sh | Edit-class tool writes whose target is a git checkout that is not a registered worktree or objective workspace; exempts `~/.claude` (`:105`) | no | no | no | no | no | exempts the Claude config dir, so a policy file there is outside it | no |
| guard-sensitive-files.sh | write targets (Edit-class and Bash-parsed) that are lockfiles, `.yarn/releases/*`, `.github/workflows/*`, shadcn `components/ui/*` when `components.json` exists, gitignored `dist|build|out|.next|target/*`; unresolvable shell writes become an advisory only | no | no | no | no | no | best host: add a path rule to `classify()` (`:99`); same parser covers Edit, Write, `sed -i`, `>`, `tee`, `cp` | no |
| docker-guard.py | `docker|podman|compose` run/create/start/up/build/pull/volume create/network create/prune and wrappers `make|npm run ... docker|e2e|db`; inline `PM_ALLOW_DOCKER=1` approves | no | no | no | no | no | no | no |
| cursor-agent-tools-guard.sh | Cursor only: a tool outside the active subagent's `tools:` list | no | no | no | no | no | no | could deny MCP tool names for subagents that do not list them (L) |

Candidate summary:
- git/gh Bash actions: protect-other-branches.sh already tokenises segments, resolves the repo slug, understands `cd`/`git -C`/`--repo`, and keeps a force flag in the OpenCode port (`platforms/opencode/plugin/rules.ts:468,606`). It is the natural host for push/merge/delete levels. Needs: a default-branch lookup (it never resolves one, by design: `:285`), a force flag, a `branch -D` detector, a non-PR `gh api` path/method classifier, and an `ask` output.
- File targets (policy file, workflows, guard scripts): guard-sensitive-files.sh `classify()`.
- docker-guard.py is the template for a regex ladder, but its inline self-approval token is the wrong shape for R3/R4 (D5).
- cursor-agent-tools-guard.sh is the only identity-aware guard (per subagent); the only candidate for "this agent may never call merge".

### B4 Mod (`mod/register.tsx`, `mod/modules.json`)

| Item | Max R | Flags | Behaviour | Evidence |
|---|---|---|---|---|
| `tool.check` / approval | none | | Not registered anywhere in `mod/`; no `{ deny }` return, no allow. `docs/engineering/architecture/mods.md:118` states "answers no `tool.check`, returns no `{ deny }` anywhere" | grep of `mod/` for `tool.check` found only docs |
| `on('tool.call')` objective_status | R0 | M A | answers the plugin's own read-only tool from `.dev-files/objectives/` | `mod/register.tsx:492-497` |
| `on('tool.call')` counter | R0 | | pass-through; `.catch(next)` | `register.tsx:547-550` |
| `on('agent.spawn')` | R0 | | only counts; `.catch(next)` so a failure never blocks a spawn | `register.tsx:360-364` |
| `on('prompt.submit')` | R0 | N? S | when `semantic_skill_suggest` is true, sends the first 2000 chars of long prompts to `$.model.classify`; adds a context note | `register.tsx:139,505-523` |
| `on('session.compact')`, `attribution.text` | R0 | | adds instructions; appends commit trailer | `register.tsx:571-598,599-603` |
| `$.fs`, `$.store` | R1 | | reads objectives, `CLAUDE.md`; writes two small store keys | `register.tsx:162-259,455,521` |
| `$.process`, network | none | | not used; Anthropic directory holds `MOD_RUNS_PROCESS`, `MOD_ANSWERS_PERMISSION`, `MOD_HOOKS_POLICY_EVENT` | `mods.md:113-118` |

### B5 MCP server (`.mcp.json`, `scripts/github-mcp.sh`, `platforms/{cursor/mcp.json,agent-plugins/mcp.json}`, `gemini-extension.json`, `opencode.json`)

One stdio server, `github`, started by one script on every platform: Claude `.mcp.json:5`, Cursor `platforms/cursor/mcp.json`, Codex `.codex-plugin/plugin.json` (`mcpServers: ./.mcp.json`), Gemini `gemini-extension.json`, OpenCode `opencode.json` (`bash scripts/github-mcp.sh`). Token: Claude `${user_config.github_token}`; Cursor `${GITHUB_TOKEN}`; OpenCode `{env:GITHUB_PERSONAL_ACCESS_TOKEN}`. The wrapper adds no restriction flag.

Tools the server exposes here (Claude id = `mcp__plugin_tamirs-superpowers_github__<tool>`). Max R is by tool, `arg` means it depends on arguments:

| Tool(s) | Max R | Notes |
|---|---|---|
| `get_*`, `list_*`, `search_*`, `issue_read`, `pull_request_read`, `get_me` | R0 | |
| `add_issue_comment`, `add_comment_to_pending_review`, `add_reply_to_pull_request_comment`, `update_issue_comment`, `sub_issue_write`, `request_copilot_review`, `assign_copilot_to_issue` | R2 | `assign_copilot_to_issue` starts a Copilot agent that may open PRs (cost, side effects) |
| `create_pull_request`, `create_branch`, `update_pull_request_branch` | R2 | |
| `issue_write` | R2 create, R3 on close | `state_reason` |
| `update_pull_request` | R2, R3 when closing or changing base | arg-dependent |
| `pull_request_review_write` | R2 comment, R3 approve/request changes | approval can satisfy required reviews |
| `create_or_update_file`, `push_files` | R2 on a non-default branch; R3 on the default branch (omitted branch = default); R4 when path is `.github/workflows/*`, a hook script, or a policy file | bypasses `guard-sensitive-files.sh`; the guard's own remedy tells the agent to use this tool (`guard-sensitive-files.sh:121`) |
| `delete_file` | R2 / R3 / R4 same as above | |
| `merge_pull_request` | R3 | merge method arg; no `--admin` equivalent, bounded by branch protection and token rights |
| `fork_repository` | R4 (UNCLASSIFIED rule; could be relaxed to R2) | creates a repo |
| `create_repository` | R4 | |
| `delete_repository` | R4 | needs the `delete_repo` PAT scope; fails with `repo`-only (M, GitHub API behaviour) |
| No tools for delete-branch, tag, release, ruleset in this tool list | n/a | force-push is impossible through MCP |

## C) Per-action catalog additions (dot-form ids)

"Point" = where a check can attach today. All Bash points are PreToolUse `Bash|Shell` (Claude, Codex, Cursor), `run_shell_command` (Gemini), `permission.hook("evaluate")` (OpenCode).

| id | R | Seen in | Enforcement point available | Currently gated by |
|---|---|---|---|---|
| git.commit | R1 | agents, pr-dev | none needed | none |
| git.push.branch (own branch) | R2 | `Bash(git push *)` allow | protect-other-branches.sh | claim check only |
| git.push.default | R3 | same | same, needs default-branch lookup | none (reproduced, D1) |
| git.push.force | R3 own branch, R4 default | same | same; Gemini policy rule `no-force-push` (`tamirs-superpowers.toml:24`); OpenCode `rules.ts:606` | Gemini and OpenCode only |
| git.branch.delete.local (`-D`) | R1 | Bash | Bash hook; Gemini rule `no-branch-force-delete` (`:33`) | Gemini only |
| branch.delete.remote (`git push --delete`, `:branch`, `gh api -X DELETE .../git/refs/...`) | R3 | Bash | Bash hook | claim check on `--delete` destination only |
| git.tag.create / release.create | R4 | `Bash(git tag *)` allow, `gh release` | Bash hook (not parsed) | none |
| pr.create | R2 | pr-dev, MCP `create_pull_request` | Bash hook, MCP matcher | none |
| pr.comment / issue.comment | R2 | `gh pr comment`, MCP | same | claim check on Bash side |
| pr.merge | R3 (R4 with `--admin`) | `gh pr merge --auto/--admin` in `skills/dev-workflow/pr-dev/SKILL.md:167,309,324`; MCP `merge_pull_request` | Bash hook; MCP matcher `mcp__plugin_tamirs-superpowers_github__merge_pull_request`; server `--exclude-tools` | claim check only on Bash; none on MCP |
| pr.close / issue.close | R3 | `gh pr close` | Bash hook; MCP `update_pull_request`/`issue_write` | claim check only |
| file.write.remote | R2/R3/R4 by branch and path | MCP `create_or_update_file`, `push_files`, `gh api -X PUT contents` | MCP matcher (inspect `branch`, `path`); Bash hook for `gh api` | none |
| workflow.edit | R4 | `.github/workflows/*` | guard-sensitive-files.sh (local only) | local writes only; MCP route open |
| repo.create | R4 | `Bash(gh repo create *)` allow, MCP `create_repository`, `fork_repository` | Bash hook; MCP matcher; server `--exclude-tools` | none |
| repo.delete | R4 | MCP `delete_repository`, `gh repo delete`, `gh api -X DELETE repos/o/r` | same | none |
| ruleset.apply / branch.protection.write | R4 | `scripts/github-policy.sh apply`, `gh api -X PUT .../protection` | Bash hook on script name and `gh api` path; script's own TTY confirm | TTY confirm or typed `--yes` |
| config.global.write | R4 | `setup.sh`, `install.sh`, `update.sh`, `uninstall.sh`, `usage-capture/enable.sh`, `capture-config.sh review` (staging) | Bash hook on those script names; guard-sensitive-files.sh for `~/.claude/**` targets | TTY confirm or typed `--yes` |
| policy.edit (permission policy file, guard scripts, `hooks.json`, `settings.d/*`) | R4 | any write | guard-sensitive-files.sh `classify()` (Edit and Bash targets) | none; `~/.claude` explicitly exempt from worktree rule |
| docker.state | R1 | docker-guard.py | PreToolUse | regex + self-approval |
| deps.install (hook-run `npm ci` etc.) | R1 + code exec | session-init, capture-task-slug | env `SUPERPOWERS_WORKTREE_INSTALL_DEPS` | opt-out only |
| worktree.cleanup (auto) | R1 | session-init | env `SUPERPOWERS_WORKTREE_CLEANUP` | clean-only |
| net.notify | R2 | notify-pushover.sh | tier switch | credentials absent = inert |
| proc.daemon | R1 | usage-capture-ensure.sh | env opt-in | env opt-in |
| mcp.read | R0 | MCP get/list/search | none needed | none |

## D) Findings

Severity: Critical, High, Medium, Low. Each ends with confidence.

**D1 High. Force-push, remote delete, merge, branch protection and `gh api` DELETE all pass the only Bash guard (H).**
Reproduced with crafted stdin, unclaimed repo, output was `{}` (allow) for every one: `git push --force origin feat`; `git push origin +feat:master` (force to the default branch); `git push origin --delete feat`; `git branch -D feat`; `gh pr merge 5 --repo example/demo --squash --admin`; `gh api -X DELETE repos/example/demo/git/refs/heads/feat`; `gh api -X PUT repos/example/demo/branches/master/protection`; `gh pr close 7 --repo example/demo`; also `make deliver`, `python3 -c 'os.system("gh pr merge ...")'` and a raw `curl -X DELETE https://api.github.com/...`. `bash -c '...'` was parsed (a claim file appeared). Cause: the guard is a concurrency guard, not a danger guard (`hooks/protect-other-branches.sh:1-14`), the force flag is dropped (`lib/agent-claim.sh:551`), and `gh api` is matched only on PR/issue paths (`:226-247`). The allow list also pre-approves `Bash(git push *)`, `Bash(gh api *)`, `Bash(gh repo create *)`, `Bash(python3 *)` (`permissions-allow.json:5,9,17,19`) and the default mode is bypass.

**D2 High. `core/policies/git.md` "no force-push" is enforced on 2 of 5 platforms only (H).** Gemini denies `git push --force|-f` and `git branch -D` through a static policy (`platforms/gemini/policies/tamirs-superpowers.toml:24,33`); OpenCode refuses every force push (`platforms/opencode/plugin/rules.ts:606`, default allows no prefix). Claude Code, Codex and Cursor, which run `protect-other-branches.sh`, do not. The guard with the richest feature set is the weakest on this rule.

**D3 High. The GitHub MCP server bypasses every Bash-level guard and every hook (H for wiring, L for host matcher behaviour).** No manifest has a hook matcher for an MCP tool name: `hooks/hooks.json` matchers are `Bash|Shell` and Edit-class; Cursor `preToolUse` has no matcher but its scripts read `tool_input.command`/`file_path` and so pass an MCP call; Gemini matchers are anchored `^(run_shell_command)$` and `^(replace|write_file)$`. Reachable R3/R4 tools: `merge_pull_request` (R3), `delete_repository` and `create_repository` (R4), `push_files`/`create_or_update_file`/`delete_file` onto the default branch (R3) or `.github/workflows/*` (R4). The repo's own guard message tells the agent to use `create_or_update_file` to edit a workflow (`hooks/guard-sensitive-files.sh:121`; the Gemini policy message and OpenCode `rules.ts:85` repeat it), so the sanctioned remedy is the unguarded path. `scripts/github-mcp.sh:25-30` passes no `--read-only`, `--toolsets`, `--tools` or `--exclude-tools`, although the installed v2.1.0 supports all four. Plugin agents are not exposed (allowlists list no GitHub tool); the main session and any agent without a `tools:` list (built-in general-purpose) are.

**D4 High. Mod override risk is latent, not present (H for today, M for the host fact).** The mod registers no `tool.check`, never returns deny, and its gating-site hooks pass through on failure (`register.tsx:293,364,527,550,597`; `mods.md:118`). The host fact (a mod `tool.check` can approve over a user deny on personal accounts) means adding any permission logic to the mod would be able to widen, not only narrow, a user deny rule. The directory also holds `MOD_ANSWERS_PERMISSION`/`MOD_HOOKS_POLICY_EVENT` (`mods.md:118`), so a permission-answering mod risks the submission. Also, its `.catch(next)` convention means a mod can never fail closed by default. Recommendation for the next stage (not a design): keep enforcement in bash hooks and settings deny rules, treat the mod as display only.

**D5 Medium. Agent-typed approval tokens turn deny into a suggestion (H).** `docker-guard.py:170` accepts `PM_ALLOW_DOCKER=1` in the command text and its deny message tells the agent to re-run with it (`:180-183`). `guard-sensitive-files.sh:67` reads `PM_ALLOW_PROTECTED` from the hook's own environment (an agent prefix does not reach it on Claude, but its deny message says "set it in the environment and retry" and OpenCode/Gemini have equivalents). `github-policy.sh` and `setup.sh` accept `--yes`/env twins an agent can type. For R3/R4 the approval channel must be one the model cannot write.

**D6 Medium. `hook_allow` is not neutral on Cursor (M).** On Claude it prints `{}` (no decision, user rules still apply); on Cursor it prints `{"permission":"allow"}` (`hooks/lib/hook-output.sh:109-114`), an explicit allow. Whether Cursor treats a hook allow as overriding its own `ask`/deny config is not measured here (L). A level-aware layer that emits `ask` needs a `hook_ask` helper; none exists, though `gemini-output.sh:182` already translates Claude `ask`.

**D7 Medium. Policy and guard files are unprotected (H).** No rule protects the permission policy file, `hooks/*.sh`, `hooks/hooks.json`, `platforms/claude/settings.d/*` or the installed plugin cache. `enforce-worktree-edits.sh:105` exempts `~/.claude` entirely, so an agent can edit `~/.claude/settings.json` or the cached copy of the guards; `guard-sensitive-files.sh:99-135` has no such rule. In a contributor worktree the guards are ordinary source. R4 by rubric.

**D8 Medium. Fail-open on two platforms (H).** `onFailure: "block"` exists only in `hooks/hooks.json` (4 guards). `platforms/codex/hooks.json` has no `onFailure` or `failClosed`; Gemini states fail-open (`core/capabilities/platforms.json`, gemini `hooks.notes`); Gemini hook firing is "NOT OBSERVED" (status `unknown`). Cursor uses `failClosed: true` (4 guards).

**D9 Medium. Unattended side effects on the hook path (H).** Session and prompt hooks run dependency installs from the repo's lockfile by default (`worktree-common.sh:266-271,417-463`: lifecycle scripts of whatever the checkout contains) and detached auto-deletion of clean worktrees (`:675-731`). Both R1, but code execution on an untrusted checkout with network, no prompt, in a hook.

**D10 Medium. Read-only is prose for five Bash-holding agents (H).** security-reviewer, spec-reviewer, performance-reviewer, debugging-specialist, orchestrator can run any command. Only architecture-reviewer and research-agent are read-only by capability. Cursor needs `cursor-agent-tools-guard.sh` just to honour `tools:`, and even that guard only gates by tool name (Bash is one name).

**D11 Medium. Global-config writers gate on a TTY, not on the harness (H).** `setup.sh`, `install.sh` (`--yes` baked in), `uninstall.sh`, `github-policy.sh apply` (up to `--all`/`--org`, org-level rulesets), `usage-capture/enable.sh` all reach R4. `capture-config.sh --adopt all` can carry an agent-made permission edit into the canonical source and from there to every platform, behind a PR that must be reviewed. Skills `github-policy`, `capture-config`, `usage-capture` are model-invocable.

**D12 Low. Dead or mismatched MCP allowlist in research-agent (L).** `mcp__claude_ai_Context7__*` vs `mcp__plugin_context7_context7__*`.

**D13 Low. Pre-approved `Bash(python3 *)` and `Bash(gh api *)` defeat any Bash prefix rule (H).** A static deny rule on `Bash(gh pr merge *)` is bypassed by `python3 -c`, `bash script.sh`, `make`, and by `curl` to the API (reproduced as allowed in D1). Text-level gates are reducible, not complete.

**D14 Low. Legitimate merges must stay possible.** pr-dev merges by design (`gh pr merge --auto ... --delete-branch`, `--admin` for a solo contributor, `pr-dev/SKILL.md:167,309,324-354`) and the user's rule allows merge when `/pr-dev` is active. A level-aware gate needs a way to recognise that context (skill-scoped state), or it will block the sanctioned path.

## E) Enforcement map

Cell legend: Y = a hook or policy wired today can host it; W = could host it with wiring only (no new platform feature); X = unreachable by any hook on that platform; ? = host behaviour not measured.

| Capability | claude | codex | cursor | gemini | opencode |
|---|---|---|---|---|---|
| Hook mechanism wired | `hooks/hooks.json` (PreToolUse) | `platforms/codex/hooks.json` | `platforms/cursor/hooks.json` | `platforms/gemini/hooks.json` via `gemini-wrap.sh` (unobserved) | none; TS plugin `platforms/opencode/plugin/guard.ts` |
| Bash command deny (push, merge, delete, force) | Y host: protect-other-branches.sh | Y host (same script) | Y host (same script) | Y host + static `policies/*.toml` | Y host: `guard.ts` + `rules.ts` |
| Bash command ask | W (needs `hook_ask`; under bypass ? ) | ? | W (Cursor dialect has ask, not emitted) | W (translator supports ask; policy allows `ask_user`) | W (`evaluate` hook can set effect) |
| Edit/Write path deny (policy file, workflows) | Y: guard-sensitive-files.sh | Y (apply_patch normalised) | Y | Y + static rule | Y |
| `~/.claude` or global config path | X (worktree rule exempts it; no sensitive rule) | X | X | X | X |
| GitHub MCP tool deny (merge, delete_repository, create_repository, file writes) | W: add matcher `mcp__plugin_tamirs-superpowers_github__.*` (L) | ? | W: `beforeMCPExecution` or the matcherless preToolUse, not wired (L) | W: policy `toolName`/`mcpName` rule (L) | ? permission rules for MCP actions; `guard.ts` covers `edit`/`shell` only |
| Server-level MCP restriction (`--read-only`, `--exclude-tools`) | Y via `scripts/github-mcp.sh` | Y same | Y same | Y same | Y same |
| Fail-closed on hook crash | Y (4 guards) | X | Y (`failClosed`) | X | ? (plugin throw) |
| Identity-aware (per subagent) | X | X | Y (`cursor-agent-tools-guard.sh`, tool-name only) | X | Y via per-agent `permissions:` rules from `build-opencode-agents.sh` |
| Static deny rules outside hooks | `permissions.deny` supported by host, not shipped | ? (exec policy rules not used) | `cli-config.json` supports deny; installer deliberately never writes it | Y: 5 deny rules shipped | `permissions:` ordered rules per agent |
| Survives `bypassPermissions` / auto mode | Y for hook deny (stated `docker-guard.py:9-11`); ask ? | ? | ? | ? | ? |

Unreachable by any hook on any platform today:
- Every MCP tool call (no wiring on any platform; GitHub MCP server is the same binary everywhere).
- Actions taken inside an interpreter, script, make target or `curl` (D1, D13): Bash hooks see the outer command string only; protect-other-branches has no UNSURE channel and returns allow.
- Anything done outside the session: the user's terminal, CI, other machines, scheduled or remote agents, the GitHub web UI.
- Writes under `~/.claude` (global settings, plugin cache, installed guards).
- Host-side state: Claude `permissions` and `autoMode`, which hooks cannot read or alter.
- On OpenCode: lifecycle hooks (no hooks.json); only `edit` and `shell` permission actions are guarded.
- On Gemini and Codex: guard failure (fail-open), and Gemini hook firing is unobserved.

## Counts

Audited: 10 agents; 16 script entries (setup, install, update, uninstall, github-policy, capture-config, notify-pushover, github-mcp, doctor, agent-health, collector, enable, probe-platform-versions, check-platform-targets, check-repo-description, statusline) plus the 13 build-* scripts and the setup lib set as one group each; 32 hook entry scripts, 8 libs, 4 manifests; 1 mod module with 11 handler sites; 1 MCP server with about 45 tools in 15 rows. Ungated R3/R4 paths: 9 (git push to default or force, remote ref delete, `gh pr merge` and `gh api` mutation, `gh repo create/delete`, branch protection via `gh api`, MCP merge, MCP file writes on the default branch or workflows, MCP repo create/delete/fork, edits to the policy and guard files).
