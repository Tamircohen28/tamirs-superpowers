# Phase 0 file inventory — summary

Baseline commit `c9399aa`, generated **2026-08-19**. Source of record:
[`file-inventory.csv`](file-inventory.csv) — 451 rows, one per tracked file.
Provenance and scope: [`README.md`](README.md).

```
git ls-files | wc -l                                    451
tail -n +2 file-inventory.csv | wc -l                    451
```

---

## 1. Counts

### By `kind`

| kind | files | notes |
|------|------:|-------|
| canonical | 133 | rules, hooks libs, scripts, SKILL.md bodies, contract scripts |
| fixture | 89 | all under `skills/repo/_contract/fixtures/**` |
| documentation | 86 | `docs/**`, references, root prose |
| adapter-specific | 55 | `.cursor/**`, `.codex*/**`, `.claude*/**`, `hooks/*.sh`, shims |
| asset | 48 | templates, images, HTML, LICENSE copies |
| test | 32 | evals, `tests/`, CI workflow, smoke script |
| generated | 7 | `.opencode/agent/*.md` (6) + `platform-targets.md` |
| legacy | 1 | `docs/agent-guidelines/multi-agent-review-2026-07-02.md` |

### By `migration_action`

| action | files |
|--------|------:|
| change | 384 |
| keep | 49 |
| generate | 18 |
| move | 0 |
| delete | 0 |

**No file is proposed for deletion or physical move.** That is deliberate and matches
brief non-negotiable #8 ("no destructive directory migrations"): everything either stays
put, changes in place, or becomes a generated artifact of a canonical source that already
lives somewhere else in the tree. The 18 `generate` rows are the drift surface — the 10
`.cursor/rules/*.mdc`, the 6 `.opencode/agent/*.md`, `.claude/rules/skill-frontmatter.md`,
and `platform-targets.md`.

`keep = yes` for all 451 files.

---

## 2. ⚠️ Files nothing validates — `validated_by = NONE`

