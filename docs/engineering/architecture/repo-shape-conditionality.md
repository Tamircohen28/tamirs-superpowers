# Repo-shape conditionality

Where this plugin hardcoded assumptions that are only true for *some* repositories.

**Status:** most findings were implemented on branch `feat/github-policy`; see the
STATUS column. This document is kept because the unfixed rows are a real backlog and
the fixed rows record *why* each default is what it is — that reasoning is otherwise
only in commit messages.

## Status of the major findings

| # | finding | status |
|---|---------|--------|
| §0.1 | `required_approving_review_count` derived, not stored | **done** — `1 if (bypass AND collaborators > 1) else 0` |
| §1 | 11 hardcoded default-branch sites | **done** — shared helper that exits 1 rather than guessing; static check prevents regression |
| §1 | scaffold templates pushed to `master` while `gh repo create` makes `main` | **done** — generated workflows carry no `on.*.branches` filter |
| §2 | archived/fork repos skipped rather than "brought into compliance" | **done** |
| §3 | `pr-dev` naming this repo as the `--admin` case | **done** — derived from solo + bypass |
| §3 | merge method chosen unconditionally | **done** — reads all three merge flags |
| §4 | `run-pre-pr-gates.sh` exiting 0 with no Makefile | **done** — fails loudly with a named cause |
| §4 | stack detection covering 6 languages, silent otherwise | **done** — widened; reports "unknown, no commands" |
| §5 | `doctor.sh` hard-failing on non-plugin repos | **done** |
| §5 | shadcn guard blocking hand-written `src/components/ui` | **done** — keys on `components.json` |
| §5 | Tier-3 done requiring green CI on repos with no CI | **done** |
| §6 | contract asserting non-universals | **partial** — 27 `_when_*` conditionals added; docs-tree tiering by purpose remains |
| §6 | S4-04 (auto-merge) scored as a defect | **open** — a team-norm preference, same class as the retired S4-03 |
| §5 | `wix-ip-guard.sh` patterns hardcoded in a shipped hook | **open** — should read a user-level list |
| §5 | captured config always promoted machine-global | **open** — some settings are legitimately per-repo |

---


What in this plugin hardcodes an assumption that is only true for *some* repositories.
Read-only audit, branch `feat/github-policy`. All paths relative to the repo root.

---

## 0. Direct answers first

### 0.1 What should `required_approving_review_count` be for a solo private repo with an admin bypass actor?

**0. Keep it at 0, and remove the bypass actor instead of raising the count.**

With one collaborator who is also the admin, a review requirement of ≥1 has exactly
two possible outcomes: the owner self-approves (GitHub permits this on a PR they did
not author — but they authored all of them, so it is unsatisfiable), or the owner
merges with `--admin`. The second is what actually happens, and it does not skip only
the review rule — `--admin` bypasses **required status checks, linear history, and
thread resolution at the same time**. So a review count of 1 on a solo repo converts
a green-CI gate into a bypass habit. That is a net *loss* of safety, and the policy
file already says so at `config/github/repository-policy.json:96`.

The real gate on a solo repo is `required_review_thread_resolution: true`
(`repository-policy.json:103`) — a bot review (Copilot, CodeQL, a Claude reviewer)
opens threads, and the merge blocks until they are resolved. That is a review
requirement that a single human can genuinely satisfy without a bypass.

The one case where ≥1 is right is the one this repo already documents at
`repository-policy.json:133`: a repo that carries an admin bypass actor **and** may
receive outside PRs. There the count binds collaborators while the owner keeps the
escape hatch. Note the asymmetry that makes it coherent — the count is only
meaningful *because* the bypass exists. On a repo with no bypass actor, raising the
count to 1 is unsatisfiable, not stricter. **The correct derivation is therefore
`count = 1 if (bypass_actor_present AND collaborators > 1) else 0`**, and both
inputs are readable from the API.

### 0.2 Is a repo-profile concept already latent here?

Yes, three of them, and they are weaker than they look. A shape system should extend
these, not add a fourth.

