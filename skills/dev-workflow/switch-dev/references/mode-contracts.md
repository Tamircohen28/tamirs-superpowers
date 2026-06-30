# Mode contracts — handoff / resume / status

## Argument parsing

```bash
SHARED_DIR="$(cd "$CLAUDE_SKILL_DIR/../_shared/scripts" 2>/dev/null && pwd)"
SKILL_DIR="${CLAUDE_SKILL_DIR:-$(git rev-parse --show-toplevel)/skills/dev-workflow/switch-dev}"
bash "$SKILL_DIR/scripts/parse-mode-args.sh" $ARGUMENTS
```

| Position | Name | Default | Values |
|----------|------|---------|--------|
| 1 | `mode` | `handoff` when issue given, else infer | `handoff`, `resume`, `status` |
| 2+ | `issue` | — | `#N` or `N` |
| optional | `target_platform` | `any` on handoff | `claude`, `cursor`, `codex`, `any` |

If user says `/switch-dev #42` with no mode → `handoff`.
If user says `/switch-dev resume #42` → `resume`.

## Shared scripts

Resolve `SHARED_DIR` as sibling of `switch-dev`:

```
skills/dev-workflow/_shared/scripts/
```

| Script | Purpose |
|--------|---------|
| `detect-platform.sh` | Current platform |
| `resolve-worktree.sh` | Platform worktree path |
| `parse-issue-resume.sh` | Read Resume block |
| `update-issue-resume.sh` | Write Resume + label + comment |
| `list-agent-worktrees.sh` | Active worktrees |

## handoff mode

**Purpose:** Persist session context to GitHub issue before switching platforms or ending session.

**Stop condition:** Issue updated, comment posted, resume prompt printed.

**Must not:** Write code or open PRs.

## resume mode

**Purpose:** Load issue context and prepare worktree on current platform.

**Stop condition:** Resume summary + worktree path + continuation prompt printed.

**May suggest:** `/start-dev #N` if no branch/worktree exists yet.

## status mode

**Purpose:** Dashboard of agent-labeled issues and platform worktrees.

**Stop condition:** Table printed. Read-only.
