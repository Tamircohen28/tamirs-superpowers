---
name: docs-review
description: 'Internal docs-quality sweep invoked by repo-standards polish phase 6. Audits README.md and docs/** across 11 axes: repo inventory, visual cleanliness, git freshness, stray plan files, template conformance, broken links/anchors, agent-instruction consistency, recent-change sync, cross-platform docs consistency, install-command verification, and generated skill/platform table verification. Returns pass/fail summary to caller.'
when_to_use: Called by repo-standards polish phase 6. Also valid when another skill explicitly needs a full documentation audit — e.g. 'run docs-review on $PROJECT_DIR'. Not for direct user invocation.
argument-hint: '[optional: subset glob like ''docs/user/**'' or single file path]'
arguments: []
disable-model-invocation: true
user-invocable: false
allowed-tools:
- Bash
- Read
- Write
- Edit
- Glob
- Grep
disallowed-tools: []
model: claude-sonnet-4-6
effort: low
context: ''
agent: ''
hooks: {}
paths: []
shell: bash
metadata:
  tamirs:
    visibility: internal
    category: documentation
    role: reviewer
    validation-tier: 2
    updated-date: '2026-08-19'
    capabilities:
      required:
        - skills
        - shell
      optional:
        - git
    tags:
      - documentation
      - audit
      - links
      - freshness
      - cleanup
      - workflow
      - platform-consistency
  capability: documentation-quality
  provider: developer-workflow
  agents:
  - docs-review
  updated-date: '2026-08-19'
---

# docs-review

A documentation-quality sweep: every Markdown file under `README.md` (root) and
`docs/**` is audited against eight axes, then fixed in place. The goal is to
finish a sweep with a clean working tree, zero broken links, no stray plan
files in git, and every doc reflecting the current state of the codebase —
including accurate counts of agents, skills, and commands.

## When repo-standards invokes this skill

| repo-standards step | Action |
|---------------------|--------|
| **Polish phase 6** — after standards scaffolding and multi-agent setup | Full audit of `$TARGET_ROOT/README.md` and `docs/**` |
| **Re-run** — after manual P1 doc fixes | Confirm link-clean and counts accurate |

`repo-standards` sets the working directory to `$TARGET_ROOT` before calling this skill. **Always treat the current working directory as the repo root** for all axes — never use the plugin install path or absolute paths from this skill's own directory.

When invoked from `repo-standards`, print a pass/fail summary at the end (format below). Return control only when all P1 doc issues are fixed or explicitly listed for repo-standards to handle.

```
=== docs-review complete ===
Files audited: N
Fixes applied: N
Broken links: N (0 = pass)
Stale docs updated: N
Plan files flagged: N (user confirmation pending)
Platform doc inconsistencies: N (0 = pass)
Install commands verified: N ok / N failed (0 failed = pass)
Generated tables: N in sync / N drifted (0 drifted = pass)
```

## Why this skill exists

Docs drift faster than code. A sweep that's "by hand" misses files,
mis-classifies plan dumps as canonical reference material, and leaves behind
stale agent/skill counts. This skill codifies the routine so the audit is
exhaustive and its judgement calls are explicit.

## Scope

**Full audit (all 8 axes):** `README.md` (repo root), every `*.md` under `docs/`.

**Consistency-check only (Axes 0 + 6):**
- `CLAUDE.md` — verify agent/skill counts match filesystem; update stale claims
- `.github/copilot-instructions.md` — verify architecture description, counts, commands
- `docs/engineering/reference/agent-quick-ref.md` — verify every `plugin/agents/pm-*.md` has an entry

**Out of scope:** `plugin/skills/**/*.md`, `plugin/agents/*.md`, `.claude/rules/*.md` — those have their own validators (`validate-skills.sh`, `validate-agents.sh`).

If the user passes a path argument, restrict the per-file audit to that subset (still run Axis 0 first).

## Axis 0 — Repo State Inventory (ALWAYS FIRST)

**Run before any per-file work.** Generates ground truth used by Axes 6 and 7. All paths are relative to the repo root (current working directory when this skill is invoked).