- **`skills/repo/_contract/scripts/detect-contract-profile.sh`** — 15 lines. It tests
  exactly one thing: `[[ -d "$ROOT/canonical/rules" ]]` (line 11) → `plugin-gold`,
  else `app-gold`. That is the *entire* profile system. It reads no manifest, no
  language, no visibility, no ownership.
- **`skills/repo/repo-scaffold/scripts/detect-stack.sh`** — 74 lines. Emits one of
  `nextjs | node | python | swift | generic | plugin-hint`. File signals are only
  `next.config.*` (L41), `package.json` + grep `"next"` (L44-48), `pyproject.toml` /
  `requirements.txt` / `setup.py` (L50), `Package.swift` (L53). Everything else falls
  through to **description keyword matching** (L16-37) — i.e. the profile of a new
  repo is decided by prose. It cannot detect Go, Rust, Ruby, Java, PHP, .NET, Elixir,
  Deno, Bun, Terraform, Docker; it cannot tell pnpm/yarn/bun from npm; and
  `plugin-hint` is reachable *only* from description text, never from files.
- **`scripts/github-policy.sh:284-306`** (`list_repos_paged`) — already fetches
  `full_name, fork, archived, default_branch, owner.type` per repo. This is the
  closest thing to a real shape probe in the codebase, and it is the right place to
  extend: adding `visibility` and a collaborator count to that one `jq` selector
  gives every dimension section 0.1 needs.

So: one binary profile (`canonical/rules` present?), one keyword-driven stack guess,
and one already-paginated fact fetcher that stops two fields short. The gap between
them is the whole finding.

### 0.3 The smallest change that captures most of the value

Three edits, in this order. Everything else in this report can wait.

1. **Stop guessing the default branch — anywhere.** The policy file bans literal
   branch names and `scripts/check-github-policy.sh:76-84` enforces that ban *inside
   the policy file only*. Eleven places outside it still hardcode one
   (§1). Extend the existing scanner to the skills/scripts/hooks tree and add one
   shared `default_branch()` helper that reads `origin/HEAD` and **fails** rather
   than falling back. `hooks/protect-other-branches.sh:244-274` already does exactly
   this — promote it, don't reinvent it.
2. **Add two fields to `list_repos_paged`** (`scripts/github-policy.sh:298-302`):
   `visibility` and collaborator count. Then derive `required_approving_review_count`
   per §0.1 instead of storing it per-repo in `repositories.<owner/repo>`.
3. **Make `run-pre-pr-gates.sh` fail loudly on a repo it does not understand**
   instead of `exit 0`. Today a repo with no Makefile silently passes a gate
   described as mandatory (§4).

That is one shared helper, two jq fields, and one exit code. No new config file, no
profile prompt, no user-facing question. Everything else below is a follow-on.

---

## 1. The default branch — the single largest cluster

`config/github/repository-policy.json:9` states the rule correctly and gives the
reason (15 of 19 repos default one way, 4 the other). The rule is enforced only
against that one JSON document. Outside it:

| what | where | assumed | actually depends on | risk if wrong |
|---|---|---|---|---|
| `DEFAULT_BRANCH="${DEFAULT_BRANCH:-master}"` | `skills/dev-workflow/pr-dev/scripts/cleanup-after-merge.sh:57` | master | `origin/HEAD` | cleanup checks out a branch that does not exist on 15/19 repos |
| fallback `main` | `skills/dev-workflow/_shared/scripts/objective-state.sh:118`; `resolve-worktree.sh:108,113` | main | same | **contradicts the line above** — two scripts in one skill guess opposite ways |
| `--base master` in the capture PR command | `scripts/capture-config.sh:742` | master | repo default | copy-pasted `gh pr create` fails |
| `origin/main` in the resume protocol | `core/global-rules.md:95` (×2) | main | repo default | the duplicate-PR guard silently inspects a nonexistent ref and never fires |
| `origin/master` in the version-bump rule | `rules/dev/plugin-version-bump.md:102,107,148` | master | repo default | rule is `alwaysApply: true`; the release check returns garbage on a main repo |
| `${DEFAULT_BRANCH:-main}` in the worked example | `rules/dev/git-worktree-agent-workflow.md:86` | main | repo default | most-copied snippet in the tree; re-seeds the literal |
| `branches: [master]` ×8 + `git push origin master` | `skills/repo/_contract/templates/legacy-scaffold-templates.md:249,251,281,283,312,314,336,338`; `repo-scaffold/SKILL.md:110,409` | master | **`gh repo create` makes `main`** | a freshly scaffolded repo pushes to a nonexistent branch and its CI never triggers |
| default-branch guardrail enumerates 3 names | `skills/dev-workflow/start-dev/SKILL.md:232` | main/master/develop | actual default ref | a `trunk` default is not guarded against direct push |
| fallback to `main` on symbolic-ref failure | `rules/dev/gh-cli-preference.md:49` | main | remote HEAD | fresh clone with unset `origin/HEAD` → every downstream compare is wrong |

