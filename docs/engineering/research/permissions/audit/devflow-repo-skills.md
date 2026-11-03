# Danger-score audit: dev-workflow and repo skills (objective permissions-design, task-004)

Read-only static audit of `skills/dev-workflow/**` and `skills/repo/**` (fixtures excluded). Paths are relative to `skills/` unless they start with `scripts/`. Nothing was executed.

## A) Method and assumptions

- Read each `SKILL.md` frontmatter and body, then followed every script/reference call (`gh`, `git push/branch/worktree`, `rm`, `curl`, writes outside the repo). R-levels follow the task rubric exactly (R0 observe, R1 local reversible, R2 shared-additive, R3 shared-mutating, R4 irreversible/privileged; unclear = R4).
- **All 14 audited dev-workflow and repo skills are `disable-model-invocation: false`, so all are model-invocable and subagent-reachable** (the flag columns below only list deviations: network, secrets). Only `diagnose-objective` scopes `Bash(...)` in `allowed-tools`; the other 13 omit Bash, so every `gh`/`git` call rides the ambient Bash permission, not a skill-scoped one.
- Secrets: no skill in scope reads or writes a credential file. `gh`/`git` use ambient auth (`gh auth status` only). `network` = any `gh`/`curl` call.
- Assumption A1: `git branch -D`, `git commit`, local merge/rebase are R1 (reflog undoes them); a force-removed dirty worktree or `rm -rf` of non-git content is **not** git-undoable and is scored R3 (local destructive, no rubric slot; conservative).
- Assumption A2: resolving/replying to a PR review thread is R2 (reversible, own PR), but flagged as a merge-gate input (see D-9).
- `scripts/github-policy.sh` (repo root, outside the scoped dirs) was read only for its gate (lines 14-76) because three in-scope skills call it.
- Not audited: `hooks/` (out of this audit's scope; covered by [`non-skill-surfaces.md`](non-skill-surfaces.md)) and the `_contract/templates` payloads (they are templates for generated repos, not steps this plugin runs).

## B) Per-skill table

| skill | max R | R-profile of steps | flags | existing gate | evidence |
|---|---|---|---|---|---|
| decision | R0 | R0 (`gh issue/pr view`) | network | none needed; read-only | decision/SKILL.md:98,164 |
| diagnose-objective | R1 | R0 reads; R1 writes `diagnosis.md` only | scoped Bash allowlist (3 scripts) | write-surface stated: "the only write" | diagnose-objective/SKILL.md:12-15,62,147 |
| plan-dev | R2 | R1 `.dev-files/` plan; R2 `gh issue create` | network | auto when the user's request asked for issues, else asks once (prose) | plan-dev/SKILL.md:217-228 |
| worker-dev | R1 | R1 commit + handoff in own worktree; push R2 only if dispatch said so | none | explicit MUST-NOT list (PR, auto-merge, merge base, out-of-scope write, push); scope enforced by `handoff.sh` (`--force` bypass exists) | worker-dev/SKILL.md:56-66; _shared/scripts/handoff.sh:115,142 |
| orchestrate-dev | R2 (R1 own; R2 via deliver-dev) | R1 worktree add, local merge of worker branches, state; R1 rebase of own branch | subagent fan-out | objective scope, `objective-state.sh validate`, one-PR rule; delegates push/PR to deliver-dev | orchestrate-dev/SKILL.md:168-250,300; references/early-start.md:12 |
| deliver-dev | R2 | R0 diff review; R1 gates; R2 push, `gh pr create`; records auto-merge policy (no merge call) | network | `integrate-ready` gate, red-gate stop, "never force-push / force auto-merge" (prose) | deliver-dev/SKILL.md:66,122-130,160-173,196 |
| start-dev | R2 | R1 edit/commit in worktree; R2 push + `gh pr create` (route C); hands to pr-dev | network | route A hard stop (no PR/merge); "never push default branch" (prose); Tier 2 before push | start-dev/SKILL.md:146,200-203,230-232 |
| pr-dev | R4 | R0 poll; R1 fix commits; R2 push/reply/rerun/update-branch; R3 auto-merge, issue close, remote-branch delete; R4 `--admin` | network; ambient `gh` auth | `resolve-merge-policy.sh` precedence (env, objective, policy.json, repo capability, default); "ask before merging" when policy=skip (prose); `--admin` "needs user intent" (prose) | pr-dev/SKILL.md:140-170,300-358,395,428; scripts/resolve-merge-policy.sh:12-14,416-418 |
| switch-dev | R2 | R1 handoff record; R2 `git push`, issue body/label/comment, label create | network | optional/skip-if-no-`gh`; local state wins (no confirmation) | switch-dev/SKILL.md:132,180,233-234; _shared/scripts/update-issue-resume.sh:103-128 |
| cleanup | R3 | R0 inventory; R1 build-dir rm, ff-sync; R3 remote-branch delete, forced worktree remove, `drop`, hard-reset option | network; subagent-spawn of pr-dev | interactive: per-item `yes`/`drop` waits (prose). `cleanup.sh`: dry-run default, `--yes` to execute, open-PR/dirty/ignored/unpushed guards | cleanup/SKILL.md:138-141,260,267,298,314,353-357; cleanup/scripts/cleanup.sh:34,133,172-206 |
| github-policy | R4 | R0 `audit/plan/verify`; R4 `apply` (rulesets), `--org-level` | network | **code-enforced**: per-change TTY confirm, `--yes` explicit, `GITHUB_POLICY_ALLOW_LIVE` for no-TTY, never-weaken/org CONFLICT refusal; no-TTY prints plan | github-policy/SKILL.md:54-65,112; scripts/github-policy.sh:14-76 |
| multi-agent-repo | R2 | R0 review; R1 plan files; R2 branch push + `gh pr create` (dev mode) | network | "Never merge", stops at PR; dev-only mode gate (prose) | multi-agent-repo/SKILL.md:226-227; references/mode-contracts.md:74 |
| repo-scaffold | R4 | R4 `gh repo create`; R2 initial push; R3 repo merge-settings PATCH; R4 `github-policy apply`; R1 writes in `/tmp/<repo>` incl. `.claude/settings.json` | network; model-invocable | one-line plan printed, then proceeds (no confirm); policy apply degrades to "not applied" without admin | repo-scaffold/SKILL.md:150,162,436,442,449,261 |
| repo-standards | R4 | R0 audit/ip-scan; R1 edits on `feat/repo-standards-setup`; R2 push+PR; R3 merge-settings PATCH; R4 `github-policy apply` | network | "Never merge. Never `gh repo create`."; apply relies on tool TTY gate; ip-scan acknowledgement | repo-standards/SKILL.md:186,209-211,231; references/polish-phases.md:11 |

Shared scripts: `_shared/scripts/resolve-worktree.sh` (R1: `worktree add/move`), `objective-state.sh`/`handoff.sh` (R1 state), `update-issue-resume.sh` (R2), `run-pre-pr-gates.sh` (runs repo `make`/pm test targets: R1 but executes repo code). `_contract/scripts/*` are check/score scripts (R0) except `enable-repo-merge-settings.sh` (R3), `ensure-branch-protection.sh` (R4 shim), `check-platform-targets.sh --sync` (curl + file write, R1) and `sync-contract-scripts.sh` (R1 copy).

## C) Per-ACTION catalog

Columns: id | R | skills | where | currently confirmed? (yes / no / partial; "partial" = prose or policy-resolver only)

### R0/R1 (listed for completeness, merged)

| id | R | skills | where | confirmed |
|---|---|---|---|---|
| repo.read (gh view/api GET, git log/diff) | R0 | all | e.g. pr-dev/scripts/fetch-pr-state.sh:66-72; decision/SKILL.md:98 | n/a |
| net.fetch.public (curl api.github.com / npm registry, `--sync`) | R1 | repo-standards (6b) | _contract/scripts/check-platform-targets.sh:267-295 | no (flag-gated `--sync`) |
| fs.state.write (`.dev-files/**`, handoffs, `diagnosis.md`) | R1 | plan/orchestrate/worker/deliver/diagnose/switch | _shared/scripts/objective-state.sh:131,178; handoff.sh:150,235; diagnose-objective/SKILL.md:147 | n/a |
| git.commit | R1 | worker, start, pr-dev, repo-standards, multi-agent | worker-dev/SKILL.md:129; pr-dev/SKILL.md:392 | n/a |
| git.worktree.add | R1 | orchestrate, start, switch | _shared/scripts/resolve-worktree.sh:203-209; early-start.md:7 | no |
| git.worktree.move (`--migrate`) | R1 | none by default | resolve-worktree.sh:~434 (dirty refused; `--confirm-dirty`) | yes (dirty refusal in code) |
| git.merge.local (workers into `objective/<id>`) | R1 | orchestrate | orchestrate-dev/SKILL.md:250 | no |
| git.rebase.own | R1 | orchestrate | references/early-start.md:12 | no |
| git.sync.ff (`fetch --prune`, `merge --ff-only`) | R1 | cleanup, pr-dev | cleanup.sh:105,254-255; cleanup-after-merge.sh:105-111 | partial (skips if dirty/diverged) |
| branch.delete.local (`git branch -D`) | R1 | pr-dev | cleanup-after-merge.sh:132 | no (no merged check) |
| fs.build_dirs.delete (`rm -rf` ignored dirs) | R1 (A1: R3 if any is not regenerable) | cleanup | cleanup.sh:225; cleanup/SKILL.md:298 | yes (skill `yes`; script `--yes`, check-ignore guard) |
| subagent.spawn | R1 | orchestrate, plan, start, pr-dev, cleanup, repo-* | `Agent` in allowed-tools (all) | n/a (inherits caller's permissions) |
| scaffold.local.write (incl. `.claude/settings.json` allow-list in the NEW repo) | R1 | repo-scaffold | repo-scaffold/SKILL.md:261; REPO_ROOT=/tmp/<repo> (:169) | no |
| worktree.remove (clean) | R1 | pr-dev, cleanup | cleanup-after-merge.sh:119; cleanup.sh:206 | partial |

### R2 shared-additive

| id | R | skills | where | confirmed |
|---|---|---|---|---|
| git.push.branch | R2 | deliver, start, pr-dev, switch, multi-agent, repo-scaffold, repo-standards | deliver-dev/SKILL.md:122; start-dev/SKILL.md:200; pr-dev/SKILL.md:395; switch-dev/SKILL.md:132; multi-agent-repo/SKILL.md:226; repo-scaffold/SKILL.md:436,474,482; repo-standards/SKILL.md:231 | no (default-branch ban is prose: start-dev/SKILL.md:230) |
| pr.create | R2 | deliver, start, multi-agent, repo-standards | deliver-dev/SKILL.md:130; start-dev/SKILL.md:201; multi-agent-repo/SKILL.md:227; repo-standards/SKILL.md:231 | no |
| pr.comment.reply (review reply POST) | R2 | pr-dev | pr-dev/SKILL.md:235 | partial (reply is stated in chat first, not gated) |
| pr.thread.resolve (GraphQL `resolveReviewThread`) | R2 (merge-gate input) | pr-dev | pr-dev/SKILL.md:241; scripts/resolve-thread.sh:39 | no |
| pr.review_request (`@codex review` comment) | R2 | pr-dev | pr-dev/SKILL.md:366 | no |
| ci.rerun (`gh run rerun --failed`, max 3) | R2 | pr-dev | pr-dev/SKILL.md:264 | partial (budget in prose) |
| pr.update_branch | R2 | pr-dev | pr-dev/SKILL.md:277 | partial (once, only when strict) |
| issue.create | R2 | plan-dev | plan-dev/SKILL.md:228 | partial (asks once unless user requested) |
| issue.edit.resume (body Resume block + owner line) | R2 | switch-dev | _shared/scripts/update-issue-resume.sh:103; switch-dev/SKILL.md:180 | no |
| issue.label.edit (add/remove `agent:*`) | R2 | switch-dev | update-issue-resume.sh:108,113; switch-dev/SKILL.md:233-234 | no |
| label.create (`agent:*`) | R2 | switch-dev | update-issue-resume.sh:111 | no |
| issue.comment (handoff comment) | R2 | switch-dev | update-issue-resume.sh:128 | no |
| objective.set_delivery (records auto-merge/PR url) | R1 | deliver, pr-dev | deliver-dev/SKILL.md:170; objective-state.sh:19 | n/a |

### R3 shared-mutating (or local-destructive per A1)

| id | R | skills | where | confirmed |
|---|---|---|---|---|
| pr.auto_merge.enable (`gh pr merge --auto --delete-branch`) | R3 | pr-dev (via start/deliver/cleanup) | pr-dev/SKILL.md:167,309; policy default `enable`: scripts/resolve-merge-policy.sh:416-418, pr-dev/SKILL.md:147 | partial (resolver; default = enable) |
| pr.merge (manual after readiness "ask") | R3 | pr-dev | pr-dev/SKILL.md:317-322 (command not shown) | partial (prose ask) |
| branch.delete.remote | R3 | pr-dev, cleanup | pr-dev/scripts/cleanup-after-merge.sh:124-126; cleanup/scripts/cleanup.sh:133; cleanup/SKILL.md:148; also `--delete-branch` at pr-dev/SKILL.md:167,309 | pr-dev script: no; cleanup.sh: partial (dry-run default, open-PR + regex guard); cleanup skill: yes (`yes` wait) |
| worktree.remove.force (dirty/ignored content lost) | R3 (A1) | pr-dev, cleanup | cleanup-after-merge.sh:119 (`--force` fallback); cleanup.sh:206; cleanup/SKILL.md:267 | pr-dev script: no; cleanup.sh: yes (dirty/ignored/unpushed guards); cleanup skill: partial |
| worktree.drop (user-chosen discard incl. gitignored) | R3 (A1) | cleanup | cleanup/SKILL.md:260 | yes (explicit `drop` per worktree) |
| git.reset_to_remote (local default branch) | R3 (A1) | cleanup | cleanup/SKILL.md:314 | yes (push/reset prompt) |
| issue.close (linked issues "if still open") | R3 | pr-dev | pr-dev/SKILL.md:428 | no |
| repo.settings.merge (PATCH `allow_auto_merge`, `delete_branch_on_merge`) | R3 | repo-scaffold, repo-standards | _contract/scripts/enable-repo-merge-settings.sh:14; repo-scaffold/SKILL.md:442; repo-standards/SKILL.md:209 | no |
| git.force_push (non-default branch) | R3 | none executes it | banned in prose: deliver-dev/SKILL.md:125; cleanup/SKILL.md:357 | n/a (latent, prose-only ban) |
| git.push.default_branch (non-force) | R3 | none intentionally (repo-scaffold pushes the new repo's initial default branch: R2 in context) | start-dev/SKILL.md:230 prose ban; repo-scaffold/SKILL.md:436 | no code guard |

### R4 irreversible / privileged

| id | R | skills | where | confirmed |
|---|---|---|---|---|
| pr.merge.admin (`--admin`, bypasses protection) | R4 | pr-dev | pr-dev/SKILL.md:324-358 | partial (conditions + "needs user intent" are prose; `admin_bypass_available` is advisory) |
| repo.create (`gh repo create ... --private`) | R4 | repo-scaffold | repo-scaffold/SKILL.md:162 | no (plan line printed at :152, then proceeds) |
| ruleset.apply (repo-level rulesets) | R4 | repo-scaffold, repo-standards, github-policy | repo-scaffold/SKILL.md:449; repo-standards/SKILL.md:211; github-policy/SKILL.md:110-112 | yes in code (scripts/github-policy.sh:14-76: TTY confirm; no-TTY prints plan) |
| ruleset.apply.org (`--org-level`, covers future repos) | R4 | github-policy | github-policy/SKILL.md:159-161 | yes (flag typed on purpose + confirm) |
| branch_protection.apply (legacy shim, default verb `apply`) | R4 | repo-scaffold/-standards (legacy callers) | _contract/scripts/ensure-branch-protection.sh:70-76 | partial (delegates to github-policy gate; verb defaults to write) |
| branch_protection.remove (Mode 5 migration last step) | R4 | github-policy | github-policy/SKILL.md:181-199 | partial (prose "never run for the user"; tool does not write classic) |
| git.force_push.default | R4 | none executes it | cleanup/SKILL.md:357 (prose ban) | n/a (latent) |
| release.tag / release publish | R4 | none executes (policy text only) | _contract/references/versioning-policy.md:39 | n/a |
| config.global.write (`~/.claude`, `~/.codex`, ...) | R4 | none found in scope | switch-dev/SKILL.md:308 states it does not | n/a |
| plugin.permission_policy.edit | R4 | none found in scope | - | n/a |

Merge note: `pr.auto_merge.enable` appears 3x in pr-dev prose (startup, merge section, loop) and as a policy record in deliver-dev; it is one action. `--delete-branch` is part of both auto-merge and the `--admin` merge, so it also implies `branch.delete.remote`.

## D) Findings (ungated or prose-only R3/R4)

| # | severity | finding | evidence | suggested minimal gate | confidence |
|---|---|---|---|---|---|
| D-1 | High | `cleanup-after-merge.sh` deletes the remote branch, `git branch -D`s the local one and force-removes the worktree for whatever `headRefName` the PR has. It never checks the PR is `MERGED`, never compares the branch to the default/base branch, never checks `isCrossRepository` (a fork PR whose head is named like an origin branch) and has no protected-branch test; the worktree removal falls back to `--force` (loses uncommitted work). Callers say "after merge" but the script trusts that. | pr-dev/scripts/cleanup-after-merge.sh:73,119,124-126,132; no `state`/`MERGED` match in file | refuse unless `gh pr view --json state,isCrossRepository` is `MERGED`/false and `BRANCH != base/default`; drop the `--force` fallback (or ask) | High (absence of checks confirmed by grep) |
| D-2 | High | `--admin` merge (R4, bypasses required checks/linear history/thread resolution) is governed only by prose ("two cases and no others", "still requires user's merge intent"). `admin_bypass_available` tells whether it would work, not whether it is allowed. | pr-dev/SKILL.md:324-358 | classify `pr.merge.admin` R4 never-auto; require an explicit per-call permission prompt, independent of any merge policy | High |
| D-3 | High | `repo-scaffold` runs `gh repo create` (R4) as soon as it prints a plan line; there is no confirmation. Repo name/description are derived from free text, the skill is model-invocable and subagent-reachable. | repo-scaffold/SKILL.md:150,162 | gate `repo.create` (R4) with a per-call prompt showing owner/name/visibility | High |
| D-4 | High | `enable-repo-merge-settings.sh` PATCHes repository settings (`allow_auto_merge`, `delete_branch_on_merge`) with no dry-run, plan or confirmation, and is called unconditionally by repo-scaffold and repo-standards polish before the guarded `github-policy apply`. It is the switch that makes the default auto-merge path (D-5) possible. | _contract/scripts/enable-repo-merge-settings.sh:14-16; repo-scaffold/SKILL.md:442; repo-standards/SKILL.md:209 | add an `--apply` default-off (print the PATCH otherwise), or route through `github-policy.sh` | High |
| D-5 | Medium | Default merge policy is `enable` auto-merge with `--delete-branch` whenever the repo allows it (R3 with no per-PR confirmation). The resolver is a real gate (env override, objective, `.dev-files/policy.json`, repo capability) but its default and the three precedence lists differ: deliver-dev lists 4 rules and omits `TAMIRS_AUTO_MERGE` and `policy.json`; pr-dev lists 5. The "ask" branch for `skip` is prose. | pr-dev/SKILL.md:140-170; deliver-dev/SKILL.md:160-167; scripts/resolve-merge-policy.sh:12-14,416-418 | permission level should own the default (standard: OFF unless configured); deliver-dev should reference the resolver instead of restating precedence | High |
| D-6 | Medium | `cleanup.sh --yes` (unattended): (a) protection is a name regex (`main/master/develop/release/*/hotfix/*`), not GitHub's `protected` flag that the interactive skill requires; (b) `git branch -r --merged` also lists branches pointing at the default tip (just-created, no commits yet), which are then deleted; (c) the unpushed-commit test `git log origin/<b>..HEAD 2>/dev/null` yields empty when `origin/<b>` does not exist, and "remote branch gone" is then treated as merged, so a clean in-flight worker worktree with local-only commits can be force-removed (its branch ref survives). | cleanup/scripts/cleanup.sh:98,108-110,133,189-206; cleanup/SKILL.md:353 | skip branches with `ahead==0` and require `protected==false` via API; treat a missing `origin/<b>` with local commits as unpushed; skip `.agent-worktrees/**` of non-terminal objectives | Medium (read-only inference of git behaviour; not executed) |
| D-7 | Medium | `pr-dev` can resolve review threads and reply with no gate; the canonical solo posture makes thread resolution the real merge gate, so resolving another person's thread is a gate-opening R2. Reply text is "stated in conversation", which is a notice, not a confirmation. | pr-dev/SKILL.md:235-241; github-policy/SKILL.md:219 | allow auto-resolve only for threads the agent replied to and fixed; keep human-authored threads at R3 | Medium |
| D-8 | Medium | `ensure-branch-protection.sh` (legacy name still called by older scaffolded repos) defaults to the **apply** verb; only `--verify-only` makes it read-only. The downstream `github-policy` gate saves it, but the R4 entry point hides behind a read-sounding name. | _contract/scripts/ensure-branch-protection.sh:70-76 | classify the shim by name as R4; or flip its default to `audit` | High |
| D-9 | Medium | The `github-policy` gate is TTY-based (prompts go to `/dev/tty`; no TTY prints the plan). In an agent Bash there is no TTY, so `apply` can never succeed there except via `GITHUB_POLICY_ALLOW_LIVE=1`, which the skill forbids agents to set in prose only. Skill text "confirms each change at the terminal" (repo-standards:211) is misleading for agent runs. | github-policy/SKILL.md:62; scripts/github-policy.sh:50-51,76; repo-standards/SKILL.md:211-215 | the permission layer, not an env var, should be the declared owner of unattended R4 | Medium |
| D-10 | Low-Med | `pr-dev` closes linked issues manually after merge (`gh issue close`, R3) with no confirmation; GitHub's `Closes #N` already does this on merge. | pr-dev/SKILL.md:428 | drop the step or classify `issue.close` R3 ask | High |
| D-11 | Low-Med | Push has no default-branch guard in skill code; bans are prose (`start-dev` "Never push directly to the default branch", deliver-dev/cleanup "never force-push"). No in-scope script force-pushes, so the exposure is behavioural. The worktree hooks (not audited) may add a guard. | start-dev/SKILL.md:230; deliver-dev/SKILL.md:125; cleanup/SKILL.md:357 | classify `git.push.default_branch` R3 and `git.force_push*` R3/R4 in the policy so the layer, not prose, enforces them | Medium |
| D-12 | Low | `update-issue-resume.sh` and `switch-dev` GitHub writes resolve the repo from cwd and accept no `--repo` (pr-dev's own docs call the same hazard a "wrong answer, not an error"). Issue body is rewritten wholesale from a read-modify-write (race with human edits). | _shared/scripts/update-issue-resume.sh:41,103; pr-dev/SKILL.md:116-120 | require explicit repo in the action id context | Medium |
| D-13 | Low | `handoff.sh --force` bypasses the scope guard (R1, but weakens the integrator's trust boundary); only the worker-dev contract says never to use it. | _shared/scripts/handoff.sh:115,142-144,227-229 | keep `handoff.sh --force` out of any auto-allow | High |
| D-14 | Info | `repo-scaffold` writes a `.claude/settings.json` permissions allow-list into each generated repo: policy-adjacent content authored by a model, not the plugin's own policy (so R1 here). | repo-scaffold/SKILL.md:261 | cover it when ADR 004 defines what a generated repo inherits | Medium |

Counts: 14 findings; **ungated or prose-only R3/R4 actions: 8** (D-1 branch/worktree deletion, D-2 `--admin`, D-3 repo.create, D-4 repo.settings.merge, D-5 default auto-merge [resolver-only], D-8 shim apply, D-10 issue.close, D-11 default-branch/force push [prose-only ban]); code-enforced R4 (`ruleset.apply`) is the one well-gated action.

## E) Level-fit preview (table only)

supervised = ask for every R2+. standard = R2 automatic, R3 ask, auto-merge OFF unless configured. unattended = R3 automatic unless flagged never-auto; R4 never automatic. `*` = R3 whose loss is not git-recoverable (candidate for a never-auto flag; decision deferred to ADR 004). R4 rows prompt at every level.

| action | R | supervised | standard | unattended |
|---|---|---|---|---|
| repo.read, fs.state.write, git.commit, git.worktree.add/move, git.merge.local, git.rebase.own, git.sync.ff, branch.delete.local, worktree.remove (clean), subagent.spawn, scaffold.local.write, objective.set_delivery, net.fetch.public | R0-R1 | auto | auto | auto |
| fs.build_dirs.delete | R1 | auto | auto | auto |
| git.push.branch | R2 | ask | auto | auto |
| pr.create | R2 | ask | auto | auto |
| pr.comment.reply, pr.review_request | R2 | ask | auto | auto |
| pr.thread.resolve | R2 | ask | auto | auto |
| ci.rerun, pr.update_branch | R2 | ask | auto | auto |
| issue.create, issue.edit.resume, issue.comment, issue.label.edit, label.create | R2 | ask | auto | auto |
| pr.auto_merge.enable | R3 | ask | ask (auto only if `delivery.auto_merge` / `TAMIRS_AUTO_MERGE=always` configured) | auto |
| pr.merge (manual) | R3 | ask | ask | auto |
| branch.delete.remote | R3 | ask | ask | auto |
| issue.close | R3 | ask | ask | auto |
| repo.settings.merge | R3 | ask | ask | auto |
| worktree.remove.force* | R3 | ask | ask | auto* |
| worktree.drop* | R3 | ask | ask | auto* |
| git.reset_to_remote* | R3 | ask | ask | auto* |
| git.push.default_branch | R3 | ask | ask | auto |
| git.force_push (non-default)* | R3 | ask | ask | auto* |
| pr.merge.admin | R4 | ask | ask | ask (never auto) |
| repo.create | R4 | ask | ask | ask (never auto) |
| ruleset.apply, ruleset.apply.org | R4 | ask | ask | ask (never auto) |
| branch_protection.apply / .remove | R4 | ask | ask | ask (never auto) |
| git.force_push.default | R4 | ask | ask | ask (never auto) |
| release.tag, config.global.write, plugin.permission_policy.edit (none present in scope) | R4 | ask | ask | ask (never auto) |

Prompt counts for one typical objective run (deliver, drive, merge, clean up), by level: supervised about 6 prompts (push, PR create, reply/resolve batches, auto-merge, remote-branch delete); standard 2 (auto-merge decision unless configured, remote-branch delete); unattended 0 plus R4 when it occurs.
