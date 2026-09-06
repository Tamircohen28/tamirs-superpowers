---
name: run-tamirs-superpowers
description: 'Use when running, validating, or testing the tamirs-superpowers Claude Code plugin — checks JSON validity, shellcheck hooks, SKILL.md frontmatter, statusline output, hook wiring, and absence of hardcoded paths or internal references. Trigger phrases: ''run the plugin health check'', ''validate the plugin'', ''test tamirs-superpowers'', ''smoke test the plugin'', ''check the plugin'', ''is the plugin clean''.'
when_to_use: User wants to validate, test, or run a health check on this plugin. Also auto-load whenever editing SKILL.md files, hooks, or plugin.json.
argument-hint: '[none — runs full plugin health check]'
arguments: []
disable-model-invocation: false
user-invocable: true
allowed-tools:
- Bash
- Read
disallowed-tools: []
model: claude-sonnet-4-6
effort: low
context: ''
agent: ''
hooks: {}
paths: []
shell: bash
metadata:
  updated-date: '2026-06-23'
  tamirs:
    visibility: internal
    category: local
    capabilities:
      required: [shell, skills]
      optional: [git, github_cli]
    role: test-engineer
    updated-date: "2026-08-19"
    validation-tier: 2

---

# run-tamirs-superpowers

**tamirs-superpowers** is a Claude Code plugin — pure Markdown, JSON, and Bash. There is no build step. The plugin runs inside every Claude Code session automatically. The "interactive surface" is the plugin's validation harness (`make validate`) and the `smoke.sh` driver in this directory.

## Prerequisites

```bash
brew install shellcheck jq   # shellcheck for hook lint, jq for JSON checks
python3 -m pip install -q -r scripts/requirements-validate.txt  # PyYAML for frontmatter validator
```

## Run (agent path) — smoke.sh

The driver runs a 7-category health check. Always run from repo root:

```bash
bash .claude/skills/run-tamirs-superpowers/smoke.sh
```

**What it checks** (all verified in this session):

| Check | What it does |
|---|---|
| 1. `make validate` | shellcheck every tracked `.sh` at any depth, validate all JSON, validate SKILL.md frontmatter (portable core + `metadata.tamirs` + Claude extensions) |
| 2. `scripts/statusline.sh` | runs the live statusline and checks it produces output |
| 3. `plugin.json` | all required fields present, `.statusLine` is an object not a string |
| 4. SKILL.md quality | `python3 scripts/validate-skill-frontmatter.py` — tiered: portable core fails the build, `metadata.tamirs` warns while absent, Claude fields validated when present |
| 5. Hook wiring | every `.sh` in `hooks/` is referenced in `hooks.json` |
| 6. No `/Users/` paths | skills must use `$CLAUDE_SKILL_DIR` or relative paths, not hardcoded absolutes |
| 7. No employer/internal refs | internal-hostname shapes must be absent from skill files; no employer is named in the pattern — set `$TAMIRS_EMPLOYER_PATTERN` for a private one |

Exit 0 = all 7 sections pass. Exit 1 = at least one FAIL (not WARN).

**Expected clean output:**
```
  PASS  make validate
  PASS  statusline.sh — output: [unknown] ctx:--
  PASS  plugin.json .name = tamirs-superpowers
  ...
  PASS: 31  |  WARN: 4  |  FAIL: 0
Plugin health: OK (warnings=4)
```

Known warnings (not failures): none when `hooks/` contains only lifecycle scripts wired in `hooks.json`.

`scripts/github-mcp.sh` is wired via `.mcp.json`, not `hooks.json`.

## Run (human path) — make validate

For a quick syntax check without the full smoke test:

```bash
make validate   # shellcheck + JSON + frontmatter
make lint       # shellcheck only
```

To run the full Claude Code plugin validator (requires `claude` CLI):

```bash
make plugin-validate
```

## Statusline

The statusline script runs automatically in every Claude Code session. To test it in isolation:

```bash
bash scripts/statusline.sh
```

Expected output format: `[<branch>] ctx:<n> | <model> | ...`

## Adding a skill

Skills live at `skills/<domain>/<name>/SKILL.md`. After adding or editing one:

```bash
make validate   # must pass before committing
```

Frontmatter fields required by the smoke test (in addition to `name` and `description`):
- `allowed-tools: [...]`
- `when_to_use: "..."` (user-invocable skills only)
- `metadata.updated-date: "YYYY-MM-DD"`

## Gotchas

- **`statusLine` in `plugin.json` must be an object** — `{"type": "command", "command": "..."}` — not a string. Setting it to a plain string causes Claude Code to silently ignore it.
- **`make validate` does not run `claude plugin validate`** — the Makefile's `validate` target is local-only. The authoritative validator is `claude plugin validate .` (requires the CLI).
- **`set -euo pipefail` in smoke scripts exits on first grep non-match** — health check scripts must not use `set -e`; they need to complete all checks before reporting.
- **`find` in `skills/` returns `skills/toolkit/skill-creator/SKILL.md` with a `/Users/` path** — the workflow-agent-improved version has this; file it as a WARN, not FAIL, until it's cleaned.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `make validate` fails on shellcheck | Run `shellcheck hooks/<script>.sh` and fix the flagged line |
| `make validate` fails on JSON | Run `jq empty .claude-plugin/plugin.json` to get the parse error |
| SKILL.md missing `description:` | The YAML block must have `description:` as its own line (not nested) |
| `plugin.json .statusLine` is wrong type | Set `"statusLine": {"type": "command", "command": "bash ${CLAUDE_PLUGIN_ROOT}/scripts/statusline.sh"}` |
| Smoke test exits early | The script must not use `set -euo pipefail`; remove it if added |