**Rank: A (derive).** There is no preference here to configure — the answer is a fact
in the remote. The counter-example to copy is `scripts/github-policy.sh:618`
(`resolve_branch` from the API) and `hooks/protect-other-branches.sh:244-274` (refuses
to guess; denies instead).

---

## 2. `config/github/repository-policy.json` — beyond approvals

| setting | line | current | should depend on | recommended by shape |
|---|---|---|---|---|
| `required_approving_review_count` | 102, 134 | 0 canonical / 1 for this repo | bypass actor × collaborator count | see §0.1 — derive, do not store per-repo |
| `bypass_actors: []` vs live drift | 70, 79 | canonical empty; live repo has RepositoryRole 5 `always` | solo vs team | solo: **empty** is right, and the count follows. Team: bypass + count 1 |
| `strict_required_status_checks_policy` | 27, 90 | false, with a long correctness argument | the *development architecture*, not the repo | **C — correctly universal for this fleet.** The O(N²) argument at line 22 holds for any parallel-worker repo. It would be wrong only for a low-PR-volume repo where staleness matters more than throughput. Leave it; the comment already forbids changing it without changing the architecture |
| `required_linear_history` | 82 | always on | merge model | **C.** Genuinely universal here — it is what makes strict-off safe. Do not decouple these two |
| `deletion` / `non_fast_forward` | 58, 62 | default branch only | — | **C.** Should arguably *extend* to release branches (`release/*`, `stable`) where a release model exists. Currently no non-default branch has any protection |
| `allowed_merge_methods: [merge, squash, rebase]` | 98 | all three permitted | — | **C** at the policy layer. The bug is downstream: `pr-dev` picks squash unconditionally (§3) |
| `default_contexts: []` | 24 | empty for every repo | the repo's own CI job names | **A.** Correct that it is per-repo, but a scaffolded repo generates jobs named `CI` and `secret-scan` and then never registers them, so it merges on red until hand-edited. Register generated job names at scaffold time |
| `do_not_enforce_on_create` | 29, 89 | true | — | **C** |
| Actions concurrency classification | 157-228 | pattern-based, `unclassified_action: "report"` | — | **C, and the model to imitate.** It classifies by evidence, declares a precedence, and refuses to guess on unknown input. This is the shape system the rest of the plugin needs |
| **Missing entirely**: `allow_auto_merge`, `delete_branch_on_merge`, `allow_update_branch` | — | not in the policy at all | team norms | these are asserted by `score-standards-gaps.sh:124-125` as universal goods but are not policy content; move them in or drop the assertions |
| **Missing entirely**: visibility, fork, archived | — | policy applies uniformly | — | an archived repo should be skipped, not "brought into compliance". `github-policy.sh:284` already reads both flags |

---

## 3. `skills/dev-workflow/**`

