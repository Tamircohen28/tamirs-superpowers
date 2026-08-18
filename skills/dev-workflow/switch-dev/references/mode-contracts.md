# Mode contracts — handoff / resume / status

## Argument parsing

```bash
SKILL_DIR="${CLAUDE_SKILL_DIR:-$(git rev-parse --show-toplevel)/skills/dev-workflow/switch-dev}"
SHARED_DIR="$(cd "$SKILL_DIR/../_shared/scripts" && pwd)"
bash "$SKILL_DIR/scripts/parse-mode-args.sh" $ARGUMENTS
```

Output JSON: `{ mode, issue, objective, task, target_platform, constraints }`

| Position | Name | Default | Values |
|----------|------|---------|--------|
| 1 | `mode` | `handoff` | `handoff`, `resume`, `status` |
| any | `issue` | — | `#N` or `N` |
| any | `objective` | — | `objective=<slug>` or `obj:<slug>` |
| any | `task` | — | `task-NNN` or `task=task-NNN` |
| any | `target_platform` | `any` on handoff | `claude`, `cursor`, `codex`, `gemini`, `opencode`, `any` (also `agent:<x>`, `claude-code`) |

Unrecognised words become `constraints` — free text passed through to the handoff note.

`/switch-dev #42` → handoff. `/switch-dev resume #42` → resume. `/switch-dev status` → status (no arguments needed; the parser handles the empty-argument case).

## Shared scripts

`SHARED_DIR` is `skills/dev-workflow/_shared/scripts/`:

| Script | Purpose |
|--------|---------|
| `detect-platform.sh` | Current platform |
| `resolve-worktree.sh` | Worktree path for a branch (understands legacy `.<platform>/.worktrees/` and objective worktrees) |
| `objective-state.sh` | Read/write `.dev-files/objectives/<id>/` — primary state |
| `handoff.sh` | `emit` / `show` / `list` / `validate` `handoffs/<task-id>.json` |
| `parse-issue-resume.sh` | Read a Resume block (optional GitHub mirror) |
| `update-issue-resume.sh` | Write Resume + label + comment (optional GitHub mirror) |
| `list-agent-worktrees.sh` | Active worktrees |

Every GitHub-touching script is **optional**: when `gh` is missing or the repo has no remote, the mode still completes on local state alone and says so.

## handoff mode

**Purpose:** persist enough state that another tool — or the same tool tomorrow — can continue without re-explaining the task.

**Does:** push commits; write/update the local handoff record; mirror to the GitHub issue Resume block when `gh` and an issue are available; print a resume prompt for the target platform, including any capability degradation.

**Stop condition:** local handoff written, mirror attempted, resume prompt printed.

**Must not:** write code, open PRs, or merge.

## resume mode

**Purpose:** load state on the current platform and get to the point of continuing.

**Does:** read local objective/task/handoff state first, then the issue Resume block if one exists; resolve the worktree for the recorded branch; claim ownership (label swap when GitHub is available); print the continuation checklist.

**Stop condition:** summary + worktree path + next step printed.

**May suggest:** `/start-dev` (or `worker-dev`) when no branch/worktree exists yet.

## status mode

**Purpose:** read-only dashboard of what is in flight.

**Does:** list local objectives and their task statuses; list agent-labelled issues when `gh` is available; list active worktrees.

**Stop condition:** table printed. Never mutates anything.