**This is the most important output of Phase 0.** 147 files have no validator at all;
another 43 carry a validator plus an explicit caveat (`NONE (…)` — e.g. "outside `make
lint`'s find scope", "evals are never executed in CI"). Together **190 of 451 tracked
files (42%) are not provably correct by any command in `make validate` or CI.**

### 2.1 Skill-local executables — 47 files, zero linting

`make lint` runs `find scripts skills/repo/_contract/scripts -maxdepth 1 -name '*.sh'`
plus `find hooks -maxdepth 1 -name '*.sh'`. **Every executable under
`skills/<domain>/<skill>/scripts/` falls outside that glob.** These are shipped to users
and run on their machines:

```
skills/creative/algorithmic-art/scripts/validate_artifact.sh
skills/debugging/targeted-debug/scripts/extract-error-paths.sh
skills/dev-workflow/_shared/scripts/detect-multi-platform-repo.sh
skills/dev-workflow/_shared/scripts/detect-platform.sh
skills/dev-workflow/_shared/scripts/list-agent-worktrees.sh
skills/dev-workflow/_shared/scripts/parse-issue-resume.sh
skills/dev-workflow/_shared/scripts/resolve-worktree.sh
skills/dev-workflow/_shared/scripts/run-pre-pr-gates.sh
skills/dev-workflow/_shared/scripts/update-issue-resume.sh
skills/dev-workflow/plan-dev/scripts/validate_plan.py
skills/dev-workflow/pr-dev/scripts/cleanup-after-merge.sh
skills/dev-workflow/pr-dev/scripts/fetch-pr-state.sh
skills/dev-workflow/pr-dev/scripts/resolve-thread.sh
skills/dev-workflow/start-dev/scripts/detect-stack.sh
skills/dev-workflow/switch-dev/scripts/parse-mode-args.sh
skills/documentation/changelog-review/scripts/check-skill-frontmatter.sh
skills/documentation/changelog-review/scripts/validate-plugin-json.sh
skills/documentation/docs-review/scripts/check-template.sh
skills/documentation/docs-review/scripts/detect-plan-files.sh
skills/documentation/docs-review/scripts/file-freshness.sh
skills/documentation/docs-review/scripts/validate-links.sh
skills/mcp/mcp-builder/scripts/scaffold.sh
skills/mcp/mcp-pagination/scripts/check-pagination.sh
skills/repo/cleanup/scripts/cleanup.sh
skills/repo/multi-agent-repo/scripts/check-agent-drift.sh          (re-export shim)
skills/repo/multi-agent-repo/scripts/inventory-agent-setup.sh      (re-export shim)
skills/repo/multi-agent-repo/scripts/parse-mode-args.sh
skills/repo/multi-agent-repo/scripts/score-inventory-gaps.sh       (re-export shim)
skills/repo/repo-scaffold/scripts/detect-stack.sh
skills/repo/repo-standards/scripts/assert-contract.sh              (re-export shim)
skills/repo/repo-standards/scripts/check-repo-hygiene.sh           (re-export shim)
skills/repo/repo-standards/scripts/ip-scan.sh                      (re-export shim)
skills/repo/repo-standards/scripts/parse-mode-args.sh
skills/repo/repo-standards/scripts/score-contract-gaps.sh          (re-export shim)
skills/repo/repo-standards/scripts/score-standards-gaps.sh         (re-export shim)
skills/repo/repo-standards/scripts/standards-inventory.sh          (re-export shim)
skills/toolkit/session-report/analyze-sessions.mjs
skills/toolkit/skill-creator/eval-viewer/generate_review.py
skills/toolkit/skill-creator/scripts/__init__.py
skills/toolkit/skill-creator/scripts/aggregate_benchmark.py
skills/toolkit/skill-creator/scripts/generate_report.py
skills/toolkit/skill-creator/scripts/improve_description.py
skills/toolkit/skill-creator/scripts/package_skill.py
skills/toolkit/skill-creator/scripts/quick_validate.py
skills/toolkit/skill-creator/scripts/run_eval.py
skills/toolkit/skill-creator/scripts/run_loop.py
skills/toolkit/skill-creator/scripts/utils.py
```

`cleanup.sh` deletes branches and worktrees. `run-pre-pr-gates.sh` is the pre-PR gate
itself. Neither is shellchecked, neither has a behaviour test. **Cheapest high-value fix
in the whole refactor: drop `-maxdepth 1` and add `skills` to the `make lint` find roots.**

### 2.2 `hooks/lib/*.sh` — the shared hook library is unlinted

`find hooks -maxdepth 1` also excludes `hooks/lib/`:

- `hooks/lib/worktree-common.sh` — **NONE**. This is the file `CLAUDE.md` says must never
  be modified without shellcheck; `make lint` does not actually shellcheck it.
- `hooks/lib/hook-output.sh` — **NONE**.
- `hooks/lib/agent-claim.sh` — covered by `tests/test-concurrency-guard.sh`, but still
  not shellchecked.

### 2.3 Platform-truth files with no validator

| file | why it matters |
|------|----------------|
| `.cursor-version` | Cursor desktop/CLI/changelog pins; **no script reads it** — a 4th version-truth source that can drift silently from `platform-targets.json` |
| `.codex-version` | same, for Codex |
| `.codex/config.toml` | the only Codex project config; nothing parses it |
| `.cursor/hooks/warn-contributor-policy.sh` | a shipped Cursor hook, outside `make lint` |
| `.cursor/rules/*.mdc` (all 10) | the Cursor adapter surface — nothing checks any of them against `rules/dev/` |
| `.claude/rules/skill-frontmatter.md` | duplicate of the Cursor rule, unchecked |
| `.gitignore` | encodes the three platform worktree roots the refactor is moving |

### 2.4 Everything else unvalidated

- `skills/**/references/*.md` — 40 files, the actual instructional payload of most skills.
- `skills/repo/_contract/templates/**` — 25 files. Only the 5 templates that happen to be
  byte-identical to a fixture are indirectly validated; the other 20 render nothing that
  CI ever renders.
- `skills/**/templates/*.tmpl` — 11 files.
- `skills/**/evals/**` — the JSON parses (`jq empty`), but **no CI job ever executes an
  eval**; `evals/files/plan.md` and the two eval fixtures have no validator at all.
- `rules/dev/*.md` — all 7 canonical rules. The canonical source of the rule system is
  itself unchecked, in either direction, against its adapter copies.
- `.claude/memory/*.md` (8), `.github/` templates + `dependabot.yml` (5), `CHANGELOG.md`,
  `docs/CHANGELOG.md`, `docs/agent-guidelines/platform-equivalence.md`, `SECURITY.md`,
  `CODEOWNERS`, `LICENSE`, `templates/global-CLAUDE.md`, both `assets/*.png`,
  `scripts/normalize-skill-frontmatter.py`, `scripts/pushover_format.py`,
  `.dev-files/README.md`.

### 2.5 Validators that exist but never run in CI

`.github/workflows/ci.yml` does **not** run `make validate`. It runs `make lint`,
`make test-hooks`, `make test-repo-contract`, `make platform-targets-cochange`, plus
standalone JSON / frontmatter / secret-scan / `claude plugin validate` / manifest-alignment
jobs. These `make validate` prerequisites therefore run **on the maintainer's machine only**:

- `check-doc-claims` — the skill-count and target-coverage guard
- `check-marketplace-schema`
- `check-feature-equivalence` (via `check-platform-equivalence`)
- `opencode-agents-check` — **so `.opencode/agent/*.md` drift from `agents/*.md` cannot
  fail CI**, even though the whole point of committing the generated files is that users
  installing from a clone get them without a build step.

---

## 3. Duplication clusters

Detected byte-exactly via git blob object ids, then confirmed by diff.

### 3.1 The three plugin manifests
`.claude-plugin/plugin.json` · `.cursor-plugin/plugin.json` · `.codex-plugin/plugin.json`
carry the same `name`, `version`, `description` (including the skill count), `author`,
`homepage`, `repository`, `license`, `keywords`, `skills[]` and `mcpServers`. Only
`check-manifest-version-alignment.sh` compares them, and **only the `version` field** —
description, keywords and `skills[]` can diverge freely. `opencode.json` is a **fourth**
place the skill-domain list is maintained, and it enumerates `skills/repo/*` individually
where the manifests use `./skills/repo`.

### 3.2 The two marketplace descriptors
`.claude-plugin/marketplace.json` and `.agents/plugins/marketplace.json` describe the same
catalog in two schemas, with the skill count copied into both descriptions.

### 3.3 `agents/*.md` → `.opencode/agent/*.md` (6 pairs, generated)
Generated by `scripts/build-opencode-agents.sh`; drift is detectable
(`make opencode-agents-check`) but **not enforced in CI** (§2.5).

### 3.4 Cursor rule copies vs `rules/dev/` — and the asymmetry
`.cursor/rules/*.mdc` are thin restatements that name their canonical source in prose.
Nothing verifies the pointer or the content. The mapping is **not one-to-one**:

| canonical `rules/dev/` | cursor `.mdc` |
|---|---|
| cross-platform-handoff · dev-files-workspace · git-worktree-agent-workflow · plugin-version-bump · skill-quality-standards | present ✅ |
| **gh-cli-preference** · **user-facing-script-standards** | **missing — Cursor never sees these rules** |
| *(no canonical source)* | commit-conventions · hooks-guide · plugin-structure · skills-guide — **Cursor-only rules with no canonical home** |
| *(no canonical source)* | skill-frontmatter — canonical-ish copy lives in `.claude/rules/skill-frontmatter.md`; the two are near-identical prose maintained separately |

### 3.5 `feature-equivalence.json` vs the platform registry vs the prose matrix
Three overlapping capability descriptions:
- `skills/repo/_contract/feature-equivalence.json` — **claude/cursor/codex only**; no
  opencode, no claude-desktop, no gemini.
- `docs/engineering/build-and-release/platform-targets.json` — 4 targets, each with a
  hand-maintained `capabilities[]` array.
- `docs/agent-guidelines/platform-equivalence.md` — prose restatement, unvalidated.

This is the cluster the new capability registry should absorb.

### 3.6 Contract scripts — 4 and 5-way byte-identical copies
- `check-agent-drift.sh` — **5 identical copies**: `_contract/scripts/`,
  `_contract/templates/check-agent-drift.sh.tmpl`, and the `scaffold-gold` /
  `scaffold-plugin-gold` / `scaffold-claude-plugin-gold` fixtures.
  (`scripts/check-agent-drift.sh` at the repo root is a *different* implementation with
  the same name — a genuine naming collision.)
- `check-feature-equivalence.sh` — **4 identical copies**: `scripts/`,
  `_contract/scripts/`, `_contract/templates/*.tmpl`, `scaffold-plugin-gold` fixture.
  (`scaffold-gold` and `scaffold-claude-plugin-gold` share a *different, older* copy —
  already drifted.)
- `check-platform-targets.sh` — 3 identical fixture copies; the root `scripts/` and
  `_contract/scripts/` versions have **already diverged** (26 diff lines).
- `_contract/templates/github/ci.yml.tmpl` ≡ `scaffold-gold/.github/workflows/ci.yml`;
  `build.mjs.tmpl` ≡ `scaffold-plugin-gold/scripts/build.mjs`; `validate.mjs.tmpl` ≡ its
  fixture. Template and fixture are the same bytes stored twice.

### 3.7 Fixture-to-fixture duplication
15 further pairs shared between `scaffold-gold` and `scaffold-plugin-gold` (`CLAUDE.md`,
`.gitignore`, `.nvmrc`, `LICENSE`, `docs/**`, `.github/**`, `.cursor/rules/000-project.mdc`,
the `run-scaffold-gold` SKILL.md ×3). `scaffold-gold/CODEOWNERS` and both fixture
`LICENSE`s are identical to the repo root's.

### 3.8 Small ones
`CHANGELOG.md` / `docs/CHANGELOG.md`; `skills/creative/algorithmic-art/LICENSE.txt` ≡
`skills/toolkit/skill-creator/LICENSE.txt`; `AGENTS.md` / `CLAUDE.md` overlapping
contributor policy; `scaffold-plugin-gold`'s `canonical/skills/example-skill/SKILL.md` ≡
its own committed build output under `plugins/`.

---

## 4. Files referencing a path the refactor moves — 36

### 4.1 Platform-shaped worktree roots (`.claude/.worktrees` → `.agent-worktrees`) — 24

`.cursor/rules/cross-platform-handoff.mdc` · `.cursor/rules/git-worktree-agent-workflow.mdc` ·
`.gitignore` · `CHANGELOG.md` · `README.md` · `docs/engineering/architecture/overview.md` ·
`docs/user/concepts.md` · `docs/user/cross-platform-workflow.md` ·
`docs/user/troubleshooting.md` · `hooks/directory-added.sh` ·
`hooks/enforce-worktree-edits.sh` · `hooks/handoff-reminder.sh` ·
`hooks/lib/worktree-common.sh` · `hooks/session-init.sh` ·
`rules/dev/cross-platform-handoff.md` · `rules/dev/git-worktree-agent-workflow.md` ·
`skills/dev-workflow/_shared/scripts/list-agent-worktrees.sh` ·
`skills/dev-workflow/_shared/scripts/resolve-worktree.sh` ·
`skills/dev-workflow/start-dev/SKILL.md` · `skills/dev-workflow/start-dev/evals/evals.json` ·
`skills/dev-workflow/switch-dev/SKILL.md` · `skills/dev-workflow/switch-dev/evals/evals.json` ·
`skills/dev-workflow/switch-dev/references/platform-capabilities.md` ·
`skills/dev-workflow/switch-dev/references/resume-schema.md` ·
`skills/repo/_contract/templates/legacy-scaffold-templates.md` · `skills/repo/cleanup/SKILL.md`

Of these, **only `hooks/*.sh` (top level) are covered by any validator.**
`hooks/lib/worktree-common.sh` — the file that actually computes the worktree root — is
in the unvalidated set (§2.2).

### 4.2 The 16-field Claude skill contract — 10

`.claude/rules/skill-frontmatter.md` · `.claude/skills/run-tamirs-superpowers/SKILL.md` ·
`.cursor/rules/plugin-structure.mdc` · `.cursor/rules/skill-frontmatter.mdc` ·
`.cursor/rules/skills-guide.mdc` · `AGENTS.md` · `CLAUDE.md` ·
`rules/dev/skill-quality-standards.md` · `skills/toolkit/skill-creator/SKILL.md` ·
`skills/toolkit/skill-creator/references/frontmatter-template.md`

Plus the two enforcing scripts, `scripts/validate-skill-frontmatter.py` and
`scripts/normalize-skill-frontmatter.py`, and every one of the 27 shipped `SKILL.md`
files that satisfies it.

---

## 5. Version truth at baseline — confirmed drift

Every value below was read from commit `c9399aa`.

| Source | Field | Value |
|--------|-------|-------|
| `.claude-plugin/plugin.json` | `version` | **2.0.1** |
| `.cursor-plugin/plugin.json` | `version` | **2.0.1** |
| `.codex-plugin/plugin.json` | `version` | **2.0.1** |
| newest git tag | — | **v2.0.1** |
| `README.md` line 16 | version badge | **`version-2.0.0`** ❌ stale |
| `docs/.../platform-targets.json` | `reviewed_by_skill` | **`tamirs-superpowers@2.0.0`** ❌ stale |
| `.claude-plugin/marketplace.json` | *(no version field)* | — |
| `.agents/plugins/marketplace.json` | *(no version field)* | — |
| `CHANGELOG.md` | newest heading | `## [Unreleased]` |

**Root cause, confirmed by reading the script:**
`skills/repo/_contract/scripts/check-manifest-version-alignment.sh` iterates exactly
`.claude-plugin/plugin.json .cursor-plugin/plugin.json .codex-plugin/plugin.json` and
compares them to the git tag. It never reads `README.md` and never reads
`platform-targets.json`. The two stale values are therefore invisible to every gate in
`make validate` and every job in CI — the drift is not an oversight by a contributor, it
is unreachable by the tooling.

### Secondary version drift — skill count

| Source | Claim |
|--------|-------|
| `README.md` line 37 (intro) | "bundling **27** skills" |
| `README.md` line 43 (Features) | "**26 bundled skills**" ❌ |
| `.claude-plugin/plugin.json` description | "**27** bundled skills" |
| `.cursor-plugin` / `.codex-plugin` descriptions | "**27** bundled skills" |
| `.claude-plugin/marketplace.json` description | "**27** bundled skills" |
| `CLAUDE.md` domain table | "**27** skills total" |
| **actual** `find skills -name SKILL.md \| grep -v _contract/fixtures \| wc -l` | **27** |

`scripts/check-doc-claims.sh` **does not catch this** — verified by running it against a
pristine `git archive c9399aa` checkout:

```
$ bash scripts/check-doc-claims.sh <baseline>
EXIT=0
```

It exited 0 and reported "27 skills, targets consistent" — the count it read off the
baseline tree, matching the manifests and disagreeing with the README, without failing.
(That count is quoted because it is the value observed at commit `c9399aa`. This file is a
frozen Phase 0 record, so its numbers must not be updated to track the current tree — see
[`README.md`](README.md).)

The blind spot is in the patterns. The Markdown pass greps `[0-9]+ skills`, which does not
match `26 bundled skills` (no digit adjacent to ` skills`); the `[0-9]+ bundled skills`
pass is scoped to `--include='*.json'`, so it only ever sees the manifest descriptions.
The one place the count is wrong is exactly the one shape neither pattern covers.
**Fix: run the `bundled skills` pattern over `*.md` too.** Note this checker is also a
`make validate`-only prerequisite with no CI job (§2.5), so even once the pattern is
fixed it will not gate a PR until it is wired into `ci.yml`.

### Platform-pin drift

| Source | Codex | Cursor |
|--------|-------|--------|
| `.codex-version` | **0.147.0** | — |
| `platform-targets.json` `latest_known` | 0.147.0 | 3.16.17 |
| `platform-targets.json` `validated_against` | **0.146.0** | 3.16.17 |
| `README.md` badge | **0.146.0** | 3.16.17 |
| `.cursor-version` | — | 3.16.17 (+ `changelog_feature: 3.11`, `changelog_date: 2026-08-17`, `cli_changelog_date: 2026-08-11`, `frontier_model: grok-4.6`) |

The README badge is checked against `validated_against` by
`scripts/check-platform-targets.sh`, so 0.146.0 is *consistent*, not drifted. But
`.codex-version` and `.cursor-version` are read by **no script at all** — they are a
fourth version-truth source held in sync purely by hand.

Other baseline facts worth pinning: `platform-targets.json` has
`schema_version: 2`, `last_reviewed: 2026-08-17`, and
`supported_targets: [claude_code, cursor, codex, opencode]` — four targets, no
`gemini`, no `claude_desktop`.

---

## 6. Risk list for the refactor

1. **Moving the worktree root touches 24 files, 20 of them unvalidated.** The one file
   that computes the path (`hooks/lib/worktree-common.sh`) is not shellchecked and has no
   behaviour test. Add a test *before* moving it, not after.
2. **CI ≠ `make validate`.** Five checks (`check-doc-claims`, `check-marketplace-schema`,
   `check-feature-equivalence`, `check-platform-targets` non-co-change modes,
   `opencode-agents-check`) run locally only. Any refactor that "makes `make validate`
   pass" can still merge a broken tree, and any new generated artifact will drift
   undetected the same way `.opencode/agent/` can today.
3. **Generated-file drift is currently unenforceable for the whole adapter layer.** 18
   files are proposed as `generate`; exactly one of those groups (`.opencode/agent/`) has
   a drift checker at all, and it is not in CI.
4. **The Cursor rule set is asymmetric.** Two canonical rules never reach Cursor and four
   Cursor rules have no canonical home. A naive "generate `.cursor/rules/` from
   `rules/dev/`" step would silently **delete** `commit-conventions`, `hooks-guide`,
   `plugin-structure` and `skills-guide` unless they are promoted to `rules/dev/` first.
5. **`skill-frontmatter` has no canonical owner.** It exists as a `.claude/rules/` file
   and a `.cursor/rules/` file with no `rules/dev/` source. Phase 2 changes this contract;
   both copies must move together or the platforms will disagree about the schema.
6. **89 fixture files encode the 4-target world.** `scaffold-gold`,
   `scaffold-plugin-gold` and `scaffold-claude-plugin-gold` all assert
   `.claude`/`.cursor`/`.codex`/`.agents` layouts. Adding Gemini as first-class means the
   fixtures — and `make test-repo-contract`, the one contract gate that *is* in CI — have
   to change in the same PR, or the gold files start lying about what the scaffolder emits.
7. **Contract-script duplication will fight the refactor.** Editing
   `check-agent-drift.sh` means editing 5 byte-identical files, and
   `check-platform-targets.sh` / `check-feature-equivalence.sh` have already drifted
   between their copies. Any change to platform enumeration has to be applied N times, by
   hand, with no checker that they agree.
8. **`${CLAUDE_PLUGIN_ROOT}` is load-bearing in a shared file.** `.mcp.json` is referenced
   by all three manifests but expands a Claude-only variable; Cursor and Codex inherit an
   MCP stub that only resolves under Claude. Gemini and OpenCode adapters must not assume
   this works.
9. **47 shipped skill scripts are unlinted**, including `cleanup.sh` (deletes branches and
   worktrees) and `run-pre-pr-gates.sh` (the pre-PR gate itself). Widening `make lint`'s
   find roots is cheap and should land in Phase 1, before those scripts get edited.
10. **Evals are decorative.** 30+ eval JSON files parse but are never executed. Any claim
    that a skill's triggering behaviour survived the refactor has no evidence behind it.
11. **The skill-count guard has a proven blind spot.** `check-doc-claims.sh` passes on a
    tree whose README says "26 bundled skills" (§5). The count is restated in 7+ places —
    three manifests, the marketplace descriptor, README twice, `CLAUDE.md` — and the
    refactor will add or rename skills. Fix the pattern *and* wire the checker into CI
    before touching the skill tree, or the count silently goes wrong again.
12. **`.codex-version` / `.cursor-version` are orphan truth.** Nothing reads them. If the
    refactor introduces a canonical version/pin source, these two must either be wired
    into it or deleted — leaving them is guaranteed future drift.