| assumption | where | actually depends on | rank |
|---|---|---|---|
| "**This repository (`tamirs-superpowers`) is exactly that case: `--admin` is its normal merge path**" | `pr-dev/SKILL.md:306` | the repo the agent is *in* | **A.** The single most repo-specific line in the tree. A team repo inheriting this bypasses its own protection. Derive from collaborator count + bypass actor |
| Squash chosen unconditionally; falls back to `merge`, never `rebase` | `pr-dev/scripts/resolve-merge-policy.sh:80,94` | `squash/merge/rebaseMergeAllowed` | **A** — all three flags are already fetched two lines away |
| `DELETE_BRANCH=true` always; "**Always** delete the remote branch" | `resolve-merge-policy.sh:83`; `pr-dev/SKILL.md:409` | long-lived / protected head branches | **A** (check head-branch protection) |
| Auto-merge enabled by default unless `.dev-files/policy.json` opts out | `resolve-merge-policy.sh:135-136`; `deliver-dev/SKILL.md:168` | team norms | **B** — a genuine preference. But note: with `jq` absent (`resolve-merge-policy.sh:65,89`) the opt-out file is *silently discarded* and the default wins. Fix that regardless |
| Admin bypass inferred from `viewerPermission == ADMIN` | `resolve-merge-policy.sh:95-99` | org rulesets can block admins too | **A** — read the ruleset's bypass actors, which the policy file already models |
| Branch protection API assumed readable | `resolve-merge-policy.sh:107-119` | 404s when absent *or* when the token lacks scope — indistinguishable | **A**, and today a strict base reads as loose (`pr-dev/SKILL.md:272`) |
| ≥1 check exists; `length>0 and all(...)` | `pr-dev/references/ci-monitor-loop.md:25` | repo having CI | **A.** A no-CI PR polls to the 30-minute timeout instead of merging |
| `reviewDecision=REVIEW_REQUIRED` is terminal | `pr-dev/SKILL.md:295`; `ci-monitor-loop.md:83` | a second human existing | **A** — same derivation as §0.1 |
| Merge queue probed but errors discarded | `resolve-merge-policy.sh:123-129` | GHES version / token scope | **A** — a queue-enabled repo never triggers the queue branch and pr-dev fights the queue |
| No CODEOWNERS awareness anywhere in dev-workflow | grep: zero hits | CODEOWNERS + `require_code_owner_review` | **A.** Meanwhile `repo-scaffold/SKILL.md:282` writes a CODEOWNERS file that, at review count 0, is decorative |
| GitHub is the only forge | `fetch-pr-state.sh:36-37,48`; `resolve-thread.sh:27`; `update-issue-resume.sh:41,103` | — | **B/C** — a defensible scope limit, but `fetch-pr-state.sh:36` is `set -euo pipefail` with no guard, so it hard-exits rather than reporting "not GitHub" |
| Issue-driven workflow (`gh issue`, `agent:*` labels) | `plan-dev/SKILL.md:238`; `start-dev/SKILL.md:61`; `switch-dev/SKILL.md:66` | Issues enabled; labels pre-created | **A** (detect) — `gh issue create --label` on an unknown label aborts a plan export mid-way |
| PR body must carry `Closes #N` + attribution | `start-dev/references/pr-templates.md:27,46,68,94,111` | vs `deliver-dev:153` which says follow `.github/pull_request_template.md` | **A** — two competing instructions; prefer the repo's template when present |

---

## 4. Stack and test-command assumptions

| assumption | where | rank |
|---|---|---|
| **`run-pre-pr-gates.sh` exits 0 when no Makefile exists** | `_shared/scripts/run-pre-pr-gates.sh:17-20,29,35,41` — targets `repo-standards-gate`, `agent-polish-gate`, `agent:check` | **A, highest severity in this section.** The gate is documented as mandatory and is a silent no-op in essentially every third-party repo. `deliver-dev`/`pr-dev` then report gates as run |
| "In this repository … `make validate`" presented as *the* gate | `deliver-dev/references/pre-pr-gates.md:37-38` | **A** |
| `make validate` blocks the capture PR | `scripts/capture-config.sh:709-715` | **A** — capture is unusable outside this repo |
| Stack detection = fixed 6-language whitelist with fixed commands | `start-dev/scripts/detect-stack.sh:24-101` — `python -m pytest` even with no pytest; `bundle exec rspec` even for minitest | **A.** Java/Kotlin/PHP/.NET/Elixir/Swift/Bazel emit **zero** commands → step 4 of start-dev validates nothing and reports success |
| Package manager from lockfile only; no lockfile ⇒ npm | `detect-stack.sh:51-57` | **A** — misses `packageManager`, bun, corepack |
| Worktree dep install is JS-or-poetry only | `hooks/lib/worktree-common.sh:365-386` | **A** — Go/Rust/uv worktrees come up without deps; the log does not say why |
| Lockfile-hash skip keyed to the same JS set | `worktree-common.sh` `worktree_lockfile_hash`, used :356-360 | **A** — non-JS repos get an empty hash, so work is redone or skipped every create |
| `DEV_PORT` written into `.env.local` | `worktree-common.sh:207-221` | **B** — harmless noise outside Next/Vite, but silently behaves differently depending on gitignore |
| Tier-1 validation menu is jest/vitest/tsc/pytest/go/cargo/shellcheck | `worker-dev/references/tier-1-validation.md:37-43`; `plan-dev/SKILL.md:179` | **A** — workers fabricate plausible `--validation` entries for commands that do not exist |
| CI evidence sample is npm | `pre-pr-gates.md:60-62` | **A** |