```bash
# Count entities — gracefully handle repos that lack these paths
AGENT_COUNT=$(ls plugin/agents/pm-*.md 2>/dev/null | wc -l | tr -d ' ')
PLUGIN_SKILL_COUNT=$(ls -d plugin/skills/*/ 2>/dev/null | wc -l | tr -d ' ')
DEV_SKILL_COUNT=$(ls -d .claude/skills/*/ 2>/dev/null | wc -l | tr -d ' ')
HOOK_COUNT=$(jq '.hooks | length' plugin/hooks/hooks.json 2>/dev/null || echo "?")
CLAUDE_AGENT_CLAIM=$(grep -oP '\d+(?= sub-agent)' CLAUDE.md 2>/dev/null | head -1 || echo "?")
CLAUDE_SKILL_CLAIM=$(grep -oP '\d+(?= MCP skill)' CLAUDE.md 2>/dev/null | head -1 || echo "?")
```

Print an inventory table:
```
=== Axis 0 — Repo State Inventory ===
agents:        20  (CLAUDE.md claims: 20) ✓
plugin skills: 32  (CLAUDE.md claims: 29) ✗ → NEEDS UPDATE
dev skills:    11
hooks:         13
```

If counts differ AND `tooling/ci/regen-claude-md.sh` exists, run it to auto-update CLAUDE.md:
```bash
[[ -f tooling/ci/regen-claude-md.sh ]] && bash tooling/ci/regen-claude-md.sh
```
If the script doesn't exist, update the stale counts in CLAUDE.md manually via Edit.

Then generate the per-file manifest:
```bash
{ find . -maxdepth 1 -name 'README.md'; find docs -name '*.md' -type f 2>/dev/null; } | sort > /tmp/review-docs-manifest.txt
TOTAL=$(wc -l < /tmp/review-docs-manifest.txt)
echo "=== $TOTAL files queued for audit ==="
```

If `docs/` does not exist in this repo, note it in the summary and skip Axes 2–5 for that directory.

## The five doc audit axes

The skill walks each in-scope file once and applies all five checks. Fixes are
applied in-place. Findings are appended to `docs/review-${DATE}.md`.

### Axis 1 — Visual cleanliness

Goal: a reader scanning the doc isn't tripped by formatting noise.

What to fix:
- Stray trailing whitespace, mixed tabs/spaces, inconsistent heading levels.
- Code fences without language hints (` ``` ` instead of ` ```bash `).
- Tables with mismatched column counts.
- Long lines inside paragraphs (soft 100 chars; hard cap 200).
- Bullets: pick `-` consistently (avoid mixing `-`, `*`, `+` within one file).

What to leave alone:
- Deliberate ASCII diagrams. Code blocks of legitimately long single-line commands.

### Axis 2 — Freshness vs git history

Goal: every doc reflects the current state of the codebase.

Locate the skill's own scripts directory. On Claude Code it is `$CLAUDE_SKILL_DIR`, set automatically; on any harness that does not set it, resolve the skill directory from the path this SKILL.md was loaded from and substitute it everywhere `$CLAUDE_SKILL_DIR` appears below. The scripts themselves are plain bash and depend only on `git`, `grep` and `sed` — they are not platform-specific.
```bash
bash "$CLAUDE_SKILL_DIR/scripts/file-freshness.sh" <FILE>
```

Prints `last_doc_update`, `repo_changes_since`, and `verdict` (`fresh` / `review` / `stale`).

When verdict is `stale`: read the listed downstream changes and update the doc.
Common fixes: rename broken links, remove references to deleted scripts/agents,
update counts. Do NOT rewrite wholesale — fix only what drifted.

### Axis 3 — Stray plan / work files

Goal: `docs/` is canonical reference material, not a dumping ground.

```bash
bash "$CLAUDE_SKILL_DIR/scripts/detect-plan-files.sh"
```

Signals: filename has `-plan`, `-research`, `-analysis`, `-review`, or ticket id;
located directly under `docs/` and not linked from any README; last commit says
"wip" or "from claude session".

For each confirmed one-off: `git rm --cached <file>` and add pattern to `.gitignore`.

