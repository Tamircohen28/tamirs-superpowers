# Statusline

`scripts/statusline.sh` renders a 2-3 line status display in the Claude Code footer on every turn. It is wired via the `statusLine` field in `.claude-plugin/plugin.json`:

```json
"statusLine": {
  "type": "command",
  "command": "f=$(ls $HOME/.claude/plugins/cache/tamirs-plugins/tamirs-superpowers/*/scripts/statusline.sh 2>/dev/null | sort -rV | head -1) && [ -n \"$f\" ] && bash \"$f\""
}
```

The command uses a `$HOME`-based glob rather than `${CLAUDE_PLUGIN_ROOT}` because Claude Code only sets `CLAUDE_PLUGIN_ROOT` during hook execution — it is not set when running the `statusLine` command. The glob finds the latest installed version automatically, so the path survives plugin updates.

Claude Code invokes the script and passes a JSON blob on stdin containing session context. The script parses it and emits colored ANSI lines.

## Output format

```
[Sonnet 4.6 (1M) ● High] 📁 my-repo ⎇ feat/add-auth ctx:12% v2.1.220
5h: ████████░░ 78% | resets in 1h 23m | 4m12s | $0.43
7d: ███░░░░░░░ 31% | resets in 3d 4h
```

**Line 1:** Model name (color-coded by tier), effort level, repo name, git branch (hyperlinked to GitHub), context window usage, Claude Code version (dim). The version is omitted entirely when Claude Code does not supply it.

**Line 2:** 5-hour rate limit bar, percentage, reset time, session duration, session cost.

**Line 3:** 7-day rate limit bar (only shown when data is available).

## Input schema

Claude Code passes a JSON object on stdin with these fields (all optional — the script handles missing gracefully):

| Field | Type | Description |
|-------|------|-------------|
| `model.display_name` | string | Model name, e.g. `"Sonnet 4.6 (1M context)"` |
| `workspace.current_dir` | string | Absolute path of current working directory |
| `worktree.branch` | string | Current git branch |
| `effort.level` | string | `low` / `medium` / `high` / `xhigh` / `max` |
| `context_window.used_percentage` | number | 0–100 |
| `rate_limits.five_hour.used_percentage` | number | 0–100 |
| `rate_limits.five_hour.resets_at` | number | Unix epoch when the limit resets |
| `rate_limits.seven_day.used_percentage` | number | 0–100 |
| `rate_limits.seven_day.resets_at` | number | Unix epoch |
| `cost.total_duration_ms` | number | Session wall-clock time in ms |
| `cost.total_cost_usd` | number | Cumulative session cost in USD |
| `version` | string | Claude Code version, e.g. `"2.1.220"` |

## Color coding

| Element | Color |
|---------|-------|
| Model: Haiku | Yellow |
| Model: Sonnet | Green |
| Model: Opus | Blue |
| Rate limit bar: <70% | Green |
| Rate limit bar: 70–89% | Yellow |
| Rate limit bar: ≥90% | Red |
| Repo name | Bold green |
| Branch name | Yellow (hyperlinked) |
| Claude Code version | Dim |

## Helper functions

| Function | Purpose |
|----------|---------|
| `fmt_model` | Color-codes the model name by tier |
| `fmt_effort` | Renders effort level with icon and color |
| `fmt_pct` | Rounds a float to nearest integer |
| `fmt_resets` | Formats epoch to "resets in Xh Ym" |
| `fmt_duration` | Formats ms to "Xd Yh Zm" |
| `fmt_cost` | Formats USD as "$X.XX" |
| `fmt_version` | Renders the Claude Code version dim as "vX.Y.Z" |
| `build_bar` | Renders a 10-character block progress bar (█░) |
| `bar_color` | Returns ANSI color code based on percentage |
| `github_repo_url` | Resolves remote URL → GitHub HTTPS URL for hyperlinking |

## Branch hyperlinking

The branch name is rendered as a terminal hyperlink (`\e]8;;URL\aLabel\e]8;;\a`) pointing to `https://github.com/<owner>/<repo>/tree/<branch>`. This works in terminals that support OSC 8 (iTerm2, Warp, most modern terminals). Falls back to plain text in unsupported terminals.

The URL is resolved by reading the git remote for the current branch (falls back to `origin`), then converting SSH or HTTPS remote URLs to a GitHub HTTPS URL.

## Dependencies

- `bash` 4.0+ (uses `printf -v` and associative patterns)
- `jq` — for JSON parsing
- `git` — for branch detection and remote URL resolution
- ANSI escape code support in the terminal

## Modifying the statusline

1. Edit `scripts/statusline.sh`
2. Test locally: `echo '{}' | bash scripts/statusline.sh`
3. Test with real data: copy a sample JSON payload from Claude Code's debug output and pipe it in
4. Run `make lint` to confirm shellcheck passes
5. Reload the plugin: `/reload-plugins`