---

## 5. `hooks/**` and machine-vs-repo scope

| assumption | where | rank |
|---|---|---|
| `.github/workflows/*` always protected, remedy is GitHub MCP | `hooks/guard-sensitive-files.sh:26-27` | **A** — wrong for GitLab/Buildkite/no-CI repos, and the offered remedy may not be configured |
| Same guard blocks `*/src/components/ui/*`, `*/.yarn/releases/*`, `*/dist/*`, `*/build/*` | `guard-sensitive-files.sh:26` | **A.** `src/components/ui` is hand-written source in every non-shadcn repo; the denial explains it as "generated shadcn UI" |
| Tier-3 definition-of-done requires green CI (`gh run list`, `gh pr checks`) | `hooks/check-done.sh:89,94` | **A** — a CI-less repo can never satisfy done; agents block or fabricate |
| Every repo carries `plugin-version.json` / `plugin.json` / `marketplace.json` | `scripts/check-version-truth.sh:50,175`; `scripts/doctor.sh:68-74`; `hooks/plugin-reload-reminder.sh:25` | **A** — `doctor.sh` emits a hard `bad "no canonical version"` for any ordinary app repo. `detect-contract-profile.sh` already answers this question; use it |
| Any `SKILL.md` write must route through `/skill-creator` | `hooks/skill-creator-guard.sh:20-23` | **A** — blocks editing a vendored or third-party SKILL.md |
| `.dev-files/` objectives assumed present | `hooks/skill-suggest.sh:120-121` | **A** — `rules/dev/dev-files-workspace.md:86` says opting in is per-repo *and this repo does not opt in*, while the rule declares `alwaysApply: true` |
| platform-sync trigger keys on `CHANGELOG.md` alone | `hooks/skill-suggest.sh:111` | **A** — fires in every repo |
| Global worktree layout `~/.claude/worktrees/<repo>/<slug>` stated as *the* policy | `worktree-common.sh:4`; `session-init.sh:136`; `enforce-worktree-edits.sh:129` | **A** — `objective-common.sh:26-31` already supports `.agent-worktrees/` + `SUPERPOWERS_AGENT_WORKTREE_ROOT`, and `core/policies/git.md:33-35` calls both valid. Two sources of truth for "where do I edit" |
| Worktree shapes recognized: `.claude/ .cursor/ .codex/ .gemini/ .opencode/` | `worktree-common.sh:90`; `objective-common.sh:92,152` | **A** — a foreign worktree is classified as the main checkout and edits are denied |
| Wix IP patterns hardcoded in a shipped hook | `hooks/wix-ip-guard.sh:23` | **B** — a personal-config value living in plugin code, with no config seam. Should read a user-level list |
| One GitHub handle / one employer / one projects path | `core/global-rules.md:33,36,40` | **B** — placeholders imply substitution; nothing validates it happened |
| Captured config is always machine-global | `scripts/lib/capture-common.sh:52-54,184-199` vs `scripts/setup.sh:1-3` | **A/B** — permissions, hooks and MCP servers are legitimately per-repo `.claude/settings.json`; today they are promoted machine-wide and leak across projects |
| `SETUP_ALL_TARGETS` fixed 5-platform list | `scripts/setup.sh:53` | **C** — a closed set is correct here; it mirrors the capability registry |
| `python3` / `jq` assumed on PATH | `list-agent-worktrees.sh:23`; `resolve-merge-policy.sh:65,89` | **A** — jq's absence silently discards policy files (see §3) |