Orphan check (skip gracefully if script doesn't exist):
```bash
[[ -f tooling/check-doc-orphans.py ]] && python3 tooling/check-doc-orphans.py
```

### Axis 4 — Template / standard conformance

Goal: every doc complies with `.claude/rules/documentation-standards.md` (if present).

```bash
bash "$CLAUDE_SKILL_DIR/scripts/check-template.sh" <FILE>
```

Reports: audience path match, `docs/user/**` footer presence, Mermaid violations
(no `classDef`, `class`, `style`, `fill:`), has-purpose-sentence.

### Axis 5 — Link / cross-reference / diagram validity

Goal: every link resolves; every Mermaid diagram parses.

```bash
bash "$CLAUDE_SKILL_DIR/scripts/validate-links.sh" <FILE>
```

Reports: broken relative links (with line number), missing heading anchors,
unparseable Mermaid blocks, raw-file-path link text.

External `https://` URLs are sampled but not blocked on (`--skip-external` accepted).

## Axis 6 — Agent-instruction file consistency

After Axis 0, verify the consistency-check-only files. Repos differ in which of these exist — check the ones present, skip the rest without comment:

1. **CLAUDE.md** — run `bash tooling/ci/regen-claude-md.sh --dry-run` and show diff. Update if any count or table drifted.
2. **`.github/copilot-instructions.md`** — READ the file and check:
   - Agent count matches `$AGENT_COUNT`
   - Skill count matches `$PLUGIN_SKILL_COUNT`
   - Investigation style: "linear pipeline" not "hypothesis-driven loop"
   - No references to `src/`, `dev-env/`, `platforms/` (not active directories)
   - Commands list reflects skills-based approach; no `plugin/commands/` references
   - Agent registration: "1 file: `plugin/agents/pm-name.md`" not "4 registrations in src/"
   - Apply fixes in-place for any stale content found
3. **`docs/engineering/reference/agent-quick-ref.md`** — verify every `plugin/agents/pm-*.md` has an entry; flag missing ones for the user to fill.

## Axis 7 — Recent Changes Sync

Flag docs that reference entities deleted in the last 45 days:

```bash
git log --since=45.days.ago --oneline --name-only | grep -v '^[a-f0-9]' | sort -u
```

Derive the deleted-entity list **from git**, not from a hardcoded list — a list baked into
this skill goes stale the moment the repo moves on:

```bash
# files deleted in the window, whose basenames may still be referenced in docs
git log --since=45.days.ago --diff-filter=D --name-only --pretty=format: \
  | grep -E '\.(md|sh|py|json)$' | sort -u
```

For each deleted path, grep `README.md` and `docs/**` for its basename and for its
directory. Then flag docs that still mention:

- any entity deleted in the window (agents, skills, scripts, commands, directories);
- agent/skill counts that no longer match the Axis 0 inventory.

For each flagged doc: READ it, remove or update the stale references.

## Axis 8 — Cross-platform docs consistency

Goal: a repo that supports several agent platforms documents them **once**, and every
platform-facing file agrees with the canonical source instead of drifting from it.

Resolve the platform list from the capability registry, exactly as `platform-sync` does —
`core/capabilities/platforms.json`, else
`docs/engineering/build-and-release/platform-targets.json`. Never hardcode a platform list
in a doc or in this audit; a hardcoded list is the drift.

```bash
# which platform-facing docs exist here?
ls -1 CLAUDE.md AGENTS.md GEMINI.md 2>/dev/null
ls -1 .cursor/rules/*.mdc .claude/rules/*.md 2>/dev/null
ls -1 opencode.json .mcp.json 2>/dev/null
```

Check, for each platform-facing file that exists:

1. **Canonical-source discipline.** Per-platform files should *point at* the canonical
   policy (usually `AGENTS.md`), not restate it. Flag any passage of substantive policy
   duplicated verbatim across two platform files — that is a future divergence, and it is
   a finding even while the two copies still agree.
2. **Platform-set agreement.** Every doc that enumerates supported platforms must list the
   same set the registry does. A doc naming four targets when the registry has six is a
   P1 finding. Report the diff both ways: documented-but-not-in-registry, and
   in-registry-but-undocumented.
3. **Capability honesty.** A doc must not claim a feature on a platform whose registry
   entry marks that capability `unsupported` or `unknown`. Cross-check every "works with X"
   claim. Silence is better than a false claim; an `unknown` documented as working is the
   worst case, because nobody will re-check it.
4. **Per-platform install/config paths** named in docs must match what the adapters
   actually use (`.claude-plugin/`, `.cursor/rules/`, `.codex-plugin/`, `.gemini/`,
   `opencode.json`). Verify the path exists in the repo, or that the doc is describing the
   user's machine rather than this repo — and says so.

Report each finding with the file, the line, and the registry fact that contradicts it.

## Axis 9 — Install-command verification

Goal: every command a reader is told to run is real. A wrong install command is the single
highest-cost documentation defect — it fails at the reader's first contact with the project.

Extract every command from fenced blocks in `README.md` and `docs/**` that installs,
updates, or removes the project:

```bash
grep -rnE '^\s*(make (install|update|uninstall)|bash scripts/[a-z-]+\.sh|/plugin (marketplace )?(install|update)|npm i(nstall)? -g|pip install|brew install|curl .*\| *(ba)?sh)' \
  README.md docs/ 2>/dev/null
```

For each extracted command, verify **without executing anything that mutates the system**:

| Command shape | Verification |
|---|---|
| `make <target>` | `make -n <target>` exits 0 — the target exists |
| `bash scripts/<x>.sh` | the file exists and is executable; `bash -n` parses it |
| `/plugin install <name>@<marketplace>` | the marketplace name and plugin name match the manifest |
| package-manager install | the package name matches the one this repo publishes |
| `curl ... \| sh` | flag it — a piped remote script in docs needs an explicit reason |

Never run an install command to test it. `make -n`, `bash -n`, and reading the manifest are
the verification; actually installing mutates the user's machine and is out of scope for a
docs audit.

Also verify **version strings**: any version quoted in install docs or badges must match the
canonical version source (`plugin-version.json` where present, else the manifests). Defer to
`scripts/check-version-truth.sh` when it exists rather than re-deriving the comparison here.

Report: `N commands verified, N failed`, each failure with file, line, command, and reason.

## Axis 10 — Generated skill / platform table verification

Goal: tables that enumerate skills, agents, or platforms match the filesystem. These are the
tables that silently rot, because nothing fails when they do.

```bash
# ground truth
find skills -name SKILL.md -not -path '*/_contract/*' | wc -l    # skill count
find skills -mindepth 1 -maxdepth 1 -type d | sed 's|.*/||' | sort  # domains
find agents -name '*.md' 2>/dev/null | wc -l                     # agent count
```

Then, for every table or count claim in `README.md`, `CLAUDE.md`, `AGENTS.md` and `docs/**`:

1. **Counts** — "27 skills" must equal the ground-truth count. Check every occurrence; a
   repo typically states the count in three or four places and updates two of them.
2. **Domain tables** — every domain directory on disk has a row, and every row has a
   directory. Report both directions.
3. **Per-skill rows** — every `SKILL.md` on disk appears, and every listed skill exists.
   A skill added without a table row is invisible to users; a row for a deleted skill sends
   them at nothing.
4. **Platform tables** — the platform set matches the registry (Axis 8 rule 2).
5. **Generated-file marker** — if a table is generated, it must say so and name the
   generator. Fix the generator and regenerate; never hand-edit a generated table. If a
   table is hand-maintained and drifts repeatedly, recommend generating it.

Where a repo ships a regeneration script, run it and commit its output instead of editing by
hand:

```bash
[[ -f tooling/ci/regen-claude-md.sh ]] && bash tooling/ci/regen-claude-md.sh
```

Report: `N tables in sync, N drifted`, each drift with the file, the claim, and the truth.


## End-to-end sweep procedure

1. **Axis 0** — generate inventory + manifest; update CLAUDE.md if counts differ.
2. **Axis 6** — check consistency-check-only files; fix in-place.
3. **Axis 7** — scan recent changes; flag stale doc references.
3a. **Axis 8** — cross-platform docs consistency against the capability registry.
3b. **Axis 9** — install-command verification (`make -n` / `bash -n` / manifest match).
3c. **Axis 10** — generated skill/platform table verification against the filesystem.
4. **Per-file audit** — for each file in `/tmp/review-docs-manifest.txt`:
   - READ the file (required — no skipping based on git alone)
   - Run Axes 1–5 using scripts from `$CLAUDE_SKILL_DIR/scripts/`; apply fixes in-place
   - Print `[✓] path/to/file.md — N fixes applied` or `[·] path/to/file.md — clean`
5. **Untrack plan files** — for Axis 3 hits confirmed by the user.
6. **Run validators** (skip any that don't exist in this repo):
   ```bash
   [[ -f tooling/check-doc-orphans.py ]] && python3 tooling/check-doc-orphans.py
   [[ -f tooling/ci/validate-skills.sh ]] && bash tooling/ci/validate-skills.sh plugin/skills
   [[ -f tests/unit/skills/footer-center-aligned.sh ]] && bash tests/unit/skills/footer-center-aligned.sh
   ```
7. **Render review report** — fill `$CLAUDE_SKILL_DIR/templates/review-report.md.tmpl`; save to `docs/review-${DATE}.md`.
8. **Final summary** — print the structured block from the "When repo-standards invokes this skill" section above.

## Hard rules (do NOT break these)

- **Never mark a file as reviewed without reading it.** `[✓]` requires: file read + all 5 axes checked. Scanning git log is not a substitute.
- **Axis 0 MUST run before any per-file audit.** Never skip it, even on partial sweeps.
- **Never delete a doc the user has not confirmed.** Untrack first, retain working-tree copy.
- **Never rewrite a whole doc wholesale.** Fix only the drifted parts.
- **Never invent links.** If a target doesn't exist, remove the link or flag for the user.
- **Never paraphrase command names, file paths, or agent names.** Use canonical forms from `CLAUDE.md`.
- **Plan files are not always trash.** The detector flags candidates; the human confirms.
- **Never hardcode a platform list.** Axes 8 and 10 resolve platforms from the capability
  registry. A list written into this skill is the drift it is supposed to catch.
- **Never execute an install command to verify it.** `make -n`, `bash -n`, and reading the
  manifest are the verification. Mutating the machine is out of scope for a docs audit.
- **Never let a doc claim a capability the registry marks `unsupported` or `unknown`.**
  Removing an unverified claim is always correct; leaving it because it might be true is not.

## References

All paths below are relative to `$CLAUDE_SKILL_DIR` (this skill's install directory), not the repo being audited.

- **[`scripts/file-freshness.sh`](scripts/file-freshness.sh)** — git-history-driven freshness verdict.
- **[`scripts/detect-plan-files.sh`](scripts/detect-plan-files.sh)** — stray plan/work file detector.
- **[`scripts/check-template.sh`](scripts/check-template.sh)** — audience/footer/Mermaid/purpose checks.
- **[`scripts/validate-links.sh`](scripts/validate-links.sh)** — relative-link, anchor, Mermaid, link-text checks.
- **[`templates/review-report.md.tmpl`](templates/review-report.md.tmpl)** — canonical report shape.
- **[`references/sweep-checklist.md`](references/sweep-checklist.md)** — quick-reference per-file checklist (load when doing a partial sweep).
- **[`references/known-canonical-plans.md`](references/known-canonical-plans.md)** — plan-shaped filenames that must NOT be untracked.
- **[`evals/evals.json`](evals/evals.json)** — pinned behaviors for CI regression testing.

## Existing repo validators this skill defers to

- `tooling/check-doc-orphans.py` — orphan detection for `docs/user/` and `docs/engineering/`.
- `tests/unit/skills/footer-center-aligned.sh` — footer block conformance.
- `.claude/rules/documentation-standards.md` — the rule the skill enforces.
- `tooling/ci/regen-claude-md.sh` / `regen-testing-md.sh` — auto-regenerated counts.

This skill orchestrates them; it does NOT re-implement them.
