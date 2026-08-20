# Install — Claude Code

Claude Code is the reference target. Everything in the toolkit runs here as shipped.

**Platform:** Claude. **Surface:** Claude Code, the CLI — registry id `claude_code`.
Claude's other supported surface is [Claude Desktop](claude-desktop.md) (desktop app), which
installs the same plugin from the same marketplace listing and has its own guide. What is
measured below was measured on the CLI; see
[platform differences](../platform-differences.md) for how the two surfaces compare.

---

## Install

Two sources, same plugin. Pick one.

**From this repo (standalone):**

```text
/plugin marketplace add Tamircohen28/tamirs-superpowers
/plugin install tamirs-superpowers@tamirs-superpowers
```

**From the catalog:**

```text
/plugin marketplace add Tamircohen28/tamirs-marketplace
/plugin install tamirs-superpowers@tamirs-marketplace
```

The `@` suffix names the *marketplace*, so it differs between the two — using the wrong one
is the most common install error.

Since Claude Code 2.1.221 an installed plugin activates immediately when it is safe to do
so. On older versions, finish with `/reload-plugins`.

**Local development install** (working on the toolkit itself, not using it):

```bash
claude --plugin-dir /path/to/tamirs-superpowers
```

## Verify

```bash
bash scripts/doctor.sh .
claude plugin validate .
```

`doctor` reports the detected platform, version drift, and which optional features are
usable. `claude plugin validate` checks the manifest, skills, agents, and hook wiring.

In the session:

```text
/orchestrate-dev
```

The slash menu should list the toolkit's skills, and the statusline should show your branch
and worktree state in the footer.

Individual surfaces:

```bash
jq empty hooks/hooks.json          # hooks parse
jq empty .mcp.json                 # MCP stubs parse
echo '{}' | bash scripts/statusline.sh   # statusline renders and never blocks on stdin
```

## Update

```text
/plugin marketplace update tamirs-superpowers
/plugin update tamirs-superpowers@tamirs-superpowers
```

Claude Code caches by the manifest `version` field, so a push without a version bump does
**not** reach installed users. If an update appears to do nothing, check the version:

```bash
jq -r .version plugin-version.json
```

## Uninstall

```text
/plugin uninstall tamirs-superpowers@tamirs-superpowers
/plugin marketplace remove tamirs-superpowers
```

Then restart the session. Anything you configured outside the plugin —
`~/.claude/pushover.env`, a manual `statusLine` entry in `~/.claude/settings.json` — is
yours to remove separately.

---

## Machine-level setup

Installing the plugin does not write any config. Rendering this repo's canonical
configuration into `~/.claude` is a separate, optional step:

```bash
git clone https://github.com/Tamircohen28/tamirs-superpowers.git
cd tamirs-superpowers
bash scripts/setup.sh plan  --targets claude    # writes nothing
bash scripts/setup.sh apply --targets claude    # diff → confirm → write
bash scripts/setup.sh remove --targets claude   # undo, from a fixed-name backup
```

Eight modules, each skippable and each shown as a diff first:

| Module | Writes | What it does |
|---|---|---|
| `settings` | `~/.claude/settings.json` | Deep-merges every fragment in `platforms/claude/settings.d/` — permissions `allow`/`ask`/`defaultMode`, model, effort level, theme, auto-mode policy, marketplaces, env |
| `plugins` | `~/.claude/settings.json` | `enabledPlugins`, per key, `false` included |
| `statusline` | `~/.claude/settings.json` | Wires `statusLine` to a version-agnostic command that survives updates |
| `agents` | `~/.claude/agents/` | Copies the specialist subagent definitions |
| `claude-md` | `~/.claude/CLAUDE.md` | Renders `core/global-rules.md`. Not mergeable, so it asks overwrite / backup-and-write / skip |
| `notifications-creds` | `~/.claude/pushover.env` | Mode 600; needs `PUSHOVER_TOKEN` and `PUSHOVER_USER` in the environment |
| `notifications-hook` | `~/.claude/settings.json` | One `Notification` hook; other Notification hooks are left alone |
| `exit-guard` | `~/.claude/ensure-exit.sh` | Proxy exit-node guard; needs `CLAUDE_EXIT_PROXY` and `CLAUDE_EXIT_PUBLIC_IP` |

> **`apply` will disable plugins the canonical set records as off** — 15 of the 23 it
> tracks. That is intended, and the plan prints the exact count before writing. Read
> [setup](../setup.md#applying-will-switch-some-plugins-off) first.

`make install` is now a thin shim over `setup.sh apply --yes --targets claude`. Third-party
keys survive: objects merge key by key, and `~/.claude/settings.local.json` is never read or
written.

`plan` writes nothing and is the default when there is no terminal, so a hook or CI run can
never adopt anything silently. `apply` shows a diff and asks per change, defaulting to
**No**. Re-running is a no-op — idempotence is a content comparison. Full reference:
[setup](../setup.md) · [platform setup](../platform-setup.md).

## Capabilities and limitations

| Capability | Status | Notes |
|---|---|---|
| skills · auto-invocation | native | Description-driven; suppressed per skill with `disable-model-invocation` |
| subagents · parallel subagents | native | **The only target where orchestration runs concurrently** |
| agent teams | native (experimental) | Documented as evolving — no skill requires it |
| hooks | native | The only target where `hooks/hooks.json` runs as shipped |
| MCP · slash commands · statusline | native | |
| worktree isolation | native | Automated by the repo's worktree hooks |
| plugin marketplace | native | Install and update path |
| structured questions | native | Interactive sessions only; headless runs must not block on one |
| session transcripts | native | JSONL under `~/.claude/projects` — `/session-report` parses this format and no other |
| artifacts | partial | Present on some surfaces and account configurations; no shipped skill requires it |
| extension install | unsupported | Claude installs plugins, not git-URL extensions — use the marketplace or `--plugin-dir` |

Source of truth: [`core/capabilities/platforms.json`](../../../core/capabilities/platforms.json).
Cross-platform comparison: [platform differences](../platform-differences.md).

## Troubleshooting

Statusline missing, hooks not firing, skills not appearing after an update — see
[troubleshooting](../troubleshooting.md).