---

## 6. `repo-scaffold` + `standards-contract.json`

### 6.1 How far the `app-gold` / `plugin-gold` split actually goes

Only to `canonical/rules` existing. Everything the two profiles *share* is asserted as
universal, and much of it is not:

| contract assertion | line | genuinely universal? |
|---|---|---|
| `docs/CONTRIBUTING.md`, `docs/CHANGELOG.md`, `docs/README.md`, `docs/user`, `docs/engineering` | 7-12, 29-33 | **No.** 13 mandatory docs files on a one-file CLI or a library is guaranteed rot. Should tier by purpose (library / app / plugin / experiment) |
| README badges `ci, license, author, version` | 19-24 | **Partly.** `ci` presumes CI exists; `license` presumes a LICENSE, which a private repo may deliberately lack; `version` presumes a release model |
| `require_root_changelog` | 26 | **No** — depends on a release model |
| `versioning.md` at a fixed path | 27 | **No** — same |
| CI job `secret-scan` required (+ `validate` for plugin) | 41-43, +139:7-9 | **Yes, C.** Secret scanning is the one thing every repo wants. Keep |
| `forbidden_patterns: runs-on: [self-hosted` | 44-46 | **Yes, C.** Matches the hard constraint in CLAUDE.md |
| `require_cursor_mdc`, `require_agent_guidelines_dir`, `require_drift_script`, `require_agent_check_target` | 48-54 | **No** — these are multi-agent-repo requirements asserted against every repo, including single-target ones |
| `require_capability_registry_when_multi` | 79 | **Yes, C** — correctly conditional, and the only `_when_*` key in the file. This is the pattern to replicate |
| `plugin.required_paths` (10 paths incl. `scripts/build.mjs`, `dist/gemini/…`) | +139:32-43 | Correct **for `plugin-gold`**, but it hardcodes a Node build (`build.mjs`, `package-lock.json`, +139:34,37) — a plugin repo built with Python or pure shell cannot satisfy it |
| `exit_gate p1/p2/p3 = 0` | 81-85 | **B** — zero P3s is a maintenance-mode-hostile bar for an experiment or fixture repo |

`score-standards-gaps.sh:122-139` then asserts, as universal P1/P2 gaps: auto-merge
enabled (S4-04), delete-branch-on-merge (S4-05), thread resolution (S4-10), linear
history (S4-11). Three of those are defensible; **S4-04 (auto-merge)** is a team-norm
preference being scored as a defect. Note the file already records the lesson —
`standards-contract.json:87` explains that S4-03 was retired precisely because it
asserted a review requirement that contradicted the solo posture. S4-04 is the same
class of error, not yet caught.

### 6.2 `repo-scaffold` defaults (the highest-value subset)

| default | where | hardcoded | depends on | suggested by shape |
|---|---|---|---|---|
| Visibility | `SKILL.md:157` | `--private`, unconditionally | audience | plugin/marketplace/OSS → public; app/internal → private. **B** (a real choice) but strongly hinted by `--type plugin` |
| Owner | `SKILL.md:156,282,300` | literal `TamirCohen28` in repo name, CODEOWNERS, badge URLs, LICENSE | authed account | **A** — `gh api user -q .login` |
| License | `SKILL.md:300` | MIT + "2026 Tamir Cohen" | visibility + reuse intent | **B** — private app often wants *no* LICENSE |
| Default branch | `SKILL.md:110,409` + 8 lines in `legacy-scaffold-templates.md` | `master`, while `gh repo create` makes `main` | — | **A**, see §1 |
| Node version / package manager | `SKILL.md:305,314`; `ci.yml.tmpl:16-18` | `.nvmrc` = `22`, `npm ci` | lockfile in `--src` | **A** |
| Test config | `SKILL.md:307-313` | writes `vitest.config.ts` for all node/nextjs | existing runner | **A** — writing a vitest config into a jest repo is actively wrong |
| Secret scan | `ci.yml.tmpl:27` | greps 2 patterns in `*.json`/`*.yml` only | secret surface | **A** — misses `.env`, `.ts`, `.py`, private keys. Use gitleaks |
| `release.yml` + force-pushed `stable` branch | `legacy-scaffold-templates.md:393-426` | always created | release model | **B** — most repos never tag; a library needs a publish step that is absent entirely |
| `claude.yml` requiring `ANTHROPIC_API_KEY` | `SKILL.md:269` | always | secret configured | **A/B** — a permanently red or skipped workflow otherwise |
| SECURITY.md with a hardcoded personal email | `SKILL.md:302` | `tamircohen2468@gmail.com` | visibility | **A** — public → GitHub private vulnerability reporting; private → omit |
| CODE_OF_CONDUCT, CONTRIBUTING fork flow | `SKILL.md:301,206` | always | visibility | **A** — a fork section on a private solo repo is noise |
| Capability registry (6 targets) | `SKILL.md:341-347` | written unconditionally | number of AI targets | **A** — `INDEX.md:33` already says it is for ≥2 harnesses; Agent E ignores that |
| Clone location | `SKILL.md:163` | `REPO_ROOT=/tmp/$REPO_NAME` | — | **A** — new repo lands on a volume that gets wiped |
| Issue templates | `INDEX.md:11` | `agent_task.yml.tmpl` exists but **no agent ever writes it** | — | bug, not a shape issue — fix the wiring |
| `.gitignore` bodies | `SKILL.md:304` | node / python / generic — **no swift body** despite swift being an emitted stack | stack | **A** |

Two internal contradictions worth fixing while in there: `SKILL.md:95` vs
`scaffold-requirements.md:12-18` specify different badge sets; `SKILL.md:97-106` vs
`scaffold-requirements.md:35-51` specify different docs trees.

---

## 7. Ranking summary

**A — derive from observable facts (the large majority).** Default branch (§1), merge
method / delete-branch / admin-bypass / review-required (§3), CI existence (§3, §5),
stack and test commands (§4), plugin-vs-app repo detection (§5), owner and visibility
in scaffold (§6.2). Every one of these has an authoritative answer in the remote, in
`git`, or in the file tree. A setup-time answer to any of them goes stale the first
time a repo gains CI, gains a collaborator, or renames its default branch — and for
19 repos it is 19 questions whose answers are already sitting in one API response.

**B — genuine preference, no signal reveals it.** Auto-merge as a default posture;
license choice; visibility for a new repo; release model (tag / publish / none);
`exit_gate` strictness for experiment repos; the employer-IP pattern list. These
belong in one small per-repo block, and the file for it already exists:
`config/github/repository-policy.json`'s `repositories.<owner/repo>` map. Do not
create a second one.

**C — correctly universal, leave alone.** `strict_required_status_checks_policy:
false` with `required_linear_history: true` (the two are a matched pair; the O(N²)
argument at `repository-policy.json:22` is architecture-level, not repo-level).
Deletion and force-push protection on the default branch. The `secret-scan` CI job and
the `self-hosted` runner ban. `do_not_enforce_on_create`. The Actions
concurrency classifier (`repository-policy.json:157-228`) — and it is also the best
model in the codebase for how a shape system should behave: classify by evidence,
declare a precedence, and **report rather than guess** on unknown input
(`unclassified_action: "report"`, line 161).

## 8. Where I am unsure

- Whether `required_review_thread_resolution` alone is enough of a gate on a repo with
  no review bots configured. If no bot ever opens a thread, it gates nothing — I did
  not verify which of the 19 repos have a reviewing bot installed.
- Whether GitHub still permits an owner to approve a PR authored by a *bot* account
  they control; if so, a bot-authored-PR workflow would make count 1 satisfiable on a
  solo repo without `--admin`. Worth checking before acting on §0.1.
- I did not read `skills/repo/repo-standards/references/polish-phases.md` or the three
  `fixtures/` trees file-by-file; the fixture assertions are reported from
  `standards-contract.json` (which they are generated against) rather than from the
  fixture contents.
